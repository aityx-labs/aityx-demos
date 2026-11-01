/// The calls datyx routes to aityx, as the API accounts for them:
/// `GET /api/aityx` and `GET /api/aityx/calls/{id}`
/// (`datyx/specs/aityx.md`). Read here, shown by the aityx tab.
library;

DateTime? _time(Object? value) => value is String ? DateTime.tryParse(value) : null;

int _int(Object? value) => (value as num?)?.toInt() ?? 0;

/// The calls' account over the window: how many, how many failed (a
/// status other than 2xx), the input tokens and their cost summed, and
/// latency in milliseconds (mean, median, 95th percentile; null without
/// calls).
class AityxStats {
  const AityxStats({
    this.calls = 0,
    this.failed = 0,
    this.inputTokens = 0,
    this.costUsd = 0,
    this.avgMillis,
    this.p50Millis,
    this.p95Millis,
    this.lastCalledAt,
  });

  factory AityxStats.fromJson(Map<String, Object?> json) => AityxStats(
    calls: _int(json['calls']),
    failed: _int(json['failed']),
    inputTokens: _int(json['inputTokens']),
    costUsd: (json['costUsd'] as num?)?.toDouble() ?? 0,
    avgMillis: (json['avgMillis'] as num?)?.toDouble(),
    p50Millis: (json['p50Millis'] as num?)?.toInt(),
    p95Millis: (json['p95Millis'] as num?)?.toInt(),
    lastCalledAt: _time(json['lastCalledAt']),
  );

  final int calls;
  final int failed;
  final int inputTokens;
  final double costUsd;
  final double? avgMillis;
  final int? p50Millis;
  final int? p95Millis;
  final DateTime? lastCalledAt;
}

/// One hour of the last 24 (its start, UTC): its calls, failures, input
/// tokens and median latency (null without calls).
class AityxHour {
  const AityxHour(this.hour, {this.calls = 0, this.failed = 0, this.inputTokens = 0, this.p50Millis});

  factory AityxHour.fromJson(Map<String, Object?> json) => AityxHour(
    _time(json['hour']) ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    calls: _int(json['calls']),
    failed: _int(json['failed']),
    inputTokens: _int(json['inputTokens']),
    p50Millis: (json['p50Millis'] as num?)?.toInt(),
  );

  final DateTime hour;
  final int calls;
  final int failed;
  final int inputTokens;
  final int? p50Millis;
}

/// A value of a breakdown (a purpose, a model, a decision; null when the
/// calls had none) and its calls, failures and input tokens.
class AityxCount {
  const AityxCount(this.name, {this.calls = 0, this.failed = 0, this.inputTokens = 0});

  factory AityxCount.fromJson(Map<String, Object?> json) => AityxCount(
    json['name'] as String?,
    calls: _int(json['calls']),
    failed: _int(json['failed']),
    inputTokens: _int(json['inputTokens']),
  );

  final String? name;
  final int calls;
  final int failed;
  final int inputTokens;
}

/// What the API says of personalization: whether it is active, the
/// personalizer's name, and a note on what it does or will do.
class AityxPersonalization {
  const AityxPersonalization({this.active = false, this.name = 'none', this.note});

  factory AityxPersonalization.fromJson(Map<String, Object?> json) => AityxPersonalization(
    active: json['active'] == true,
    name: json['name'] as String? ?? 'none',
    note: json['note'] as String?,
  );

  final bool active;
  final String name;
  final String? note;
}

/// One call routed to aityx, without its bodies: who (a user's email, or
/// a service's name), why ([purpose]), which model and decision, how many
/// questions, how long, aityx's HTTP status and mode, the input tokens and
/// their cost (null when the answer had no usage), a short error, and
/// whether the personalization hook changed the body.
class AityxCallInfo {
  const AityxCallInfo({
    required this.id,
    this.at,
    this.caller,
    this.service = false,
    this.purpose,
    this.model,
    this.decision,
    this.questions = 0,
    this.millis = 0,
    this.status = 0,
    this.mode,
    this.inputTokens,
    this.costUsd,
    this.error,
    this.personalized = false,
  });

  factory AityxCallInfo.fromJson(Map<String, Object?> json) => AityxCallInfo(
    id: _int(json['id']),
    at: _time(json['at']),
    caller: json['caller'] as String?,
    service: json['service'] == true,
    purpose: json['purpose'] as String?,
    model: json['model'] as String?,
    decision: json['decision'] as String?,
    questions: _int(json['questions']),
    millis: _int(json['millis']),
    status: _int(json['status']),
    mode: json['mode'] as String?,
    inputTokens: (json['inputTokens'] as num?)?.toInt(),
    costUsd: (json['costUsd'] as num?)?.toDouble(),
    error: json['error'] as String?,
    personalized: json['personalized'] == true,
  );

  final int id;
  final DateTime? at;
  final String? caller;
  final bool service;
  final String? purpose;
  final String? model;
  final String? decision;
  final int questions;
  final int millis;

  /// aityx's HTTP status, as datyx answered it.
  final int status;
  final String? mode;
  final int? inputTokens;
  final double? costUsd;
  final String? error;
  final bool personalized;

  /// Failed: a status other than 2xx, as the API counts it.
  bool get failed => status < 200 || status >= 300;
}

/// One call with what was sent to aityx and what it answered: the JSON
/// recorded, or its text as a string when it was truncated past 64 KB or
/// isn't JSON; null when there was none (aityx unreachable).
class AityxCallDetail {
  const AityxCallDetail({
    required this.call,
    this.request,
    this.requestTruncated = false,
    this.response,
    this.responseTruncated = false,
  });

  factory AityxCallDetail.fromJson(Map<String, Object?> json) => AityxCallDetail(
    call: AityxCallInfo.fromJson(json),
    request: json['request'],
    requestTruncated: json['requestTruncated'] == true,
    response: json['response'],
    responseTruncated: json['responseTruncated'] == true,
  );

  final AityxCallInfo call;
  final Object? request;
  final bool requestTruncated;
  final Object? response;
  final bool responseTruncated;
}

/// `GET /api/aityx?days=N`: the caller's calls routed to aityx over the
/// last [days] (with the services' bucket, HealthHub's calls, when
/// [sharesServiceCalls]): whether datyx has an aityx key ([configured]),
/// the price per million input tokens, personalization, the totals, the
/// last hour's calls, the last 24 hours hour by hour (oldest first), the
/// breakdowns (the most called first) and the latest 50 calls, newest
/// first.
class AityxAccount {
  const AityxAccount({
    this.since,
    this.days = 7,
    this.configured = true,
    this.sharesServiceCalls = false,
    this.pricePerMillionInputTokens,
    this.personalization = const AityxPersonalization(),
    this.totals = const AityxStats(),
    this.lastHour = 0,
    this.perHour = const [],
    this.byPurpose = const [],
    this.byModel = const [],
    this.byDecision = const [],
    this.calls = const [],
  });

  factory AityxAccount.fromJson(Map<String, Object?> json) {
    List<AityxCount> counts(Object? list) => [
      for (final c in (list as List?) ?? const []) AityxCount.fromJson((c as Map).cast()),
    ];
    return AityxAccount(
      since: _time(json['since']),
      days: (json['days'] as num?)?.toInt() ?? 7,
      configured: json['configured'] != false,
      sharesServiceCalls: json['sharesServiceCalls'] == true,
      pricePerMillionInputTokens: (json['pricePerMillionInputTokens'] as num?)?.toDouble(),
      personalization: json['personalization'] is Map
          ? AityxPersonalization.fromJson((json['personalization'] as Map).cast())
          : const AityxPersonalization(),
      totals: json['totals'] is Map ? AityxStats.fromJson((json['totals'] as Map).cast()) : const AityxStats(),
      lastHour: _int(json['lastHour']),
      perHour: [
        for (final h in (json['perHour'] as List?) ?? const []) AityxHour.fromJson((h as Map).cast()),
      ],
      byPurpose: counts(json['byPurpose']),
      byModel: counts(json['byModel']),
      byDecision: counts(json['byDecision']),
      calls: [
        for (final c in (json['calls'] as List?) ?? const []) AityxCallInfo.fromJson((c as Map).cast()),
      ],
    );
  }

  final DateTime? since;
  final int days;
  final bool configured;
  final bool sharesServiceCalls;
  final double? pricePerMillionInputTokens;
  final AityxPersonalization personalization;
  final AityxStats totals;
  final int lastHour;
  final List<AityxHour> perHour;
  final List<AityxCount> byPurpose;
  final List<AityxCount> byModel;
  final List<AityxCount> byDecision;
  final List<AityxCallInfo> calls;
}
