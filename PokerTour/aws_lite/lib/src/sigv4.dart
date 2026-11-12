/// AWS Signature Version 4, the little of it Poker Tour needs: a
/// presigned GET of one S3 object (the browser fetches the key with it),
/// and signed headers for a request the server sends itself (S3, Lambda).
/// Pure Dart, tested against AWS's published examples.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'credentials.dart';

/// A presigned URL for `GET https://[host]/[path]`, good for [expires]
/// seconds from [now], signed for [region] and the S3 [service] with
/// [credentials] (the session token goes in the query too). The browser
/// then fetches it with a plain GET: no custom headers, so no CORS
/// preflight; the bucket's CORS rules must still allow the origin.
Uri presignGet({
  required AwsCredentials credentials,
  required String region,
  required String host,
  required String path,
  DateTime? now,
  int expires = 300,
  String service = 's3',
}) {
  final at = (now ?? DateTime.now()).toUtc();
  final amzDate = amzDateOf(at);
  final dateStamp = amzDate.substring(0, 8);
  final scope = '$dateStamp/$region/$service/aws4_request';
  final canonicalPath = _canonicalPath(path);
  final query = <String, String>{
    'X-Amz-Algorithm': 'AWS4-HMAC-SHA256',
    'X-Amz-Credential': '${credentials.accessKeyId}/$scope',
    'X-Amz-Date': amzDate,
    'X-Amz-Expires': '$expires',
    if (credentials.sessionToken.isNotEmpty)
      'X-Amz-Security-Token': credentials.sessionToken,
    'X-Amz-SignedHeaders': 'host',
  };
  final canonicalQuery = _canonicalQuery([for (final e in query.entries) (e.key, e.value)]);
  final canonicalRequest = [
    'GET',
    canonicalPath,
    canonicalQuery,
    'host:$host\n',
    'host',
    'UNSIGNED-PAYLOAD',
  ].join('\n');
  final signature = _signature(credentials, dateStamp, region, service, amzDate, scope, canonicalRequest);
  return Uri.parse(
    'https://$host$canonicalPath?$canonicalQuery&X-Amz-Signature=$signature',
  );
}

/// A request signed in its headers: the URL to send it to (its path in
/// SigV4's canonical form) and every header to send, the signature
/// among them.
class SignedRequest {
  const SignedRequest(this.uri, this.headers);

  final Uri uri;
  final Map<String, String> headers;
}

/// Signs [method] [uri] with [body], for [region] and [service], with
/// [credentials]: adds `host`, `x-amz-date`, `x-amz-content-sha256`
/// (S3 wants it; the others ignore it), the session token when there is
/// one, and `Authorization` to [headers]. Every header given is signed.
SignedRequest signRequest({
  required AwsCredentials credentials,
  required String region,
  required String service,
  required String method,
  required Uri uri,
  Map<String, String> headers = const {},
  List<int> body = const [],
  DateTime? now,
}) {
  final at = (now ?? DateTime.now()).toUtc();
  final amzDate = amzDateOf(at);
  final dateStamp = amzDate.substring(0, 8);
  final scope = '$dateStamp/$region/$service/aws4_request';
  final payloadHash = sha256.convert(body).toString();
  final host = uri.hasPort && uri.port != (uri.scheme == 'https' ? 443 : 80) ? '${uri.host}:${uri.port}' : uri.host;
  final all = <String, String>{
    for (final e in headers.entries) e.key.toLowerCase().trim(): e.value.trim(),
    'host': host,
    'x-amz-date': amzDate,
    'x-amz-content-sha256': payloadHash,
    if (credentials.sessionToken.isNotEmpty) 'x-amz-security-token': credentials.sessionToken,
  };
  final names = all.keys.toList()..sort();
  final canonicalHeaders = names.map((n) => '$n:${all[n]}\n').join();
  final signedHeaders = names.join(';');
  final canonicalPath = '/${uri.pathSegments.map(awsEncode).join('/')}';
  final canonicalQuery = _canonicalQuery([
    for (final e in uri.queryParametersAll.entries)
      for (final v in e.value) (e.key, v),
  ]);
  final canonicalRequest = [
    method.toUpperCase(),
    canonicalPath,
    canonicalQuery,
    canonicalHeaders,
    signedHeaders,
    payloadHash,
  ].join('\n');
  final signature = _signature(credentials, dateStamp, region, service, amzDate, scope, canonicalRequest);
  final sent = {...all};
  sent.remove('host'); // the client sets it
  sent['authorization'] =
      'AWS4-HMAC-SHA256 Credential=${credentials.accessKeyId}/$scope, SignedHeaders=$signedHeaders, Signature=$signature';
  return SignedRequest(uri.replace(path: canonicalPath), sent);
}

/// `yyyyMMddTHHmmssZ`.
String amzDateOf(DateTime utc) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${utc.year}${two(utc.month)}${two(utc.day)}T'
      '${two(utc.hour)}${two(utc.minute)}${two(utc.second)}Z';
}

/// RFC 3986 encoding, as SigV4 wants it: only the unreserved characters
/// stay, the rest is %XX in upper case. [path] keeps its slashes.
String awsEncode(String value, {bool path = false}) {
  const unreserved = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~';
  final out = StringBuffer();
  for (final byte in utf8.encode(value)) {
    final char = String.fromCharCode(byte);
    if (unreserved.contains(char) || (path && char == '/')) {
      out.write(char);
    } else {
      out.write('%${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}');
    }
  }
  return out.toString();
}

String _canonicalPath(String path) {
  final p = path.startsWith('/') ? path : '/$path';
  return awsEncode(p, path: true);
}

/// Sorted by name, then by value, each encoded.
String _canonicalQuery(List<(String, String)> query) {
  final pairs = [for (final (n, v) in query) (awsEncode(n), awsEncode(v))]
    ..sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
  return pairs.map((p) => '${p.$1}=${p.$2}').join('&');
}

String _signature(AwsCredentials credentials, String dateStamp, String region, String service, String amzDate, String scope, String canonicalRequest) {
  final stringToSign = [
    'AWS4-HMAC-SHA256',
    amzDate,
    scope,
    sha256.convert(utf8.encode(canonicalRequest)).toString(),
  ].join('\n');
  return _hex(_hmac(_signingKey(credentials.secretAccessKey, dateStamp, region, service), stringToSign));
}

List<int> _hmac(List<int> key, String data) =>
    Hmac(sha256, key).convert(utf8.encode(data)).bytes;

List<int> _signingKey(String secret, String dateStamp, String region, String service) {
  final kDate = _hmac(utf8.encode('AWS4$secret'), dateStamp);
  final kRegion = _hmac(kDate, region);
  final kService = _hmac(kRegion, service);
  return _hmac(kService, 'aws4_request');
}

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
