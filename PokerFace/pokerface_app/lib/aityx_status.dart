import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// A small light, top right: whether the API has an aityx key and aityx
/// accepts it (the API's GET /api/aityx), checked at start and every
/// minute. Grey while checking, green when ready, red otherwise; the
/// reason on hover and for screen readers.
class AityxStatus extends StatefulWidget {
  const AityxStatus({super.key, this.client, this.baseUrl});

  /// Asks the API: a real client unless a test says.
  final http.Client? client;

  /// The API's base URL, as for HttpPokerApi: empty for the page's own
  /// origin (the web server proxies /api/).
  final String? baseUrl;

  static const every = Duration(minutes: 1);

  @override
  State<AityxStatus> createState() => _AityxStatusState();
}

class _AityxStatusState extends State<AityxStatus> {
  static const _defaultBaseUrl = String.fromEnvironment('API_BASE_URL');

  late final http.Client _client = widget.client ?? http.Client();
  Timer? _timer;

  /// null while the first check runs.
  bool? _ok;
  String _message = 'aityx: checking';

  @override
  void initState() {
    super.initState();
    _check();
    _timer = Timer.periodic(AityxStatus.every, (_) => _check());
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (widget.client == null) _client.close();
    super.dispose();
  }

  Uri get _url {
    final base = widget.baseUrl ?? _defaultBaseUrl;
    return base.isEmpty
        ? Uri.base.resolve('/api/aityx')
        : Uri.parse('$base/api/aityx');
  }

  Future<void> _check() async {
    bool ok;
    String message;
    try {
      final response = await _client
          .get(_url)
          .timeout(const Duration(seconds: 20));
      final json = jsonDecode(response.body);
      if (response.statusCode != 200 || json is! Map) {
        throw FormatException('HTTP ${response.statusCode}');
      }
      ok = json['ok'] == true;
      final detail = json['detail'] is String ? json['detail'] as String : '';
      message = ok
          ? 'aityx: ready — accepts the key (${json['url']})'
          : json['key'] == false
          ? 'aityx: no key — AITYX_API_KEY is not set'
          : 'aityx: not working — $detail';
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
      null => Colors.grey,
      true => Colors.green,
      false => Colors.red,
    };
    return Semantics(
      label: _message,
      child: Tooltip(
        message: _message,
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
    );
  }
}

/// [child] (the app's navigator) with the light over its top right
/// corner, in an Overlay of its own so the light's tooltip can show. Only
/// the light takes taps; the rest pass through to [child].
class WithAityxStatus extends StatelessWidget {
  const WithAityxStatus({super.key, required this.child, this.status});

  final Widget child;

  /// The light: [AityxStatus] unless a test says.
  final Widget? status;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Positioned.fill(
          child: Overlay(
            initialEntries: [
              OverlayEntry(
                builder: (context) => SafeArea(
                  child: Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6, right: 6),
                      child: status ?? const AityxStatus(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
