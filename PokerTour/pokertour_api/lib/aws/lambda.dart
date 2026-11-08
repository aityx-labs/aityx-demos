/// Lambda from the server: one call, the asynchronous invocation of the
/// runner function when an admin asks for a tournament now.
library;

import 'dart:async';
import 'dart:convert';

import 'package:aws_lite/aws_lite.dart';
import 'package:http/http.dart' as http;

import 's3.dart' show AwsException;

class LambdaClient {
  LambdaClient({required this.credentials, required this.region, http.Client? client, this.timeout = const Duration(seconds: 20)})
    : _client = client ?? http.Client();

  final AwsCredentials credentials;
  final String region;
  final http.Client _client;
  final Duration timeout;

  /// Invokes [function] with [payload] without waiting for it (Lambda
  /// queues the event and answers 202).
  Future<void> invokeAsync(String function, Object payload) async {
    final uri = Uri(scheme: 'https', host: 'lambda.$region.amazonaws.com', pathSegments: ['2015-03-31', 'functions', function, 'invocations']);
    final body = utf8.encode(jsonEncode(payload));
    final signed = signRequest(
      credentials: credentials,
      region: region,
      service: 'lambda',
      method: 'POST',
      uri: uri,
      headers: {'content-type': 'application/json', 'x-amz-invocation-type': 'Event'},
      body: body,
    );
    final request = http.Request('POST', signed.uri)
      ..headers.addAll(signed.headers)
      ..bodyBytes = body;
    final http.Response response;
    try {
      response = await http.Response.fromStream(await _client.send(request)).timeout(timeout);
    } on TimeoutException {
      throw const AwsException(0, 'Lambda did not answer');
    } catch (error) {
      throw AwsException(0, 'Lambda could not be reached (${error.runtimeType})');
    }
    if (response.statusCode != 202) {
      throw AwsException(response.statusCode, 'Lambda refused the invocation: ${utf8.decode(response.bodyBytes, allowMalformed: true)}');
    }
  }
}
