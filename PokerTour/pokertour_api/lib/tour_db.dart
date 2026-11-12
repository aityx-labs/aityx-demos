/// Where the tour keeps its strategies and its players' aliases: a
/// DynamoDB table (on AWS, and on a laptop in Floci), or memory in tests.
/// One table, four kinds of item under a partition key each:
///
///   pk STRATEGY, sk the entry's id    a player's strategy in the tour
///   pk PLAYER,   sk the owner's id    a player's name and alias
///   pk QUEUE,    sk the source        a tournament asked for, waiting
///                                     (lib/queue.dart): one per source
///   pk RUNNER,   sk LOCK              who is playing the tournaments, and
///                                     until when (`holder`, `until` in ms)
///
/// with the rest as JSON in `data`. The presets are not in it (they come
/// with the models), nor are the records and the history (leaderboard.json,
/// lib/leaderboard.dart).
library;

import 'dart:convert';
import 'dart:io';

import 'aws/dynamodb.dart';
import 'leaderboard.dart' show TourEntry;
import 'queue.dart' show TournamentRequest;

/// A player, as the leaderboard names them: their alias, else their name.
class Player {
  const Player({required this.ownerId, required this.name, this.alias, this.lastEntryAt});

  factory Player.fromJson(Map<String, Object?> json) => Player(
    ownerId: json['ownerId'] as String,
    name: json['name'] as String? ?? '',
    alias: json['alias'] as String?,
    lastEntryAt: DateTime.tryParse(json['lastEntryAt'] as String? ?? '')?.toUtc(),
  );

  final String ownerId;

  /// The Google name (or the email's local part).
  final String name;

  /// What they chose to be called; null for their name.
  final String? alias;

  /// When they last asked to enter a strategy (checked on aityx or not):
  /// entries are rate-limited per player.
  final DateTime? lastEntryAt;

  String get shown => (alias ?? '').trim().isNotEmpty ? alias!.trim() : name;

  Map<String, Object?> toJson() => {
    'ownerId': ownerId,
    'name': name,
    'alias': alias,
    if (lastEntryAt != null) 'lastEntryAt': lastEntryAt!.toUtc().toIso8601String(),
  };
}

abstract interface class TourDb {
  /// The players' strategies in the tour.
  Future<List<TourEntry>> entries();

  Future<void> putEntry(TourEntry entry);

  Future<void> deleteEntry(String id);

  Future<List<Player>> players();

  Future<Player?> player(String ownerId);

  Future<void> putPlayer(Player player);

  /// Queues [request]: false when one from its source is waiting already.
  Future<bool> enqueue(TournamentRequest request);

  /// The tournaments waiting, in no order.
  Future<List<TournamentRequest>> queued();

  /// Takes [source]'s request out of the queue: false when it was gone.
  Future<bool> dequeue(String source);

  /// Takes the runner's lock for [holder] until [until]: when nobody
  /// holds it, its holder's time ran out by [now], or [holder] has it.
  Future<bool> lock(String holder, DateTime until, DateTime now);

  /// Whether someone holds the lock at [now].
  Future<bool> locked(DateTime now);

  /// Lets the lock go, when [holder] has it; any holder's when null (a
  /// laptop's server at its start, the table's only player).
  Future<void> unlock(String? holder);
}

/// In memory: for tests.
class MemoryTourDb implements TourDb {
  final _entries = <String, String>{};
  final _players = <String, Player>{};

  @override
  Future<List<TourEntry>> entries() async => [
    for (final e in _entries.values) TourEntry.fromJson((jsonDecode(e) as Map).cast()),
  ];

  @override
  Future<void> putEntry(TourEntry entry) async => _entries[entry.id] = jsonEncode(entry.toJson());

  @override
  Future<void> deleteEntry(String id) async => _entries.remove(id);

  @override
  Future<List<Player>> players() async => _players.values.toList();

  @override
  Future<Player?> player(String ownerId) async => _players[ownerId];

  @override
  Future<void> putPlayer(Player player) async => _players[player.ownerId] = player;

  final _queue = <String, TournamentRequest>{};
  (String, DateTime)? _lock;

  @override
  Future<bool> enqueue(TournamentRequest request) async {
    if (_queue.containsKey(request.source)) return false;
    _queue[request.source] = request;
    return true;
  }

  @override
  Future<List<TournamentRequest>> queued() async => _queue.values.toList();

  @override
  Future<bool> dequeue(String source) async => _queue.remove(source) != null;

  @override
  Future<bool> lock(String holder, DateTime until, DateTime now) async {
    final lock = _lock;
    if (lock != null && lock.$1 != holder && lock.$2.isAfter(now)) return false;
    _lock = (holder, until);
    return true;
  }

  @override
  Future<bool> locked(DateTime now) async => _lock != null && _lock!.$2.isAfter(now);

  @override
  Future<void> unlock(String? holder) async {
    if (holder == null || _lock?.$1 == holder) _lock = null;
  }
}

class DynamoTourDb implements TourDb {
  DynamoTourDb(this.dynamo, this.table);

  final DynamoClient dynamo;
  final String table;

  static Map<String, Object?> _key(String pk, String sk) => {
    'pk': {'S': pk},
    'sk': {'S': sk},
  };

  static Map<String, Object?> _item(String pk, String sk, Map<String, Object?> data) => {
    ..._key(pk, sk),
    'data': {'S': jsonEncode(data)},
  };

  static Map<String, Object?>? _data(Map<String, Object?> item) {
    final text = (item['data'] as Map?)?['S'];
    if (text is! String) return null;
    try {
      return (jsonDecode(text) as Map).cast();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<TourEntry>> entries() async {
    final out = <TourEntry>[];
    for (final item in await dynamo.query(table, 'pk', 'STRATEGY')) {
      try {
        out.add(TourEntry.fromJson(_data(item)!));
      } catch (error) {
        stderr.writeln('tour db: a strategy could not be read, skipped: $error');
      }
    }
    return out;
  }

  @override
  Future<void> putEntry(TourEntry entry) => dynamo.put(table, _item('STRATEGY', entry.id, entry.toJson()));

  @override
  Future<void> deleteEntry(String id) => dynamo.delete(table, _key('STRATEGY', id));

  @override
  Future<List<Player>> players() async => [
    for (final item in await dynamo.query(table, 'pk', 'PLAYER'))
      if (_data(item) case final data?) Player.fromJson(data),
  ];

  @override
  Future<Player?> player(String ownerId) async {
    final item = await dynamo.get(table, _key('PLAYER', ownerId));
    final data = item == null ? null : _data(item);
    return data == null ? null : Player.fromJson(data);
  }

  @override
  Future<void> putPlayer(Player player) => dynamo.put(table, _item('PLAYER', player.ownerId, player.toJson()));

  @override
  Future<bool> enqueue(TournamentRequest request) async {
    try {
      await dynamo.put(table, _item('QUEUE', request.source, request.toJson()), condition: 'attribute_not_exists(pk)');
      return true;
    } on DynamoConditionFailed {
      return false;
    }
  }

  @override
  Future<List<TournamentRequest>> queued() async {
    final out = <TournamentRequest>[];
    for (final item in await dynamo.query(table, 'pk', 'QUEUE')) {
      try {
        out.add(TournamentRequest.fromJson(_data(item)!));
      } catch (error) {
        stderr.writeln('tour db: a queued tournament could not be read, skipped: $error');
      }
    }
    return out;
  }

  @override
  Future<bool> dequeue(String source) async {
    try {
      await dynamo.delete(table, _key('QUEUE', source), condition: 'attribute_exists(pk)');
      return true;
    } on DynamoConditionFailed {
      return false;
    }
  }

  static final _lockKey = _key('RUNNER', 'LOCK');

  @override
  Future<bool> lock(String holder, DateTime until, DateTime now) async {
    try {
      await dynamo.put(
        table,
        {
          ..._lockKey,
          'holder': {'S': holder},
          'until': {'N': '${until.millisecondsSinceEpoch}'},
        },
        condition: 'attribute_not_exists(pk) OR #until <= :now OR #holder = :holder',
        names: {'#until': 'until', '#holder': 'holder'},
        values: {
          ':now': {'N': '${now.millisecondsSinceEpoch}'},
          ':holder': {'S': holder},
        },
      );
      return true;
    } on DynamoConditionFailed {
      return false;
    }
  }

  @override
  Future<bool> locked(DateTime now) async {
    final item = await dynamo.get(table, _lockKey);
    final until = int.tryParse('${(item?['until'] as Map?)?['N']}');
    return until != null && until > now.millisecondsSinceEpoch;
  }

  @override
  Future<void> unlock(String? holder) async {
    try {
      if (holder == null) {
        await dynamo.delete(table, _lockKey);
      } else {
        await dynamo.delete(
          table,
          _lockKey,
          condition: '#holder = :holder',
          names: {'#holder': 'holder'},
          values: {
            ':holder': {'S': holder},
          },
        );
      }
    } on DynamoConditionFailed {
      // Another holder's lock, after ours lapsed: theirs to let go.
    }
  }
}
