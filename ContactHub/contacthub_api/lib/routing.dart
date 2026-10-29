/// Routing a request: the body sent to aityx (models/routing.json, with the
/// message as its state) and the routing read back from aityx's answer,
/// apart from the HTTP plumbing in bin/server.dart so it can be tested
/// without a server.
library;

import 'orders.dart';

/// The longest message accepted, in characters.
const maxMessageLength = 2000;

/// A request the API refuses before calling aityx.
class InvalidRequest implements Exception {
  InvalidRequest(this.message);

  final String message;

  @override
  String toString() => message;
}

/// aityx answered, but not with a routing.
class RoutingFailed implements Exception {
  RoutingFailed(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Who handles each department's requests. The people are made up.
class Department {
  const Department(this.name, this.person, this.role, this.email);

  final String name;
  final String person;
  final String role;
  final String email;

  Map<String, Object?> toJson(String id) => {
    'id': id,
    'name': name,
    'person': person,
    'role': role,
    'email': email,
  };
}

const departments = <String, Department>{
  'customer_service': Department(
    'Customer Service',
    'Maria Lopez',
    'Customer Service Lead',
    'customer-service@contacthub.example',
  ),
  'billing': Department(
    'Billing & Payments',
    'David Chen',
    'Billing Operations Manager',
    'billing@contacthub.example',
  ),
  'marketing': Department(
    'Marketing',
    'Aisha Patel',
    'Product Marketing Manager',
    'marketing@contacthub.example',
  ),
  'tech_support': Department(
    'Technical Support',
    'Lukas Schmidt',
    'Technical Support Lead',
    'support@contacthub.example',
  ),
  'trust_safety': Department(
    'Trust & Safety',
    'Grace Okafor',
    'Trust & Safety Investigator',
    'trust-safety@contacthub.example',
  ),
  'hr': Department(
    'Human Resources',
    'Sofia Rossi',
    'Talent Acquisition Partner',
    'careers@contacthub.example',
  ),
  'seller_services': Department(
    'Seller Services',
    'Kenji Tanaka',
    'Seller Success Manager',
    'sellers@contacthub.example',
  ),
  'procurement': Department(
    'Procurement & Vendors',
    'Olivia Brown',
    'Vendor Relations Manager',
    'vendors@contacthub.example',
  ),
  'business_sales': Department(
    'Business Sales',
    'Rafael Silva',
    'Business Accounts Executive',
    'business@contacthub.example',
  ),
  'legal': Department(
    'Legal & Privacy',
    'Hannah Weiss',
    'Privacy Counsel',
    'legal@contacthub.example',
  ),
  'press': Department(
    'Public Relations',
    'Tom Becker',
    'Media Relations Manager',
    'press@contacthub.example',
  ),
  'investor_relations': Department(
    'Investor Relations',
    'Priya Nair',
    'Investor Relations Director',
    'investors@contacthub.example',
  ),
  'general_inquiries': Department(
    'General Inquiries',
    'Sam Taylor',
    'Front Desk Coordinator',
    'hello@contacthub.example',
  ),
};

/// The message from the app's request body, `{"message": "..."}`, trimmed.
String messageFrom(Object? body) {
  if (body is! Map) throw InvalidRequest('expected an object');
  final message = body['message'];
  if (message is! String) throw InvalidRequest('message is required');
  final trimmed = message.trim();
  if (trimmed.isEmpty) throw InvalidRequest('message is empty');
  if (trimmed.length > maxMessageLength) {
    throw InvalidRequest('message is longer than $maxMessageLength characters');
  }
  return trimmed;
}

/// The body sent to aityx's /v1/systemone: the questions and the routing
/// model from [model] (models/routing.json), and the state: the message,
/// [today], and the order it names from the order book (lib/orders.dart).
Map<String, Object?> routingRequest(
  Map<String, Object?> model,
  String message, {
  DateTime? today,
}) {
  final day = today ?? DateTime.now().toUtc();
  return {
    ...model,
    'state': {
      'message': message,
      'today': isoDate(day),
      'order': orderState(message, day),
    },
  };
}

/// The routing in aityx's [answer] to [sent]; throws [RoutingFailed] when
/// it holds none.
Map<String, Object?> toRouting(
  Map<String, Object?> sent,
  Map<String, Object?> answer,
) {
  if (answer['decision_error'] case final Map error) {
    throw RoutingFailed('the routing model failed: ${error['code']}');
  }
  final answers = answer['answers'];
  final receipt = answer['receipt'];
  if (answers is! Map || receipt is! Map) {
    throw RoutingFailed('no answers');
  }
  T read<T>(String name, String field) {
    final value = (answers[name] as Map?)?[field];
    if (value is! T) throw RoutingFailed('no $name.$field');
    return value;
  }

  final departmentId = read<String>('department', 'choice');
  final department = departments[departmentId];
  if (department == null) throw RoutingFailed('unknown $departmentId');
  final table = _tables(sent);
  final rules = (receipt['decisions'] as Map?) ?? {};
  ({int rule, String? why})? fired(String decision) {
    final rule = (rules[decision] as Map?)?['rule'];
    final rows = table[decision];
    if (rule is! int || rows == null || rule < 1 || rule >= rows.length) {
      return null;
    }
    return (rule: rule, why: _why(rows[0], rows[rule]));
  }

  double probability(String name) => read<num>(name, 'noul').toDouble();
  bool flag(String name) => read<num>(name, 'noul') >= 0.5;
  final topic = answers['topic'] as Map?;
  final departmentRule = fired('department');
  final priorityRule = fired('priority');
  final resolutionRule = fired('resolution');
  final amountRule = fired('refund_amount');
  final order = ((sent['state'] as Map?)?['order'] as Map?) ?? const {};
  final resolution = (answers['resolution'] as Map?)?['choice'];
  num? number(String name) => (answers[name] as Map?)?['number'] as num?;

  return {
    'department': department.toJson(departmentId),
    'reason': departmentRule?.why,
    'department_rule': departmentRule?.rule,
    'priority': read<String>('priority', 'level'),
    'priority_reason': priorityRule?.why,
    'priority_rule': priorityRule?.rule,
    'response_hours': read<num>('response_hours', 'number'),
    'needs_review': flag('needs_review'),
    'topic': {
      'choice': topic?['choice'],
      'confidence': topic?['confidence'],
      'probabilities': topic?['probabilities'] ?? const {},
    },
    'request_kind': (answers['request_kind'] as Map?)?['choice'],
    'checks': [
      for (final (id, label) in const [
        ('urgent', 'Urgent'),
        ('sensitive_data', 'Card number, password or ID in the message'),
        ('abusive', 'Abusive or threatening'),
      ])
        {
          'id': id,
          'label': label,
          'flagged': flag(id),
          'probability': probability('${id}_probability'),
        },
      {
        'id': 'clear_topic',
        'label': 'Topic unclear (low confidence, or no department fits)',
        'flagged': !flag('clear_topic'),
        'probability': (topic?['confidence'] as num?)?.toDouble(),
      },
    ],
    // The order on file, and what the store's policy offers for it; absent
    // for a model without the order rules.
    if (resolution is String)
      'policy': {
        'request_kind': (answers['request_kind'] as Map?)?['choice'],
        'resolution': resolution,
        'reason': resolutionRule?.why,
        'resolution_rule': resolutionRule?.rule,
        'refund_amount': number('refund_amount'),
        'amount_reason': amountRule?.why,
        'amount_rule': amountRule?.rule,
        'refund_by': (answers['refund_by'] as Map?)?['date'],
        'days_since_order': number('days_since_order'),
        'days_since_delivery': number('days_since_delivery'),
        'order': order['status'] == 'none' ? null : order,
        'order_number': order['number'],
      },
  };
}

/// The decision tables in [sent]'s model, by decision name.
Map<String, List<Object?>> _tables(Map<String, Object?> sent) {
  final decisions = (sent['decision'] as Map?)?['decisions'];
  if (decisions is! Map) return const {};
  return {
    for (final MapEntry(:key, :value) in decisions.entries)
      if (value is Map && value['table'] is List)
        '$key': value['table'] as List<Object?>,
  };
}

/// A table row's `# why`: an object row's `why`, or the cell under the
/// header's `# ...` column.
String? _why(Object? header, Object? row) {
  if (row is Map) return row['why'] as String?;
  if (row is List && header is List) {
    final column = header.indexWhere((h) => h is String && h.startsWith('#'));
    if (column >= 0 && column < row.length) return row[column] as String?;
  }
  return null;
}

/// The API's answer to the app: the routing, and the aityx call behind it,
/// unless aityx's answer somehow contains the key (it never should).
Map<String, Object?> withAityx(
  Map<String, Object?> routing,
  Map<String, Object?> sent,
  Map<String, Object?> answer,
  String text,
  String key,
) => {
  'routing': routing,
  if (key.isEmpty || !text.contains(key))
    'aityx': {'request': sent, 'response': answer},
};
