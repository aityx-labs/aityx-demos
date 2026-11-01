/// Triage at the desk ([specs/triage.md](../../specs/triage.md)): each
/// admission the API records is triaged by aityx from what the patient
/// said at the desk and their age, and nothing else (not their condition,
/// which the simulation knows and a desk wouldn't). One call to aityx's
/// /v1/systemone does it: Jev reads the complaint into the probabilities
/// of eight danger signs and four choices, and the decision
/// (data/triage/triage.json, compiled in as lib/triage_seed.dart by
/// tool/generate_triage.dart) turns them into the level, the longest
/// wait, the area of the hospital, and whether a nurse confirms it, with
/// the rule behind each. The answer's receipt is kept with it.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'conditions.dart';
import 'conditions_seed.dart';
import 'triage_seed.dart';

/// Jev's questions and the decision: the request aityx gets, but its
/// state.
final Map<String, Object?> triageModel = (jsonDecode(triageModelJson) as Map).cast<String, Object?>();

/// The danger signs Jev gives a probability of, by the name of its
/// question less `_probability`, most urgent first.
const dangerSigns = [
  'life_threat',
  'breathing',
  'cardiac',
  'stroke',
  'major_injury',
  'serious_infection',
  'dehydration',
  'self_harm',
];

/// The questions Jev answers with one of their options.
const triageChoices = ['pain', 'onset', 'visit_purpose', 'body_system'];

/// The areas of the hospital a patient goes to.
const triageAreas = ['resuscitation', 'emergency', 'mental_health', 'minor_care', 'outpatients', 'day_unit'];

/// The body aityx gets for one patient: [model]'s questions and decision
/// ([triageModel] unless given), and the state, what the desk knows.
Map<String, Object?> triageRequest({required String complaint, required int age, Map<String, Object?>? model}) => {
  ...(model ?? triageModel),
  'state': {'complaint': complaint, 'age': age},
};

/// aityx's answer held no triage.
class TriageFailed implements Exception {
  TriageFailed(this.message);

  final String message;

  @override
  String toString() => message;
}

/// One rule of a decision table that fired: its number (the receipt's,
/// from 1, the header being row 0) and its `# why`.
typedef FiredRule = ({int rule, String? why});

/// What aityx decided for one patient, and what it read to decide it.
class TriageResult {
  const TriageResult({
    required this.level,
    required this.waitMinutes,
    required this.area,
    required this.nurseCheck,
    required this.levelRule,
    required this.areaRule,
    required this.signs,
    required this.choices,
    required this.receipt,
    this.inputTokens,
  });

  /// One of [triageLevels].
  final String level;
  final int waitMinutes;

  /// One of [triageAreas].
  final String area;

  /// Whether a nurse confirms the level: a danger sign in doubt, or a
  /// fever at 65 or older.
  final bool nurseCheck;
  final FiredRule? levelRule;
  final FiredRule? areaRule;

  /// Each of [dangerSigns], Jev's probability that it is present.
  final Map<String, double> signs;

  /// Each of [triageChoices], Jev's option and its confidence.
  final Map<String, ({String choice, double? confidence})> choices;

  /// aityx's receipt: what it read from Jev, where each input came from,
  /// and each decision's value and rule.
  final Map<String, Object?> receipt;
  final int? inputTokens;

  Map<String, Object?> get signsJson => {for (final e in signs.entries) e.key: e.value};

  Map<String, Object?> get choicesJson => {
    for (final e in choices.entries) e.key: {'choice': e.value.choice, 'confidence': e.value.confidence},
  };
}

/// The triage in aityx's [answer] to [sent] ([triageRequest]); throws
/// [TriageFailed] when it holds none.
TriageResult toTriage(Map<String, Object?> sent, Map<String, Object?> answer) {
  if (answer['decision_error'] case final Object error) {
    throw TriageFailed('the triage decision failed: ${error is Map ? error['code'] ?? error : error}');
  }
  final answers = answer['answers'];
  final receipt = answer['receipt'];
  if (answers is! Map || receipt is! Map) throw TriageFailed('aityx answered no triage');
  T read<T>(String name, String field) {
    final value = (answers[name] as Map?)?[field];
    if (value is! T) throw TriageFailed('aityx answered no $name');
    return value;
  }

  final level = read<String>('level', 'choice');
  if (!triageLevels.contains(level)) throw TriageFailed('aityx answered an unknown level $level');
  final area = read<String>('area', 'choice');
  final decisions = ((receipt['decisions'] as Map?) ?? const {}).cast<String, Object?>();
  final tables = _tables(sent);
  FiredRule? fired(String decision) {
    final rule = (decisions[decision] as Map?)?['rule'];
    final rows = tables[decision];
    if (rule is! int || rows == null || rule < 1 || rule >= rows.length) return null;
    return (rule: rule, why: _why(rows[0], rows[rule]));
  }

  final usage = answer['usage'];
  return TriageResult(
    level: level,
    waitMinutes: read<num>('wait_minutes', 'number').round(),
    area: area,
    nurseCheck: read<num>('nurse_check', 'noul') >= 0.5,
    levelRule: fired('level'),
    areaRule: fired('area'),
    signs: {for (final sign in dangerSigns) sign: read<num>('${sign}_probability', 'noul').toDouble()},
    choices: {
      for (final name in triageChoices)
        name: (
          choice: read<String>(name, 'choice'),
          confidence: ((answers[name] as Map)['confidence'] as num?)?.toDouble(),
        ),
    },
    receipt: receipt.cast<String, Object?>(),
    inputTokens: usage is Map ? (usage['input_tokens'] as num?)?.toInt() : null,
  );
}

/// The `# why` of each rule of [decision]'s table in [triageModel], in
/// the order aityx tries them (rule 1 first): what a triage's detail
/// shows, each rule up to the one that fired.
List<String?> triageRules(String decision) {
  final table = _tables(triageModel)[decision];
  if (table == null) return const [];
  return [for (final row in table.skip(1)) _why(table[0], row)];
}

/// The decision tables of [sent]'s decision, by name: each a list of
/// rows, the header first.
Map<String, List<Object?>> _tables(Map<String, Object?> sent) {
  final decisions = ((sent['decision'] as Map?)?['decisions'] as Map?) ?? const {};
  return {
    for (final MapEntry(:key, :value) in decisions.entries)
      if (value is Map && value['table'] is List) key as String: value['table'] as List<Object?>,
  };
}

/// A table row's `# why`: the `why` of a when/then row, or the cell under
/// the header's `# why` of a row written as an array.
String? _why(Object? header, Object? row) {
  if (row is Map) return row['why'] as String?;
  if (header is List && row is List) {
    final at = header.indexOf('# why');
    if (at >= 0 && at < row.length) return row[at] as String?;
  }
  return null;
}

/// The reference level of what a patient with [conditionCode] says on a
/// visit of kind [visit] (first, repeat or last), from its [template]
/// (0 to 2): the level a nurse applying the same policy gives it
/// ([MedicalCondition.triageOf]). Null when any of them is unknown.
String? referenceLevel(List<MedicalCondition> conditions, Object? conditionCode, Object? visit, Object? template) {
  if (template is! int) return null;
  for (final condition in conditions) {
    if (condition.code != conditionCode) continue;
    for (final kind in VisitKind.values) {
      if (kind.json != visit) continue;
      final levels = condition.triageOf(kind);
      return template >= 0 && template < levels.length ? levels[template] : null;
    }
  }
  return null;
}

/// aityx's answer to one call: its status, its body, the shape that ran
/// (X-aityx-Mode: defined, jev or jev_aityx) and how long it took.
class AityxAnswer {
  const AityxAnswer(this.status, this.body, {this.mode, required this.millis});

  final int status;
  final Map<String, Object?> body;
  final String? mode;
  final int millis;
}

/// aityx's /v1/systemone at [base], called with [_key], which is never
/// logged nor put in an error.
class Aityx {
  Aityx(this.base, this._key, {this.timeout = const Duration(seconds: 60)});

  final Uri base;
  final String _key;
  final Duration timeout;
  final _client = HttpClient()..connectionTimeout = const Duration(seconds: 10);

  bool get configured => _key.isNotEmpty;

  /// `<base>/v1/systemone`, whether or not [base]'s path ends in a slash.
  Uri get systemone => base.replace(path: '${base.path.replaceAll(RegExp(r'/+$'), '')}/v1/systemone');

  /// Posts [body]; throws when no answer comes within [timeout] or the
  /// answer isn't a JSON object.
  Future<AityxAnswer> call(Map<String, Object?> body) async {
    final watch = Stopwatch()..start();
    final request = await _client.postUrl(systemone).timeout(timeout);
    request.headers
      ..contentType = ContentType.json
      ..set(HttpHeaders.acceptHeader, 'application/json')
      ..set(HttpHeaders.authorizationHeader, 'Bearer $_key');
    request.add(utf8.encode(jsonEncode(body)));
    final response = await request.close().timeout(timeout);
    final text = await response.transform(utf8.decoder).join().timeout(timeout);
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      throw TriageFailed('aityx answered ${response.statusCode} without JSON');
    }
    if (json is! Map) throw TriageFailed('aityx answered ${response.statusCode} without a JSON object');
    return AityxAnswer(
      response.statusCode,
      json.cast<String, Object?>(),
      mode: response.headers.value('x-aityx-mode'),
      millis: watch.elapsedMilliseconds,
    );
  }

  void close() => _client.close(force: true);
}

/// The triage of one admission, as recorded (lib/db.dart's
/// admission_triage): the result, or the error that kept it from one.
Future<Map<String, Object?>> triageAdmission(Aityx aityx, Map<String, Object?> admission) async {
  final sent = triageRequest(complaint: admission['complaint'] as String, age: admission['age'] as int);
  final reference = referenceLevel(conditionSeed, admission['conditionCode'], admission['visit'], admission['template']);
  final watch = Stopwatch()..start();
  try {
    final answer = await aityx.call(sent);
    if (answer.status != 200) {
      final error = answer.body['error'];
      throw TriageFailed(
        'aityx answered ${answer.status}${error is Map ? ': ${error['code'] ?? error['message'] ?? ''}' : ''}',
      );
    }
    final result = toTriage(sent, answer.body);
    return {
      'eventId': admission['eventId'],
      'level': result.level,
      'waitMinutes': result.waitMinutes,
      'area': result.area,
      'nurseCheck': result.nurseCheck,
      'levelRule': result.levelRule?.rule,
      'levelWhy': result.levelRule?.why,
      'areaRule': result.areaRule?.rule,
      'areaWhy': result.areaRule?.why,
      'signs': result.signsJson,
      'choices': result.choicesJson,
      'receipt': result.receipt,
      'reference': reference,
      'error': null,
      'inputTokens': result.inputTokens,
      'millis': answer.millis,
      'mode': answer.mode,
    };
  } catch (error) {
    final message = error is TriageFailed || error is TimeoutException || error is SocketException
        ? '$error'
        : 'the triage failed: ${error.runtimeType}';
    return {
      'eventId': admission['eventId'],
      'reference': reference,
      'error': message,
      'millis': watch.elapsedMilliseconds,
    };
  }
}

/// Triages the admissions it is given in the background, a few at a time,
/// so the feed never waits on aityx: [work] triages one and records it.
/// Beyond [limit] waiting, the oldest are dropped, and each drop is
/// logged: they stay untriaged.
class Triager {
  Triager(this._work, {this.concurrency = 4, this.limit = 500});

  final Future<void> Function(Map<String, Object?> admission) _work;
  final int concurrency;
  final int limit;
  final _queue = ListQueue<Map<String, Object?>>();
  var _running = 0;
  var _stopped = false;
  Completer<void>? _idle;

  /// How many admissions wait to be triaged.
  int get pending => _queue.length;

  /// Completes once nothing is waiting or being triaged.
  Future<void> get idle => _running == 0 && _queue.isEmpty ? Future<void>.value() : (_idle ??= Completer()).future;

  /// Queues [admission]; returns at once.
  void triage(Map<String, Object?> admission) {
    if (_stopped) return;
    _queue.addLast(admission);
    if (_queue.length > limit) {
      stderr.writeln('triage: dropped ${_queue.removeFirst()['eventId']}, too many waiting for aityx');
    }
    _pump();
  }

  void _pump() {
    while (!_stopped && _running < concurrency && _queue.isNotEmpty) {
      final admission = _queue.removeFirst();
      _running++;
      unawaited(
        _work(admission)
            .catchError((Object error) => stderr.writeln('triage: ${admission['eventId']}: $error'))
            .whenComplete(() {
              _running--;
              _pump();
              if (_running == 0 && _queue.isEmpty) {
                _idle?.complete();
                _idle = null;
              }
            }),
      );
    }
  }

  /// Stops triaging; logs the admissions still waiting, which stay
  /// untriaged.
  void stop() {
    _stopped = true;
    if (_queue.isNotEmpty) stderr.writeln('triage: stopping with ${_queue.length} not triaged');
  }
}
