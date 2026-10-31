/// Kafka through its REST proxy: Karapace, the kafka-rest service of
/// compose.yaml, which speaks the Confluent REST Proxy v2 API. Plain HTTP
/// with dart:io, so the API needs no Kafka client library, and the
/// single native executable stays one.
///
/// Every call throws on a failure (no answer, or a status that isn't 2xx);
/// callers retry.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// The v2 API's media types: JSON records, and everything else.
const kafkaJson = 'application/vnd.kafka.json.v2+json';
const kafkaV2 = 'application/vnd.kafka.v2+json';

/// A record read from a topic.
class KafkaRecord {
  const KafkaRecord({
    required this.topic,
    required this.key,
    required this.value,
    required this.partition,
    required this.offset,
  });

  final String topic;
  final Object? key;
  final Object? value;
  final int partition;
  final int offset;
}

/// A call the proxy refused, with its status and body.
class KafkaRestException implements Exception {
  const KafkaRestException(this.status, this.body, this.what);

  final int status;
  final String body;
  final String what;

  @override
  String toString() => 'Kafka REST $what: $status $body';
}

class KafkaRest {
  /// [base]: the proxy's URL, HEALTHHUB_KAFKA_REST_URL. One [HttpClient]
  /// for every call, so the people of the simulation share its pooled
  /// connections instead of opening one each per turn.
  KafkaRest(this.base, {HttpClient? client})
    : _client = client ?? (HttpClient()..connectionTimeout = const Duration(seconds: 5));

  final Uri base;
  final HttpClient _client;

  /// How long one call may take; a records poll adds its own timeout.
  static const _timeout = Duration(seconds: 10);

  /// Whether the proxy answers GET /topics with 200: the health check.
  Future<bool> ping() async {
    try {
      await _call('GET', '/topics', what: 'list topics', timeout: const Duration(seconds: 3));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Writes JSON [records] to [topic], each a {"key", "value"} map. The
  /// proxy reports a failed record in its answer, not in the status, so
  /// that throws too.
  Future<void> produce(String topic, List<Map<String, Object?>> records) async {
    final answer = await _call(
      'POST',
      '/topics/${Uri.encodeComponent(topic)}',
      what: 'produce to $topic',
      contentType: kafkaJson,
      body: {'records': records},
    );
    final offsets = answer is Map ? answer['offsets'] : null;
    if (offsets is List) {
      for (final offset in offsets) {
        if (offset is Map && offset['error_code'] != null) {
          throw KafkaRestException(200, jsonEncode(offset), 'produce to $topic');
        }
      }
    }
  }

  /// A new consumer instance in [group], reading JSON from [topics]; when
  /// the group has no committed offset yet, from [offsetReset]: `latest`,
  /// the newest records on, or `earliest`, every record the topic keeps.
  /// The proxy commits the offsets read (Karapace's default, said here so
  /// a stable group resumes where it was even if the default changes).
  Future<KafkaConsumer> consumer(
    String group,
    List<String> topics, {
    String? name,
    String offsetReset = 'latest',
  }) async {
    if (offsetReset != 'latest' && offsetReset != 'earliest') {
      throw ArgumentError.value(offsetReset, 'offsetReset', 'is latest or earliest');
    }
    final groupPath = '/consumers/${Uri.encodeComponent(group)}';
    final created = await _call(
      'POST',
      groupPath,
      what: 'create a consumer in $group',
      contentType: kafkaV2,
      body: {
        'name': ?name,
        'format': 'json',
        'auto.offset.reset': offsetReset,
        'auto.commit.enable': 'true',
      },
    );
    final instance = created is Map ? created['instance_id'] : null;
    if (instance is! String) {
      throw KafkaRestException(200, jsonEncode(created), 'create a consumer in $group');
    }
    // Built from our own base, not the answer's base_uri, which names the
    // host the proxy advertises and may not resolve from here.
    final consumer = KafkaConsumer._(this, '$groupPath/instances/${Uri.encodeComponent(instance)}');
    try {
      await _call(
        'POST',
        '${consumer.path}/subscription',
        what: 'subscribe to $topics',
        contentType: kafkaV2,
        body: {'topics': topics},
      );
    } catch (_) {
      await consumer.close();
      rethrow;
    }
    return consumer;
  }

  /// One call: [body] as JSON, the answer's JSON (null when empty).
  Future<Object?> _call(
    String method,
    String path, {
    required String what,
    String? contentType,
    String accept = kafkaV2,
    Object? body,
    Duration timeout = _timeout,
  }) async {
    final request = await _client.openUrl(method, Uri.parse(_join('$base', path))).timeout(timeout);
    request.headers.set(HttpHeaders.acceptHeader, accept);
    if (body != null) {
      request.headers.set(HttpHeaders.contentTypeHeader, contentType ?? kafkaV2);
      request.add(utf8.encode(jsonEncode(body)));
    }
    final HttpClientResponse response;
    final String text;
    try {
      response = await request.close().timeout(timeout);
      text = await response.transform(utf8.decoder).join().timeout(timeout);
    } on TimeoutException {
      // A timeout only stops the wait: abort, or a proxy that never
      // answers keeps one socket open per call.
      request.abort();
      rethrow;
    }
    if (response.statusCode < 200 || response.statusCode > 299) {
      throw KafkaRestException(response.statusCode, text, what);
    }
    return text.isEmpty ? null : jsonDecode(text);
  }

  /// Closes the connections; calls after this fail.
  void close() => _client.close(force: true);
}

/// A consumer instance on the proxy. Close it when done: otherwise the
/// proxy keeps it, and its group membership, until its idle timeout
/// (KARAPACE_CONSUMER_IDLE_DISCONNECT_TIMEOUT in compose.yaml).
class KafkaConsumer {
  KafkaConsumer._(this._rest, this.path);

  final KafkaRest _rest;

  /// The instance's path on the proxy.
  final String path;

  /// The records that arrived since the last poll, waiting up to
  /// [timeout] on the proxy for some when there are none.
  Future<List<KafkaRecord>> poll({Duration timeout = const Duration(seconds: 1)}) async {
    final answer = await _rest._call(
      'GET',
      '$path/records?timeout=${timeout.inMilliseconds}',
      what: 'read records',
      accept: kafkaJson,
      timeout: timeout + KafkaRest._timeout,
    );
    if (answer is! List) return const [];
    return [
      for (final record in answer)
        if (record is Map)
          KafkaRecord(
            topic: record['topic'] as String? ?? '',
            key: record['key'],
            value: record['value'],
            partition: (record['partition'] as num?)?.toInt() ?? 0,
            offset: (record['offset'] as num?)?.toInt() ?? 0,
          ),
    ];
  }

  /// Deletes the instance; a failure is ignored, since the proxy drops an
  /// idle instance after its idle timeout.
  Future<void> close() async {
    try {
      await _rest._call('DELETE', path, what: 'delete a consumer', contentType: kafkaV2);
    } catch (_) {}
  }
}

/// [base] and [path] joined with one slash; [path] may carry a query.
String _join(String base, String path) =>
    base.endsWith('/') ? '${base.substring(0, base.length - 1)}$path' : '$base$path';
