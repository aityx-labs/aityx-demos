/// Where the tour keeps its strategies and its players' aliases: a
/// DynamoDB table (on AWS, and on a laptop in Floci), or memory in tests.
/// One table, two kinds of item under a partition key each:
///
///   pk STRATEGY, sk the entry's id    a player's strategy in the tour
///   pk PLAYER,   sk the owner's id    a player's name and alias
///
/// with the rest as JSON in `data`. The presets are not in it (they come
/// with the models), nor are the records and the history (leaderboard.json,
/// lib/leaderboard.dart).
library;

import 'dart:convert';
import 'dart:io';

import 'aws/dynamodb.dart';
import 'leaderboard.dart' show TourEntry;

/// A player, as the leaderboard names them: their alias, else their name.
class Player {
  const Player({required this.ownerId, required this.name, this.alias});

  factory Player.fromJson(Map<String, Object?> json) => Player(
    ownerId: json['ownerId'] as String,
    name: json['name'] as String? ?? '',
    alias: json['alias'] as String?,
  );

  final String ownerId;

  /// The Google name (or the email's local part).
  final String name;

  /// What they chose to be called; null for their name.
  final String? alias;

  String get shown => (alias ?? '').trim().isNotEmpty ? alias!.trim() : name;

  Map<String, Object?> toJson() => {'ownerId': ownerId, 'name': name, 'alias': alias};
}

abstract interface class TourDb {
  /// The players' strategies in the tour.
  Future<List<TourEntry>> entries();

  Future<void> putEntry(TourEntry entry);

  Future<void> deleteEntry(String id);

  Future<List<Player>> players();

  Future<Player?> player(String ownerId);

  Future<void> putPlayer(Player player);
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
}
