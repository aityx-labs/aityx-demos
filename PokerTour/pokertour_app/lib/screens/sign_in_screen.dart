import 'package:flutter/material.dart';

import '../api/preview_poker_api.dart';
import '../app_version.dart';
import '../auth/sign_in_button.dart';
import '../game/controller.dart';
import '../table/controls_bar.dart';
import '../table/table_view.dart';
import '../theme.dart';
import '../tour/leaderboard_panel.dart';
import '../tour/links.dart';
import '../tour/tour_session.dart';

/// The page before the table: the table itself, seated with the presets,
/// and its controls, under a veil that takes every click; on the veil,
/// what the tour is, the sign-in with Google, and the leaderboard as it
/// stands. Only accounts in the tour's domains get to the table; they
/// play on their own aityx key.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, required this.session});

  final TourSession session;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  TourSession get session => widget.session;

  /// The table behind the veil: never played.
  final GameController _preview = GameController(api: PreviewPokerApi());

  @override
  void initState() {
    super.initState();
    _preview.load();
  }

  @override
  void dispose() {
    _preview.dispose();
    super.dispose();
  }

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
      body: Stack(
        children: [
          // The table and its controls, out of reach: no pointer, no
          // focus, nothing for a screen reader.
          Positioned.fill(
            key: const Key('table-preview'),
            child: ExcludeSemantics(
              child: ExcludeFocus(
                child: IgnorePointer(
                  child: ListenableBuilder(
                    listenable: _preview,
                    builder: (context, _) => Column(
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: TableView(controller: _preview),
                          ),
                        ),
                        ControlsBar(controller: _preview, onPlayers: () {}),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: ColoredBox(
              key: const Key('sign-in-veil'),
              color: Aityx.bg0.withValues(alpha: 0.72),
              child: _welcome(context),
            ),
          ),
        ],
      ),
    );
  }

  /// On the veil: the welcome with the sign-in, and the leaderboard.
  Widget _welcome(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
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
                        'the strategies against each other four times a day, '
                        'whenever a strategy is entered, and whenever an admin asks.',
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
    final allowed = session.config?.domains ?? const <String>[];
    final domains = allowed.contains('*') ? 'Google' : allowed.join(' or ');
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
            const SizedBox(height: 8),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('By signing in you agree to the', style: muted),
                TextButton(key: const Key('terms'), onPressed: () => openPage('tos'), child: const Text('Terms')),
                Text('and the', style: muted),
                TextButton(key: const Key('privacy'), onPressed: () => openPage('privacy'), child: const Text('Privacy Policy')),
              ],
            ),
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
