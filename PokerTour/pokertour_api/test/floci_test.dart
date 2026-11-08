/// The tour's table and bucket code against Floci, the local AWS
/// (floci/compose.yaml, `devbox services up`): a table of its own, made and
/// dropped here, and a prefix of its own in the local bucket. Skipped when
/// Floci isn't running.
library;

import 'dart:io';
import 'dart:math';

import 'package:aws_lite/aws_lite.dart';
import 'package:poker_core/table.dart';
import 'package:pokertour_api/auth.dart';
import 'package:pokertour_api/aws/dynamodb.dart';
import 'package:pokertour_api/aws/s3.dart';
import 'package:pokertour_api/leaderboard.dart';
import 'package:pokertour_api/store.dart';
import 'package:pokertour_api/tour_db.dart';
import 'package:test/test.dart';

import 'models.dart';
import 'queue_test.dart' show queueRules;

const credentials = AwsCredentials(accessKeyId: 'test', secretAccessKey: 'test');

Future<bool> _up(Uri floci) async {
  try {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    final request = await client.getUrl(floci.resolve('/_floci/init'));
    final response = await request.close();
    await response.drain<void>();
    client.close();
    return response.statusCode == 200;
  } catch (_) {
    return false;
  }
}

void main() async {
  final env = Platform.environment;
  final floci = Uri.parse((env['POKERTOUR_AWS_ENDPOINT'] ?? '').isEmpty ? 'http://localhost:9811' : env['POKERTOUR_AWS_ENDPOINT']!);
  final up = await _up(floci);
  final run = 'test-${Random().nextInt(1 << 30)}';
  final dynamo = DynamoClient(credentials: credentials, region: 'us-east-1', endpoint: floci);
  final s3 = S3Client(credentials: credentials, region: 'us-east-1', endpoint: floci);
  late Models models;

  setUpAll(() async {
    if (!up) return;
    models = await loadModels();
    await dynamo.call('CreateTable', {
      'TableName': run,
      'AttributeDefinitions': [
        {'AttributeName': 'pk', 'AttributeType': 'S'},
        {'AttributeName': 'sk', 'AttributeType': 'S'},
      ],
      'KeySchema': [
        {'AttributeName': 'pk', 'KeyType': 'HASH'},
        {'AttributeName': 'sk', 'KeyType': 'RANGE'},
      ],
      'BillingMode': 'PAY_PER_REQUEST',
    });
  });
  tearDownAll(() async {
    if (!up) return;
    await dynamo.call('DeleteTable', {'TableName': run});
    for (final name in ['leaderboard.json', 'live.json']) {
      await s3.delete('pokertour-local', '$run/$name');
    }
  });

  test('strategies and aliases round-trip through DynamoDB; the file through S3', () async {
    const ana = Identity(subject: '1', email: 'ana@aletyx.com', name: 'Ana');
    final db = DynamoTourDb(dynamo, run);
    final boards = Boards(store: S3Store(s3, 'pokertour-local', prefix: '$run/'), db: db, models: models);
    final rules = {
      'name': 'Ana One',
      'tagline': '',
      'decisions': {'action': {'expr': '"call"'}, 'raise_to': {'expr': 'min_raise'}},
    };
    final entry = await boards.update((b) => b.enter(ana, rules));
    await db.putPlayer(Player(ownerId: ana.ownerId, name: 'Ana', alias: 'River Queen'));

    final board = await boards.read();
    expect(board.entries[entry.id]?.strategy.name, 'Ana One');
    expect(board.standings().firstWhere((r) => r['id'] == entry.id)['owner'], 'River Queen');
    expect((await db.player(ana.ownerId))?.alias, 'River Queen');
    expect(await db.player('nobody'), isNull);

    await boards.update((b) => b.withdraw(ana, entry.id));
    expect(await db.entries(), isEmpty);
    expect((await s3.get('pokertour-local', '$run/leaderboard.json'))?.text, contains('"revision"'));
  }, skip: up ? false : 'Floci is not running at $floci (devbox services up)');

  group('the tournament queue in DynamoDB', () {
    // Each test its own table's items: the queue and the lock are one per table.
    setUp(() async {
      if (!up) return;
      for (final source in ['schedule', 'admin', 'strategy']) {
        await dynamo.delete(run, {'pk': {'S': 'QUEUE'}, 'sk': {'S': source}});
      }
      await dynamo.delete(run, {'pk': {'S': 'RUNNER'}, 'sk': {'S': 'LOCK'}});
    });
    queueRules(() => DynamoTourDb(dynamo, run));
  }, skip: up ? false : 'Floci is not running at $floci (devbox services up)');
}
