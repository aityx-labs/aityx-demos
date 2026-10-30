import 'dart:io';
import 'dart:math';

import 'package:healthhub_api/kafka_rest.dart';
import 'package:test/test.dart';

/// Against the real Kafka REST proxy (kafka-rest of compose.yaml, at
/// HEALTHHUB_KAFKA_REST_URL or 127.0.0.1:9805), when it is up; skipped
/// otherwise, so the suite passes without Docker.
void main() {
  test('a record produced through the proxy is consumed back', () async {
    final url = Platform.environment['HEALTHHUB_KAFKA_REST_URL'] ?? '';
    final kafka = KafkaRest(Uri.parse(url.isEmpty ? 'http://127.0.0.1:9805' : url));
    addTearDown(kafka.close);
    if (!await kafka.ping()) {
      markTestSkipped('Kafka REST proxy not answering');
      return;
    }
    // A topic of its own, so a test never writes into the moves a running
    // dev API reads. The proxy doesn't create topics: the kafka service's
    // health check makes this one along with healthhub.people.moves.
    const topic = 'healthhub.test';
    final id = 'live-${Random().nextInt(1 << 32)}';
    final consumer = await kafka.consumer('healthhub-test-$id', [topic]);
    addTearDown(consumer.close);

    // "latest" only applies once the consumer has its partitions, which
    // takes a poll or two: produce until the record comes back.
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      await kafka.produce(topic, [
        {'key': id, 'value': {'id': id, 'lat': 41.1554}},
      ]);
      final records = await consumer.poll(timeout: const Duration(seconds: 2));
      final mine = records.where((r) => r.key == id).toList();
      if (mine.isNotEmpty) {
        expect(mine.first.topic, topic);
        expect(mine.first.value, {'id': id, 'lat': 41.1554});
        return;
      }
    }
    fail('the record did not come back within 30 s');
  }, timeout: const Timeout(Duration(seconds: 60)));
}
