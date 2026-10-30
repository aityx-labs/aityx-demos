/// One systemone call: the request body in, the answer out, timed.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'body.dart';
import 'connection.dart';
import 'key_store.dart';
import 'settings.dart';

/// Thrown when there is no key at all (AityxSource.none).
class AityxNoKey implements Exception {
  const AityxNoKey();

  /// What to show people.
  static const message = 'aityx is not set up: set your key on the index page';

  @override
  String toString() => message;
}

/// Thrown when the request never got an answer: the network, CORS, an ad
/// blocker, or the timeout. The browser doesn't say which.
class AityxUnreachable implements Exception {
  const AityxUnreachable([this.cause]);

  /// What to show people.
  static const message = 'aityx did not answer';

  /// Why, as far as the app can tell: "timed out after 90 s", or the
  /// error's type. Never holds the key.
  final String? cause;

  @override
  String toString() => message;
}

/// aityx's answer to one call.
class AityxAnswer {
  const AityxAnswer({
    required this.status,
    required this.json,
    required this.text,
    required this.took,
  });

  /// The HTTP status: aityx's, or (in dev mode) the proxy's 502.
  final int status;

  /// The body as JSON; null when it isn't JSON.
  final Object? json;

  /// The body as text (UTF-8).
  final String text;

  /// From sending the request to reading the whole answer.
  final Duration took;

  /// Whether aityx answered 200.
  bool get ok => status == 200;

  /// aityx's error `code` ("invalid_request", "proxy_unreachable"...), if
  /// the body has one.
  String? get code => _field('code');

  /// aityx's error `detail`, if the body has one.
  String? get detail => _field('detail');

  /// What went wrong, for people; null when [ok]: "aityx rejected the key"
  /// on 401 and 403, else "aityx answered HTTP n", plus aityx's detail.
  String? get problem {
    if (ok) return null;
    if (status == 401 || status == 403) return 'aityx rejected the key';
    final why = detail;
    return 'aityx answered HTTP $status${why == null ? '' : ': $why'}';
  }

  String? _field(String name) {
    final body = json;
    if (body is! Map) return null;
    final value = body[name];
    return value is String && value.isNotEmpty ? value : null;
  }
}

/// Calls aityx's systemone on the connection's key.
///
/// Give it a [connection] to use that one always (tests); without one, it
/// resolves it (AityxSettings.resolve) on the first call and again once
/// the key store's key or URL changes, or while there's no key (the dev
/// key may turn up).
class AityxClient {
  AityxClient({
    http.Client? client,
    AityxConnection? connection,
    this.store,
    this.origin,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _fixed = connection;

  final http.Client _client;
  final bool _ownsClient;
  final AityxConnection? _fixed;

  /// The key store; AityxSettings.store when null.
  final AityxKeyStore? store;

  /// The page's origin, for the dev proxy; Uri.base when null.
  final Uri? origin;

  Future<AityxConnection>? _resolving;
  AityxConnection? _resolved;
  String? _resolvedFor;

  AityxKeyStore get _keys => store ?? AityxSettings.store;

  /// What the store holds now, to tell when it changed.
  String _snapshot() {
    final keys = _keys;
    return '${keys.sessionOnly} ${keys.url} ${keys.key}';
  }

  /// The connection calls use now.
  Future<AityxConnection> connection() {
    final fixed = _fixed;
    if (fixed != null) return Future.value(fixed);
    final now = _snapshot();
    final resolving = _resolving;
    if (resolving != null && _resolvedFor == now) return resolving;
    final resolved = _resolved;
    if (resolved != null &&
        _resolvedFor == now &&
        resolved.source != AityxSource.none) {
      return Future.value(resolved);
    }
    _resolvedFor = now;
    final next = AityxSettings.resolve(
      client: _client,
      origin: origin,
      store: _keys,
    );
    _resolving = next;
    return next.then((connection) {
      if (identical(_resolving, next)) {
        _resolving = null;
        _resolved = connection;
      }
      return connection;
    });
  }

  /// POSTs [body] (a JSON string, or anything jsonEncode takes) to
  /// systemone. Answers whatever aityx answers, errors included: check
  /// [AityxAnswer.ok] and [AityxAnswer.problem]. Throws [AityxNoKey] with
  /// no key and [AityxUnreachable] when no answer comes within [timeout].
  Future<AityxAnswer> systemone(
    Object body, {
    Duration timeout = const Duration(seconds: 90),
  }) async {
    final to = await connection();
    if (to.source == AityxSource.none) throw const AityxNoKey();
    final payload = body is String ? body : jsonEncode(body);
    final watch = Stopwatch()..start();
    final http.Response response;
    try {
      response = await _client
          .post(to.systemone, headers: to.headers(), body: payload)
          .timeout(timeout);
    } on TimeoutException {
      throw AityxUnreachable('timed out after ${spoken(timeout)}');
    } catch (error) {
      throw AityxUnreachable('${error.runtimeType}');
    }
    final text = bodyText(response);
    return AityxAnswer(
      status: response.statusCode,
      json: tryJson(text),
      text: text,
      took: watch.elapsed,
    );
  }

  /// Closes the HTTP client, unless it was given one.
  void close() {
    if (_ownsClient) _client.close();
  }
}
