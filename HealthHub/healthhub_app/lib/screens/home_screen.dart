import 'package:flutter/material.dart';

import '../app_version.dart';
import '../auth/auth_controller.dart';
import '../auth/user_menu.dart';
import '../location/location_controller.dart';
import '../location/user_location_map.dart';
import '../theme.dart';

/// Home: where the user lands after signing in. A dashboard of tiles; for
/// now one, the map with the user's position highlighted.
class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.auth,
    required this.location,
    this.showTiles = true,
  });

  final AuthController auth;
  final LocationController location;
  final bool showTiles;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(AppVersion.title),
      actions: [UserMenu(auth: auth), const SizedBox(width: 12)],
    ),
    body: CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 720,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 4 / 3,
            ),
            delegate: SliverChildListDelegate([
              _Tile(
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
                child: UserLocationMap(location: location, showTiles: showTiles),
              ),
            ]),
          ),
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
