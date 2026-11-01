import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../api/health_hub_api.dart';
import '../location/user_location_map.dart' show CareCenterLook, CareCenterPin, PersonLook, PersonPin;
import '../people/person_screen.dart' show AdmissionRow, PersonLink;
import '../screens/link_text.dart';
import '../sim_clock.dart';
import '../theme.dart';
import 'occupancy_timeline.dart';

/// How the care center view asks the API: `GET /api/care-centers/{id}`.
typedef CareCenterLoader = Future<CareCenterDetail> Function(int id);

/// How it changes the flow at a care center, and learns its factor now:
/// `POST /api/care-centers/{id}/flow`.
typedef FlowControl = Future<double> Function(int id, FlowAction action);

/// Makes the care centers named under it links to their view: home puts it
/// over its tiles. Without one (the index), a [CareCenterLink] is plain
/// text and a pin on the map shows its tooltip. With [admissions] and
/// [forecast], the view plots its people in care per hour; with [flow],
/// it doubles and halves the flow of people there.
class CareCenterOpener extends InheritedWidget {
  const CareCenterOpener({
    super.key,
    required this.load,
    this.occupancy,
    this.forecast,
    this.flow,
    this.showTiles = true,
    required super.child,
  });

  final CareCenterLoader load;
  final HourlyOccupancyLoader? occupancy;
  final OccupancyForecastLoader? forecast;
  final FlowControl? flow;

  /// The view's map tiles; off in tests, which have no network.
  final bool showTiles;

  static CareCenterOpener? of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<CareCenterOpener>();

  /// Opens the view of care center [id], whose people are links too when
  /// [context] has a person opener.
  void open(BuildContext context, int id) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => withOpeners(
        context,
        CareCenterScreen(id: id, load: load, occupancy: occupancy, forecast: forecast, flow: flow, showTiles: showTiles),
      ),
    ),
  );

  @override
  bool updateShouldNotify(CareCenterOpener oldWidget) =>
      load != oldWidget.load ||
      occupancy != oldWidget.occupancy ||
      forecast != oldWidget.forecast ||
      flow != oldWidget.flow ||
      showTiles != oldWidget.showTiles;
}

/// A care center's name that opens its view, underlined on hover; plain
/// text without an [id] or where there is no [CareCenterOpener].
class CareCenterLink extends StatelessWidget {
  const CareCenterLink(this.id, this.text, {super.key, this.style, this.overflow});

  final int? id;
  final String text;
  final TextStyle? style;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    final opener = CareCenterOpener.of(context);
    final id = this.id;
    if (opener == null || id == null) return Text(text, style: style, overflow: overflow);
    return LinkText(
      text,
      key: Key('care-center-link-$id'),
      onTap: () => opener.open(context, id),
      style: style,
      overflow: overflow,
    );
  }
}

/// One care center, of any kind: where it is on the map, with the people
/// there and on their way; what it is; its capacity in the simulation and
/// how much of it is in use now; its admissions per hour and datyx's
/// forecast of the next ones (with [admissions] and [forecast]); who is
/// there; its admissions. Beside what it is, with [flow] while the
/// simulation runs, buttons to double and halve the flow of people there.
/// Read again every 5 seconds while shown, as people come and go.
class CareCenterScreen extends StatefulWidget {
  const CareCenterScreen({
    super.key,
    required this.id,
    required this.load,
    this.occupancy,
    this.forecast,
    this.flow,
    this.showTiles = true,
  });

  final int id;
  final CareCenterLoader load;
  final HourlyOccupancyLoader? occupancy;
  final OccupancyForecastLoader? forecast;
  final FlowControl? flow;
  final bool showTiles;

  /// How often the view reads the care center again.
  static const refresh = Duration(seconds: 5);

  @override
  State<CareCenterScreen> createState() => _CareCenterScreenState();
}

class _CareCenterScreenState extends State<CareCenterScreen> {
  CareCenterDetail? _center;
  Object? _error;
  Timer? _poll;
  bool _loading = false;

  /// The flow factor the last press answered, until a read that started
  /// after it says it; whether a press is under way; how many there were.
  double? _flowNow;
  bool _changingFlow = false;
  int _presses = 0;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(CareCenterScreen.refresh, (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  /// Reads the care center; a failed read after a good one keeps what is
  /// shown, the next one tries again.
  Future<void> _load() async {
    if (_loading) return;
    _loading = true;
    final presses = _presses;
    try {
      final center = await widget.load(widget.id);
      if (mounted) {
        setState(() {
          _center = center;
          _error = null;
          if (presses == _presses && !_changingFlow) _flowNow = null;
        });
      }
    } catch (error) {
      if (mounted && _center == null) setState(() => _error = error);
    } finally {
      _loading = false;
    }
  }

  /// Doubles, halves or resets the flow, one press at a time; a refusal
  /// in a snack bar.
  Future<void> _changeFlow(FlowAction action) async {
    final control = widget.flow;
    if (control == null || _changingFlow) return;
    setState(() {
      _changingFlow = true;
      _presses++;
    });
    try {
      final factor = await control(widget.id, action);
      if (mounted) setState(() => _flowNow = factor);
    } catch (error) {
      if (!mounted) return;
      final message = error is ApiException && error.status == 401
          ? 'Sign in to change the flow.'
          : 'The flow can\'t be changed: ${error is ApiException ? error.message : error}';
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _changingFlow = false);
    }
  }

  /// What it is, and beside it, while the simulation sends people there,
  /// the buttons of its flow: to the right when the view is wide, under it
  /// when it isn't.
  Widget _top(CareCenterDetail center) {
    final factor = _flowNow ?? center.flow;
    if (widget.flow == null || factor == null || center.serves.isEmpty) return _Header(center);
    final flow = FlowCard(factor: factor, busy: _changingFlow, onChange: _changeFlow);
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth < 720
          ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [_Header(center), const SizedBox(height: 16), flow])
          : IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _Header(center)),
                  const SizedBox(width: 16),
                  SizedBox(width: 320, child: flow),
                ],
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final center = _center;
    final error = _error;
    return Scaffold(
      appBar: AppBar(
        title: Text(center?.name ?? 'Care center ${widget.id}'),
        actions: [IconButton(tooltip: 'Refresh', onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      body: center == null
          ? (error == null
                ? const Center(child: CircularProgressIndicator())
                : _Message(
                    error is ApiException && error.status == 404
                        ? 'No care center with the id ${widget.id}.'
                        : 'The care center can\'t be read: ${error is ApiException ? error.message : error}',
                  ))
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _top(center),
                    const SizedBox(height: 16),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final map = SizedBox(
                          height: 300,
                          child: _CenterMap(center, showTiles: widget.showTiles),
                        );
                        final usage = UsageCard(center);
                        if (constraints.maxWidth < 720) {
                          return Column(children: [map, const SizedBox(height: 16), usage]);
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: map),
                            const SizedBox(width: 16),
                            SizedBox(width: 320, child: usage),
                          ],
                        );
                      },
                    ),
                    if (widget.occupancy != null && widget.forecast != null) ...[
                      const SizedBox(height: 16),
                      OccupancyTimelineCard(
                        occupancy: widget.occupancy!,
                        forecast: widget.forecast!,
                        hospitalId: widget.id,
                        capacity: center.capacity,
                        unit: center.unit,
                      ),
                    ],
                    const SizedBox(height: 16),
                    _People(center),
                    const SizedBox(height: 16),
                    _Admissions(center),
                  ],
                ),
              ),
            ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Aityx.muted)),
    ),
  );
}

/// A card of the view: an icon and a title over its content.
class _Section extends StatelessWidget {
  const _Section({required this.icon, required this.title, this.subtitle, required this.child});

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Aityx.orange, size: 20),
              const SizedBox(width: 10),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              if (subtitle != null) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    subtitle!,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Aityx.muted, fontSize: 12),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    ),
  );
}

/// What it is and where: the kind's icon in its colour, the name, the
/// registry's type, the address, how to reach it, who runs it.
class _Header extends StatelessWidget {
  const _Header(this.center);
  final CareCenterDetail center;

  @override
  Widget build(BuildContext context) {
    const muted = TextStyle(color: Aityx.muted, fontSize: 13);
    final kind = center.kind;
    final place = [
      ?center.address,
      [?center.postalCode, ?center.city].join(' '),
      ?center.region,
      ?center.country,
    ].where((part) => part.isNotEmpty).join(', ');
    final reach = [?center.phone, ?center.website].join(' · ');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: kind.color.withValues(alpha: 0.2),
              child: Icon(kind.icon, color: kind.color, size: 30),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    center.name,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Aityx.fg0),
                  ),
                  Text(
                    [kind.label, if (center.subtype != null && center.subtype != kind.label) center.subtype!].join(' · '),
                    style: TextStyle(color: kind.color, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  if (place.isNotEmpty) Text(place, style: muted),
                  if (reach.isNotEmpty) SelectableText(reach, style: muted),
                  const SizedBox(height: 4),
                  Text(
                    [
                      'id ${center.id}',
                      if (center.ownership != null && center.ownership != 'unknown') center.ownership!,
                      if (center.source != null) 'from ${center.source}',
                    ].join(' · '),
                    style: muted.copyWith(fontFamily: 'monospace', fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The flow of people to a care center in the simulation: its factor
/// now ("Flow ×2") and buttons to double and halve it (1/8 to 8), and to
/// set it back to normal; all disabled while a press is under way
/// ([busy]).
class FlowCard extends StatelessWidget {
  const FlowCard({super.key, required this.factor, required this.busy, required this.onChange});

  final double factor;
  final bool busy;
  final ValueChanged<FlowAction> onChange;

  @override
  Widget build(BuildContext context) {
    final normal = factor == 1;
    final color = normal ? Aityx.muted : (factor > 1 ? Aityx.orange : Aityx.blue);
    final times = factor > 1
        ? (factor == 2 ? 'twice' : '${factor.round()} times')
        : switch ((1 / factor).round()) {
            2 => 'half',
            4 => 'a quarter',
            8 => 'an eighth',
            final n => '1/$n',
          };
    final says = normal ? 'People come here as usual.' : 'The visits headed here come $times as often.';
    return Card(
      key: const Key('flow-card'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // As tall with the reset as without, so the card doesn't jump.
            SizedBox(
              height: 32,
              child: Row(
              children: [
                const Icon(Icons.groups_outlined, color: Aityx.orange, size: 20),
                const SizedBox(width: 10),
                const Expanded(child: Text('Flow of people', style: TextStyle(fontWeight: FontWeight.w700))),
                if (busy)
                  const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                else if (!normal)
                  IconButton(
                    key: const Key('flow-reset'),
                    tooltip: 'Back to the normal flow',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                    onPressed: () => onChange(FlowAction.reset),
                    icon: const Icon(Icons.restart_alt, size: 20),
                  ),
              ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Flow ${flowLabel(factor)}',
              key: const Key('flow-factor'),
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: normal ? Aityx.fg0 : color),
            ),
            Text(says, style: const TextStyle(color: Aityx.muted, fontSize: 12)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Tooltip(
                  message: 'Twice as many arrivals here: the visits headed here come twice as often (up to ×8)',
                  child: FilledButton.tonalIcon(
                    key: const Key('flow-double'),
                    onPressed: busy || factor >= flowMax ? null : () => onChange(FlowAction.doubled),
                    icon: const Icon(Icons.keyboard_double_arrow_up),
                    label: const Text('Double the flow'),
                  ),
                ),
                Tooltip(
                  message: 'Half as many arrivals here: the visits headed here come half as often (down to ×1/8)',
                  child: OutlinedButton.icon(
                    key: const Key('flow-halve'),
                    onPressed: busy || factor <= flowMin ? null : () => onChange(FlowAction.halved),
                    icon: const Icon(Icons.keyboard_double_arrow_down),
                    label: const Text('Halve the flow'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Where it is: a map around it, its pin with how many are there now, and
/// the people on their way to it where they are.
class _CenterMap extends StatelessWidget {
  const _CenterMap(this.center, {required this.showTiles});

  final CareCenterDetail center;
  final bool showTiles;

  @override
  Widget build(BuildContext context) {
    final lat = center.lat;
    final lon = center.lon;
    if (lat == null || lon == null) {
      return const Card(child: _Message('The registry has no location for it, so it isn\'t on the map.'));
    }
    final at = LatLng(lat, lon);
    final coming = center.now.onTheWay;
    final points = [at, for (final p in coming) LatLng(p.lat, p.lon)];
    return Card(
      key: const Key('care-center-map'),
      clipBehavior: Clip.antiAlias,
      child: FlutterMap(
        options: MapOptions(
          initialCenter: at,
          initialZoom: 15,
          initialCameraFit: points.length > 1
              ? CameraFit.coordinates(coordinates: points, padding: const EdgeInsets.all(48), maxZoom: 16)
              : null,
          minZoom: 2,
          maxZoom: 19,
          backgroundColor: Aityx.bg0,
          interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
        ),
        children: [
          if (showTiles)
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'ai.aletyx.healthhub',
              tileBuilder: darkModeTileBuilder,
            ),
          MarkerLayer(
            markers: [
              for (final person in coming)
                Marker(
                  point: LatLng(person.lat, person.lon),
                  width: PersonPin.size,
                  height: PersonPin.size,
                  child: PersonPin(person, simTime: simWhen(center.now.day, center.now.simTime), key: Key('on-the-way-${person.id}')),
                ),
              Marker(
                point: at,
                width: 44,
                height: 44,
                child: _HerePin(center),
              ),
            ],
          ),
          if (showTiles)
            const SimpleAttributionWidget(
              source: Text('OpenStreetMap contributors'),
              backgroundColor: Color(0xAA17161A),
            ),
        ],
      ),
    );
  }
}

/// The care center's pin, as on home's map but not a link (this is its
/// view), with a badge of how many are there now.
class _HerePin extends StatelessWidget {
  const _HerePin(this.center);
  final CareCenterDetail center;

  @override
  Widget build(BuildContext context) {
    final inUse = center.now.inUse;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Center(
          child: SizedBox(
            width: 30,
            height: 30,
            child: CareCenterPin(
              CareCenter(
                id: center.id,
                name: center.name,
                kind: center.kind,
                lat: center.lat ?? 0,
                lon: center.lon ?? 0,
                subtype: center.subtype,
                address: center.address,
                phone: center.phone,
              ),
              opens: false,
            ),
          ),
        ),
        if (inUse > 0)
          Positioned(
            right: 0,
            top: 0,
            child: Container(
              key: const Key('here-badge'),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: PersonState.atHospital.color,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Aityx.bg0, width: 1.5),
              ),
              child: Text(
                '$inUse',
                style: const TextStyle(color: Aityx.bg0, fontSize: 11, fontWeight: FontWeight.w800),
              ),
            ),
          ),
      ],
    );
  }
}

/// The colour of how full it is: green, amber from 60%, red from 90%.
Color usageColor(double usage) => usage >= 0.9 ? Aityx.red : (usage >= 0.6 ? Aityx.amber : Aityx.green);

/// How much of its capacity is in use now, highlighted: "3 of 8 beds",
/// a bar in [usageColor], the share; who is on the way, how many have it
/// as their hospital; and that the capacity is the simulation's.
class UsageCard extends StatelessWidget {
  const UsageCard(this.center, {super.key});

  final CareCenterDetail center;

  @override
  Widget build(BuildContext context) {
    const muted = TextStyle(color: Aityx.muted, fontSize: 12);
    final now = center.now;
    final usage = now.usage;
    final color = usageColor(usage);
    return Container(
      key: const Key('usage-card'),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withValues(alpha: 0.18), Aityx.bg1],
        ),
        border: Border.all(color: color, width: 1.5),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bed_outlined, color: color, size: 22),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Capacity in use now',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Aityx.fg0),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 10,
            runSpacing: 4,
            children: [
              Text(
                '${now.inUse}',
                key: const Key('usage-in-use'),
                style: const TextStyle(fontSize: 40, height: 1, fontWeight: FontWeight.w800, color: Aityx.fg0),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'of ${center.capacity} ${center.unit}',
                  key: const Key('usage-capacity'),
                  style: const TextStyle(color: Aityx.fg, fontSize: 15),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: usage.clamp(0, 1).toDouble(),
              minHeight: 8,
              color: color,
              backgroundColor: Aityx.bg2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${(usage * 100).round()}% in use${usage > 1 ? ', over capacity' : ''}',
            key: const Key('usage-percent'),
            style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          if (now.enabled) ...[
            Text(
              [
                '${now.onTheWay.length} on the way',
                if (center.kind == CareCenterKind.hospital)
                  '${now.assigned} ${now.assigned == 1 ? 'person has' : 'people have'} it as their hospital',
              ].join(' · '),
              style: const TextStyle(color: Aityx.fg, fontSize: 12),
            ),
            if (now.simTime != null)
              Text(
                'Simulated time: ${simWhen(now.day, now.simTime)}',
                style: muted,
              ),
          ] else
            const Text('The simulation runs in dev mode only: nobody is here in prod.', style: muted),
          const SizedBox(height: 8),
          Text(
            'The capacity is the simulation\'s, sized to its few people a city: the registries don\'t say '
            'how many ${center.unit} a place has.',
            style: muted.copyWith(fontSize: 11),
          ),
        ],
      ),
    );
  }
}

/// Who is there now, and who is on the way, each a link to their view.
class _People extends StatelessWidget {
  const _People(this.center);
  final CareCenterDetail center;

  @override
  Widget build(BuildContext context) {
    final now = center.now;
    final String? none = !now.enabled
        ? 'The simulation runs in dev mode only.'
        : center.serves.isEmpty
        ? 'The simulation sends nobody to a ${center.subtype ?? center.kind.noun}: it sends people to health '
              'stations, urgent care, adult mental health and dialysis clinics, and general hospitals.'
        : null;
    return _Section(
      icon: Icons.groups_outlined,
      title: 'People here now',
      subtitle: 'and on their way, as the stream last said',
      child: none != null && now.here.isEmpty && now.onTheWay.isEmpty
          ? Text(none, style: const TextStyle(color: Aityx.muted))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (now.here.isEmpty && now.onTheWay.isEmpty)
                  const Text('Nobody is here or on the way now.', style: TextStyle(color: Aityx.muted)),
                for (final person in now.here) _PersonRow(person, center.kind),
                for (final person in now.onTheWay) _PersonRow(person, center.kind),
              ],
            ),
    );
  }
}

/// One person at the care center or on the way: their state's dot, who
/// (a link), their condition, what they are doing.
class _PersonRow extends StatelessWidget {
  const _PersonRow(this.person, this.kind);
  final Person person;

  /// The care center's kind, which they are going to or at.
  final CareCenterKind kind;

  @override
  Widget build(BuildContext context) {
    final color = person.state.color;
    return Container(
      key: Key('care-center-person-${person.id}'),
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border(left: BorderSide(color: color, width: 4)),
        borderRadius: const BorderRadius.horizontal(right: Radius.circular(6)),
      ),
      child: Row(
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
          const SizedBox(width: 10),
          Flexible(
            child: PersonLink(
              person.id,
              [person.name ?? person.id, if (person.age != null) '${person.age}'].join(', '),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              [
                if (person.conditionName != null)
                  [person.conditionName!, if (person.conditionType != null) '(${person.conditionType!.label})']
                      .join(' '),
                person.state.labelAt(kind),
              ].join(' · '),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Aityx.muted, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

/// Its admissions: counted in this run and in all, and the latest, each
/// with who (a link) and aityx's triage.
class _Admissions extends StatelessWidget {
  const _Admissions(this.center);
  final CareCenterDetail center;

  @override
  Widget build(BuildContext context) {
    final a = center.admissions;
    return _Section(
      icon: Icons.local_hospital,
      title: 'Admissions',
      subtitle: a.latestOfRun ? 'the latest of this run, with aityx\'s triage' : 'the latest of any run',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _Stat('${a.thisRun}', 'this run', key: const Key('admissions-this-run')),
              _Stat('${a.thisRunAcute} · ${a.thisRunChronic}', 'acute · chronic, this run'),
              _Stat('${a.total}', 'in all runs', key: const Key('admissions-total')),
            ],
          ),
          const SizedBox(height: 12),
          if (a.latest.isEmpty)
            const Text('No admissions recorded here.', style: TextStyle(color: Aityx.muted))
          else
            for (final admission in a.latest) AdmissionRow(admission, showPerson: true),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label, {super.key});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    width: 170,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Aityx.bg1,
      border: Border.all(color: Aityx.border),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Aityx.fg0)),
        Text(label, style: const TextStyle(color: Aityx.muted, fontSize: 12)),
      ],
    ),
  );
}
