/// GET /api/aityx: whether the API has an aityx key and aityx accepts it,
/// for the app's status light. The call is in bin/server.dart; what its
/// answer means is here, so it can be tested without aityx.
library;

import 'dart:convert';

/// No key: nothing to ask aityx.
const Map<String, Object?> noKey = {
  'key': false,
  'ok': false,
  'detail': 'AITYX_API_KEY is not set',
};

/// What aityx's answer to an empty POST /v1/systemone says about the key:
/// aityx checks the key first, so a working key gets 400
/// "invalid_request" (state is required) and a bad one 401, without
/// running any model. [url] is aityx's origin; [location], a redirect's.
Map<String, Object?> aityxStatus({
  required String url,
  required int status,
  required String body,
  String? location,
}) {
  final result = <String, Object?>{'key': true, 'ok': false, 'url': url};
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
    final host = Uri.tryParse(location ?? '')?.host ?? '';
    return result
      ..['detail'] =
          'aityx answered HTTP $status, a redirect to '
          '${host.isEmpty ? 'another page' : host}: '
          'AITYX_URL may be behind a login';
  }
  final detail = json is Map ? json['detail'] : null;
  return result
    ..['detail'] =
        'aityx answered HTTP $status${detail is String ? ': $detail' : ''}';
}

/// The call itself failed: no answer, or not in time.
Map<String, Object?> aityxUnreachable(String url, Object error) => {
  'key': true,
  'ok': false,
  'url': url,
  'detail': 'aityx did not answer: ${error.runtimeType}',
};
