/// `GET /api/aityx`: whether the API has an aityx key and whether aityx
/// accepts it, for the app's status light.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// What the status light shows, from aityx's answer to an empty request:
/// [status] and [body] when it answered, [location] its Location header,
/// [error] when it didn't. [url] is aityx's base URL; never the key.
Map<String, Object?> aityxStatus({
  required bool key,
  Uri? url,
  int? status,
  String? body,
  String? location,
  Object? error,
}) {
  if (!key) {
    return {'key': false, 'ok': false, 'detail': 'AITYX_API_KEY is not set'};
  }
  final result = <String, Object?>{'key': true, 'ok': false};
  if (url == null || url.scheme != 'https' || url.host.isEmpty) {
    return result..['detail'] = 'AITYX_URL must be an https URL';
  }
  result['url'] = url.origin;
  if (error != null || status == null) {
    return result..['detail'] = 'aityx did not answer: ${error.runtimeType}';
  }
  Object? json;
  try {
    json = jsonDecode(body ?? '');
  } on FormatException {
    json = null;
  }
  if (status == 400 && json is Map && json['code'] == 'invalid_request') {
    return result
      ..['ok'] = true
      ..['detail'] = 'aityx accepts the key';
  }
  if (status >= 300 && status < 400) {
    final host = Uri.tryParse(location ?? '')?.host ?? '';
    return result
      ..['detail'] =
          'aityx answered HTTP $status, a redirect to '
          '${host.isEmpty ? 'elsewhere' : host}: AITYX_URL may be behind a '
          'login';
  }
  final detail = json is Map ? json['detail'] : null;
  return result
    ..['detail'] =
        'aityx answered HTTP $status'
        '${detail is String ? ': $detail' : ''}';
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

  /// Posts an empty request to /v1/systemone: aityx checks the key first,
  /// so a working key gets 400 "invalid_request" (state is required) and a
  /// bad one 401, without running any model.
  Future<Map<String, Object?>> _run() async {
    if (key.isEmpty) return aityxStatus(key: false);
    try {
      final call = await client
          .postUrl(url.resolve('/v1/systemone'))
          .timeout(const Duration(seconds: 10));
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
      return aityxStatus(
        key: true,
        url: url,
        status: answer.statusCode,
        body: text,
        location: answer.headers.value(HttpHeaders.locationHeader),
      );
    } catch (error) {
      return aityxStatus(key: true, url: url, error: error);
    }
  }
}
