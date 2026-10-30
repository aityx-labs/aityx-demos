import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../api/health_hub_api.dart';
import '../theme.dart';
import 'location_controller.dart';

/// Gives the care centers between the given degrees: the API's
/// `GET /api/care-centers`.
typedef CareCentersLoader =
    Future<CareCenters> Function({
      required double west,
      required double south,
      required double east,
      required double north,
    });

/// Gives the simulated people and the homes between the given degrees:
/// the API's `GET /api/people`.
typedef PeopleLoader =
    Future<People> Function({
      required double west,
      required double south,
      required double east,
      required double north,
    });

/// A map of OpenStreetMap's tiles, darkened to the aityx palette, with the
/// user's location highlighted: an orange dot in a white ring and a halo,
/// inside the circle of how sure the device is. It shows the whole world
/// until the location comes, then flies there; a button brings it back,
/// and two more zoom in and out. With [careCenters], the hospitals, clinics
/// and health stations in view are pinned on it, each kind with its own
/// icon and colour, and a legend says which is which. With [people], and
/// while the API runs its dev-mode simulation, the simulated people and
/// their homes are drawn too, and the legend tells the simulated time.
class UserLocationMap extends StatefulWidget {
  const UserLocationMap({
    super.key,
    required this.location,
    this.careCenters,
    this.people,
    this.showTiles = true,
    this.zoom = 14,
  });

  final LocationController location;

  /// Where the care centers come from; none are shown without it.
  final CareCentersLoader? careCenters;

  /// Where the simulated people come from; none are shown without it, or
  /// while it says the simulation is off.
  final PeopleLoader? people;

  /// Off in tests, which have no network for the tiles.
  final bool showTiles;

  /// How close to come once the location is known.
  final double zoom;

  @override
  State<UserLocationMap> createState() => _UserLocationMapState();
}

class _UserLocationMapState extends State<UserLocationMap> {
  static const _world = LatLng(20, 0);
  static const _minZoom = 2.0;
  static const _maxZoom = 19.0;

  final _map = MapController();
  bool _ready = false;
  bool _centred = false;

  /// The care centers of the last area asked, and whether there were more.
  CareCenters _centers = const CareCenters([]);
  Timer? _settle;

  /// Counts the asks, so an answer that arrives after a newer ask is dropped.
  int _asked = 0;

  /// The simulated people as last read, and the timer that reads them again.
  People _people = const People(enabled: false);
  Timer? _poll;
  bool _polling = false;
  bool _pollAgain = false;

  @override
  void initState() {
    super.initState();
    widget.location.addListener(_moved);
    _followPeople();
  }

  @override
  void didUpdateWidget(UserLocationMap old) {
    super.didUpdateWidget(old);
    if ((old.people == null) != (widget.people == null)) _followPeople();
  }

  @override
  void dispose() {
    widget.location.removeListener(_moved);
    _settle?.cancel();
    _poll?.cancel();
    _map.dispose();
    super.dispose();
  }

  /// Reads the people in view every 5 seconds while the map is shown, and
  /// once the view has settled after a move ([_viewChanged]). They move
  /// every turn, a second by default, but the map needn't follow each one.
  void _followPeople() {
    _poll?.cancel();
    _poll = null;
    if (widget.people == null) {
      _people = const People(enabled: false);
      return;
    }
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _loadPeople());
  }

  Future<void> _loadPeople() async {
    final load = widget.people;
    // Not before the map knows its view, and a slow answer isn't asked for
    // again on top of itself: a view that settles meanwhile is asked for
    // once it comes.
    if (load == null || !_ready) return;
    if (_polling) {
      _pollAgain = true;
      return;
    }
    _polling = true;
    try {
      final area = _area(_map.camera.visibleBounds);
      final people = await load(west: area.west, south: area.south, east: area.east, north: area.north);
      if (mounted && !_pollAgain) setState(() => _people = people);
    } catch (_) {
      // The API or Kafka may be down for a moment: keep what the map shows.
    } finally {
      _polling = false;
    }
    if (_pollAgain && mounted) {
      _pollAgain = false;
      await _loadPeople();
    }
  }

  /// Asks for the care centers and the people in view once the map has
  /// stood still for a moment, not on every frame of a drag.
  void _viewChanged(MapCamera camera) {
    if (widget.careCenters == null && widget.people == null) return;
    _settle?.cancel();
    _settle = Timer(const Duration(milliseconds: 400), () {
      _loadCentres(camera.visibleBounds);
      _loadPeople();
    });
  }

  /// [bounds] as the API takes an area: one span of longitudes (the world
  /// wraps around), within the poles.
  static ({double west, double south, double east, double north}) _area(LatLngBounds bounds) {
    final wraps = bounds.west > bounds.east || bounds.east - bounds.west >= 360;
    return (
      west: wraps ? -180 : math.max(-180, bounds.west),
      south: math.max(-90, bounds.south),
      east: wraps ? 180 : math.min(180, bounds.east),
      north: math.min(90, bounds.north),
    );
  }

  Future<void> _loadCentres(LatLngBounds bounds) async {
    final load = widget.careCenters;
    if (load == null) return;
    final ask = ++_asked;
    final area = _area(bounds);
    try {
      final centers = await load(west: area.west, south: area.south, east: area.east, north: area.north);
      if (mounted && ask == _asked) setState(() => _centers = centers);
    } catch (_) {
      // The API may not be up yet: keep what the map shows; the next move asks again.
    }
  }

  /// The first location found centres the map once; later ones only move
  /// the dot, so a user looking around isn't pulled back.
  void _moved() {
    if (!_centred && _ready && widget.location.location != null) _centre();
    setState(() {});
  }

  void _centre() {
    final here = widget.location.location;
    if (here == null) return;
    _map.move(here.point, widget.zoom);
    _centred = true;
  }

  void _zoomBy(double step) {
    final camera = _map.camera;
    _map.move(camera.center, (camera.zoom + step).clamp(_minZoom, _maxZoom));
  }

  @override
  Widget build(BuildContext context) {
    final here = widget.location.location;
    return Stack(
      children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: here?.point ?? _world,
            initialZoom: here != null ? widget.zoom : 2,
            minZoom: _minZoom,
            maxZoom: _maxZoom,
            backgroundColor: Aityx.bg0,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
            onMapReady: () {
              _ready = true;
              _centred = here != null;
              if (!_centred) _centre();
              _viewChanged(_map.camera);
            },
            onPositionChanged: (camera, _) => _viewChanged(camera),
          ),
          children: [
            if (widget.showTiles)
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'ai.aletyx.healthhub',
                tileBuilder: darkModeTileBuilder,
              ),
            if (_centers.centers.isNotEmpty)
              MarkerLayer(
                markers: [
                  for (final center in _centers.centers)
                    Marker(
                      point: LatLng(center.lat, center.lon),
                      width: 28,
                      height: 28,
                      child: CareCenterPin(center, key: Key('care-center-${center.id}')),
                    ),
                ],
              ),
            // Homes, then people above them, so someone at home stays visible.
            if (_people.enabled && _people.people.isNotEmpty) ...[
              MarkerLayer(
                markers: [
                  for (final person in _people.people)
                    Marker(
                      point: LatLng(person.homeLat, person.homeLon),
                      width: 16,
                      height: 16,
                      child: HomePin(person, key: Key('home-${person.id}')),
                    ),
                ],
              ),
              MarkerLayer(
                markers: [
                  for (final person in _people.people)
                    Marker(
                      point: LatLng(person.lat, person.lon),
                      width: 14,
                      height: 14,
                      child: PersonPin(person, simTime: _people.simTime, key: Key('person-${person.id}')),
                    ),
                ],
              ),
            ],
            if (here != null) ...[
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: here.point,
                    radius: here.accuracy,
                    useRadiusInMeter: true,
                    color: Aityx.orange.withValues(alpha: 0.12),
                    borderColor: Aityx.orange.withValues(alpha: 0.5),
                    borderStrokeWidth: 1,
                  ),
                ],
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: here.point,
                    width: 44,
                    height: 44,
                    child: const _YouAreHere(key: Key('you-are-here')),
                  ),
                ],
              ),
            ],
            if (widget.showTiles)
              const SimpleAttributionWidget(
                source: Text('OpenStreetMap contributors'),
                backgroundColor: Color(0xAA17161A),
              ),
          ],
        ),
        if (widget.careCenters != null || _people.enabled)
          Positioned(
            left: 12,
            bottom: 24,
            child: CareCenterLegend(
              truncated: _centers.truncated,
              careCenters: widget.careCenters != null,
              people: _people.enabled ? _people : null,
            ),
          ),
        Positioned(
          right: 12,
          bottom: 40,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton.filledTonal(
                key: const Key('zoom-in'),
                tooltip: 'Zoom in',
                onPressed: () => _zoomBy(1),
                icon: const Icon(Icons.add),
              ),
              IconButton.filledTonal(
                key: const Key('zoom-out'),
                tooltip: 'Zoom out',
                onPressed: () => _zoomBy(-1),
                icon: const Icon(Icons.remove),
              ),
              if (here != null) ...[
                const SizedBox(height: 8),
                IconButton.filledTonal(
                  key: const Key('recentre'),
                  tooltip: 'Back to where you are',
                  onPressed: _centre,
                  icon: const Icon(Icons.my_location),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The highlight: an orange dot in a white ring, in a soft orange halo.
class _YouAreHere extends StatelessWidget {
  const _YouAreHere({super.key});

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Aityx.orange.withValues(alpha: 0.25),
      ),
      alignment: Alignment.center,
      child: Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Aityx.orange,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 6)],
        ),
      ),
    ),
  );
}

/// How each kind of care center looks on the map.
extension CareCenterLook on CareCenterKind {
  IconData get icon => switch (this) {
    CareCenterKind.hospital => Icons.local_hospital,
    CareCenterKind.clinic => Icons.medical_services,
    CareCenterKind.healthStation => Icons.health_and_safety,
  };

  Color get color => switch (this) {
    CareCenterKind.hospital => Aityx.red,
    CareCenterKind.clinic => const Color(0xFF5B9BE6),
    CareCenterKind.healthStation => Aityx.green,
  };
}

/// A care center on the map: its kind's icon on its colour, in a white
/// ring. Tapping or hovering shows its name, type and address.
class CareCenterPin extends StatelessWidget {
  const CareCenterPin(this.center, {super.key});

  final CareCenter center;

  @override
  Widget build(BuildContext context) {
    final kind = center.kind;
    final details = [
      center.subtype ?? kind.label,
      if (center.address != null) center.address!,
      if (center.phone != null) center.phone!,
    ].join(' · ');
    return Tooltip(
      message: '${center.name}\n$details',
      triggerMode: TooltipTriggerMode.tap,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: kind.color,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 4)],
        ),
        alignment: Alignment.center,
        child: Icon(kind.icon, size: 15, color: Colors.white, semanticLabel: kind.label),
      ),
    );
  }
}

/// How a simulated person looks in each state: colours apart from the
/// orange of the user and the red, blue and green of the care centers.
extension PersonLook on PersonState {
  Color get color => switch (this) {
    PersonState.home => const Color(0xFFF2EEE4),
    PersonState.toHospital => Aityx.amber,
    PersonState.atHospital => const Color(0xFFB07CE8),
    PersonState.toHome => const Color(0xFF4FD3E8),
  };
}

/// A simulated person's home: a small muted house.
class HomePin extends StatelessWidget {
  const HomePin(this.person, {super.key});

  final Person person;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Home of ${person.id}',
    triggerMode: TooltipTriggerMode.tap,
    child: Icon(Icons.home, size: 14, color: Aityx.muted.withValues(alpha: 0.85), semanticLabel: 'Home'),
  );
}

/// A simulated person: a small dot in their state's colour, in a dark ring
/// (the care centers' rings are white). Tapping or hovering shows who they
/// are (with their name and age when the record carries them), their
/// condition, what they are doing, their hospital and the simulated time.
class PersonPin extends StatelessWidget {
  const PersonPin(this.person, {super.key, this.simTime});

  final Person person;
  final String? simTime;

  @override
  Widget build(BuildContext context) {
    final details = [
      person.state.label,
      if (person.hospitalName != null) person.hospitalName!,
      ?simTime,
    ].join(' · ');
    final who = person.name == null
        ? person.id
        : [person.name!, if (person.age != null) '${person.age}', person.id].join(', ');
    final condition = person.conditionName == null
        ? null
        : [person.conditionName!, if (person.conditionType != null) '(${person.conditionType!.label})'].join(' ');
    return Tooltip(
      message: [who, ?condition, details].join('\n'),
      triggerMode: TooltipTriggerMode.tap,
      child: Semantics(
        label: 'Person, ${person.state.label}',
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: person.state.color,
            border: Border.all(color: Aityx.bg0, width: 2),
            boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 3)],
          ),
        ),
      ),
    );
  }
}

/// Which icon is which, and a hint to zoom in when the area holds more care
/// centers than the API gives at once. With [people] (the simulation on),
/// also the homes, a person in each state, and the simulated time.
class CareCenterLegend extends StatelessWidget {
  const CareCenterLegend({super.key, this.truncated = false, this.careCenters = true, this.people});

  final bool truncated;

  /// Whether the care centers' entries show.
  final bool careCenters;
  final People? people;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('care-center-legend'),
    padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
    decoration: BoxDecoration(
      color: Aityx.bg1.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Aityx.border),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (careCenters)
          for (final kind in CareCenterKind.values) _entry(Icon(kind.icon, size: 14, color: kind.color), kind.label),
        if (careCenters && truncated)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('Zoom in to see them all', style: TextStyle(fontSize: 11, color: Aityx.muted)),
          ),
        if (people case final people?) ...[
          _entry(Icon(Icons.home, size: 14, color: Aityx.muted.withValues(alpha: 0.85)), 'Home'),
          for (final state in PersonState.values)
            _entry(
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.all(2),
                decoration: BoxDecoration(shape: BoxShape.circle, color: state.color),
              ),
              'Person, ${state.label.toLowerCase()}',
            ),
          if (people.simTime != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Simulated time ${people.simTime}${people.day != null ? ', day ${people.day}' : ''}',
                key: const Key('sim-time'),
                style: const TextStyle(fontSize: 11, color: Aityx.muted),
              ),
            ),
        ],
      ],
    ),
  );

  static Widget _entry(Widget mark, String label) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12, color: Aityx.fg)),
      ],
    ),
  );
}
