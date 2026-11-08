/// DynamoDB from the server, with signed headers (aws_lite): the four
/// calls the tour's table needs (GetItem, PutItem, DeleteItem, Query; a
/// put or a delete conditional when asked, which is what keeps the
/// tournaments one at a time), and
/// [DynamoClient.call] for any other, on
/// AWS or, on a laptop, on Floci (an [endpoint] of its own).
library;

import 'dart:async';
import 'dart:convert';

import 'package:aws_lite/aws_lite.dart';
import 'package:http/http.dart' as http;

import 's3.dart' show AwsException;

/// An item: attribute names to DynamoDB's typed values ({"S": ...}).
typedef Item = Map<String, Object?>;

/// A conditional put or delete found its condition false.
class DynamoConditionFailed extends AwsException {
  const DynamoConditionFailed(super.status, super.message);
}

class DynamoClient {
  DynamoClient({required this.credentials, required this.region, Uri? endpoint, http.Client? client, this.timeout = const Duration(seconds: 20)})
    : endpoint = endpoint ?? Uri.parse('https://dynamodb.$region.amazonaws.com/'),
      _client = client ?? http.Client();

  final AwsCredentials credentials;
  final String region;
  final Uri endpoint;
  final http.Client _client;
  final Duration timeout;

  /// The item with [key], or null when there is none.
  Future<Item?> get(String table, Item key) async {
    final answer = await call('GetItem', {'TableName': table, 'Key': key, 'ConsistentRead': true});
    return (answer['Item'] as Map?)?.cast<String, Object?>();
  }

  /// Puts [item]; with [condition] (and its [names] and [values]), only
  /// when it holds: a [DynamoConditionFailed] otherwise.
  Future<void> put(String table, Item item, {String? condition, Map<String, String>? names, Item? values}) =>
      call('PutItem', {'TableName': table, 'Item': item, ..._condition(condition, names, values)});

  /// Deletes the item with [key]; with [condition], as [put].
  Future<void> delete(String table, Item key, {String? condition, Map<String, String>? names, Item? values}) =>
      call('DeleteItem', {'TableName': table, 'Key': key, ..._condition(condition, names, values)});

  static Map<String, Object?> _condition(String? condition, Map<String, String>? names, Item? values) => {
    'ConditionExpression': ?condition,
    if (names != null && names.isNotEmpty) 'ExpressionAttributeNames': names,
    if (values != null && values.isNotEmpty) 'ExpressionAttributeValues': values,
  };

  /// Every item whose partition key [name] is [value], page after page.
  Future<List<Item>> query(String table, String name, String value) async {
    final items = <Item>[];
    Object? start;
    do {
      final answer = await call('Query', {
        'TableName': table,
        'KeyConditionExpression': '#k = :v',
        'ExpressionAttributeNames': {'#k': name},
        'ExpressionAttributeValues': {
          ':v': {'S': value},
        },
        'ConsistentRead': true,
        'ExclusiveStartKey': ?start,
      });
      for (final i in (answer['Items'] as List?) ?? const []) {
        items.add((i as Map).cast<String, Object?>());
      }
      start = answer['LastEvaluatedKey'];
    } while (start != null);
    return items;
  }

  /// Any DynamoDB [operation] with its [payload]; its answer.
  Future<Map<String, Object?>> call(String operation, Map<String, Object?> payload) async {
    final body = utf8.encode(jsonEncode(payload));
    final signed = signRequest(
      credentials: credentials,
      region: region,
      service: 'dynamodb',
      method: 'POST',
      uri: endpoint,
      headers: {'content-type': 'application/x-amz-json-1.0', 'x-amz-target': 'DynamoDB_20120810.$operation'},
      body: body,
    );
    final request = http.Request('POST', signed.uri)
      ..headers.addAll(signed.headers)
      ..bodyBytes = body;
    final http.Response response;
    try {
      response = await http.Response.fromStream(await _client.send(request)).timeout(timeout);
    } on TimeoutException {
      throw const AwsException(0, 'DynamoDB did not answer');
    } catch (error) {
      throw AwsException(0, 'DynamoDB could not be reached (${error.runtimeType})');
    }
    final text = utf8.decode(response.bodyBytes, allowMalformed: true);
    if (response.statusCode != 200) {
      final error = (() {
        try {
          return (jsonDecode(text) as Map).cast<String, Object?>();
        } catch (_) {
          return const <String, Object?>{};
        }
      })();
      final type = '${error['__type'] ?? ''}'.split('#').last;
      final message = '${error['message'] ?? error['Message'] ?? ''}';
      final what = 'DynamoDB $operation: ${[type, message].where((s) => s.isNotEmpty).join(': ')}';
      if (type == 'ConditionalCheckFailedException') throw DynamoConditionFailed(response.statusCode, what);
      throw AwsException(response.statusCode, what);
    }
    return text.isEmpty ? const {} : (jsonDecode(text) as Map).cast<String, Object?>();
  }
}
