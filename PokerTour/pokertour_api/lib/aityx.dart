/// aityx from the server, on the host's key: one systemone call per
/// decision, as the app makes them from the browser (packages/aityx_web),
/// with the same checks and words for what went wrong (poker_core's).
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:poker_core/table.dart';

/// What went wrong with a decision, in words.
class DecisionException implements Exception {
  const DecisionException(this.message, {this.strategyFault = false, this.keyFault = false});

  final String message;

  /// Whether the strategy's own rules are at fault (aityx refused the
  /// model, or decided nothing), rather than the key or the network.
  final bool strategyFault;

  /// Whether aityx rejected the key: no use asking again until the host
  /// sets another.
  final bool keyFault;

  @override
  String toString() => message;
}

/// The settings: the key (secret) and aityx's base URL.
class AityxSettings {
  const AityxSettings({required this.key, required this.url});

  final String key;
  final Uri url;

  bool get hasKey => key.isNotEmpty;

  /// `<url>/v1/systemone`.
  Uri get systemone => Uri.parse('${url.toString().replaceAll(RegExp(r'/+$'), '')}/v1/systemone');
}

/// Decides for a player on aityx.
class AityxDecider {
  AityxDecider(this.settings, this.models, {http.Client? client, this.timeout = const Duration(seconds: 30)})
    : _client = client ?? http.Client();

  final AityxSettings settings;
  final Models models;
  final http.Client _client;
  final Duration timeout;

  /// aityx calls made so far.
  int calls = 0;

  /// The action [strategy] takes in [situation]: the kind, the raise, the
  /// rule that fired and its why; throws [DecisionException].
  Future<Map<String, Object?>> act(Strategy strategy, Map<String, Object?> situation) async {
    if (!settings.hasKey) throw const DecisionException('AITYX_API_KEY is not set');
    final Map<String, Object?> state;
    try {
      state = situationFrom(situation);
    } on InvalidRequest catch (e) {
      throw DecisionException(e.message);
    }
    final sent = actRequest(models, strategy, state);
    final body = jsonEncode(sent);
    if (utf8.encode(body).length > 64 * 1024) {
      throw const DecisionException('request too large', strategyFault: true);
    }
    final http.Response response;
    calls++;
    try {
      response = await _client
          .post(
            settings.systemone,
            headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer ${settings.key}'},
            body: body,
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const DecisionException('aityx did not answer');
    } catch (error) {
      throw DecisionException('aityx could not be reached (${error.runtimeType})');
    }
    final text = utf8.decode(response.bodyBytes, allowMalformed: true);
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const DecisionException('aityx rejected the key', keyFault: true);
    }
    if (response.statusCode != 200) {
      // A 4xx about the model is the strategy's fault; a timeout, too
      // early or too many requests (408, 425, 429) and a 5xx are aityx's,
      // and pass.
      final status = response.statusCode;
      final fault = status >= 400 && status < 500 && !transientStatuses.contains(status);
      throw DecisionException(_scrub('aityx answered HTTP $status${problemDetail(text)}'), strategyFault: fault);
    }
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      throw const DecisionException('unexpected answer from aityx');
    }
    if (json is! Map) throw const DecisionException('unexpected answer from aityx');
    try {
      return toAction(sent, json.cast<String, Object?>());
    } on DecisionFailed catch (e) {
      throw DecisionException(_scrub('aityx could not decide it: $e'), strategyFault: true);
    } catch (_) {
      throw const DecisionException('unexpected answer from aityx');
    }
  }

  /// The 4xx statuses that say nothing about the strategy: aityx is busy.
  static const transientStatuses = {408, 425, 429};

  /// [message] without the key, should aityx ever echo it: messages go to
  /// answers, the live state and the standings.
  String _scrub(String message) => settings.key.isEmpty ? message : message.replaceAll(settings.key, '[the key]');

  /// Whether aityx accepts the key: POSTs `{}`, which a working key gets
  /// 400 for and a bad one 401.
  Future<bool> keyWorks() async {
    if (!settings.hasKey) return false;
    try {
      final response = await _client
          .post(settings.systemone, headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer ${settings.key}'}, body: '{}')
          .timeout(const Duration(seconds: 15));
      return response.statusCode != 401 && response.statusCode != 403 && response.statusCode < 500;
    } catch (_) {
      return false;
    }
  }

  void close() => _client.close();
}
