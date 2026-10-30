import 'package:aityx_web/aityx_web.dart' show openAityxKeyPage;
import 'package:flutter/material.dart';

import 'call_view.dart';
import 'json_layout.dart';
import 'routing.dart';

/// Topic and department ids as people read them.
const topicNames = {
  'customer_service': 'Customer Service',
  'billing': 'Billing & Payments',
  'marketing': 'Marketing',
  'tech_support': 'Technical Support',
  'trust_safety': 'Trust & Safety',
  'hr': 'Human Resources',
  'seller_services': 'Seller Services',
  'procurement': 'Procurement & Vendors',
  'business_sales': 'Business Sales',
  'legal': 'Legal & Privacy',
  'press': 'Public Relations',
  'investor_relations': 'Investor Relations',
  'general_inquiries': 'General Inquiries',
  'other': 'Other',
};

/// What the customer wants, as aityx reads it, in words.
const requestKindNames = {
  'where_is_order': 'To know where an order is',
  'return_refund': 'A return or a refund',
  'damaged_defective': 'A damaged or defective item',
  'cancel_order': 'To cancel an order',
  'price_adjustment': 'A price drop refunded',
  'duplicate_charge': 'A duplicate charge refunded',
  'none': 'Nothing about an order',
};

/// Routes [message] once and shows where it went and why, each part with
/// links to exactly the JSON behind it, then the aityx call itself.
class RoutingScreen extends StatefulWidget {
  const RoutingScreen({super.key, required this.message, this.router});

  final String message;

  /// Who routes it: aityx, from the app, unless a test says.
  final RequestRouter? router;

  @override
  State<RoutingScreen> createState() => _RoutingScreenState();
}

class _RoutingScreenState extends State<RoutingScreen> {
  late final RequestRouter _router = widget.router ?? AityxRequestRouter();
  late Future<RoutingOutcome> _outcome = _router.route(widget.message);
  final _call = CallController();

  @override
  void dispose() {
    _call.dispose();
    super.dispose();
  }

  void _retry() => setState(() {
    _outcome = _router.route(widget.message);
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Request routed')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _MessageCard(
                    widget.message,
                    onShow: () =>
                        _call.reveal(CallSide.request, 'state.message'),
                  ),
                  const SizedBox(height: 12),
                  FutureBuilder<RoutingOutcome>(
                    future: _outcome,
                    builder: (context, snapshot) => switch (snapshot) {
                      AsyncSnapshot(:final data?) => _Outcome(data, _call),
                      AsyncSnapshot(:final error?) => _Failure(
                        '$error',
                        _retry,
                        noKey: error is RoutingException && error.noKey,
                      ),
                      _ => const _Routing(),
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard(this.message, {required this.onShow});

  final String message;
  final VoidCallback onShow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.format_quote, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(child: Text(message, style: theme.textTheme.bodyLarge)),
            TextButton.icon(
              onPressed: onShow,
              iconAlignment: IconAlignment.end,
              icon: const Icon(Icons.north_east, size: 14),
              label: const Text('In the request'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Routing extends StatelessWidget {
  const _Routing();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('aityx is reading and routing your request…'),
        ],
      ),
    );
  }
}

class _Failure extends StatelessWidget {
  const _Failure(this.message, this.onRetry, {this.noKey = false});

  final String message;
  final VoidCallback onRetry;

  /// No aityx key: offer the index page's key section too.
  final bool noKey;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(Icons.error_outline, color: scheme.error, size: 32),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              if (noKey)
                FilledButton(
                  onPressed: openAityxKeyPage,
                  child: const Text('Set your key'),
                ),
              OutlinedButton(
                onPressed: onRetry,
                child: const Text('Try again'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A link to one part of the call: "Answer", "Rule 3"...
class _JsonLink {
  const _JsonLink(this.label, this.side, this.path);

  final String label;
  final CallSide side;
  final String path;
}

/// The pane's height for a call of [rows] rows: enough for all of them,
/// up to three quarters of the window (360 to 760 px).
double _paneHeight(BuildContext context, int rows) {
  final window = (MediaQuery.sizeOf(context).height * 0.75).clamp(360.0, 760.0);
  return (rows * 22.0 + 16).clamp(200.0, window);
}

class _Outcome extends StatelessWidget {
  const _Outcome(this.outcome, this.call);

  final RoutingOutcome outcome;
  final CallController call;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = outcome.routing;
    final hasCall = outcome.aityxRequest != null;
    final decision = decisionDigest(outcome.aityxResponse);
    // Only links to parts the pane shows: the response is a digest.
    final layout = layoutCall(outcome.aityxRequest, decision);
    Widget links(List<_JsonLink> links) {
      final kept = [
        for (final l in links)
          if (layout.range(
                l.side == CallSide.request ? 'request' : 'response',
                l.path,
              ) !=
              null)
            l,
      ];
      return hasCall && kept.isNotEmpty
          ? _Links(kept, call)
          : const SizedBox.shrink();
    }

    const req = CallSide.request;
    const res = CallSide.response;
    final deptRule = r.departmentRule;
    final prioRule = r.priorityRule;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DepartmentCard(
          r,
          links: links([
            const _JsonLink('Answer', res, 'answers.department'),
            if (deptRule != null)
              _JsonLink(
                'Rule $deptRule',
                req,
                'decision.decisions.department.table.$deptRule',
              ),
            const _JsonLink('Receipt', res, 'receipt.decisions.department'),
            const _JsonLink('Table', req, 'decision.decisions.department'),
          ]),
        ),
        if (r.policy case final policy? when policy.applies) ...[
          const SizedBox(height: 12),
          _PolicyCard(policy, links: links),
        ],
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final cards = [
              _FactCard(
                icon: Icons.flag_outlined,
                title: 'Priority',
                value:
                    '${_capitalize(r.priority)} · answer within '
                    '${r.responseHours} h',
                detail: r.priorityReason,
                accent: switch (r.priority) {
                  'high' => theme.colorScheme.error,
                  'low' => theme.colorScheme.secondary,
                  _ => theme.colorScheme.tertiary,
                },
                links: links([
                  const _JsonLink('Answer', res, 'answers.priority'),
                  if (prioRule != null)
                    _JsonLink(
                      'Rule $prioRule',
                      req,
                      'decision.decisions.priority.table.$prioRule',
                    ),
                  const _JsonLink('Hours', res, 'answers.response_hours'),
                  const _JsonLink(
                    'Hours table',
                    req,
                    'decision.decisions.response_hours',
                  ),
                ]),
              ),
              _FactCard(
                icon: r.needsReview
                    ? Icons.visibility_outlined
                    : Icons.task_alt,
                title: 'Review',
                value: r.needsReview
                    ? 'A person checks it first'
                    : 'Goes straight to the department',
                detail: r.needsReview
                    ? 'The topic is unclear, or the message holds sensitive '
                          'data or abuse: see the checks below.'
                    : 'The topic is clear and no check raised a flag.',
                accent: r.needsReview
                    ? theme.colorScheme.tertiary
                    : theme.colorScheme.secondary,
                links: links(const [
                  _JsonLink('Answer', res, 'answers.needs_review'),
                  _JsonLink('Rule', req, 'decision.decisions.needs_review'),
                ]),
              ),
            ];
            if (constraints.maxWidth < 640) {
              return Column(
                children: [cards[0], const SizedBox(height: 12), cards[1]],
              );
            }
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: cards[0]),
                  const SizedBox(width: 12),
                  Expanded(child: cards[1]),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        _ChecksCard(r, links: links),
        const SizedBox(height: 12),
        _TopicCard(r, links: links),
        const SizedBox(height: 24),
        Text('The aityx call', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          'One call to /v1/systemone: aityx answers the questions about the '
          'message, then the routing model decides, deterministically, from '
          'those answers. The links above jump straight to the part of the '
          'request or response behind each item.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        if (hasCall)
          CallView(
            title: 'The aityx call',
            request: outcome.aityxRequest,
            response: decision,
            fullResponse: outcome.aityxResponse,
            requestSubtitle: 'POST /v1/systemone, as the app sent it',
            responseSubtitle:
                'what was read, the answers that decide the route and the '
                'rules that fired; the probability maps are left out',
            targets: callTargets(r),
            controller: call,
            height: _paneHeight(context, layout.rows.length),
          )
        else
          const Text(
            "The aityx call is left out: aityx's answer contained the key.",
          ),
      ],
    );
  }
}

String _capitalize(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

/// The answers aityx's response shows in the pane: what aityx read, then
/// the decisions that make the route, in the order the rules run.
const _shownAnswers = [
  'topic',
  'request_kind',
  'urgent_probability',
  'sensitive_data_probability',
  'abusive_probability',
  'urgent',
  'sensitive_data',
  'abusive',
  'clear_topic',
  'department',
  'days_since_order',
  'days_since_delivery',
  'resolution',
  'refund_amount',
  'refund_by',
  'priority',
  'response_hours',
  'needs_review',
];

/// The decisions whose receipt (the rule that fired) the pane shows.
const _tracedDecisions = [
  'department',
  'resolution',
  'refund_amount',
  'priority',
  'response_hours',
];

/// What the pane shows of aityx's [response]: what it read and the answers
/// that decide the route, each without its probability map (a dozen zeros
/// and a one), the receipt of the tables, with the rule that fired in each,
/// and where every input came from. "Copy full response" has all of it.
Map<String, Object?> decisionDigest(Object? response) {
  final r = response is Map ? response : const {};
  final answers = r['answers'] is Map ? r['answers'] as Map : const {};
  final receipt = r['receipt'] is Map ? r['receipt'] as Map : const {};
  final decisions = receipt['decisions'] is Map
      ? receipt['decisions'] as Map
      : const {};
  return {
    'answers': {
      for (final name in _shownAnswers)
        if (answers[name] case final Map answer)
          name: {
            for (final MapEntry(:key, :value) in answer.entries)
              if (key != 'probabilities') '$key': value,
          },
    },
    'receipt': {
      'decisions': {
        for (final name in _tracedDecisions)
          if (decisions[name] != null) name: decisions[name],
      },
      if (receipt['provenance'] != null) 'provenance': receipt['provenance'],
    },
    if (r['decision_error'] != null) 'decision_error': r['decision_error'],
  };
}

/// The key parts of the call, for [r]: highlighted in the pane, and in its
/// "Jump to" bar; the rows that fired are exact.
List<JsonTarget> callTargets(Routing r) {
  const req = CallSide.request;
  const res = CallSide.response;
  return [
    const JsonTarget(
      req,
      'model',
      'Reading model',
      'The aityx model that answers the questions. It reads the message; it '
          'never decides the route.',
    ),
    const JsonTarget(
      req,
      'questions.topic',
      'Topic question',
      'A choice question: aityx picks one topic, each defined in plain words '
          'in its criteria, and says how confident it is.',
    ),
    const JsonTarget(
      req,
      'questions.urgent_probability',
      'Urgency question',
      'A yes/no question (noul): the probability that the message is '
          'urgent.',
    ),
    const JsonTarget(
      req,
      'questions.sensitive_data_probability',
      'Sensitive data question',
      'Whether the message contains a card number, password, bank account '
          'or ID number.',
    ),
    const JsonTarget(
      req,
      'questions.abusive_probability',
      'Abuse question',
      'Whether the message is abusive, threatening or harassing.',
    ),
    const JsonTarget(
      req,
      'questions.request_kind',
      'Request kind question',
      'A choice question: what the customer wants done with their order '
          '(where it is, a return, damage, a cancellation, a price drop, a '
          'double charge), or none.',
    ),
    const JsonTarget(
      req,
      'decision.inputs',
      'Model inputs',
      "The routing model's inputs: the questions' answers, by name, and "
          'confidence in the topic, bound with from = "jev:/answers/topic/'
          'confidence".',
    ),
    const JsonTarget(
      req,
      'decision.decisions.evidence_threshold',
      'Evidence threshold',
      "A probability from aityx's questions counts as a fact from 0.8 up.",
    ),
    const JsonTarget(
      req,
      'decision.decisions.clear_topic',
      'Clear topic rule',
      'The topic routes directly only when aityx is at least 60% confident '
          'and it fits a department.',
    ),
    const JsonTarget(
      req,
      'decision.decisions.department',
      'Department table',
      'The routing rules: abuse first, then an unclear topic, then one row '
          'per department. The first row that matches wins.',
    ),
    if (r.departmentRule case final rule?)
      JsonTarget(
        req,
        'decision.decisions.department.table.$rule',
        'Department rule $rule',
        'The row of the department table that fired for this message, with '
            'its reason.',
      ),
    const JsonTarget(
      req,
      'decision.inputs.order',
      'Order input',
      'The order the message names, from the order book: its dates, '
          'amounts, category, status and charges.',
    ),
    const JsonTarget(
      req,
      'decision.decisions.return_window_days',
      'Policy limits',
      'The store policy\'s numbers, one decision each: 30 days to refund, '
          '60 for store credit, 7 to report damage, a 1-year warranty on '
          'electronics, 14 days for a price drop, late after 10 days, a '
          'person above \$500, a 15% restocking fee on electronics after '
          '14 days, paid within 5 days.',
    ),
    const JsonTarget(
      req,
      'decision.decisions.days_since_delivery',
      'Days since delivery',
      'Today minus the delivery date, in days: what the windows are '
          'measured against.',
    ),
    const JsonTarget(
      req,
      'decision.decisions.resolution',
      'Policy table',
      'What the policy offers, by request kind, status, category, dates '
          'and amount. The first row that matches wins.',
    ),
    if (r.policy?.rule case final rule?)
      JsonTarget(
        req,
        'decision.decisions.resolution.table.$rule',
        'Policy rule $rule',
        'The row of the policy table that fired for this order.',
      ),
    if (r.policy?.amountRule case final rule?)
      JsonTarget(
        req,
        'decision.decisions.refund_amount.table.$rule',
        'Amount rule $rule',
        'The row of the amount table that fired: how much is paid back, '
            'and why.',
      ),
    const JsonTarget(
      req,
      'decision.decisions.refund_amount',
      'Amount table',
      'How much is refunded or credited for each resolution, restocking '
          'fee included.',
    ),
    const JsonTarget(
      req,
      'decision.decisions.priority',
      'Priority table',
      'How soon the department must answer: high for abuse, sensitive data, '
          'urgency, fraud and legal matters; low for product and media '
          'questions.',
    ),
    if (r.priorityRule case final rule?)
      JsonTarget(
        req,
        'decision.decisions.priority.table.$rule',
        'Priority rule $rule',
        'The row of the priority table that fired for this message.',
      ),
    const JsonTarget(
      req,
      'decision.decisions.needs_review',
      'Review rule',
      'A person checks the message first when its topic is unclear or it '
          'holds sensitive data or abuse.',
    ),
    const JsonTarget(
      req,
      'state',
      'The facts',
      'The state: the message the questions read, today, and the order on '
          'file the rules decide from.',
    ),
    const JsonTarget(
      req,
      'state.today',
      'Today',
      "The request's date, from this device's clock (UTC): every window "
          'counts from it.',
    ),
    const JsonTarget(
      req,
      'state.order',
      'The order',
      'The order on file the app sent, found by the number in the message.',
    ),
    const JsonTarget(
      req,
      'state.message',
      'The message',
      'The only fact sent: the request as typed or dictated.',
    ),
    const JsonTarget(
      res,
      'answers.topic',
      'Topic read',
      "aityx's choice of topic and its confidence: the department table's "
          'main input.',
    ),
    const JsonTarget(
      res,
      'answers.request_kind',
      'Request kind read',
      "aityx's reading of what the customer wants: the policy table's "
          'first column.',
    ),
    const JsonTarget(
      res,
      'answers.urgent_probability',
      'Urgency read',
      'The probability that the message is urgent; a fact from 0.8 up.',
    ),
    const JsonTarget(
      res,
      'answers.sensitive_data_probability',
      'Sensitive data read',
      'The probability that the message itself holds a card number, a '
          'password or an ID number; a fact from 0.8 up.',
    ),
    const JsonTarget(
      res,
      'answers.abusive_probability',
      'Abuse read',
      'The probability that the message is abusive or threatening; a fact '
          'from 0.8 up.',
    ),
    const JsonTarget(
      res,
      'answers.department',
      'The routing decision',
      'The department the rules chose: the routing.',
    ),
    const JsonTarget(
      res,
      'answers.resolution',
      'Policy resolution',
      "What the store's policy offers for the order, if the request is "
          'about one.',
    ),
    const JsonTarget(
      res,
      'answers.priority',
      'Priority',
      'How soon the department must answer: low, normal or high.',
    ),
    const JsonTarget(
      res,
      'receipt.decisions.department',
      'Rule that fired',
      'The department table\'s trace: "rule" is the row that fired, "rows" '
          'and "cells" how each row matched.',
    ),
    const JsonTarget(
      res,
      'receipt.provenance',
      'Provenance',
      "Where each input came from: the questions' answers (jev) or the "
          'state.',
    ),
    const JsonTarget(
      res,
      'decision_error',
      'Model error',
      'Present only when the model failed after the questions were answered.',
    ),
  ];
}

class _Links extends StatelessWidget {
  const _Links(this.links, this.call);

  final List<_JsonLink> links;
  final CallController call;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 0,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Icon(
          Icons.data_object,
          size: 16,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        for (final l in links)
          TextButton.icon(
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            onPressed: () => call.reveal(l.side, l.path),
            iconAlignment: IconAlignment.end,
            icon: Icon(
              l.side == CallSide.request ? Icons.north_east : Icons.south_west,
              size: 14,
            ),
            label: Text(l.label),
          ),
      ],
    );
  }
}

/// aityx's reading of the message: the topic's probabilities, and what
/// the customer wants done with their order.
class _TopicCard extends StatelessWidget {
  const _TopicCard(this.r, {required this.links});

  final Routing r;
  final Widget Function(List<_JsonLink>) links;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    const req = CallSide.request;
    const res = CallSide.response;
    final top = r.topicProbabilities.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final shown = top.take(4).where((e) => e.value > 0 || e == top.first);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "aityx's reading of the message",
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'aityx chose ${topicNames[r.topic] ?? r.topic ?? 'nothing'}'
              '${r.topicConfidence == null ? '' : ', ${(r.topicConfidence! * 100).round()}% confident'}.'
              ' The model routes from this answer, but the rules decide.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            for (final e in shown)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(
                        topicNames[e.key] ?? e.key,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 5,
                      child: LinearProgressIndicator(
                        value: e.value,
                        minHeight: 10,
                        borderRadius: BorderRadius.circular(5),
                        color: e.key == r.topic
                            ? scheme.primary
                            : scheme.outline,
                        backgroundColor: scheme.surfaceContainerHighest,
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 44,
                      child: Text(
                        '${(e.value * 100).round()}%',
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              ),
            links(const [
              _JsonLink('Answer', res, 'answers.topic'),
              _JsonLink('Question', req, 'questions.topic'),
              _JsonLink(
                'Confidence input',
                req,
                'decision.inputs.topic_confidence',
              ),
            ]),
            if (r.requestKind case final kind?) ...[
              const Divider(height: 24),
              Text(
                'What the customer wants: ${requestKindNames[kind] ?? kind}',
                style: theme.textTheme.bodyLarge,
              ),
              links(const [
                _JsonLink('Answer', res, 'answers.request_kind'),
                _JsonLink('Question', req, 'questions.request_kind'),
              ]),
            ],
          ],
        ),
      ),
    );
  }
}

class _DepartmentCard extends StatelessWidget {
  const _DepartmentCard(this.r, {required this.links});

  final Routing r;
  final Widget links;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final d = r.department;
    return Card(
      child: Container(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: scheme.primary, width: 4)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ROUTED TO',
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.primary,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              d.name,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: scheme.primaryContainer,
                  foregroundColor: scheme.onPrimaryContainer,
                  child: Text(
                    d.person.split(' ').map((w) => w[0]).take(2).join(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(d.person, style: theme.textTheme.titleMedium),
                      Text(
                        '${d.role} · ${d.email}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (r.reason != null) ...[
              const SizedBox(height: 12),
              Text(r.reason!, style: theme.textTheme.bodyLarge),
            ],
            const SizedBox(height: 8),
            links,
          ],
        ),
      ),
    );
  }
}

class _FactCard extends StatelessWidget {
  const _FactCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.detail,
    required this.accent,
    required this.links,
  });

  final IconData icon;
  final String title;
  final String value;
  final String? detail;
  final Color accent;
  final Widget links;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: accent, size: 20),
                const SizedBox(width: 8),
                Text(title, style: theme.textTheme.labelLarge),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: theme.textTheme.titleLarge?.copyWith(color: accent),
            ),
            if (detail != null) ...[
              const SizedBox(height: 6),
              Text(
                detail!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 8),
            links,
          ],
        ),
      ),
    );
  }
}

class _ChecksCard extends StatelessWidget {
  const _ChecksCard(this.r, {required this.links});

  final Routing r;
  final Widget Function(List<_JsonLink>) links;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    const req = CallSide.request;
    const res = CallSide.response;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Checks on the message', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'aityx gives a probability; the model sets the bar (0.8, or 0.6 '
              'for the topic).',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            for (final c in r.checks) ...[
              const Divider(height: 16),
              Row(
                children: [
                  Icon(
                    c.flagged
                        ? Icons.warning_amber_rounded
                        : Icons.check_circle,
                    color: c.flagged ? scheme.tertiary : scheme.secondary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.label, style: theme.textTheme.bodyLarge),
                        if (c.probability case final p?)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              children: [
                                Expanded(
                                  child: LinearProgressIndicator(
                                    value: p,
                                    minHeight: 6,
                                    borderRadius: BorderRadius.circular(3),
                                    color: c.flagged
                                        ? scheme.tertiary
                                        : scheme.secondary,
                                    backgroundColor:
                                        scheme.surfaceContainerHighest,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  c.id == 'clear_topic'
                                      ? 'confidence ${(p * 100).round()}%'
                                      : '${(p * 100).round()}%',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        links(switch (c.id) {
                          'clear_topic' => const [
                            _JsonLink(
                              'Rule',
                              req,
                              'decision.decisions.clear_topic',
                            ),
                            _JsonLink('Verdict', res, 'answers.clear_topic'),
                          ],
                          final id => [
                            _JsonLink(
                              'Question',
                              req,
                              'questions.${id}_probability',
                            ),
                            _JsonLink(
                              'Answer',
                              res,
                              'answers.${id}_probability',
                            ),
                            _JsonLink('Rule', req, 'decision.decisions.$id'),
                            _JsonLink('Verdict', res, 'answers.$id'),
                          ],
                        }),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// What each resolution is called, and how it reads: good for the
/// customer, a step to take, or a no.
const _resolutions = {
  'ask_for_order': ('Ask for the order number', _Tone.step),
  'cancel_and_refund': ('Cancel and refund', _Tone.good),
  'return_after_delivery': ('Return it once it arrives', _Tone.step),
  'share_tracking': ('On schedule: share the tracking', _Tone.good),
  'investigate_late': ('Late: open a carrier investigation', _Tone.step),
  'refund_duplicate': ('Refund the duplicate charge', _Tone.good),
  'price_adjustment': ('Refund the price difference', _Tone.good),
  'replace_or_refund': ('Replace or refund', _Tone.good),
  'warranty_repair': ('Repair under warranty', _Tone.good),
  'refund': ('Refund', _Tone.good),
  'store_credit': ('Store credit', _Tone.good),
  'manual_review': ('A person approves it', _Tone.step),
  'not_eligible': ('Not eligible', _Tone.no),
};

enum _Tone { good, step, no }

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _date(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';

String _money(double amount) {
  final cents = (amount * 100).round();
  final whole = (cents ~/ 100).toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (m) => '${m[1]},',
  );
  return '\$$whole.${(cents % 100).toString().padLeft(2, '0')}';
}

String _ago(int? days) => switch (days) {
  null || < 0 => '',
  0 => ' (today)',
  1 => ' (yesterday)',
  final d => ' ($d days ago)',
};

/// The store's policy for the order: what it offers, how much and by when,
/// why, and the order's facts it was decided from.
class _PolicyCard extends StatelessWidget {
  const _PolicyCard(this.policy, {required this.links});

  final OrderPolicy policy;
  final Widget Function(List<_JsonLink>) links;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    const req = CallSide.request;
    const res = CallSide.response;
    final (label, tone) =
        _resolutions[policy.resolution] ?? (policy.resolution, _Tone.step);
    final accent = switch (tone) {
      _Tone.good => scheme.secondary,
      _Tone.step => scheme.tertiary,
      _Tone.no => scheme.error,
    };
    final order = policy.order;
    final rule = policy.rule;
    Widget fact(String name, String value) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              name,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );

    return Card(
      margin: EdgeInsets.zero,
      child: Container(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: accent, width: 4)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "THE STORE'S POLICY",
              style: theme.textTheme.labelMedium?.copyWith(
                color: accent,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: accent,
              ),
            ),
            if (policy.refundAmount > 0) ...[
              const SizedBox(height: 4),
              Text(
                '${_money(policy.refundAmount)}'
                '${policy.refundBy == null ? '' : ', paid by ${_date(policy.refundBy!)}'}',
                style: theme.textTheme.titleLarge,
              ),
              if (policy.amountReason != null)
                Text(
                  policy.amountReason!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
            if (policy.reason != null) ...[
              const SizedBox(height: 8),
              Text(policy.reason!, style: theme.textTheme.bodyLarge),
            ],
            links([
              const _JsonLink('Answer', res, 'answers.resolution'),
              if (rule != null)
                _JsonLink(
                  'Rule $rule',
                  req,
                  'decision.decisions.resolution.table.$rule',
                ),
              if (policy.refundAmount > 0) ...[
                const _JsonLink('Amount', res, 'answers.refund_amount'),
                if (policy.amountRule case final amountRule?)
                  _JsonLink(
                    'Amount rule $amountRule',
                    req,
                    'decision.decisions.refund_amount.table.$amountRule',
                  ),
              ],
              const _JsonLink(
                'Limits',
                req,
                'decision.decisions.return_window_days',
              ),
            ]),
            const Divider(height: 24),
            if (order == null)
              Text(
                policy.orderNumber == null
                    ? 'The message names no order.'
                    : 'Order ${policy.orderNumber} is not on file.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              )
            else ...[
              Text(
                'Order ${order.number} · ${order.item}',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              fact(
                'Ordered',
                '${_date(order.placedOn)}${_ago(policy.daysSinceOrder)}',
              ),
              fact(
                order.status == 'delivered' ? 'Delivered' : 'Expected',
                '${_date(order.deliveredOn)}'
                '${order.status == 'delivered' ? _ago(policy.daysSinceDelivery) : ' · ${order.status}'}',
              ),
              fact(
                'Paid',
                '${_money(order.amount)}'
                    '${order.currentPrice != order.amount ? ' · ${_money(order.currentPrice)} today' : ''}'
                    '${order.charges > 1 ? ' · charged ${order.charges} times' : ''}',
              ),
              fact('Category', switch (order.category) {
                'final_sale' => 'Final sale',
                'electronics' => 'Electronics',
                _ => 'Standard',
              }),
              links(const [
                _JsonLink('The order', req, 'state.order'),
                _JsonLink('Today', req, 'state.today'),
                _JsonLink(
                  'Days since delivery',
                  res,
                  'answers.days_since_delivery',
                ),
                _JsonLink('Request kind', res, 'answers.request_kind'),
              ]),
            ],
          ],
        ),
      ),
    );
  }
}
