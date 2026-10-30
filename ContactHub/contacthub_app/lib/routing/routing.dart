import 'dart:convert';

import 'package:aityx_web/aityx_web.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../aityx/routing.dart'
    show
        InvalidRequest,
        RoutingFailed,
        messageFrom,
        routingRequest,
        toRouting,
        withAityx;

/// The department a request went to, and who there handles it.
class Department {
  const Department({
    required this.id,
    required this.name,
    required this.person,
    required this.role,
    required this.email,
  });

  factory Department.fromJson(Map<String, Object?> json) => Department(
    id: json['id'] as String,
    name: json['name'] as String,
    person: json['person'] as String,
    role: json['role'] as String,
    email: json['email'] as String,
  );

  final String id;
  final String name;
  final String person;
  final String role;
  final String email;
}

/// One of the checks run on the message, and whether it raised a flag.
class RoutingCheck {
  const RoutingCheck({
    required this.id,
    required this.label,
    required this.flagged,
    this.probability,
  });

  factory RoutingCheck.fromJson(Map<String, Object?> json) => RoutingCheck(
    id: json['id'] as String,
    label: json['label'] as String,
    flagged: json['flagged'] as bool,
    probability: (json['probability'] as num?)?.toDouble(),
  );

  /// `urgent`, `sensitive_data`, `abusive` or `clear_topic`.
  final String id;
  final String label;
  final bool flagged;

  /// aityx's probability behind it (for `clear_topic`, its confidence in the
  /// topic).
  final double? probability;
}

/// The order a request names, as the order book (lib/aityx/orders.dart)
/// has it.
class OrderOnFile {
  const OrderOnFile({
    required this.number,
    required this.item,
    required this.placedOn,
    required this.deliveredOn,
    required this.amount,
    required this.currentPrice,
    required this.category,
    required this.status,
    required this.charges,
  });

  factory OrderOnFile.fromJson(Map<String, Object?> json) => OrderOnFile(
    number: json['number'] as String,
    item: json['item'] as String,
    placedOn: DateTime.parse(json['placed_on'] as String),
    deliveredOn: DateTime.parse(json['delivered_on'] as String),
    amount: (json['amount'] as num).toDouble(),
    currentPrice: (json['current_price'] as num).toDouble(),
    category: json['category'] as String,
    status: json['status'] as String,
    charges: (json['charges'] as num).toInt(),
  );

  final String number;
  final String item;
  final DateTime placedOn;

  /// When it was delivered, or, before that, is expected.
  final DateTime deliveredOn;
  final double amount;
  final double currentPrice;

  /// `standard`, `final_sale` or `electronics`.
  final String category;

  /// `processing`, `shipped` or `delivered`.
  final String status;
  final int charges;
}

/// What the store's policy offers for the order a request is about.
class OrderPolicy {
  const OrderPolicy({
    required this.requestKind,
    required this.resolution,
    required this.reason,
    required this.rule,
    required this.refundAmount,
    this.amountReason,
    this.amountRule,
    required this.refundBy,
    required this.daysSinceOrder,
    required this.daysSinceDelivery,
    required this.order,
    required this.orderNumber,
  });

  factory OrderPolicy.fromJson(Map<String, Object?> json) => OrderPolicy(
    requestKind: json['request_kind'] as String?,
    resolution: json['resolution'] as String,
    reason: json['reason'] as String?,
    rule: json['resolution_rule'] as int?,
    refundAmount: (json['refund_amount'] as num?)?.toDouble() ?? 0,
    amountReason: json['amount_reason'] as String?,
    amountRule: json['amount_rule'] as int?,
    refundBy: switch (json['refund_by']) {
      final String d => DateTime.parse(d),
      _ => null,
    },
    daysSinceOrder: (json['days_since_order'] as num?)?.toInt(),
    daysSinceDelivery: (json['days_since_delivery'] as num?)?.toInt(),
    order: switch (json['order']) {
      final Map o => OrderOnFile.fromJson(o.cast<String, Object?>()),
      _ => null,
    },
    orderNumber: json['order_number'] as String?,
  );

  /// What the customer wants: `return_refund`, `cancel_order`...
  final String? requestKind;

  /// `refund`, `store_credit`, `not_eligible`...; `none` when no order
  /// policy applies.
  final String resolution;
  final String? reason;

  /// The resolution table's row that fired.
  final int? rule;
  final double refundAmount;

  /// Why that amount: the amount table's row that fired, and its number.
  final String? amountReason;
  final int? amountRule;
  final DateTime? refundBy;
  final int? daysSinceOrder;

  /// -1 when not delivered.
  final int? daysSinceDelivery;
  final OrderOnFile? order;

  /// The number the message gave, even when it's not on file.
  final String? orderNumber;

  bool get applies => resolution != 'none';
}

/// Where a request was routed: aityx's decision, read for the app.
class Routing {
  const Routing({
    required this.department,
    required this.reason,
    required this.departmentRule,
    required this.priority,
    required this.priorityReason,
    required this.priorityRule,
    required this.responseHours,
    required this.needsReview,
    required this.topic,
    required this.topicConfidence,
    required this.topicProbabilities,
    required this.requestKind,
    required this.checks,
    this.policy,
  });

  factory Routing.fromJson(Map<String, Object?> json) {
    final topic = (json['topic'] as Map?)?.cast<String, Object?>() ?? {};
    return Routing(
      department: Department.fromJson(
        (json['department'] as Map).cast<String, Object?>(),
      ),
      reason: json['reason'] as String?,
      departmentRule: json['department_rule'] as int?,
      priority: json['priority'] as String,
      priorityReason: json['priority_reason'] as String?,
      priorityRule: json['priority_rule'] as int?,
      responseHours: (json['response_hours'] as num).toInt(),
      needsReview: json['needs_review'] as bool,
      topic: topic['choice'] as String?,
      topicConfidence: (topic['confidence'] as num?)?.toDouble(),
      topicProbabilities: {
        for (final MapEntry(:key, :value)
            in ((topic['probabilities'] as Map?) ?? const {}).entries)
          '$key': (value as num).toDouble(),
      },
      requestKind: json['request_kind'] as String?,
      checks: [
        for (final check in (json['checks'] as List?) ?? const [])
          RoutingCheck.fromJson((check as Map).cast<String, Object?>()),
      ],
      policy: switch (json['policy']) {
        final Map p => OrderPolicy.fromJson(p.cast<String, Object?>()),
        _ => null,
      },
    );
  }

  final Department department;

  /// Why: the `# why` of the department table's row that fired.
  final String? reason;

  /// That row's number in the table (1-based; row 0 is the header).
  final int? departmentRule;

  /// `low`, `normal` or `high`.
  final String priority;
  final String? priorityReason;
  final int? priorityRule;
  final int responseHours;
  final bool needsReview;

  /// aityx's reading: its choice of topic, its confidence, every topic's
  /// probability, and what the customer wants done with their order
  /// (`return_refund`, `cancel_order`..., `none` when the message isn't
  /// about an order).
  final String? topic;
  final double? topicConfidence;
  final Map<String, double> topicProbabilities;
  final String? requestKind;
  final List<RoutingCheck> checks;

  /// The store's policy for the order the request names, if any.
  final OrderPolicy? policy;
}

/// A routed request: the [routing], and the aityx call behind it, unless
/// it was left out (see withAityx).
class RoutingOutcome {
  const RoutingOutcome(this.routing, {this.aityxRequest, this.aityxResponse});

  factory RoutingOutcome.fromJson(Map<String, Object?> json) {
    final aityx = json['aityx'] as Map?;
    return RoutingOutcome(
      Routing.fromJson((json['routing'] as Map).cast<String, Object?>()),
      aityxRequest: aityx?['request'],
      aityxResponse: aityx?['response'],
    );
  }

  final Routing routing;
  final Object? aityxRequest;
  final Object? aityxResponse;
}

/// Routes a request: aityx, from the app, unless a test says.
abstract interface class RequestRouter {
  Future<RoutingOutcome> route(String message);
}

/// The routing model, assets/models/routing.json, read once.
Future<Map<String, Object?>> loadRoutingModel() => _routingModel ??= rootBundle
    .loadString('assets/models/routing.json')
    .then((text) => (jsonDecode(text) as Map).cast<String, Object?>())
    .catchError((Object error) {
      _routingModel = null;
      throw error;
    });

Future<Map<String, Object?>>? _routingModel;

/// Routes on aityx, from the app itself: the routing model with the
/// message, today and the order it names as its state (lib/aityx/), POSTed
/// to /v1/systemone on the user's key, or in dev mode through the index
/// server, which adds its own (package:aityx_web).
class AityxRequestRouter implements RequestRouter {
  AityxRequestRouter({
    AityxClient? aityx,
    Future<Map<String, Object?>> Function()? model,
    this.today,
  }) : _aityx = aityx ?? _sharedClient,
       _model = model ?? loadRoutingModel;

  /// One client for the app's routings: it resolves the key once, and
  /// again when the index page changes it.
  static final _sharedClient = AityxClient();

  /// The most a routing may take: Jev reads the message, then the rules
  /// run.
  static const timeout = Duration(seconds: 100);

  final AityxClient _aityx;
  final Future<Map<String, Object?>> Function() _model;

  /// Today, in UTC: the device's clock unless a test says.
  final DateTime Function()? today;

  /// Throws [RoutingException] with a message for the user.
  @override
  Future<RoutingOutcome> route(String message) async {
    final String text;
    try {
      text = messageFrom({'message': message});
    } on InvalidRequest catch (error) {
      throw RoutingException(_couldNot(error.message));
    }
    final sent = routingRequest(await _model(), text, today: today?.call());
    // The key the call goes out on, to keep it off the screen below; read
    // again after the call, in case the index page changed it meanwhile.
    final before = (await _aityx.connection()).key;
    final AityxAnswer answer;
    try {
      answer = await _aityx.systemone(sent, timeout: timeout);
    } on AityxNoKey {
      throw const RoutingException('${AityxNoKey.message}.', noKey: true);
    } on AityxUnreachable catch (error) {
      throw RoutingException(
        error.cause?.startsWith('timed out') ?? false
            ? '${AityxUnreachable.message} in time.'
            : '${AityxUnreachable.message}.',
      );
    }
    // In dev mode, the index server's proxy answers 502 proxy_unreachable
    // when aityx doesn't answer it: the same as no answer at all.
    if (answer.code == 'proxy_unreachable') {
      throw const RoutingException('${AityxUnreachable.message}.');
    }
    if (!answer.ok) throw RoutingException(_couldNot(answer.problem!));
    final json = answer.json;
    if (json is! Map) {
      throw RoutingException(_couldNot('unexpected answer from aityx'));
    }
    try {
      final received = json.cast<String, Object?>();
      final routing = toRouting(sent, received);
      final shown = withAityx(
        routing,
        sent,
        received,
        answer.text,
        before ?? '',
      );
      final after = (await _aityx.connection()).key;
      if (after != null && after.isNotEmpty && answer.text.contains(after)) {
        shown.remove('aityx');
      }
      return RoutingOutcome.fromJson(shown);
    } on RoutingFailed catch (error) {
      throw RoutingException(_couldNot('aityx could not route it: $error'));
    } catch (_) {
      throw RoutingException(_couldNot('unexpected answer from aityx'));
    }
  }

  /// "Could not route it: [why]." with one final period.
  static String _couldNot(String why) =>
      'Could not route it: ${why.endsWith('.') ? why.substring(0, why.length - 1) : why}.';
}

class RoutingException implements Exception {
  const RoutingException(this.message, {this.noKey = false});

  final String message;

  /// Whether it failed for want of a key: the screen offers the index
  /// page's key section.
  final bool noKey;

  @override
  String toString() => message;
}
