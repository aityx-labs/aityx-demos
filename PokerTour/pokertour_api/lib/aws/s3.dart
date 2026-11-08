/// S3 from the server, with the function's own credentials and signed
/// headers (aws_lite): get, put and delete one object, the put
/// conditional on the ETag when asked (S3's If-Match and If-None-Match),
/// which is what keeps leaderboard.json whole between the API and the
/// runner. On a laptop, the [S3Client.endpoint] is Floci's (path-style
/// URLs).
library;

import 'dart:async';
import 'dart:convert';

import 'package:aws_lite/aws_lite.dart';
import 'package:http/http.dart' as http;

/// AWS answered an error, or didn't answer.
class AwsException implements Exception {
  const AwsException(this.status, this.message);

  final int status;
  final String message;

  @override
  String toString() => 'AWS: $message (HTTP $status)';
}

/// The conditional put found another version in place.
class S3Conflict extends AwsException {
  const S3Conflict(super.status, super.message);
}

class S3Object {
  const S3Object(this.bytes, this.etag);

  final List<int> bytes;
  final String etag;

  String get text => utf8.decode(bytes);
}

class S3Client {
  S3Client({required this.credentials, required this.region, this.endpoint, http.Client? client, this.timeout = const Duration(seconds: 20)})
    : _client = client ?? http.Client();

  final AwsCredentials credentials;
  final String region;

  /// An S3 of another address (Floci's), path-style; null for AWS's.
  final Uri? endpoint;
  final http.Client _client;
  final Duration timeout;

  Uri url(String bucket, String key) => endpoint == null
      ? Uri(scheme: 'https', host: '$bucket.s3.$region.amazonaws.com', pathSegments: key.split('/'))
      : endpoint!.replace(pathSegments: [bucket, ...key.split('/')]);

  /// The object, or null when there is none.
  Future<S3Object?> get(String bucket, String key) async {
    final response = await _send('GET', url(bucket, key));
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) throw _error(response);
    return S3Object(response.bodyBytes, response.headers['etag'] ?? '');
  }

  /// Writes the object and gives its ETag. [ifMatch]: only when the ETag
  /// in place is this one; [ifNoneMatch]: only when there is no object;
  /// an [S3Conflict] otherwise.
  Future<String> put(
    String bucket,
    String key,
    List<int> bytes, {
    String contentType = 'application/octet-stream',
    String? ifMatch,
    bool ifNoneMatch = false,
  }) async {
    final response = await _send(
      'PUT',
      url(bucket, key),
      headers: {
        'content-type': contentType,
        'if-match': ?ifMatch,
        if (ifNoneMatch) 'if-none-match': '*',
      },
      body: bytes,
    );
    if (response.statusCode == 412 || response.statusCode == 409) {
      throw S3Conflict(response.statusCode, 'the object changed');
    }
    if (response.statusCode != 200) throw _error(response);
    return response.headers['etag'] ?? '';
  }

  Future<void> delete(String bucket, String key) async {
    final response = await _send('DELETE', url(bucket, key));
    if (response.statusCode != 204 && response.statusCode != 200 && response.statusCode != 404) throw _error(response);
  }

  Future<http.Response> _send(String method, Uri uri, {Map<String, String> headers = const {}, List<int> body = const []}) async {
    final signed = signRequest(credentials: credentials, region: region, service: 's3', method: method, uri: uri, headers: headers, body: body);
    final request = http.Request(method, signed.uri)
      ..headers.addAll(signed.headers)
      ..bodyBytes = body;
    try {
      return await http.Response.fromStream(await _client.send(request)).timeout(timeout);
    } on TimeoutException {
      throw const AwsException(0, 'S3 did not answer');
    } on AwsException {
      rethrow;
    } catch (error) {
      throw AwsException(0, 'S3 could not be reached (${error.runtimeType})');
    }
  }

  AwsException _error(http.Response response) {
    final body = utf8.decode(response.bodyBytes, allowMalformed: true);
    final code = RegExp('<Code>([^<]*)</Code>').firstMatch(body)?.group(1);
    final message = RegExp('<Message>([^<]*)</Message>').firstMatch(body)?.group(1);
    return AwsException(response.statusCode, [?code, ?message].join(': ').ifEmpty('S3 refused the request'));
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}
