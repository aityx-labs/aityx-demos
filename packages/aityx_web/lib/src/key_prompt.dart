/// The key, asked for in the app: a small form, only while there is none.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'check.dart';
import 'connection.dart';
import 'key_store.dart';
import 'platform/platform_vm.dart'
    if (dart.library.js_interop) 'platform/platform_web.dart'
    as platform;
import 'settings.dart';

/// A small form for the user's aityx key, for an app to put where it calls
/// aityx: the key, optionally the aityx URL, **Save**, and a link to the
/// aityx console, where keys are made.
///
/// It takes no room at all while there is a key: the user's, set here or
/// on the index page, or the index server's dev key. It shows only when
/// there is none, and goes away once a key is saved.
///
/// **Save** checks the key with aityx first (one empty call, which runs no
/// model) and saves only a key aityx accepts, the way the index page does:
/// in localStorage, as `aityx.key` (with `aityx.url`), where the index
/// page and every demo of the origin read it.
class AityxKeyPrompt extends StatefulWidget {
  const AityxKeyPrompt({
    super.key,
    this.client,
    this.store,
    this.origin,
    this.onSaved,
    this.padding = EdgeInsets.zero,
    this.alignment = Alignment.center,
    this.maxWidth = 560,
  });

  /// The HTTP client for the check, and for asking the index server
  /// whether it has a dev key: a new one each time unless given.
  final http.Client? client;

  /// The key store: AityxSettings.store unless given.
  final AityxKeyStore? store;

  /// The page's origin: Uri.base unless given.
  final Uri? origin;

  /// Called once a key is saved: the app can run the call that needed it.
  final VoidCallback? onSaved;

  /// Around the form, only while it shows.
  final EdgeInsetsGeometry padding;

  /// Where the form sits when there's more room than [maxWidth].
  final AlignmentGeometry alignment;

  /// The form's width, at most.
  final double maxWidth;

  @override
  State<AityxKeyPrompt> createState() => _AityxKeyPromptState();
}

class _AityxKeyPromptState extends State<AityxKeyPrompt> {
  late AityxKeyStore _keys;
  StreamSubscription<void>? _changes;
  late final AppLifecycleListener _lifecycle;
  final _key = TextEditingController();
  final _url = TextEditingController();

  /// Whether there's no key anywhere: false until the first look says so.
  bool _needed = false;

  /// Counts the looks, so a slow one doesn't overwrite a later one.
  int _look = 0;
  bool _checking = false;
  String? _problem;

  @override
  void initState() {
    super.initState();
    _listen();
    // Back to the tab: the dev key may have turned up.
    _lifecycle = AppLifecycleListener(onResume: _lookForKey);
    _lookForKey();
  }

  void _listen() {
    _keys = widget.store ?? AityxSettings.store;
    _changes = _keys.changes.listen((_) => _lookForKey());
  }

  @override
  void didUpdateWidget(AityxKeyPrompt oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      _changes?.cancel();
      _listen();
      _lookForKey();
    }
  }

  @override
  void dispose() {
    _changes?.cancel();
    _lifecycle.dispose();
    _key.dispose();
    _url.dispose();
    super.dispose();
  }

  /// Whether the form is needed: with a key in the store it isn't, and
  /// nothing is asked; without one, the index server says whether it
  /// lends its own (no call to aityx, so nothing of the user's quota).
  Future<void> _lookForKey() async {
    final look = ++_look;
    var needed = false;
    if (_keys.key == null) {
      final connection = await AityxSettings.resolve(
        client: widget.client,
        origin: widget.origin,
        store: _keys,
      );
      needed = connection.source == AityxSource.none;
    }
    if (!mounted || look != _look || needed == _needed) return;
    setState(() {
      _needed = needed;
      if (!needed) {
        // Nothing typed is kept once the form is gone.
        _key.clear();
        _problem = null;
      }
    });
  }

  void _say(String problem) => setState(() => _problem = problem);

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
      _problem = null;
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
        _problem = '$why. Not saved.';
      });
      return;
    }
    _keys.save(key, url: url);
    if (_keys.key != key) {
      // The browser refused the storage (blocked, some private modes).
      setState(() {
        _checking = false;
        _problem = 'aityx accepts the key, but this browser could not save it.';
      });
      return;
    }
    setState(() {
      _checking = false;
      _needed = false;
      _problem = null;
      _key.clear();
    });
    widget.onSaved?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (!_needed) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final small = theme.textTheme.bodySmall;
    const border = OutlineInputBorder();
    final key = TextField(
      key: const ValueKey('aityx-key-field'),
      controller: _key,
      obscureText: true,
      autocorrect: false,
      enableSuggestions: false,
      enabled: !_checking,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _save(),
      decoration: const InputDecoration(
        labelText: 'Your aityx key',
        isDense: true,
        border: border,
      ),
    );
    final url = TextField(
      key: const ValueKey('aityx-url-field'),
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
    );
    final save = FilledButton(
      key: const ValueKey('aityx-key-save'),
      onPressed: _checking ? null : _save,
      child: Text(_checking ? 'Checking…' : 'Save'),
    );
    return Padding(
      padding: widget.padding,
      child: Align(
        alignment: widget.alignment,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: widget.maxWidth),
          // Its own Material, for the fields, wherever the app puts it.
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) => constraints.maxWidth >= 440
                      ? Row(
                          children: [
                            Expanded(flex: 3, child: key),
                            const SizedBox(width: 8),
                            Expanded(flex: 2, child: url),
                            const SizedBox(width: 8),
                            save,
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            key,
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(child: url),
                                const SizedBox(width: 8),
                                save,
                              ],
                            ),
                          ],
                        ),
                ),
                if (_problem case final problem?)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        problem,
                        style: small?.copyWith(color: scheme.error),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Semantics(
                    link: true,
                    child: InkWell(
                      key: const ValueKey('aityx-console-link'),
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
      ),
    );
  }
}
