import 'package:flutter/material.dart';

import '../aityx/player_keys.dart';
import '../theme.dart';
import 'enter.dart';
import 'files.dart';
import 'tour_api.dart';
import 'tour_session.dart';

/// The Profile tab: who is signed in and what the leaderboard calls them
/// (an alias, their name to begin with), the aityx key the player's table
/// runs on, both saved by one button, **Save profile**, and their
/// strategies in the tour, to upload or remove. Their own key (and,
/// optionally, its URL) goes here: it runs their table, their strategies
/// and their bots; without one, they can't play. Players never get the
/// host's key.
class ProfilePanel extends StatefulWidget {
  const ProfilePanel({super.key, required this.session});

  final TourSession session;

  @override
  State<ProfilePanel> createState() => _ProfilePanelState();
}

class _ProfilePanelState extends State<ProfilePanel> {
  late final _key = TextEditingController();
  final _alias = TextEditingController();
  bool _aliasFilled = false;
  String? _aliasShown;
  bool _saving = false;
  final _url = TextEditingController();
  String? _urlShown;
  bool _showKey = false;
  String? _problem;

  TourSession get s => widget.session;
  PlayerKeys get keys => s.keys;

  @override
  void dispose() {
    _key.dispose();
    _alias.dispose();
    _url.dispose();
    super.dispose();
  }

  /// **Save profile**: the name on the leaderboard when it changed, then
  /// the key when one was typed (or its URL changed); one message for both.
  Future<void> _saveProfile() async {
    final key = _key.text.trim();
    final url = _url.text.trim();
    if (url.isNotEmpty) {
      final parsed = Uri.tryParse(url);
      if (parsed == null || !parsed.isScheme('https') || parsed.host.isEmpty) {
        setState(() => _problem = 'The URL must be an https address, like ${keys.defaultUrl}.');
        return;
      }
    }
    final me = s.me;
    final alias = _alias.text.trim();
    final aliasChanged = me != null && alias != (me.alias ?? me.defaultName) && !(alias.isEmpty && me.alias == null);
    // A key typed in; or, with the player's own key, only its URL changed.
    final own = keys.ownKey;
    final newKey = key.isNotEmpty ? key : (own != null && url.isNotEmpty && url != _urlShown ? own : null);
    if (newKey == null && !aliasChanged) {
      setState(() => _problem = own == null ? 'Paste your aityx key first.' : null);
      if (own != null) _tell('Nothing changed.');
      return;
    }
    setState(() {
      _saving = true;
      _problem = null;
    });
    String? aliasProblem;
    if (aliasChanged) {
      try {
        // Their name is no alias: the leaderboard shows it anyway.
        await s.setAlias(alias == me.defaultName ? '' : alias);
      } on TourException catch (e) {
        aliasProblem = e.message;
      }
    }
    if (newKey != null) {
      keys.save(newKey, url: url);
      _key.clear();
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      _showKey = false;
    });
    _tell(
      [
        if (aliasChanged)
          aliasProblem != null
              ? 'Your name was not saved: $aliasProblem.'
              : 'The leaderboard calls you ${s.me?.alias ?? s.me?.defaultName ?? 'by your name'}.',
        if (newKey != null) 'Your key is set: your table runs on it from the next decision.',
      ].join(' '),
    );
  }

  void _tell(String text) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text)));

  Future<void> _remove(TourStrategy t) async {
    try {
      await s.withdraw(t.id);
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('${t.strategy.name} is out of the tour.')));
      }
    } on TourException catch (e) {
      if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  void _forget() {
    keys.forget();
    _url.text = _urlShown = keys.defaultUrl;
    setState(() => _problem = null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final user = s.auth.user;
        final source = keys.source;
        final me = s.me;
        // The alias as the server has it, else the name, into the field
        // when it arrives or changes (not while the player types).
        if (me != null && (!_aliasFilled || me.alias != _aliasShown)) {
          _aliasFilled = true;
          _aliasShown = me.alias;
          _alias.text = me.alias ?? me.defaultName;
        }
        // The URL the key goes to (the player's own, else this server's
        // aityx), into the field when it changes, unless the player typed
        // another.
        final urlNow = keys.ownUrl ?? keys.defaultUrl;
        if (urlNow != _urlShown) {
          final typed = _url.text.trim();
          if (typed.isEmpty || typed == _urlShown) _url.text = urlNow;
          _urlShown = urlNow;
        }
        return ListView(
          key: const Key('profile'),
          padding: const EdgeInsets.all(16),
          children: [
            if (user != null) ...[
              Row(
                children: [
                  if (user.picture != null)
                    CircleAvatar(radius: 20, backgroundImage: NetworkImage(user.picture!))
                  else
                    const CircleAvatar(radius: 20, child: Icon(Icons.person)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(child: Text(user.label, style: theme.textTheme.titleSmall, overflow: TextOverflow.ellipsis)),
                            if (s.admin) ...[
                              const SizedBox(width: 8),
                              _Badge(text: 'admin', color: Aityx.green),
                            ],
                          ],
                        ),
                        Text(user.email, style: muted, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    key: const Key('sign-out'),
                    onPressed: s.auth.signOut,
                    icon: const Icon(Icons.logout, size: 18),
                    label: const Text('Sign out'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('alias'),
                controller: _alias,
                enabled: me != null,
                maxLength: 32,
                decoration: InputDecoration(
                  labelText: 'Your name on the leaderboard',
                  hintText: me?.defaultName ?? user.label,
                  isDense: true,
                  counterText: '',
                ),
                onSubmitted: (_) => _saveProfile(),
              ),
              const Divider(height: 32),
            ],
            Text('Your aityx key', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Your table runs on it: your players, your strategies, your bots. '
              'Set yours to play.',
              style: muted,
            ),
            const SizedBox(height: 12),
            Container(
              key: const Key('demo-key-note'),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Aityx.amber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber, size: 18, color: Aityx.amber),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Use a key made for demos only. Never reuse a production key here.'),
                  ),
                ],
              ),
            ),
            if (s.needsKey) ...[
              const SizedBox(height: 12),
              Container(
                key: const Key('needs-key'),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.error.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  keys.key == null
                      ? 'There is no aityx key for your table yet. Set yours below to play.'
                      : 'aityx rejected ${keys.whose}. Set a key that works below.',
                ),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              key: const Key('own-key'),
              controller: _key,
              obscureText: !_showKey,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: source == KeySource.own ? 'Replace your key' : 'Your key',
                hintText: 'aityx_sk_…',
                isDense: true,
                suffixIcon: IconButton(
                  tooltip: _showKey ? 'Hide' : 'Show',
                  onPressed: () => setState(() => _showKey = !_showKey),
                  icon: Icon(_showKey ? Icons.visibility_off : Icons.visibility, size: 18),
                ),
              ),
              onSubmitted: (_) => _saveProfile(),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('own-url'),
              controller: _url,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'URL (optional)',
                hintText: keys.defaultUrl,
                isDense: true,
              ),
              onSubmitted: (_) => _saveProfile(),
            ),
            const SizedBox(height: 12),
            if (_problem != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_problem!, style: TextStyle(color: scheme.error)),
              ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  key: const Key('save-profile'),
                  onPressed: _saving ? null : _saveProfile,
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: const Text('Save profile'),
                ),
                if (source == KeySource.own)
                  OutlinedButton.icon(
                    key: const Key('forget-key'),
                    onPressed: _forget,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Forget my key'),
                  ),
              ],
            ),
            if (s.player != null) ...[
              const Divider(height: 32),
              Row(
                children: [
                  Expanded(child: Text('Your strategies in the tour', style: theme.textTheme.titleMedium)),
                  if (filesSupported)
                    TextButton.icon(
                      key: const Key('upload-strategy'),
                      onPressed: () => uploadToTour(context),
                      icon: const Icon(Icons.upload_file_outlined, size: 18),
                      label: const Text('Upload a strategy'),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              if (s.myStrategies.isEmpty)
                Text('None yet: upload one, or write one in Players and enter it.', style: muted)
              else
                for (final t in s.myStrategies)
                  ListTile(
                    key: Key('my-strategy-${t.id}'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(t.strategy.name),
                    subtitle: t.strategy.tagline.isEmpty ? null : Text(t.strategy.tagline, maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: IconButton(
                      key: Key('remove-${t.id}'),
                      tooltip: 'Remove it from the tour',
                      onPressed: () => _remove(t),
                      icon: const Icon(Icons.delete_outline, size: 20),
                    ),
                  ),
            ],
          ],
        );
      },
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: color)),
    child: Text(text, style: TextStyle(fontSize: 10, color: color)),
  );
}
