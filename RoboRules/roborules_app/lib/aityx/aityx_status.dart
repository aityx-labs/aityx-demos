import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// A discreet light, top right on every screen: whether the API has an
/// aityx key and aityx accepts it (the API's /api/aityx), with why on
/// hover. Checked at start and every minute.
class AityxStatus extends StatefulWidget {
  const AityxStatus({super.key, this.client, this.baseUrl});

  /// The API, at API_BASE_URL as [HttpBattleApi] reads it: empty means
  /// the app's own origin (the dev server's or nginx's /api/ proxy).
  final String? baseUrl;
  final http.Client? client;

  static const _defaultBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// [child] with the light over its top right corner, in an [Overlay] of
  /// its own so the tooltip works above the app's navigator. [light] is
  /// for tests.
  static Widget over(Widget? child, {Widget light = const AityxStatus()}) =>
      Overlay.wrap(
        child: Stack(
          children: [
            ?child,
            // The dot 6 px from the corner: 2 and its padding.
            Positioned(top: 2, right: 2, child: SafeArea(child: light)),
          ],
        ),
      );

  @override
  State<AityxStatus> createState() => _AityxStatusState();
}

class _AityxStatusState extends State<AityxStatus> {
  late final http.Client _client = widget.client ?? http.Client();
  Timer? _timer;

  /// Null while the first check runs.
  bool? _ok;
  String _label = 'aityx: checking…';

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

  Uri get _url {
    final base = widget.baseUrl ?? AityxStatus._defaultBaseUrl;
    return base.isEmpty
        ? Uri.base.resolve('/api/aityx')
        : Uri.parse('$base/api/aityx');
  }

  Future<void> _check() async {
    bool ok;
    String label;
    try {
      final response = await _client
          .get(_url)
          .timeout(const Duration(seconds: 20));
      final json = jsonDecode(response.body);
      if (response.statusCode != 200 || json is! Map) {
        throw const FormatException();
      }
      ok = json['ok'] == true;
      label = ok
          ? 'aityx: ready — accepts the key (${json['url']})'
          : json['key'] == false
          ? 'aityx: no key — AITYX_API_KEY is not set'
          : 'aityx: not working — ${json['detail'] ?? 'no answer'}';
    } catch (_) {
      ok = false;
      label = 'aityx: the API did not answer';
    }
    if (!mounted) return;
    setState(() {
      _ok = ok;
      _label = label;
    });
  }

  @override
  Widget build(BuildContext context) {
    final color = switch (_ok) {
      null => Colors.grey,
      true => Colors.green,
      false => Colors.red,
    };
    return Tooltip(
      message: _label,
      child: Semantics(
        label: _label,
        excludeSemantics: true,
        // A little room around the dot, for the pointer.
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Opacity(
            opacity: 0.8,
            child: Container(
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
