import 'package:flutter/material.dart';

import '../app_version.dart';
import '../auth/sign_in_button.dart';
import '../theme.dart';
import '../tour/leaderboard_panel.dart';
import '../tour/tour_session.dart';

/// The page before the table: what the tour is, the sign-in with Google,
/// and, under it, the leaderboard as it stands. Only accounts in the
/// tour's domains get to the table; the key comes from the host's S3
/// object once they're in.
class SignInScreen extends StatelessWidget {
  const SignInScreen({super.key, required this.session});

  final TourSession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.emoji_events, color: scheme.primary),
            const SizedBox(width: 10),
            const Text(AppVersion.title),
          ],
        ),
        actions: [
          if (AppVersion.version.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Text(
                  AppVersion.version,
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
                ),
              ),
            ),
        ],
      ),
      body: ListenableBuilder(
        listenable: session,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Card(
                  key: const Key('welcome'),
                  color: Aityx.bg1,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Welcome to the Poker Tour',
                          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "No-limit hold'em where every player is a set of rules run on "
                          'aityx. Play at your own table with your aityx key, write a '
                          'strategy, and enter it in the tour: the leaderboard plays '
                          'the strategies against each other four times a day, and '
                          'whenever an admin asks.',
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 16),
                        _Status(session: session),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: LeaderboardView(session: session),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.session});

  final TourSession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final auth = session.auth;
    final domains = session.config?.domains.join(' or ') ?? '';
    switch (session.stage) {
      case TourStage.loading:
        return Row(
          children: [
            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 10),
            Expanded(child: Text(session.error ?? 'Asking the server how to sign in…', style: muted)),
          ],
        );
      case TourStage.notConfigured:
        return Text(
          'The host hasn\'t set the tour up yet: the sign-in needs a Google client id '
          '(see the README). The leaderboard below still runs.',
          key: const Key('not-configured'),
          style: muted,
        );
      case TourStage.signIn:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sign in with your $domains account to play.', style: muted),
            const SizedBox(height: 12),
            if (auth.error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(auth.error!, style: TextStyle(color: scheme.error)),
              ),
            if (auth.ready) GoogleSignInButton(auth: auth) else const LinearProgressIndicator(),
          ],
        );
      case TourStage.notAllowed:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The tour is for $domains accounts; ${auth.user?.email ?? 'this account'} isn\'t one.',
              key: const Key('not-allowed'),
              style: TextStyle(color: scheme.error),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: auth.signOut,
              icon: const Icon(Icons.logout, size: 18),
              label: const Text('Sign out and try another'),
            ),
          ],
        );
      case TourStage.ready:
        return const SizedBox.shrink();
    }
  }
}
