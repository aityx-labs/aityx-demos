import 'package:flutter/material.dart';

import '../app_version.dart';
import '../request/request_box.dart';
import '../request/voice_input.dart';
import '../routing/routing.dart';
import '../routing/routing_screen.dart';

/// The app's home: the name, a one-line welcome, the request box (typed
/// or dictated, then routed) and, when the build sets it, the version.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key, this.voice, this.router});

  /// Passed on to the request box.
  final VoiceInput? voice;

  /// Passed on to the routing screen.
  final RequestRouter? router;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.forum_outlined,
                    size: 72,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Welcome to Contact Hub',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Ask anything, and we get it to the right person.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 32),
                  RequestBox(
                    voice: voice,
                    onSubmit: (request) => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            RoutingScreen(message: request, router: router),
                      ),
                    ),
                  ),
                  if (AppVersion.version.isNotEmpty) ...[
                    const SizedBox(height: 32),
                    Text(
                      AppVersion.version,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
