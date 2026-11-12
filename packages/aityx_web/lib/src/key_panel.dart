/// The key, set, changed or forgotten in the app: a panel over it.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'check.dart';
import 'connection.dart';
import 'key_page.dart';
import 'key_store.dart';
import 'platform/platform_vm.dart'
    if (dart.library.js_interop) 'platform/platform_web.dart'
    as platform;
import 'settings.dart';

/// Whether the key panel is open: one at a time.
bool _open = false;

/// Opens the key panel over the app, where the user sets, changes or
/// forgets their aityx key without leaving for the index page; completes
/// when it closes. The status light opens it on a tap; an app can too,
/// from any [context] under MaterialApp.
///
/// The panel is in the app's topmost Overlay, so it needs no Navigator:
/// the light sits above the app's.
///
/// Embedded in another page (`?embed=1`), nothing opens: the app asks the
/// page around it for the key instead ([aityxKeyMessage]), as before.
Future<void> openAityxKey(
  BuildContext context, {
  http.Client? client,
  AityxKeyStore? store,
  Uri? origin,
  VoidCallback? onSaved,
}) {
  if (aityxEmbedded) {
    platform.postToParent(aityxKeyMessage);
    return Future.value();
  }
  if (_open) return Future.value();
  final overlay = Overlay.of(context, rootOverlay: true);
  final closed = Completer<void>();
  late final OverlayEntry entry;
  void close() {
    if (closed.isCompleted) return;
    closed.complete();
    _open = false;
    entry
      ..remove()
      ..dispose();
  }

  entry = OverlayEntry(
    builder: (context) => _Over(
      onClose: close,
      child: AityxKeyPanel(
        client: client,
        store: store,
        origin: origin,
        onSaved: onSaved,
        onClose: close,
      ),
    ),
  );
  _open = true;
  overlay.insert(entry);
  return closed.future;
}

/// [child] in the middle, over a barrier that closes on a tap, as Escape
/// does.
class _Over extends StatefulWidget {
  const _Over({required this.onClose, required this.child});

  final VoidCallback onClose;
  final Widget child;

  @override
  State<_Over> createState() => _OverState();
}

class _OverState extends State<_Over> {
  @override
  void dispose() {
    // Gone with the app around it (a hot restart, a test's end) without
    // being closed: the next tap opens a new one.
    _open = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
    },
    child: FocusScope(
      autofocus: true,
      child: Stack(
        children: [
          Positioned.fill(
            // The app behind is out of reach of assistive technology too.
            child: BlockSemantics(
              child: Semantics(
                button: true,
                label: 'Close the key panel',
                child: GestureDetector(
                  key: const ValueKey('aityx-panel-barrier'),
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onClose,
                  child: const ColoredBox(color: Color(0x99000000)),
                ),
              ),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: widget.child,
            ),
          ),
        ],
      ),
    ),
  );
}

/// "Your aityx key": which key is in use, a field for a new one (with the
/// aityx URL, optionally), **Check and save**, **Forget key** and
/// **Close**, and a link to the aityx console, where keys are made.
///
/// **Check and save** asks aityx whether it accepts the key (one empty
/// call, which runs no model) and saves only one it accepts, the way the
/// index page does: in the browser's storage, as `aityx.key` (with
/// `aityx.url`), where the index page and every demo of the origin read
/// it. A key kept "only this session" stays so. **Forget key** removes it
/// from the browser, for every demo.
///
/// Shown by [openAityxKey]; a widget of its own so an app can also put it
/// in a page.
class AityxKeyPanel extends StatefulWidget {
  const AityxKeyPanel({
    super.key,
    this.client,
    this.store,
    this.origin,
    this.onSaved,
    this.onClose,
    this.maxWidth = 440,
  });

  /// The HTTP client for the check, and for asking the index server
  /// whether it has a dev key: a new one each time unless given.
  final http.Client? client;

  /// The key store: AityxSettings.store unless given.
  final AityxKeyStore? store;

  /// The page's origin: Uri.base unless given.
  final Uri? origin;

  /// Called once a key is saved, before the panel closes.
  final VoidCallback? onSaved;

  /// Closes the panel: after a save, and from **Close**. Without one
  /// there's no **Close**, and the panel stays after a save.
  final VoidCallback? onClose;

  /// The panel's width, at most.
  final double maxWidth;

  @override
  State<AityxKeyPanel> createState() => _AityxKeyPanelState();
}

class _AityxKeyPanelState extends State<AityxKeyPanel> {
  late final AityxKeyStore _keys = widget.store ?? AityxSettings.store;
  StreamSubscription<void>? _changes;
  final _key = TextEditingController();
  late final _url = TextEditingController(text: _storedUrl);

  /// The key field's focus: it has the keyboard as soon as the panel is up.
  final _keyFocus = FocusNode();

  /// Whether the index server lends a dev key; null until it has said.
  bool? _dev;
  bool _checking = false;

  /// What happened, and whether it's bad news.
  String? _said;
  bool _bad = false;

  /// The stored URL, when it isn't aityx's own: what the field starts with.
  String get _storedUrl {
    final url = _keys.url;
    return url == null || url == aityxDefaultUrl ? '' : url;
  }

  @override
  void initState() {
    super.initState();
    // Another tab (the index page, another demo) may change the key meanwhile.
    _changes = _keys.changes.listen((_) {
      if (mounted) setState(() {});
    });
    unawaited(_lookForDevKey());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _keyFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _changes?.cancel();
    _key.dispose();
    _url.dispose();
    _keyFocus.dispose();
    super.dispose();
  }

  /// Asks the index server whether it lends a key (no call to aityx).
  Future<void> _lookForDevKey() async {
    final connection = await AityxSettings.resolve(
      client: widget.client,
      origin: widget.origin,
      store: AityxKeyStore.memory(),
    );
    if (mounted) setState(() => _dev = connection.source == AityxSource.dev);
  }

  /// Which key is in use, for people. Never the key: its last four
  /// characters at most.
  String get _status {
    final key = _keys.key;
    if (key != null) {
      final tail = key.length <= 8 ? '' : ' …${key.substring(key.length - 4)}';
      final where = _keys.sessionOnly ? 'for this session' : 'on this device';
      final url = _keys.url;
      final to = url == null || url == aityxDefaultUrl ? '' : ', for $url';
      return 'Your key$tail is set, $where$to.';
    }
    return switch (_dev) {
      null => 'Looking for a key…',
      true => 'No key of yours: this server lends its dev key.',
      false => 'No key yet.',
    };
  }

  void _say(String said, {bool bad = true}) => setState(() {
    _said = said;
    _bad = bad;
  });

  Future<void> _save() async {
    if (_checking) return;
    final key = _key.text.trim();
    if (key.isEmpty) return _say('Paste your key first.');
    if (key.contains(RegExp(r'\s'))) {
      return _say("That doesn't look like a key: it has spaces in it.");
    }
    final url = cleanAityxUrl(_url.text);
    if (url == null) {
      return _say(
        'The URL must be an https URL on aityx.ai, like $aityxDefaultUrl.',
      );
    }
    setState(() {
      _checking = true;
      _said = null;
    });
    final state = await checkAityx(
      client: widget.client,
      connection: AityxConnection.user(key, url: url),
    );
    if (!mounted) return;
    if (!state.ok) {
      final why = switch (state.kind) {
        AityxStateKind.rejected => 'aityx rejected the key',
        AityxStateKind.unreachable =>
          'aityx did not answer (the network, or the URL is wrong)',
        _ => state.detail,
      };
      setState(() {
        _checking = false;
        _said = '$why. Not saved.';
        _bad = true;
      });
      return;
    }
    // A key kept for this session only stays so.
    _keys.save(key, url: url, sessionOnly: _keys.sessionOnly);
    if (_keys.key != key) {
      // The browser refused the storage (blocked, some private modes).
      setState(() {
        _checking = false;
        _said = 'aityx accepts the key, but this browser could not save it.';
        _bad = true;
      });
      return;
    }
    setState(() {
      _checking = false;
      _said = 'Saved: aityx accepts the key. Every aityx demo here uses it.';
      _bad = false;
      _key.clear();
    });
    widget.onSaved?.call();
    widget.onClose?.call();
  }

  void _forget() {
    _keys.forget();
    _key.clear();
    _url.clear();
    _say('Forgotten: no key of yours in this browser.', bad: false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final small = theme.textTheme.bodySmall;
    const border = OutlineInputBorder();
    final hasKey = _keys.key != null;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: widget.maxWidth),
      child: Material(
        key: const ValueKey('aityx-panel'),
        color: scheme.surfaceContainerHigh,
        elevation: 8,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  'Your aityx key',
                  style: theme.textTheme.titleLarge,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _status,
                key: const ValueKey('aityx-panel-status'),
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'One key for every aityx demo: it stays in this browser, '
                'where they all read it, and goes only to aityx.',
                style: small?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('aityx-panel-key'),
                controller: _key,
                focusNode: _keyFocus,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                enabled: !_checking,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _save(),
                decoration: InputDecoration(
                  labelText: hasKey ? 'A new key' : 'Your aityx key',
                  isDense: true,
                  border: border,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('aityx-panel-url'),
                controller: _url,
                autocorrect: false,
                enableSuggestions: false,
                enabled: !_checking,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _save(),
                decoration: const InputDecoration(
                  labelText: 'URL (optional)',
                  hintText: aityxDefaultUrl,
                  isDense: true,
                  border: border,
                ),
              ),
              if (_said case final said?)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      said,
                      key: const ValueKey('aityx-panel-said'),
                      style: small?.copyWith(
                        color: _bad ? scheme.error : scheme.primary,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton(
                    key: const ValueKey('aityx-panel-save'),
                    onPressed: _checking ? null : _save,
                    child: Text(_checking ? 'Checking…' : 'Check and save'),
                  ),
                  TextButton(
                    key: const ValueKey('aityx-panel-forget'),
                    onPressed: hasKey && !_checking ? _forget : null,
                    child: const Text('Forget key'),
                  ),
                  if (widget.onClose case final close?)
                    TextButton(
                      key: const ValueKey('aityx-panel-close'),
                      onPressed: close,
                      child: const Text('Close'),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Semantics(
                  link: true,
                  child: InkWell(
                    key: const ValueKey('aityx-panel-console'),
                    onTap: () =>
                        platform.openNewTab(Uri.parse(aityxConsoleUrl)),
                    child: Text(
                      'Get a key in the aityx console',
                      style: small?.copyWith(
                        color: scheme.primary,
                        decoration: TextDecoration.underline,
                        decorationColor: scheme.primary,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
