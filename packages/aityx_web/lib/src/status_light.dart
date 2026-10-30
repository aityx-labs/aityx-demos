/// The aityx status light, top right on every screen.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'check.dart';
import 'connection.dart';
import 'key_page.dart';
import 'key_store.dart';
import 'settings.dart';

/// An 8 px dot: grey while it checks, green when aityx accepts the key,
/// red otherwise; why, on hover and for screen readers. A tap opens the
/// index page's key section in the same tab.
///
/// It checks on start, when the key store changes (the index page, in
/// another tab, sets or forgets the key), and when the window regains
/// focus, at most once every [minInterval] for focus. No timer polling:
/// each check spends a request of the user's quota.
class AityxStatusLight extends StatefulWidget {
  const AityxStatusLight({
    super.key,
    this.client,
    this.store,
    this.origin,
    this.check,
    this.onTap,
    this.minInterval = const Duration(seconds: 30),
    this.checkingColor = grey,
    this.okColor = green,
    this.failColor = red,
  });

  /// The aityx palette's dim, green and red.
  static const grey = Color(0xFF47474D);
  static const green = Color(0xFF4CC38A);
  static const red = Color(0xFFF0506E);

  /// The HTTP client for the checks: a new one per check unless given.
  final http.Client? client;

  /// The key store: AityxSettings.store unless given.
  final AityxKeyStore? store;

  /// The page's origin: Uri.base unless given.
  final Uri? origin;

  /// The check: checkAityx with [client], [store] and [origin] unless a
  /// test gives its own.
  final Future<AityxState> Function()? check;

  /// On tap: opens the index page's key section unless given.
  final VoidCallback? onTap;

  /// The least time between two checks on focus.
  final Duration minInterval;

  final Color checkingColor;
  final Color okColor;
  final Color failColor;

  @override
  State<AityxStatusLight> createState() => _AityxStatusLightState();
}

class _AityxStatusLightState extends State<AityxStatusLight> {
  late AityxKeyStore _keys;
  StreamSubscription<void>? _changes;
  late final AppLifecycleListener _lifecycle;

  /// Null while it checks.
  AityxState? _state;

  /// When the last check started.
  DateTime? _last;
  bool _running = false;

  /// A check was asked for while one ran: run again after it, and don't
  /// show the stale result.
  bool _again = false;

  @override
  void initState() {
    super.initState();
    _listen();
    // The browser's focus and visibility events reach Flutter as
    // lifecycle changes.
    _lifecycle = AppLifecycleListener(onResume: () => _trigger(force: false));
    _trigger(force: true);
  }

  void _listen() {
    _keys = widget.store ?? AityxSettings.store;
    _changes = _keys.changes.listen((_) => _trigger(force: true));
  }

  @override
  void didUpdateWidget(AityxStatusLight oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      _changes?.cancel();
      _listen();
      _trigger(force: true);
    }
  }

  @override
  void dispose() {
    _changes?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  /// A check now; unless [force], only if the last one is old enough.
  void _trigger({required bool force}) {
    final last = _last;
    if (!force &&
        last != null &&
        DateTime.now().difference(last) < widget.minInterval) {
      return;
    }
    if (_running) {
      _again = true;
      // The key changed: what the light shows is stale.
      if (force && _state != null) setState(() => _state = null);
      return;
    }
    unawaited(_run(grey: force && _state != null));
  }

  Future<void> _run({required bool grey}) async {
    _running = true;
    _last = DateTime.now();
    if (grey && mounted) setState(() => _state = null);
    final check =
        widget.check ??
        () => checkAityx(
          client: widget.client,
          store: _keys,
          origin: widget.origin,
        );
    AityxState state;
    try {
      state = await check();
    } catch (error) {
      state = AityxState(
        ok: false,
        key: _keys.key != null,
        source: _keys.key != null ? AityxSource.user : AityxSource.none,
        url: null,
        detail: 'the check failed: ${error.runtimeType}',
        kind: AityxStateKind.failing,
      );
    }
    _running = false;
    if (!mounted) return;
    if (_again) {
      _again = false;
      unawaited(_run(grey: false));
      return;
    }
    setState(() => _state = state);
  }

  void _open() {
    final onTap = widget.onTap;
    if (onTap != null) {
      onTap();
    } else {
      openAityxKeyPage(origin: widget.origin);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    final color = state == null
        ? widget.checkingColor
        : state.ok
        ? widget.okColor
        : widget.failColor;
    final message = state?.tooltip ?? 'aityx: checking';
    return Semantics(
      container: true,
      button: true,
      label: message,
      onTap: _open,
      excludeSemantics: true,
      child: Tooltip(
        message: message,
        excludeFromSemantics: true,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _open,
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.8),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// For MaterialApp.builder: [child] (the app's Navigator) with [light]
/// (an AityxStatusLight unless given) over its top right corner, the dot
/// 6 px from the edges, on every screen. Its own Overlay lets the light's
/// tooltip show above the Navigator.
///
/// ```dart
/// MaterialApp(builder: withAityxStatus, home: ...)
/// MaterialApp(
///   builder: (context, child) => withAityxStatus(context, child,
///       light: AityxStatusLight(client: mockClient, store: store)),
/// )
/// ```
Widget withAityxStatus(BuildContext context, Widget? child, {Widget? light}) =>
    Overlay.wrap(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ?child,
          Positioned(
            key: const ValueKey('aityx-status-light'),
            top: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(top: 3, right: 3),
                child: light ?? const AityxStatusLight(),
              ),
            ),
          ),
        ],
      ),
    );
