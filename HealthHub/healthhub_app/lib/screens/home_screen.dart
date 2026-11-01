import 'package:flutter/material.dart';

import '../app_version.dart';
import '../auth/auth_controller.dart';
import '../auth/user_menu.dart';
import '../care_centers/occupancy_timeline.dart';
import '../care_centers/care_center_screen.dart';
import '../events/stream_events.dart';
import '../location/location_controller.dart';
import '../location/user_location_map.dart';
import '../people/person_screen.dart';
import '../theme.dart';
import '../triage/triage_card.dart';
import 'explainers.dart';

/// Home: where the user lands after signing in. A dashboard in rows: the
/// map with the user's position highlighted, and beside it what the data
/// and the simulation are ([SimulationExplainer]); aityx's triage at the
/// desk, and beside it what aityx does ([AityxExplainer]); the latest
/// events. Below [wideFrom] wide, each explainer goes under its row.
/// With [person] and [prediction], every person it names (on the map, in
/// the events and the triage) opens their view ([PersonOpener]); with
/// [careCenter], every care center (a pin on the map, a hospital in the
/// events and the triage) opens its view ([CareCenterOpener]), which plots
/// its people in care per hour with [careCenterOccupancy] and
/// [occupancyForecast].
class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.auth,
    required this.location,
    this.careCenters,
    this.nearest,
    this.people,
    this.events,
    this.triage,
    this.triageDetail,
    this.person,
    this.prediction,
    this.careCenter,
    this.careCenterOccupancy,
    this.occupancyForecast,
    this.simulation,
    this.showTiles = true,
  });

  /// From how wide the explainers sit beside their rows, and how wide.
  static const wideFrom = 1000.0;
  static const explainerWidth = 340.0;

  final AuthController auth;
  final LocationController location;

  /// Where the map's care centers come from: the API.
  final CareCentersLoader? careCenters;

  /// Where the care center nearest the user comes from, which the map
  /// centres on: the API.
  final NearestCareCenterLoader? nearest;

  /// Where the map's simulated people come from: the API.
  final PeopleLoader? people;

  /// Where the latest events on the stream come from, under the map.
  final EventsLoader? events;

  /// Where aityx's triage of the admissions comes from, under the map.
  final TriageLoader? triage;
  final TriageDetailLoader? triageDetail;

  /// Where a person's view comes from: the API, and datyx through it.
  final PersonLoader? person;
  final PredictionLoader? prediction;

  /// Where a care center's view comes from: the API, and its admissions
  /// per hour, with datyx's forecast of them through it.
  final CareCenterLoader? careCenter;
  final HourlyOccupancyLoader? careCenterOccupancy;
  final OccupancyForecastLoader? occupancyForecast;

  /// Pauses or resumes the simulation, from the events.
  final SimulationControl? simulation;
  final bool showTiles;

  @override
  Widget build(BuildContext context) {
    var home = _scaffold(context);
    if (careCenter != null) {
      home = CareCenterOpener(
        load: careCenter!,
        occupancy: careCenterOccupancy,
        forecast: occupancyForecast,
        showTiles: showTiles,
        child: home,
      );
    }
    if (person == null || prediction == null) return home;
    return PersonOpener(person: person!, prediction: prediction!, child: home);
  }

  /// [main] with [side] to its right when the window is wide, under it
  /// when it isn't.
  static Widget _row(BuildContext context, Widget main, Widget side) => MediaQuery.sizeOf(context).width >= wideFrom
      ? Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: main),
            const SizedBox(width: 16),
            SizedBox(width: explainerWidth, child: side),
          ],
        )
      : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [main, const SizedBox(height: 16), side]);

  Widget _scaffold(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(AppVersion.title),
      actions: [UserMenu(auth: auth), const SizedBox(width: 12)],
    ),
    body: CustomScrollView(
      slivers: [
        // The map takes the whole width and most of the window's height:
        // it is what home is about, so it gets more room than a grid
        // tile would give it.
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverToBoxAdapter(
            child: _row(
              context,
              SizedBox(
                height: (MediaQuery.sizeOf(context).height * 0.78).clamp(520.0, 1100.0),
                child: _Tile(
                  key: const Key('location-tile'),
                  icon: Icons.my_location,
                  title: 'Where you are',
                  subtitle: ListenableBuilder(
                    listenable: location,
                    builder: (context, _) => Text(
                      switch (location.status) {
                        LocationStatus.asking => 'Finding where you are…',
                        LocationStatus.found => 'The orange dot is you.',
                        _ => location.message ?? 'No location.',
                      },
                      style: const TextStyle(color: Aityx.muted, fontSize: 12),
                    ),
                  ),
                  child: UserLocationMap(
                    location: location,
                    careCenters: careCenters,
                    nearest: nearest,
                    people: people,
                    showTiles: showTiles,
                  ),
                ),
              ),
              const SimulationExplainer(),
            ),
          ),
        ),
        if (triage != null && triageDetail != null)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            sliver: SliverToBoxAdapter(
              child: _row(context, TriageCard(triage: triage!, detail: triageDetail!), const AityxExplainer()),
            ),
          ),
        if (events != null)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            sliver: SliverToBoxAdapter(child: StreamEventsCard(events: events!, simulation: simulation)),
          ),
        if (AppVersion.version.isNotEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Center(
                child: Text(
                  'HealthHub ${AppVersion.version}',
                  style: TextStyle(color: Aityx.dim, fontSize: 11),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

/// A dashboard tile: a header with an icon, a title and a status line,
/// and its content filling the rest.
class _Tile extends StatelessWidget {
  const _Tile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Icon(icon, color: Aityx.orange, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle,
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(child: child),
      ],
    ),
  );
}
