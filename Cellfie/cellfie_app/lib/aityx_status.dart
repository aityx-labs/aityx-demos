/// The aityx status light: a small dot, top right on every screen, that
/// says whether the API has its aityx key and aityx accepts it (the API's
/// GET /api/aityx), with why on hover.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// What /api/aityx said; null `ok` while the first check runs.
class AityxState {
  const AityxState({this.ok, this.key = true, this.url, this.detail});

  const AityxState.checking() : this();

  /// The API did not answer, or not with the check.
  const AityxState.unreachable()
    : this(ok: false, detail: 'the API did not answer');

  factory AityxState.fromJson(Map<String, Object?> json) => AityxState(
    ok: json['ok'] == true,
    key: json['key'] != false,
    url: json['url'] as String?,
    detail: json['detail'] as String?,
  );

  final bool? ok;
  final bool key;
  final String? url;
  final String? detail;

  /// The tooltip and the screen readers' label.
  String get message {
    if (ok == null) return 'aityx: checking…';
    if (ok!) return 'aityx: ready — accepts the key (${url ?? 'aityx'})';
    if (!key) return 'aityx: no key — AITYX_API_KEY is not set';
    if (detail == 'the API did not answer') {
      return 'aityx: the API did not answer';
    }
    return 'aityx: not working — ${detail ?? 'no answer'}';
  }
}

/// Asks the API's /api/aityx.
typedef AityxChecker = Future<AityxState> Function();

/// The app's API at API_BASE_URL (empty: the app's own origin, through the
/// dev server's or nginx's /api/ proxy), as the generations reach it.
AityxChecker apiAityxChecker({http.Client? client, String? baseUrl}) {
  final httpClient = client ?? http.Client();
  final base = baseUrl ?? const String.fromEnvironment('API_BASE_URL');
  final url = base.isEmpty
      ? Uri.base.resolve('/api/aityx')
      : Uri.parse('$base/api/aityx');
  return () async {
    try {
      final response = await httpClient
          .get(url)
          .timeout(const Duration(seconds: 15));
      final json = jsonDecode(response.body);
      if (response.statusCode != 200 || json is! Map) {
        return const AityxState.unreachable();
      }
      return AityxState.fromJson(json.cast<String, Object?>());
    } catch (_) {
      return const AityxState.unreachable();
    }
  };
}

/// The dot: grey while checking, green when aityx accepts the key, red
/// otherwise. Checks at start and every minute.
class AityxStatus extends StatefulWidget {
  const AityxStatus({super.key, required this.check});

  final AityxChecker check;

  @override
  State<AityxStatus> createState() => _AityxStatusState();
}

class _AityxStatusState extends State<AityxStatus> {
  AityxState _state = const AityxState.checking();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final state = await widget.check();
    if (mounted) setState(() => _state = state);
  }

  @override
  Widget build(BuildContext context) {
    final color = switch (_state.ok) {
      null => Colors.grey,
      true => Colors.green,
      false => Colors.red,
    };
    final message = _state.message;
    return Semantics(
      label: message,
      excludeSemantics: true,
      child: Tooltip(
        message: message,
        child: Padding(
          // A larger target to hover than the dot.
          padding: const EdgeInsets.all(4),
          child: Opacity(
            opacity: 0.8,
            child: Container(
              key: const ValueKey('aityx-status-dot'),
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ),
        ),
      ),
    );
  }
}

/// [child] with the dot over its top right corner; in its own Overlay, so
/// the tooltip works above the app's Navigator.
class WithAityxStatus extends StatefulWidget {
  const WithAityxStatus({super.key, required this.check, required this.child});

  final AityxChecker check;
  final Widget child;

  @override
  State<WithAityxStatus> createState() => _WithAityxStatusState();
}

class _WithAityxStatusState extends State<WithAityxStatus> {
  late final _entry = OverlayEntry(
    builder: (context) => Stack(
      children: [
        widget.child,
        Positioned(
          top: 0,
          right: 0,
          child: SafeArea(
            child: Padding(
              // 6 px from the corner to the dot, inside its 4 px pad.
              padding: const EdgeInsets.only(top: 2, right: 2),
              child: AityxStatus(check: widget.check),
            ),
          ),
        ),
      ],
    ),
  );

  @override
  void didUpdateWidget(WithAityxStatus oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The entry builds from widget.child: rebuild it with the new one.
    _entry.markNeedsBuild();
  }

  @override
  void dispose() {
    _entry
      ..remove()
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Overlay(initialEntries: [_entry]);
}
