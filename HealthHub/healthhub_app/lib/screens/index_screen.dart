import 'package:flutter/material.dart';

import '../app_version.dart';
import '../auth/auth_controller.dart';
import '../auth/sign_in_button.dart';
import '../location/location_controller.dart';
import '../location/user_location_map.dart';
import '../theme.dart';

/// The index: the page for someone not signed in. A map filling the
/// screen with the user's location highlighted, and over it a card that
/// welcomes them and holds the sign-in. Signing in leads home.
class IndexScreen extends StatelessWidget {
  const IndexScreen({
    super.key,
    required this.auth,
    required this.location,
    this.careCenters,
    this.people,
    this.showTiles = true,
  });

  final AuthController auth;
  final LocationController location;

  /// Where the map's care centers come from: the API.
  final CareCentersLoader? careCenters;

  /// Where the map's simulated people come from: the API.
  final PeopleLoader? people;
  final bool showTiles;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Stack(
      children: [
        Positioned.fill(
          child: UserLocationMap(
            location: location,
            careCenters: careCenters,
            people: people,
            showTiles: showTiles,
          ),
        ),
        SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: _Welcome(auth: auth, location: location),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

/// The overlay: the welcome, where the location stands, the sign-in.
class _Welcome extends StatelessWidget {
  const _Welcome({required this.auth, required this.location});

  final AuthController auth;
  final LocationController location;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: const Key('welcome'),
      color: Aityx.bg1.withValues(alpha: 0.92),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.favorite, color: Aityx.orange),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Welcome to HealthHub',
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ListenableBuilder(
              listenable: location,
              builder: (context, _) => _LocationLine(location: location),
            ),
            ListenableBuilder(
              listenable: auth,
              builder: (context, _) {
                if (!auth.enabled) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (auth.ready) GoogleSignInButton(auth: auth),
                      if (auth.error != null)
                        Text(auth.error!, style: const TextStyle(color: Aityx.red, fontSize: 12)),
                    ],
                  ),
                );
              },
            ),
            if (AppVersion.version.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  'HealthHub ${AppVersion.version}',
                  style: const TextStyle(color: Aityx.dim, fontSize: 11),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One line on where the location stands, with a retry when it failed.
class _LocationLine extends StatelessWidget {
  const _LocationLine({required this.location});

  final LocationController location;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(color: Aityx.muted);
    switch (location.status) {
      case LocationStatus.asking:
        return const Text('Finding where you are…', style: style);
      case LocationStatus.found:
        return const Text('The orange dot is you.', style: style);
      case LocationStatus.denied:
      case LocationStatus.unavailable:
        return Row(
          children: [
            Expanded(child: Text(location.message ?? 'No location.', style: style)),
            TextButton(onPressed: location.start, child: const Text('Try again')),
          ],
        );
    }
  }
}
