/// The tour: the strategies entered in it (the presets, as the house's,
/// and the players' uploads), their records, and the latest tournaments.
/// The players' strategies and aliases are in the tour's table
/// (lib/tour_db.dart: DynamoDB); the records and the history in one JSON
/// file, leaderboard.json, in the store (lib/store.dart: S3). [Boards]
/// reads both and writes them back, redoing a change when another writer
/// got in first. The runner (lib/runner.dart) plays the tournaments and
/// records their results here.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:poker_core/table.dart';

import 'auth.dart' show Identity, ownerIdOf;
import 'store.dart';
import 'tour_db.dart';

/// A strategy in the tour.
class TourEntry {
  TourEntry({
    required this.id,
    required this.strategy,
    required this.owner,
    required this.ownerEmail,
    required this.preset,
    required this.enteredAt,
    this.broken,
  });

  factory TourEntry.fromJson(Map<String, Object?> json) => TourEntry(
    id: json['id'] as String,
    strategy: Strategy.fromJson(json['strategy'], id: json['id'] as String, custom: json['preset'] != true),
    owner: json['owner'] as String? ?? '',
    ownerEmail: json['ownerEmail'] as String? ?? '',
    preset: json['preset'] == true,
    enteredAt: DateTime.tryParse(json['enteredAt'] as String? ?? '') ?? DateTime.now().toUtc(),
    broken: json['broken'] as String?,
  );

  final String id;
  final Strategy strategy;

  /// Who entered it, to show: a name, or "the house" for a preset.
  final String owner;

  /// The owner's email (never sent out) ; empty for a preset.
  final String ownerEmail;
  final bool preset;
  final DateTime enteredAt;

  /// Why the runner leaves it out: aityx refused its rules. Null while it
  /// plays.
  String? broken;

  String get ownerId => preset ? 'house' : ownerIdOf(ownerEmail);

  Map<String, Object?> toJson() => {
    'id': id,
    'strategy': strategy.toJson(),
    'owner': owner,
    'ownerEmail': ownerEmail,
    'preset': preset,
    'enteredAt': enteredAt.toUtc().toIso8601String(),
    'broken': broken,
  };

  /// For the leaderboard's standings: no email, no rules. [shownOwner]:
  /// the owner's alias, else [owner].
  Map<String, Object?> toStanding(Record record, {String? shownOwner}) => {
    'id': id,
    'name': strategy.name,
    'tagline': strategy.tagline,
    'owner': shownOwner ?? owner,
    'ownerId': ownerId,
    'preset': preset,
    'tournaments': record.tournaments,
    'wins': record.wins,
    'points': record.points,
    'best': record.best,
    'last': record.last,
    'broken': broken,
  };

  /// For GET /api/strategies (signed in): the rules, with the owner's
  /// alias or name, never the email.
  Map<String, Object?> toStrategy({String? shownOwner}) => {
    'id': id,
    'name': strategy.name,
    'tagline': strategy.tagline,
    'decisions': strategy.decisions,
    'owner': shownOwner ?? owner,
    'ownerId': ownerId,
    'preset': preset,
  };
}

/// How a strategy has done.
class Record {
  Record({this.tournaments = 0, this.wins = 0, this.points = 0, this.best, this.last});

  factory Record.fromJson(Map<String, Object?> json) => Record(
    tournaments: (json['tournaments'] as num?)?.toInt() ?? 0,
    wins: (json['wins'] as num?)?.toInt() ?? 0,
    points: (json['points'] as num?)?.toInt() ?? 0,
    best: (json['best'] as num?)?.toInt(),
    last: (json['last'] as num?)?.toInt(),
  );

  int tournaments;
  int wins;
  int points;
  int? best;
  int? last;

  /// A tournament of [players], finished in [place] (1 the winner): the
  /// winner of nine gets 8 points, the last 0.
  void add({required int place, required int players}) {
    tournaments++;
    if (place == 1) wins++;
    points += players - place;
    best = best == null ? place : min(best!, place);
    last = place;
  }

  Map<String, Object?> toJson() => {
    'tournaments': tournaments,
    'wins': wins,
    'points': points,
    'best': best,
    'last': last,
  };
}

/// A finished tournament, for the history.
class TournamentResult {
  const TournamentResult({required this.number, required this.finished, required this.places, required this.hands, required this.calls});

  factory TournamentResult.fromJson(Map<String, Object?> json) => TournamentResult(
    number: (json['number'] as num).toInt(),
    finished: DateTime.tryParse(json['finished'] as String? ?? '') ?? DateTime.now().toUtc(),
    hands: (json['hands'] as num?)?.toInt() ?? 0,
    calls: (json['calls'] as num?)?.toInt() ?? 0,
    places: ((json['places'] as List?) ?? const [])
        .map((p) => (p as Map).cast<String, Object?>())
        .map((p) => (id: p['id'] as String? ?? '', name: p['name'] as String? ?? '', place: (p['place'] as num?)?.toInt() ?? 0))
        .toList(),
  );

  final int number;
  final DateTime finished;
  final int hands;
  final int calls;
  final List<({String id, String name, int place})> places;

  Map<String, Object?> toJson() => {
    'number': number,
    'finished': finished.toUtc().toIso8601String(),
    'hands': hands,
    'calls': calls,
    'places': [
      for (final p in places) {'id': p.id, 'name': p.name, 'place': p.place},
    ],
  };
}

/// Entering a strategy failed: why, for the player.
class EntryException implements Exception {
  const EntryException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The tour's state: entries, records and history, in memory; [Boards]
/// reads and writes it.
class Leaderboard {
  Leaderboard({required this.models, this.maxPerPlayer = 3, this.historyKept = 20, Random? random})
    : _random = random ?? Random.secure() {
    // The presets, the house's players, are always in.
    for (final preset in models.strategies.values) {
      entries[preset.id] = TourEntry(
        id: preset.id,
        strategy: preset,
        owner: 'the house',
        ownerEmail: '',
        preset: true,
        enteredAt: DateTime.utc(2026),
      );
    }
  }

  final Models models;
  final int maxPerPlayer;
  final int historyKept;
  final Random _random;

  final entries = <String, TourEntry>{};
  final records = <String, Record>{};
  final history = <TournamentResult>[];
  int tournamentsPlayed = 0;

  /// Bumped by every change, so two changes never write the same file.
  int revision = 0;

  /// The players' aliases or names, by owner id ([Boards] fills it).
  final ownerNames = <String, String>{};

  /// How [e]'s owner is shown: their alias, else the name they entered
  /// it under; the house for a preset.
  String ownerOf(TourEntry e) => e.preset ? e.owner : ownerNames[e.ownerId] ?? e.owner;

  /// [e] for GET /api/strategies, its owner as shown.
  Map<String, Object?> strategyOf(TourEntry e) => e.toStrategy(shownOwner: ownerOf(e));

  Record recordOf(String id) => records.putIfAbsent(id, Record.new);

  /// The entries that can play: not broken.
  List<TourEntry> get playable => entries.values.where((e) => e.broken == null).toList();

  /// The standings: by points, then wins, then fewer tournaments, then name.
  List<Map<String, Object?>> standings() {
    final rows = entries.values.toList()
      ..sort((a, b) {
        final ra = recordOf(a.id), rb = recordOf(b.id);
        if (ra.points != rb.points) return rb.points - ra.points;
        if (ra.wins != rb.wins) return rb.wins - ra.wins;
        if (ra.tournaments != rb.tournaments) return ra.tournaments - rb.tournaments;
        return a.strategy.name.toLowerCase().compareTo(b.strategy.name.toLowerCase());
      });
    return [for (final e in rows) e.toStanding(recordOf(e.id), shownOwner: ownerOf(e))];
  }

  /// The most a player's entry may hold: every decision it makes sends
  /// all of it to aityx on the host's key (the largest preset, the Shark,
  /// is about 4 KB of decisions).
  static const maxTaglineLength = 200;
  static const maxDecisionsBytes = 16 * 1024;
  static const maxDecisions = 24;

  /// Whether [json] is a strategy (name, tagline, decisions) a player may
  /// enter: within the limits above, its name plain text on one line;
  /// throws [EntryException] with what's wrong.
  static void check(Object? json) {
    final Strategy strategy;
    try {
      strategy = Strategy.fromJson(json, id: 'entry', custom: true);
    } on InvalidRequest catch (e) {
      throw EntryException(e.message);
    }
    if (!isPlainLine(strategy.name)) throw EntryException('a strategy\'s name is plain text, on one line');
    if (strategy.tagline.length > maxTaglineLength) throw EntryException('a tagline has at most $maxTaglineLength characters');
    if (strategy.decisions.length > maxDecisions) throw EntryException('a strategy has at most $maxDecisions decisions');
    if (utf8.encode(jsonEncode(strategy.decisions)).length > maxDecisionsBytes) {
      throw EntryException('a strategy\'s decisions take at most ${maxDecisionsBytes ~/ 1024} KB');
    }
  }

  /// Whether [text] is plain text on one line: no control characters, and
  /// none of the invisible ones that could make a name pass for another
  /// (zero-width, direction overrides, line separators).
  static bool isPlainLine(String text) => !text.runes.any(
    (r) =>
        r < 0x20 ||
        (r >= 0x7f && r <= 0x9f) ||
        (r >= 0x200b && r <= 0x200f) ||
        (r >= 0x2028 && r <= 0x202e) ||
        (r >= 0x2060 && r <= 0x2069) ||
        r == 0xfeff,
  );

  /// [who]'s entry of [json]'s name when its tagline and rules are the
  /// same: entering it again changes nothing.
  TourEntry? unchanged(Identity who, Object? json) {
    if (json is! Map) return null;
    final name = json['name'] is String ? (json['name'] as String).trim().toLowerCase() : null;
    final same = entries.values
        .where((e) => !e.preset && e.ownerEmail == who.email && e.strategy.name.toLowerCase() == name)
        .firstOrNull;
    if (same == null) return null;
    final tagline = json['tagline'] is String ? json['tagline'] as String : '';
    return same.strategy.tagline == tagline && jsonEncode(same.strategy.decisions) == jsonEncode(json['decisions']) ? same : null;
  }

  /// Enters [json] (name, tagline, decisions) for [who]: checked as a
  /// strategy; the player's entry of the same name is replaced by one with
  /// a new id (so a tournament playing the old rules records nothing on
  /// the new ones), and at most [maxPerPlayer] entries a player. The
  /// caller checks the rules on aityx first.
  TourEntry enter(Identity who, Object? json) {
    final Strategy strategy;
    try {
      strategy = Strategy.fromJson(json, id: 'entry', custom: true);
    } on InvalidRequest catch (e) {
      throw EntryException(e.message);
    }
    final mine = entries.values.where((e) => !e.preset && e.ownerEmail == who.email).toList();
    final sameName = mine.where((e) => e.strategy.name.toLowerCase() == strategy.name.toLowerCase()).firstOrNull;
    if (sameName == null && mine.length >= maxPerPlayer) {
      throw EntryException('you already have $maxPerPlayer strategies in the tour; withdraw one first');
    }
    if (models.strategies.values.any((p) => p.name.toLowerCase() == strategy.name.toLowerCase())) {
      throw EntryException('"${strategy.name}" is a preset\'s name; call yours something else');
    }
    final id = _newId();
    final entry = TourEntry(
      id: id,
      strategy: Strategy(id: id, name: strategy.name, tagline: strategy.tagline, decisions: strategy.decisions, custom: true),
      owner: who.displayName,
      ownerEmail: who.email,
      preset: false,
      enteredAt: DateTime.now().toUtc(),
    );
    if (sameName != null) {
      entries.remove(sameName.id);
      records.remove(sameName.id);
    }
    entries[id] = entry;
    return entry;
  }

  /// Withdraws [id], when it is [who]'s; false when there is no such
  /// entry of theirs.
  bool withdraw(Identity who, String id) {
    final entry = entries[id];
    if (entry == null || entry.preset || entry.ownerEmail != who.email) return false;
    entries.remove(id);
    records.remove(id);
    return true;
  }

  /// Records a finished tournament: [places] in finishing order (the
  /// winner first), each an entry id and the name it played under.
  TournamentResult finish(List<({String id, String name, int place})> places, {required int hands, required int calls}) {
    tournamentsPlayed++;
    for (final p in places) {
      if (entries.containsKey(p.id)) recordOf(p.id).add(place: p.place, players: places.length);
    }
    final result = TournamentResult(number: tournamentsPlayed, finished: DateTime.now().toUtc(), places: places, hands: hands, calls: calls);
    history.insert(0, result);
    if (history.length > historyKept) history.removeRange(historyKept, history.length);
    return result;
  }

  /// Marks [id] broken for [why]: the runner leaves it out.
  void markBroken(String id, String why) {
    entries[id]?.broken = why;
  }

  String _newId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    while (true) {
      final id = 'u-${List.generate(8, (_) => chars[_random.nextInt(chars.length)]).join()}';
      if (!entries.containsKey(id)) return id;
    }
  }

  /// leaderboard.json: the records and the history. The entries are in
  /// the tour's table.
  Map<String, Object?> toJson() => {
    'revision': revision,
    'tournamentsPlayed': tournamentsPlayed,
    'records': {for (final MapEntry(:key, :value) in records.entries) key: value.toJson()},
    'history': [for (final t in history) t.toJson()],
  };

  /// Takes what [json] holds: every record, the history, and the uploads
  /// of a file from before the tour's table (moved there by the next
  /// [Boards.update]).
  void fromJson(Map<String, Object?> json) {
    revision = (json['revision'] as num?)?.toInt() ?? 0;
    tournamentsPlayed = (json['tournamentsPlayed'] as num?)?.toInt() ?? 0;
    for (final e in (json['entries'] as List?) ?? const []) {
      try {
        final entry = TourEntry.fromJson((e as Map).cast());
        if (!entry.preset) entries[entry.id] = entry;
      } catch (error) {
        stderr.writeln('leaderboard: an entry could not be read, skipped: $error');
      }
    }
    for (final MapEntry(:key, :value) in ((json['records'] as Map?) ?? const {}).entries) {
      if (value is Map) records[key as String] = Record.fromJson(value.cast());
    }
    history
      ..clear()
      ..addAll([
        for (final t in (json['history'] as List?) ?? const []) TournamentResult.fromJson((t as Map).cast()),
      ]);
    // A broken preset plays again after a restart: its rules may have
    // been fixed.
    for (final e in entries.values) {
      if (e.preset) e.broken = null;
    }
  }
}

/// The leaderboard: the players' strategies and aliases from the tour's
/// table, the records and the history from leaderboard.json, read for
/// every look. [update] reads both, applies the change, and writes
/// leaderboard.json back only if nobody else wrote in between (the
/// store's conditional write; every change bumps its revision), trying
/// again a few times otherwise; then it puts and deletes the strategies
/// the change touched. On AWS the API and the runner are different
/// processes; this is what keeps an entry made during a tournament from
/// being lost when the result is recorded.
class Boards {
  Boards({required this.store, required this.models, TourDb? db, this.maxPerPlayer = 3, this.name = 'leaderboard.json', Random? random})
    : db = db ?? MemoryTourDb(),
      _random = random ?? Random.secure();

  final Store store;
  final TourDb db;
  final Models models;
  final int maxPerPlayer;
  final String name;
  final Random _random;

  Leaderboard _fresh() => Leaderboard(models: models, maxPerPlayer: maxPerPlayer, random: _random);

  /// The leaderboard as stored, its file's version ('' when there is no
  /// file yet), and the strategies as the table has them (id to JSON).
  Future<(Leaderboard, String, Map<String, String>)> _load() async {
    final board = _fresh();
    final stored = await store.read(name);
    if (stored != null) {
      try {
        final json = jsonDecode(stored.text);
        if (json is Map) board.fromJson(json.cast<String, Object?>());
      } catch (error) {
        stderr.writeln('leaderboard: $name could not be read, starting afresh: $error');
      }
    }
    final inTable = <String, String>{};
    for (final e in await db.entries()) {
      if (e.preset) continue;
      board.entries[e.id] = e;
      inTable[e.id] = jsonEncode(e.toJson());
    }
    for (final p in await db.players()) {
      board.ownerNames[p.ownerId] = p.shown;
    }
    return (board, stored?.version ?? '', inTable);
  }

  Future<(Leaderboard, String)> load() async {
    final (board, version, _) = await _load();
    return (board, version);
  }

  Future<Leaderboard> read() async => (await _load()).$1;

  /// Applies [change] to the stored leaderboard and writes it back,
  /// again from a fresh read when another writer got in first (up to
  /// [attempts] times); what [change] returned. An exception from
  /// [change] (an [EntryException]) writes nothing.
  Future<T> update<T>(T Function(Leaderboard board) change, {int attempts = 5}) async {
    for (var attempt = 1; ; attempt++) {
      final (board, version, inTable) = await _load();
      final result = change(board);
      board.revision++;
      try {
        await store.write(name, const JsonEncoder.withIndent('  ').convert(board.toJson()), ifVersion: version);
      } on StoreConflict {
        if (attempt >= attempts) rethrow;
        continue;
      }
      final now = {for (final e in board.entries.values) if (!e.preset) e.id: e};
      for (final MapEntry(:key, :value) in now.entries) {
        if (inTable[key] != jsonEncode(value.toJson())) await db.putEntry(value);
      }
      for (final id in inTable.keys) {
        if (!now.containsKey(id)) await db.deleteEntry(id);
      }
      return result;
    }
  }
}
