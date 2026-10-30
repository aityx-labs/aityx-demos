import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'theme.dart';

/// A small light, top right on every screen: green when the API has an
/// aityx key and aityx accepts it, red otherwise, grey while it checks.
/// Why, on hover and for screen readers. Asks the API's /api/aityx at
/// start and every minute.
class AityxStatus extends StatefulWidget {
  const AityxStatus({super.key, this.client, this.baseUrl});

  /// The HTTP client: a new one unless a test passes its own.
  final http.Client? client;

  /// The API, as API_BASE_URL: empty means the app's own origin.
  final String? baseUrl;

  @override
  State<AityxStatus> createState() => _AityxStatusState();
}

class _AityxStatusState extends State<AityxStatus> {
  late final http.Client _client = widget.client ?? http.Client();
  late final String _baseUrl =
      widget.baseUrl ?? const String.fromEnvironment('API_BASE_URL');
  Timer? _timer;

  /// Null while the first check runs.
  bool? _ok;
  String _message = 'aityx: checking';

  Uri get _url => _baseUrl.isEmpty
      ? Uri.base.resolve('/api/aityx')
      : Uri.parse('$_baseUrl/api/aityx');

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
          .timeout(const Duration(seconds: 15));
      final json = jsonDecode(response.body);
      if (response.statusCode != 200 || json is! Map) {
        throw const FormatException();
      }
      ok = json['ok'] == true;
      message = ok
          ? 'aityx: ready — accepts the key (${json['url']})'
          : json['key'] == false
          ? 'aityx: no key — AITYX_API_KEY is not set'
          : 'aityx: not working — ${json['detail']}';
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
      null => Aityx.dim,
      true => Aityx.green,
      false => Aityx.red,
    };
    return Semantics(
      label: _message,
      child: Tooltip(
        message: _message,
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
    );
  }
}

/// [child], with the [AityxStatus] light over its top right corner; for
/// MaterialApp.builder, so it shows on every screen. Its own Overlay lets
/// the light's tooltip show above the app's Navigator.
class WithAityxStatus extends StatefulWidget {
  const WithAityxStatus({super.key, required this.child, this.client});

  final Widget? child;

  /// The HTTP client for [AityxStatus]: a new one unless a test passes it.
  final http.Client? client;

  @override
  State<WithAityxStatus> createState() => _WithAityxStatusState();
}

class _WithAityxStatusState extends State<WithAityxStatus> {
  late final _entry = OverlayEntry(
    builder: (context) => Stack(
      children: [
        ?widget.child,
        Positioned(
          top: 0,
          right: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(top: 3, right: 3),
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
