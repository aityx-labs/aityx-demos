/// GET /api/aityx: whether the API has an aityx key and whether aityx
/// accepts it, for the app's status light. The key never appears in what
/// it answers.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// What /api/aityx answers with no key.
const Map<String, Object?> noKey = {
  'key': false,
  'ok': false,
  'detail': 'AITYX_API_KEY is not set',
};

/// What aityx's answer to the check says: an empty request to
/// /v1/systemone, which aityx checks the key of first, so a working key
/// gets 400 "invalid_request" (state is required) and a bad one 401,
/// without running any model. [location] is a redirect's Location header.
Map<String, Object?> classifyAnswer(
  Uri url,
  int status,
  String body, {
  String? location,
}) {
  final result = <String, Object?>{'key': true, 'ok': false, 'url': url.origin};
  Object? json;
  try {
    json = jsonDecode(body);
  } on FormatException {
    json = null;
  }
  if (status == 400 && json is Map && json['code'] == 'invalid_request') {
    return result
      ..['ok'] = true
      ..['detail'] = 'aityx accepts the key';
  }
  if (status >= 300 && status < 400) {
    final host = location == null ? null : Uri.tryParse(location)?.host;
    return result
      ..['detail'] =
          'aityx answered HTTP $status, a redirect to '
          '${host == null || host.isEmpty ? 'another page' : host}: '
          'AITYX_URL may be behind a login';
  }
  final detail = json is Map ? json['detail'] : null;
  return result
    ..['detail'] =
        'aityx answered HTTP $status${detail is String ? ': $detail' : ''}';
}

/// The check, kept for a minute so the app's polling doesn't call aityx
/// each time; requests that arrive while it runs share it.
class AityxCheck {
  AityxCheck(this.key, this.url, this.client);

  final String key;
  final Uri url;
  final HttpClient client;

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
    if (key.isEmpty) return noKey;
    try {
      final call = await client
          .postUrl(url.resolve('/v1/systemone'))
          .timeout(const Duration(seconds: 10));
      call
        ..followRedirects = false
        ..headers.set(HttpHeaders.authorizationHeader, 'Bearer $key')
        ..headers.contentType = ContentType.json
        ..write('{}');
      final answer = await call.close().timeout(const Duration(seconds: 10));
      final text = await answer
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 10));
      return classifyAnswer(
        url,
        answer.statusCode,
        text,
        location: answer.headers.value(HttpHeaders.locationHeader),
      );
    } catch (error) {
      return {
        'key': true,
        'ok': false,
        'url': url.origin,
        'detail': 'aityx did not answer: ${error.runtimeType}',
      };
    }
  }
}
