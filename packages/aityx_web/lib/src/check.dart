/// The status check: does aityx accept the key?
library;

import 'dart:async';

import 'package:http/http.dart' as http;

import 'body.dart';
import 'connection.dart';
import 'key_store.dart';
import 'settings.dart';

/// What a check found.
enum AityxStateKind {
  /// aityx accepts the key.
  ready,

  /// There's no key: neither the user's nor a dev key.
  noKey,

  /// aityx refused the key (401, 403).
  rejected,

  /// No answer: the network, CORS, an ad blocker, a timeout, or (dev
  /// mode) the proxy couldn't reach aityx.
  unreachable,

  /// aityx answered something unexpected.
  failing,
}

/// The result of the status check.
class AityxState {
  const AityxState({
    required this.ok,
    required this.key,
    required this.source,
    required this.url,
    required this.detail,
    required this.kind,
    this.whose = '',
  });

  /// No key anywhere.
  static const noKey = AityxState(
    ok: false,
    key: false,
    source: AityxSource.none,
    url: null,
    detail: 'set yours on the index page',
    kind: AityxStateKind.noKey,
    whose: 'no key',
  );

  /// Whether aityx accepts the key.
  final bool ok;

  /// Whether there is a key (the user's or a dev key).
  final bool key;

  final AityxSource source;

  /// The aityx URL the key goes to; null without a key.
  final String? url;

  /// Why, for people.
  final String detail;

  final AityxStateKind kind;

  /// Whose key, as AityxConnection.whose says it ("your key", "dev key
  /// from .env").
  final String whose;

  /// The light's tooltip, also its Semantics label.
  String get tooltip => switch (kind) {
    AityxStateKind.ready => url == null || url!.isEmpty
        ? 'aityx: ready — the key works'
        : 'aityx: ready — the key works with $url',
    AityxStateKind.noKey => 'aityx: no key — set yours on the index page',
    AityxStateKind.rejected => 'aityx: key rejected — $detail',
    AityxStateKind.unreachable => 'aityx: not reachable — $detail',
    AityxStateKind.failing => 'aityx: not working — $detail',
  };

  @override
  String toString() => tooltip;
}

/// Asks aityx whether it accepts the key, without running a model: POSTs
/// `{}` to systemone, which checks the key first, so a working key gets
/// 400 "invalid_request" and a bad one 401. Each check spends a request
/// of the user's quota. Resolves the connection (AityxSettings.resolve
/// with [store] and [origin]) unless given one. Never throws.
Future<AityxState> checkAityx({
  http.Client? client,
  AityxConnection? connection,
  AityxKeyStore? store,
  Uri? origin,
  Duration timeout = const Duration(seconds: 15),
}) async {
  final http.Client asker = client ?? http.Client();
  try {
    final to =
        connection ??
        await AityxSettings.resolve(
          client: asker,
          origin: origin,
          store: store,
        );
    if (to.source == AityxSource.none) return AityxState.noKey;
    try {
      final answer = await asker
          .post(to.systemone, headers: to.headers(), body: '{}')
          .timeout(timeout);
      return classifyAityx(
        status: answer.statusCode,
        body: bodyText(answer),
        connection: to,
      );
    } catch (error) {
      final where = to.source == AityxSource.dev
          ? 'the dev proxy (${to.endpoint})'
          : to.url;
      return _state(
        to,
        AityxStateKind.unreachable,
        error is TimeoutException
            ? 'no answer from $where in ${spoken(timeout)}'
            : 'no answer from $where (network, CORS or a blocker)',
      );
    }
  } finally {
    if (client == null) asker.close();
  }
}

/// What aityx's answer ([status], [body]) to the check's empty POST says
/// about [connection]'s key.
AityxState classifyAityx({
  required int status,
  required String body,
  required AityxConnection connection,
}) {
  if (connection.source == AityxSource.none) return AityxState.noKey;
  final json = tryJson(body);
  String? field(String name) {
    if (json is! Map) return null;
    final value = json[name];
    return value is String && value.isNotEmpty ? value : null;
  }

  final code = field('code');
  final detail = field('detail');
  final said = 'HTTP $status${detail == null ? '' : ': $detail'}';
  if (status == 400 && code == 'invalid_request') {
    return _state(connection, AityxStateKind.ready, 'aityx accepts the key');
  }
  if (status == 401 || status == 403) {
    return _state(
      connection,
      AityxStateKind.rejected,
      connection.source == AityxSource.user
          ? 'aityx answered $said: set a new key on the index page'
          : 'aityx answered $said',
    );
  }
  // The index server's proxy, when it couldn't reach aityx.
  if (connection.source == AityxSource.dev &&
      status == 502 &&
      (code == 'proxy_unreachable' || code == 'proxy_redirect')) {
    return _state(
      connection,
      AityxStateKind.unreachable,
      detail ?? 'the dev proxy could not reach aityx',
    );
  }
  if (status >= 300 && status < 400) {
    return _state(
      connection,
      AityxStateKind.failing,
      'aityx answered HTTP $status, a redirect: it may be behind a login',
    );
  }
  return _state(connection, AityxStateKind.failing, 'aityx answered $said');
}

AityxState _state(AityxConnection to, AityxStateKind kind, String detail) =>
    AityxState(
      ok: kind == AityxStateKind.ready,
      key: true,
      source: to.source,
      url: to.url,
      detail: detail,
      kind: kind,
      whose: to.whose,
    );
