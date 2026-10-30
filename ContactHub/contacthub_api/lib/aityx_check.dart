/// GET /api/aityx: whether the API has an aityx key and whether aityx
/// accepts it, for the app's status light. Never includes the key.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// What a key check found, from aityx's answer to an empty request:
/// [status] and [body] as aityx answered, [location] a redirect's Location.
/// aityx checks the key first, so a working key gets 400
/// "invalid_request" (state is required) and a bad one 401, without
/// running any model.
Map<String, Object?> classifyAityx(
  int status,
  String body, {
  String? location,
}) {
  if (status >= 300 && status < 400) {
    final host = location == null ? null : Uri.tryParse(location)?.host;
    return {
      'ok': false,
      'detail':
          'aityx answered HTTP $status, a redirect to '
          '${host == null || host.isEmpty ? 'another page' : host}: '
          'AITYX_URL may be behind a login',
    };
  }
  Object? json;
  try {
    json = jsonDecode(body);
  } on FormatException {
    json = null;
  }
  if (status == 400 && json is Map && json['code'] == 'invalid_request') {
    return {'ok': true, 'detail': 'aityx accepts the key'};
  }
  final detail = json is Map ? json['detail'] : null;
  return {
    'ok': false,
    'detail':
        'aityx answered HTTP $status${detail is String ? ': $detail' : ''}',
  };
}

/// The check, kept for a minute so the app's polling doesn't call aityx
/// each time; requests that arrive while it runs share it.
class AityxCheck {
  AityxCheck(this.key, this.url, {HttpClient? client})
    : _client =
          client ??
          (HttpClient()..connectionTimeout = const Duration(seconds: 10));

  final String key;
  final Uri url;
  final HttpClient _client;

  Future<Map<String, Object?>>? _check;
  DateTime _at = DateTime(0);

  Future<Map<String, Object?>> status() {
    final check = _check;
    if (check != null &&
        DateTime.now().difference(_at) < const Duration(minutes: 1)) {
      return check;
    }
    _at = DateTime.now();
    return _check = _run();
  }

  Future<Map<String, Object?>> _run() async {
    if (key.isEmpty) {
      return {'key': false, 'ok': false, 'detail': 'AITYX_API_KEY is not set'};
    }
    final result = <String, Object?>{'key': true, 'url': url.origin};
    try {
      final call = await _client.postUrl(url.resolve('/v1/systemone'));
      call.followRedirects = false;
      call.headers
        ..set(HttpHeaders.authorizationHeader, 'Bearer $key')
        ..contentType = ContentType.json;
      call.write('{}');
      final answer = await call.close().timeout(const Duration(seconds: 10));
      final text = await answer
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 10));
      return result..addAll(
        classifyAityx(
          answer.statusCode,
          text,
          location: answer.headers.value(HttpHeaders.locationHeader),
        ),
      );
    } catch (error) {
      return result
        ..['ok'] = false
        ..['detail'] = 'aityx did not answer: ${error.runtimeType}';
    }
  }
}
