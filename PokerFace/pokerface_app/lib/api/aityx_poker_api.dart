import 'dart:async';
import 'dart:convert';

import 'package:aityx_web/aityx_web.dart';
import 'package:flutter/services.dart';

import '../aityx/table.dart';
import 'poker_api.dart';

/// Decides for the players on aityx, from the browser: the presets come
/// from the app's assets (assets/models/), and each decision is one
/// systemone call on the user's key, or the index server's dev key
/// (aityx_web finds which). What the API did before, the app does now,
/// with the API's checks and its words for what went wrong.
class AityxPokerApi implements PokerApi {
  AityxPokerApi({
    AityxClient? aityx,
    AssetBundle? bundle,
    this.timeout = deadline,
  }) : _aityx = aityx ?? AityxClient(),
       _bundle = bundle ?? rootBundle;

  /// How long a decision waits for aityx, as the API waited.
  static const deadline = Duration(seconds: 30);

  /// The most a decision may hold, strategy and situation, as the API
  /// took.
  static const maxRequest = 64 * 1024;

  final AityxClient _aityx;
  final AssetBundle _bundle;
  final Duration timeout;

  Future<Models>? _models;

  /// The models, read once; read again on the next call if that failed.
  Future<Models> models() =>
      _models ??= Models.load(_bundle).catchError((Object error) {
        _models = null;
        throw ApiException('the models could not be read: $error');
      });

  @override
  Future<List<Strategy>> strategies() async =>
      (await models()).strategies.values.toList();

  @override
  Future<ActResult> act(
    Strategy strategy,
    Map<String, Object?> situation,
  ) async {
    final models = await this.models();
    final request = strategy.toRequest();
    final Strategy rules;
    final Map<String, Object?> state;
    try {
      if (utf8
              .encode(jsonEncode({'strategy': request, 'situation': situation}))
              .length >
          maxRequest) {
        throw InvalidRequest('request too large');
      }
      rules = models.strategyFrom(request);
      state = situationFrom(situation);
    } on InvalidRequest catch (e) {
      throw ApiException(e.message);
    } on JsonUnsupportedObjectError {
      throw const ApiException('invalid JSON');
    }

    final sent = actRequest(models, rules, state);
    final AityxConnection connection;
    final AityxAnswer answer;
    try {
      connection = await _aityx.connection();
      // No key: said now, rather than asking the index server's
      // /aityx/config a second time inside systemone.
      if (connection.source == AityxSource.none) throw const AityxNoKey();
      answer = await _aityx.systemone(sent, timeout: timeout);
    } on AityxNoKey {
      throw const ApiException(AityxNoKey.message);
    } on AityxUnreachable {
      throw const ApiException(AityxUnreachable.message);
    }
    final key = connection.key ?? '';
    if (!answer.ok) throw ApiException(_problem(answer, key));
    final json = answer.json;
    if (json is! Map) {
      throw const ApiException('unexpected answer from aityx');
    }
    final Map<String, Object?> action;
    try {
      action = toAction(sent, json.cast<String, Object?>());
    } on DecisionFailed catch (e) {
      throw ApiException('aityx could not decide it: $e');
    } catch (_) {
      // JSON of another shape than aityx's (an answer that isn't an
      // object, say): the API answered "internal error" to it; the table
      // and the editor catch only ApiException.
      throw const ApiException('unexpected answer from aityx');
    }
    return ActResult.fromJson(
      withAityx(
        action,
        sent,
        json.cast<String, Object?>(),
        answer.text,
        key,
        tookMs: answer.took.inMilliseconds,
      ),
    );
  }

  /// What went wrong, for people: a rejected key, the dev proxy unable to
  /// reach aityx, or aityx's status with its problem details (a custom
  /// strategy's mistake is a 422 whose errors say what to fix), unless
  /// they somehow hold the user's [key] (they never should): the message
  /// is shown.
  static String _problem(AityxAnswer answer, String key) {
    if (answer.status == 401 || answer.status == 403) {
      return 'aityx rejected the key';
    }
    if (answer.code == 'proxy_unreachable') return AityxUnreachable.message;
    final detail = key.isNotEmpty && answer.text.contains(key)
        ? ''
        : problemDetail(answer.text);
    return 'aityx answered HTTP ${answer.status}$detail';
  }
}
