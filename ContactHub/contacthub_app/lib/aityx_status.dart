import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'theme.dart';

/// A small light, top right on every screen: whether the API has an aityx
/// key and aityx accepts it (the API's /api/aityx), with why on hover.
/// Checked at start and every minute.
class AityxStatus extends StatefulWidget {
  const AityxStatus({super.key, this.client, this.baseUrl});

  /// The API's client: a real one unless a test says.
  final http.Client? client;

  /// The API's base URL, as [ApiRequestRouter]'s: API_BASE_URL, and empty
  /// means the app's own origin (the dev server's or nginx's /api/ proxy).
  final String? baseUrl;

  static const _defaultBaseUrl = String.fromEnvironment('API_BASE_URL');

  @override
  State<AityxStatus> createState() => _AityxStatusState();
}

class _AityxStatusState extends State<AityxStatus> {
  late final http.Client _client = widget.client ?? http.Client();
  Timer? _timer;

  /// Null while the first check runs.
  bool? _ok;
  String _message = 'aityx: checking';

  Uri get _url {
    final base = widget.baseUrl ?? AityxStatus._defaultBaseUrl;
    return base.isEmpty
        ? Uri.base.resolve('/api/aityx')
        : Uri.parse('$base/api/aityx');
  }

  @override
  void initState() {
    super.initState();
    _check();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _check());
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (widget.client == null) _client.close();
    super.dispose();
  }

  Future<void> _check() async {
    bool ok;
    String message;
    try {
      final response = await _client
          .get(_url)
          .timeout(const Duration(seconds: 30));
      final json = jsonDecode(response.body);
      if (response.statusCode != 200 || json is! Map) {
        throw const FormatException();
      }
      ok = json['ok'] == true;
      final detail = json['detail'];
      final url = json['url'];
      message = ok
          ? 'aityx: ready — accepts the key${url is String ? ' ($url)' : ''}'
          : json['key'] == false
          ? 'aityx: no key — AITYX_API_KEY is not set'
          : 'aityx: not working — ${detail is String ? detail : 'no answer'}';
    } catch (_) {
      ok = false;
      message = 'aityx: the API did not answer';
    }
    if (!mounted) return;
    setState(() {
      _ok = ok;
      _message = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final color = switch (_ok) {
      null => Aityx.muted,
      true => Aityx.green,
      false => Aityx.red,
    };
    return Semantics(
      label: _message,
      child: Tooltip(
        message: _message,
        child: Padding(
          // A bigger target to hover than the dot itself.
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

/// [child] with the [AityxStatus] light over its top right corner, in an
/// Overlay of its own so the light's tooltip works above the Navigator.
class WithAityxStatus extends StatefulWidget {
  const WithAityxStatus({super.key, required this.child, this.client});

  final Widget child;
  final http.Client? client;

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
              // With the light's own padding, the dot sits 6 px in.
              padding: const EdgeInsets.all(2),
              child: AityxStatus(client: widget.client),
            ),
          ),
        ),
      ],
    ),
  );

  @override
  void didUpdateWidget(WithAityxStatus oldWidget) {
    super.didUpdateWidget(oldWidget);
    _entry.markNeedsBuild();
  }

  @override
  Widget build(BuildContext context) => Overlay(initialEntries: [_entry]);
}
