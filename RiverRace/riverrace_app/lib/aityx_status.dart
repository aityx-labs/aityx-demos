import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'strategy/decide.dart';

/// Where `GET /api/aityx` is, as [decideUrl] finds `POST /api/decide`.
Uri aityxStatusUrl(String baseUrl, {required bool web, required Uri page}) {
  if (baseUrl.isNotEmpty) return Uri.parse('$baseUrl/api/aityx');
  if (web) return page.resolve('/api/aityx');
  return Uri.parse('$nativeApi/api/aityx');
}

/// A small light, top right on every screen: green when the API has an
/// aityx key and aityx accepts it, red when not, grey while it checks;
/// the reason on hover. Checks at start and every minute.
class AityxStatus extends StatefulWidget {
  const AityxStatus({super.key, this.client, this.baseUrl});

  final http.Client? client;

  /// API_BASE_URL unless a test says.
  final String? baseUrl;

  @override
  State<AityxStatus> createState() => _AityxStatusState();
}

class _AityxStatusState extends State<AityxStatus> {
  static const _defaultBaseUrl = String.fromEnvironment('API_BASE_URL');

  late final http.Client _client = widget.client ?? http.Client();
  Timer? _timer;

  /// Null while the first check runs.
  bool? _ok;
  String _reason = 'aityx: checking';

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
    final url = aityxStatusUrl(
      widget.baseUrl ?? _defaultBaseUrl,
      web: kIsWeb,
      page: Uri.base,
    );
    bool ok;
    String reason;
    try {
      final response = await _client
          .get(url)
          .timeout(const Duration(seconds: 20));
      final json = jsonDecode(response.body);
      if (response.statusCode != 200 || json is! Map) {
        throw const FormatException();
      }
      ok = json['ok'] == true;
      reason = ok
          ? 'aityx: ready — accepts the key (${json['url']})'
          : json['key'] == false
          ? 'aityx: no key — AITYX_API_KEY is not set'
          : 'aityx: not working — ${json['detail'] ?? 'no answer'}';
    } catch (_) {
      ok = false;
      reason = 'aityx: the API did not answer';
    }
    if (!mounted) return;
    setState(() {
      _ok = ok;
      _reason = reason;
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
      label: _reason,
      child: Tooltip(
        message: _reason,
        child: Padding(
          // A larger target to hover than the dot itself.
          padding: const EdgeInsets.all(4),
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
