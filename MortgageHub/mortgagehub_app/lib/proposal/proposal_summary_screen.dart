import 'package:flutter/material.dart';

import 'aityx_json_view.dart';
import 'proposal_check.dart';
import 'proposal_request.dart';

/// What the borrower asked for, after a valid proposal request: the loan
/// amount, loan-to-value and debt-to-income worked out from it, the
/// regulatory check (aityx.ai's verdict), then every answer. Done goes back
/// to the welcome page.
class ProposalSummaryScreen extends StatelessWidget {
  const ProposalSummaryScreen({super.key, required this.request, this.checker});

  final ProposalRequest request;

  /// Who runs the regulatory check: the app's API unless a test says.
  final ProposalChecker? checker;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = request;
    String yesNo(bool value) => value ? 'Yes' : 'No';
    String optional(int? amount) =>
        amount == null ? 'Not given' : money(amount);
    final address = [
      if (r.street.isNotEmpty) r.street,
      if (r.city.isNotEmpty) r.city,
      '${r.state} ${r.zip}',
    ].join(', ');

    return Scaffold(
      appBar: AppBar(title: const Text('Proposal requested')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _wideWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.check_circle_outline,
                  size: 56,
                  color: theme.colorScheme.secondary,
                ),
                const SizedBox(height: 12),
                Text(
                  'Thanks, ${r.firstName}. Your proposal request is ready.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _Figure('Loan amount', money(r.loanAmount)),
                    _Figure('Loan-to-value', percent(r.loanToValue)),
                    _Figure('Current debt-to-income', percent(r.debtToIncome)),
                  ],
                ),
                const SizedBox(height: 16),
                RegulatoryCheckCard(request: r, checker: checker),
                _narrow(
                  _Group('The loan', {
                    'Purpose': r.purpose.label,
                    'Program': r.program.label,
                    'Term': r.term.label,
                    'Rate type': r.rateType.label,
                    'Timeline': r.timeline.label,
                  }),
                ),
                _narrow(
                  _Group('The property', {
                    'Type': r.propertyType.label,
                    'Use': r.occupancy.label,
                    'Location': r.propertyFound
                        ? address
                        : '$address (not found yet)',
                    r.purpose.isPurchase ? 'Purchase price' : 'Estimated value':
                        money(r.propertyValue),
                    if (r.purpose.isPurchase)
                      'Down payment': money(r.downPayment),
                    if (!r.purpose.isPurchase)
                      'Current balance': money(r.currentBalance),
                    if (r.purpose == LoanPurpose.cashOutRefinance)
                      'Cash out': money(r.cashOut),
                    'Property taxes (year)': optional(r.annualTaxes),
                    'Insurance (year)': optional(r.annualInsurance),
                    'HOA dues (month)': optional(r.monthlyHoa),
                  }),
                ),
                _narrow(
                  _Group('About you', {
                    'Name': '${r.firstName} ${r.lastName}',
                    'Email': r.email,
                    'Phone': r.phone,
                    'Co-borrower': yesNo(r.hasCoBorrower),
                    'Credit score': r.creditScore.label,
                    'Employment': r.employment.label,
                    'Annual income': money(r.annualIncome),
                    'Monthly debts': money(r.monthlyDebts),
                    'Savings to close': optional(r.assets),
                    if (r.purpose.isPurchase)
                      'First-time buyer': yesNo(r.firstTimeBuyer),
                    'Military service': yesNo(r.militaryService),
                  }),
                ),
                const SizedBox(height: 8),
                _narrow(
                  FilledButton(
                    onPressed: () =>
                        Navigator.of(context)
                            .popUntil((route) => route.isFirst),
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The summary's width, and the regulatory check's while it shows the
/// aityx call, so the JSON has room.
const _width = 640.0;
const _wideWidth = 1100.0;

Widget _narrow(Widget child, {double width = _width}) => Center(
  child: ConstrainedBox(
    constraints: BoxConstraints(maxWidth: width),
    child: child,
  ),
);

/// Whole dollars with thousands separators: $425,000.
String money(int amount) {
  final digits = amount.abs().toString();
  final grouped = digits.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  return '${amount < 0 ? '-' : ''}\$$grouped';
}

String percent(double value) => '${value.toStringAsFixed(1)}%';

class _Figure extends StatelessWidget {
  const _Figure(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          children: [
            Text(
              value,
              style: theme.textTheme.titleLarge?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(label, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group(this.title, this.rows);

  final String title;
  final Map<String, String> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final row in rows.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(
                        row.key,
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(flex: 3, child: Text(row.value)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The regulatory check section: asks [checker] once, then shows the
/// verdict, the figures it worked out and each check with its reason, and
/// a button that shows or hides the aityx request and response behind it.
class RegulatoryCheckCard extends StatefulWidget {
  const RegulatoryCheckCard({super.key, required this.request, this.checker});

  final ProposalRequest request;

  /// Who runs the check; without one, the card makes (and closes) an
  /// [ApiProposalChecker].
  final ProposalChecker? checker;

  @override
  State<RegulatoryCheckCard> createState() => _RegulatoryCheckCardState();
}

class _RegulatoryCheckCardState extends State<RegulatoryCheckCard> {
  ApiProposalChecker? _owned;
  late final ProposalChecker _checker =
      widget.checker ?? (_owned = ApiProposalChecker());
  late Future<ProposalCheck> _check = _checker.check(widget.request);
  bool _showAityx = false;

  @override
  void dispose() {
    _owned?.close();
    super.dispose();
  }

  void _retry() {
    final check = _checker.check(widget.request);
    setState(() {
      _check = check;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final card = Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<ProposalCheck>(
          future: _check,
          builder: (context, snapshot) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Regulatory check', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              if (snapshot.hasData)
                ..._result(context, snapshot.data!)
              else if (snapshot.hasError)
                ..._error(context, snapshot.error!)
              else
                const Row(
                  children: [
                    SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Checking against current US mortgage rules with aityx…',
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
    return _narrow(card, width: _showAityx ? _wideWidth : _width);
  }

  List<Widget> _error(BuildContext context, Object error) {
    final scheme = Theme.of(context).colorScheme;
    return [
      Text(
        "Couldn't run the check: $error",
        style: TextStyle(color: scheme.error),
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _retry,
          icon: const Icon(Icons.refresh),
          label: const Text('Try again'),
        ),
      ),
    ];
  }

  List<Widget> _result(BuildContext context, ProposalCheck check) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = statusColor(context, check.status);
    final icon = statusIcon(check.status);
    return [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: color),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 10),
            Text(
              check.status.label,
              key: const Key('checkStatus'),
              style: theme.textTheme.titleMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        alignment: WrapAlignment.center,
        children: [
          _Figure(
            'Loan-to-value (max ${percent(check.maxLtv)})',
            percent(check.ltv),
          ),
          _Figure('Est. monthly payment', money(check.housingPayment.round())),
          _Figure('Debt-to-income with it', percent(check.dti)),
        ],
      ),
      const SizedBox(height: 8),
      for (final item in check.checks) _CheckRow(item),
      const SizedBox(height: 8),
      Text(
        'Payment estimated at ${check.assumedRate}% with taxes and insurance '
        'estimated when not given, without mortgage insurance. Based on the '
        'answers as given: not a credit decision or a Loan Estimate.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      if (check.aityxRequest != null || check.aityxResponse != null) ...[
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const Key('aityxToggle'),
            onPressed: () => setState(() => _showAityx = !_showAityx),
            icon: Icon(_showAityx ? Icons.expand_less : Icons.data_object),
            label: Text(
              _showAityx
                  ? 'Hide aityx request and response'
                  : 'Show aityx request and response',
            ),
          ),
        ),
        // The response first: it holds the verdict and why; a faint rule
        // between the two blocks, so where one ends and the other starts
        // is clear without the rule shouting.
        if (_showAityx) ...[
          AityxJsonView('Response', check.aityxResponse, notes: responseNotes),
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Divider(
              key: const Key('aityxSeparator'),
              height: 1,
              thickness: 1,
              color: scheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
          AityxJsonView(
            'Request: POST /v1/systemone (the API key is not shown)',
            check.aityxRequest,
            notes: requestNotes,
          ),
        ],
      ],
    ];
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow(this.item);

  final CheckItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (color, icon) = switch (item.result) {
      CheckResult.pass => (scheme.secondary, Icons.check_circle),
      CheckResult.review => (scheme.tertiary, Icons.error_outline),
      CheckResult.fail => (scheme.error, Icons.cancel),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.label, style: theme.textTheme.titleSmall),
                Text(
                  item.reason,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
