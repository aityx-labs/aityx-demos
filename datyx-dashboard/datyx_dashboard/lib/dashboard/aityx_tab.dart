import 'dart:convert';

import 'package:flutter/material.dart';

import '../api/datyx_api.dart';
import '../theme.dart';
import 'calls_panel.dart' show JsonBlock;
import 'card_title.dart';
import 'health_tab.dart' show ApiDownLine;
import 'training_tab.dart' show StatTile, span, when;

/// The windows the tab offers, in days; the API takes 1 to 30.
const aityxWindows = [1, 7, 30];

/// The aityx tab: the account of the calls datyx routes to aityx through
/// its gateway (`GET /api/aityx?days=N`, the last 7 days unless another
/// window is picked): the totals' tiles, the calls and the input tokens of
/// each of the last 24 hours, the calls by purpose, model and decision,
/// and the latest calls, each opening what was sent to aityx and what it
/// answered (`GET /api/aityx/calls/{id}`). Then **Personalization**, which
/// is coming and not active. What is shown is the API's; the tab asks and
/// shows.
class AityxTab extends StatefulWidget {
  const AityxTab({super.key, required this.api, required this.locked, required this.statusError});

  final DatyxApi api;
  final bool locked;
  final String? statusError;

  @override
  State<AityxTab> createState() => _AityxTabState();
}

class _AityxTabState extends State<AityxTab> {
  AityxAccount? _account;
  String? _error;
  int _days = 7;

  @override
  void initState() {
    super.initState();
    if (!widget.locked) _load();
  }

  @override
  void didUpdateWidget(AityxTab old) {
    super.didUpdateWidget(old);
    if (old.locked && !widget.locked) _load();
  }

  Future<void> _load() async {
    final days = _days;
    try {
      final account = await widget.api.aityx(days: days);
      if (mounted && days == _days) {
        setState(() {
          _account = account;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted && days == _days) setState(() => _error = e.message);
    }
  }

  void _window(int days) {
    if (days == _days) return;
    setState(() {
      _days = days;
      _account = null;
      _error = null;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final a = _account;
    final loaded = !widget.locked && _error == null && a != null;
    final cards = <Widget>[
      _Header(
        account: loaded ? a : null,
        days: _days,
        locked: widget.locked,
        error: widget.locked ? null : _error,
        onWindow: _window,
        onReload: _load,
      ),
      if (loaded) ...[
        _Hours(hours: a.perHour),
        _Breakdowns(account: a),
        _Calls(api: widget.api, calls: a.calls, days: a.days),
      ],
      _Personalization(personalization: loaded ? a.personalization : null),
    ];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (widget.statusError != null) ApiDownLine(widget.statusError!),
        for (var i = 0; i < cards.length; i++) ...[if (i > 0) const SizedBox(height: 16), cards[i]],
      ],
    );
  }
}

/// A count with thousands separated: 48,210.
String thousands(int n) {
  final digits = n.abs().toString();
  final out = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

/// A count in few characters: 950, 48.2K, 1.3M.
String compact(int n) {
  String trim(String s) => s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  if (n < 1000) return '$n';
  if (n < 999950) return '${trim((n / 1000).toStringAsFixed(1))}K';
  return '${trim((n / 1000000).toStringAsFixed(1))}M';
}

/// Dollars as small as aityx's prices make them: $0, $0.000175, $0.0123,
/// $1.25.
String usd(double v) {
  if (v == 0) return '\$0';
  if (v >= 1) return '\$${v.toStringAsFixed(2)}';
  if (v >= 0.01) return '\$${v.toStringAsFixed(4)}';
  if (v < 0.000001) return '< \$0.000001';
  return '\$${v.toStringAsPrecision(3)}';
}

/// A latency: milliseconds under a second (769 ms), else seconds to a
/// tenth (2.1 s); a dash for none.
String latency(num? ms) {
  if (ms == null) return '–';
  if (ms < 1000) return '${ms.round()} ms';
  return '${(ms / 1000).toStringAsFixed(1)} s';
}

String _hh(DateTime t) => t.toLocal().toString().substring(11, 16);

String _hourSpan(DateTime hour) => '${_hh(hour)}–${_hh(hour.add(const Duration(hours: 1)))}';

String _plural(int n, String one, [String? many]) => '${thousands(n)} ${n == 1 ? one : (many ?? '${one}s')}';

/// The tab's first card: what the gateway is, the window, the reload, the
/// key and the services' calls as the API says, and the totals' tiles;
/// or why there are none (signed out, the API's error, loading).
class _Header extends StatelessWidget {
  const _Header({
    required this.account,
    required this.days,
    required this.locked,
    required this.error,
    required this.onWindow,
    required this.onReload,
  });

  final AityxAccount? account;
  final int days;
  final bool locked;
  final String? error;
  final void Function(int days) onWindow;
  final Future<void> Function() onReload;

  @override
  Widget build(BuildContext context) {
    final a = account;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, box) {
                final windows = Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final d in aityxWindows)
                      ChoiceChip(
                        key: ValueKey('aityx-days-$d'),
                        label: Text(d == 1 ? '1 day' : '$d days'),
                        selected: d == days,
                        onSelected: locked ? null : (_) => onWindow(d),
                      ),
                  ],
                );
                final reload = IconButton(
                  key: const ValueKey('aityx-reload'),
                  tooltip: 'Ask again',
                  onPressed: locked ? null : onReload,
                  icon: const Icon(Icons.refresh, size: 20),
                );
                final title = Expanded(child: CardTitle('aityx', 'GET /api/aityx?days=$days'));
                // The windows beside the title when there's room, under it when not.
                return box.maxWidth >= 640
                    ? Row(children: [title, windows, const SizedBox(width: 6), reload])
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [title, reload]),
                          windows,
                        ],
                      );
              },
            ),
            const SizedBox(height: 8),
            const Text(
              'datyx routes calls to aityx through its gateway, POST /api/aityx/v1/systemone, which '
              'forwards them to aityx\'s POST /v1/systemone with datyx\'s own aityx key; HealthHub\'s desk '
              'triage goes this way. Each call is accounted for: who called and why, which model and '
              'decision, how long, the input tokens and what they cost, and what was sent and answered.',
              style: TextStyle(color: Aityx.muted),
            ),
            const SizedBox(height: 12),
            if (locked)
              const Text('Sign in to see the calls routed to aityx.', style: TextStyle(color: Aityx.muted))
            else if (error != null)
              Text(error!, key: const ValueKey('aityx-error'), style: const TextStyle(color: Aityx.red))
            else if (a == null)
              const Text('Loading…', style: TextStyle(color: Aityx.muted))
            else ...[
              if (!a.configured)
                const _Flag(
                  key: ValueKey('aityx-no-key'),
                  icon: Icons.warning_amber,
                  color: Aityx.amber,
                  text: 'datyx has no aityx key (AITYX_API_KEY): the gateway answers 503 and calls nothing, '
                      'and HealthHub calls aityx directly.',
                ),
              _Flag(
                key: const ValueKey('aityx-services'),
                icon: Icons.dns_outlined,
                color: Aityx.muted,
                text: a.sharesServiceCalls
                    ? 'Services\' calls, HealthHub\'s, are shown to every profile, with your own.'
                    : 'Only your own calls: services\' calls are kept apart (DATYX_AITYX_SHARE_SERVICE_CALLS is off).',
              ),
              const SizedBox(height: 4),
              _Totals(account: a),
            ],
          ],
        ),
      ),
    );
  }
}

/// A line the API's account says something of, with its icon.
class _Flag extends StatelessWidget {
  const _Flag({super.key, required this.icon, required this.color, required this.text});
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: const TextStyle(color: Aityx.fg, fontSize: 13))),
      ],
    ),
  );
}

class _Totals extends StatelessWidget {
  const _Totals({required this.account});
  final AityxAccount account;

  @override
  Widget build(BuildContext context) {
    final t = account.totals;
    final window = account.days == 1 ? 'in 1 day' : 'in ${account.days} days';
    final price = account.pricePerMillionInputTokens;
    final last = t.lastCalledAt;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        StatTile(key: const ValueKey('aityx-calls'), label: 'calls', value: thousands(t.calls), note: '$window, ${account.lastHour} in the last hour'),
        StatTile(
          key: const ValueKey('aityx-failed'),
          label: 'failed',
          value: thousands(t.failed),
          note: t.calls == 0 ? 'none yet' : '${(100 * t.failed / t.calls).toStringAsFixed(0)}% of calls, not 2xx',
          status: t.failed == 0 ? Aityx.green : Aityx.red,
          icon: t.failed == 0 ? Icons.check_circle_outline : Icons.error_outline,
        ),
        StatTile(key: const ValueKey('aityx-tokens'), label: 'input tokens', value: compact(t.inputTokens), note: '${thousands(t.inputTokens)} $window'),
        StatTile(
          key: const ValueKey('aityx-cost'),
          label: 'cost',
          value: usd(t.costUsd),
          note: price == null ? window : '\$$price per M input tokens',
        ),
        StatTile(key: const ValueKey('aityx-p50'), label: 'median latency', value: latency(t.p50Millis), note: 'mean ${latency(t.avgMillis)}'),
        StatTile(key: const ValueKey('aityx-p95'), label: '95th percentile', value: latency(t.p95Millis), note: 'per call'),
        StatTile(
          key: const ValueKey('aityx-last'),
          label: 'last call',
          value: last == null ? 'never' : '${span(DateTime.now().difference(last))} ago',
          note: last == null ? window : when(last),
        ),
      ],
    );
  }
}

/// The last 24 hours: the calls of each hour, answered and failed
/// stacked, and the input tokens of each, as two charts side by side
/// (one below the other when narrow), each on its own scale.
class _Hours extends StatelessWidget {
  const _Hours({required this.hours});
  final List<AityxHour> hours;

  @override
  Widget build(BuildContext context) {
    final calls = HourColumns(
      key: const ValueKey('aityx-calls-per-hour'),
      title: 'Calls per hour',
      unit: 'calls',
      keyPrefix: 'aityx-hour',
      hours: hours,
      segments: (h) => [(h.calls - h.failed, Aityx.orange), (h.failed, Aityx.red)],
      tip: (h) =>
          '${_hourSpan(h.hour)}: ${_plural(h.calls, 'call')}'
          '${h.failed == 0 ? '' : ', ${thousands(h.failed)} failed'}'
          '${h.p50Millis == null ? '' : ', median ${latency(h.p50Millis)}'}',
      legend: const [
        LegendKey(color: Aityx.orange, label: 'answered (2xx)'),
        LegendKey(color: Aityx.red, label: 'failed', icon: Icons.error_outline),
      ],
    );
    final tokens = HourColumns(
      key: const ValueKey('aityx-tokens-per-hour'),
      title: 'Input tokens per hour',
      unit: 'input tokens',
      keyPrefix: 'aityx-tokens',
      hours: hours,
      segments: (h) => [(h.inputTokens, Aityx.orange)],
      tip: (h) => '${_hourSpan(h.hour)}: ${_plural(h.inputTokens, 'input token')} in ${_plural(h.calls, 'call')}',
      format: compact,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CardTitle('The last 24 hours', 'perHour, oldest first'),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, box) => box.maxWidth >= 760
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [Expanded(child: calls), const SizedBox(width: 32), Expanded(child: tokens)],
                    )
                  : Column(children: [calls, const SizedBox(height: 20), tokens]),
            ),
          ],
        ),
      ),
    );
  }
}

/// A series' key in a legend: its swatch (and icon, for a status) and its
/// name in text.
class LegendKey extends StatelessWidget {
  const LegendKey({super.key, required this.color, required this.label, this.icon});
  final Color color;
  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
      if (icon != null) ...[const SizedBox(width: 4), Icon(icon, size: 12, color: color)],
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(color: Aityx.muted, fontSize: 11)),
    ],
  );
}

/// A column per hour on one baseline, scaled to the tallest (which the
/// subtitle names), each made of its [segments] stacked from the baseline
/// up with a 2 px gap between them, at most 24 px wide with its top
/// rounded; a tooltip per column ([tip]); the first hour and *now* under
/// the baseline, and a [legend] when there are several series.
class HourColumns extends StatelessWidget {
  const HourColumns({
    super.key,
    required this.title,
    required this.unit,
    required this.keyPrefix,
    required this.hours,
    required this.segments,
    required this.tip,
    this.legend = const [],
    this.format = thousands,
    this.height = 90,
  });

  final String title;
  final String unit;
  final String keyPrefix;
  final List<AityxHour> hours;

  /// An hour's values, bottom first, each with its color.
  final List<(int, Color)> Function(AityxHour hour) segments;
  final String Function(AityxHour hour) tip;
  final List<LegendKey> legend;
  final String Function(int value) format;
  final double height;

  int _total(AityxHour h) => segments(h).fold(0, (sum, s) => sum + (s.$1 > 0 ? s.$1 : 0));

  Widget _column(AityxHour h, int top) {
    final total = _total(h);
    final parts = [for (final s in segments(h)) if (s.$1 > 0) s];
    final tall = top == 0 || total == 0 ? 0.0 : (height * total / top).clamp(2.0, height);
    return Tooltip(
      message: tip(h),
      child: SizedBox(
        height: height,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 24),
              child: SizedBox(
                key: ValueKey('$keyPrefix-${h.hour.toIso8601String()}'),
                height: tall,
                child: Column(
                  children: [
                    for (var i = parts.length - 1; i >= 0; i--) ...[
                      Expanded(
                        flex: parts[i].$1,
                        child: Container(
                          key: ValueKey('$keyPrefix-${h.hour.toIso8601String()}-$i'),
                          decoration: BoxDecoration(
                            color: parts[i].$2,
                            borderRadius: i == parts.length - 1
                                ? const BorderRadius.vertical(top: Radius.circular(4))
                                : BorderRadius.zero,
                          ),
                        ),
                      ),
                      if (i > 0) const SizedBox(height: 2),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final top = hours.fold<int>(0, (m, h) => _total(h) > m ? _total(h) : m);
    const small = TextStyle(color: Aityx.muted, fontSize: 11);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        Text(top == 0 ? 'none in the last 24 hours' : 'the tallest hour is ${format(top)} $unit', style: small),
        // The legend's row is kept without a legend too, so charts side by
        // side share their baseline.
        const SizedBox(height: 6),
        SizedBox(height: 16, child: Wrap(spacing: 12, children: legend)),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [for (final h in hours) Expanded(child: _column(h, top))],
        ),
        Container(height: 1, color: Aityx.border),
        const SizedBox(height: 2),
        if (hours.isNotEmpty)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [Text(_hh(hours.first.hour), style: small), const Text('now', style: small)],
          ),
      ],
    );
  }
}

/// The calls by purpose, by model and by decision, side by side.
class _Breakdowns extends StatelessWidget {
  const _Breakdowns({required this.account});
  final AityxAccount account;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CardTitle('By purpose, model and decision', 'byPurpose, byModel, byDecision'),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, box) {
              final parts = [
                Breakdown(key: const ValueKey('aityx-by-purpose'), title: 'Purpose', counts: account.byPurpose),
                Breakdown(key: const ValueKey('aityx-by-model'), title: 'Model', counts: account.byModel),
                Breakdown(key: const ValueKey('aityx-by-decision'), title: 'Decision', counts: account.byDecision),
              ];
              return box.maxWidth >= 900
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < parts.length; i++) ...[if (i > 0) const SizedBox(width: 32), Expanded(child: parts[i])],
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < parts.length; i++) ...[if (i > 0) const SizedBox(height: 16), parts[i]],
                      ],
                    );
            },
          ),
        ],
      ),
    ),
  );
}

/// A breakdown's values, the most called first, at most [shown] of them
/// (the rest counted below): the name (*none* when the calls had none), a
/// bar of its calls in one hue scaled to the most called, and its calls
/// and failures in text; a tooltip per row with its input tokens too.
class Breakdown extends StatelessWidget {
  const Breakdown({super.key, required this.title, required this.counts, this.shown = 5});

  final String title;
  final List<AityxCount> counts;
  final int shown;

  @override
  Widget build(BuildContext context) {
    final top = counts.fold<int>(0, (m, c) => c.calls > m ? c.calls : m);
    final rest = counts.length - shown;
    return LayoutBuilder(
      builder: (context, box) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          if (counts.isEmpty) const Text('none yet', style: TextStyle(color: Aityx.muted, fontSize: 12)),
          for (final c in counts.take(shown))
            Tooltip(
              message:
                  '${c.name ?? 'none'}: ${_plural(c.calls, 'call')}, ${thousands(c.failed)} failed, '
                  '${_plural(c.inputTokens, 'input token')}',
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    SizedBox(
                      width: box.maxWidth * 0.45,
                      child: Text(
                        c.name ?? 'none',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: c.name == null ? Aityx.muted : Aityx.fg,
                          fontStyle: c.name == null ? FontStyle.italic : FontStyle.normal,
                        ),
                      ),
                    ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, box) => Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            key: ValueKey('$title-${c.name}'),
                            width: top == 0 ? 0 : (box.maxWidth * c.calls / top).clamp(2.0, box.maxWidth),
                            height: 10,
                            decoration: const BoxDecoration(
                              color: Aityx.orange,
                              borderRadius: BorderRadius.horizontal(right: Radius.circular(4)),
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 84,
                      child: Text(
                        c.failed == 0 ? thousands(c.calls) : '${thousands(c.calls)} · ${thousands(c.failed)} failed',
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 12, color: Aityx.muted),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (rest > 0)
            Text('and ${_plural(rest, 'other')}', style: const TextStyle(color: Aityx.muted, fontSize: 11)),
        ],
      ),
    );
  }
}

/// aityx's HTTP status as an icon and the code: green for 2xx, red else.
class HttpStatusChip extends StatelessWidget {
  const HttpStatusChip(this.status, {super.key});
  final int status;

  @override
  Widget build(BuildContext context) {
    final ok = status >= 200 && status < 300;
    final color = ok ? Aityx.green : Aityx.red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: color)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(ok ? Icons.check_circle_outline : Icons.error_outline, size: 12, color: color),
          const SizedBox(width: 4),
          Text(status == 0 ? '–' : '$status', style: TextStyle(fontSize: 11, color: color)),
        ],
      ),
    );
  }
}

/// The latest calls, newest first, as a table: when, who (a service's
/// with its icon), why, model and decision, how long, the input tokens and
/// aityx's status, a failure's error under its row. A row opens the call.
class _Calls extends StatelessWidget {
  const _Calls({required this.api, required this.calls, required this.days});
  final DatyxApi api;
  final List<AityxCallInfo> calls;
  final int days;

  static const _widths = [130.0, 160.0, 90.0, null, 80.0, 80.0, 100.0, 24.0];
  static const _minWidth = 940.0;

  Widget _row(List<Widget> cells) => Row(
    children: [
      for (var i = 0; i < cells.length; i++)
        _widths[i] == null
            ? Expanded(child: Padding(padding: const EdgeInsets.only(right: 12), child: cells[i]))
            : SizedBox(width: _widths[i], child: cells[i]),
    ],
  );

  @override
  Widget build(BuildContext context) {
    const head = TextStyle(color: Aityx.muted, fontSize: 11, fontWeight: FontWeight.bold);
    const cell = TextStyle(fontSize: 12, color: Aityx.fg);
    const mono = TextStyle(fontSize: 12, color: Aityx.fg, fontFamily: 'monospace');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CardTitle('Calls', 'the latest 50, newest first; a row opens its request and answer'),
            const SizedBox(height: 8),
            if (calls.isEmpty)
              Text(
                'No call routed to aityx in the last ${days == 1 ? 'day' : '$days days'}. HealthHub\'s desk triage '
                'calls aityx through datyx when HEALTHHUB_AITYX_VIA_DATYX is on and both share DATYX_SERVICE_TOKEN.',
                key: const ValueKey('aityx-no-calls'),
                style: const TextStyle(color: Aityx.muted),
              )
            else
              LayoutBuilder(
                builder: (context, box) => SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: box.maxWidth < _minWidth ? _minWidth : box.maxWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: _row(const [
                            Text('when', style: head),
                            Text('caller', style: head),
                            Text('purpose', style: head),
                            Text('model · decision', style: head),
                            Text('latency', style: head, textAlign: TextAlign.right),
                            Text('tokens', style: head, textAlign: TextAlign.right),
                            Padding(padding: EdgeInsets.only(left: 16), child: Text('status', style: head)),
                            SizedBox(),
                          ]),
                        ),
                        Container(height: 1, color: Aityx.border),
                        for (final c in calls)
                          InkWell(
                            key: ValueKey('aityx-call-${c.id}'),
                            borderRadius: BorderRadius.circular(6),
                            onTap: () => showDialog<void>(
                              context: context,
                              builder: (_) => AityxCallDialog(api: api, call: c),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _row([
                                    Text(c.at == null ? '' : when(c.at!), style: mono.copyWith(color: Aityx.muted)),
                                    Row(
                                      children: [
                                        Icon(c.service ? Icons.dns_outlined : Icons.person_outline, size: 14, color: Aityx.muted),
                                        const SizedBox(width: 4),
                                        Flexible(child: Text(c.caller ?? '', overflow: TextOverflow.ellipsis, style: cell)),
                                      ],
                                    ),
                                    Text(
                                      c.purpose ?? 'none',
                                      overflow: TextOverflow.ellipsis,
                                      style: c.purpose == null ? cell.copyWith(color: Aityx.muted, fontStyle: FontStyle.italic) : cell,
                                    ),
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            '${c.model ?? '?'} · ${c.decision ?? 'no decision'}',
                                            overflow: TextOverflow.ellipsis,
                                            style: cell,
                                          ),
                                        ),
                                        if (c.personalized) ...[
                                          const SizedBox(width: 6),
                                          const Text('personalized', style: TextStyle(fontSize: 11, color: Aityx.orangeLight)),
                                        ],
                                      ],
                                    ),
                                    Text(latency(c.millis), style: cell, textAlign: TextAlign.right),
                                    Text(c.inputTokens == null ? '–' : thousands(c.inputTokens!), style: cell, textAlign: TextAlign.right),
                                    Padding(
                                      padding: const EdgeInsets.only(left: 16),
                                      child: Align(alignment: Alignment.centerLeft, child: HttpStatusChip(c.status)),
                                    ),
                                    const Icon(Icons.chevron_right, size: 18, color: Aityx.muted),
                                  ]),
                                  if (c.error != null)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 130, top: 2),
                                      child: Text(c.error!, style: const TextStyle(color: Aityx.red, fontSize: 12)),
                                    ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A call routed to aityx, opened: what the table says of it at once,
/// then, as `GET /api/aityx/calls/{id}` answers, what was sent to aityx
/// and what it answered, pretty-printed JSON (as text when it was
/// truncated past 64 KB, which it says, or isn't JSON).
class AityxCallDialog extends StatefulWidget {
  const AityxCallDialog({super.key, required this.api, required this.call});

  final DatyxApi api;
  final AityxCallInfo call;

  @override
  State<AityxCallDialog> createState() => _AityxCallDialogState();
}

class _AityxCallDialogState extends State<AityxCallDialog> {
  AityxCallDetail? _detail;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final detail = await widget.api.aityxCall(widget.call.id);
      if (mounted) setState(() => _detail = detail);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  static String _text(Object? body) => body is String ? body : jsonEncode(body);

  List<Widget> _body(String label, Object? body, bool truncated, String none) => [
    if (body == null) ...[
      Text(label, style: const TextStyle(color: Aityx.muted, fontSize: 11)),
      const SizedBox(height: 4),
      Text(none, style: const TextStyle(color: Aityx.muted, fontStyle: FontStyle.italic, fontSize: 12)),
      const SizedBox(height: 8),
    ] else ...[
      if (truncated)
        const Padding(
          padding: EdgeInsets.only(bottom: 4),
          child: Text('truncated at 64 KB: shown as text', style: TextStyle(color: Aityx.amber, fontSize: 11)),
        ),
      JsonBlock(label, _text(body), key: ValueKey('aityx-$label')),
    ],
  ];

  @override
  Widget build(BuildContext context) {
    final c = widget.call;
    final d = _detail;
    final facts = [
      if (c.at != null) when(c.at!),
      '${c.service ? 'service' : 'user'} ${c.caller ?? '?'}',
      if (c.purpose != null) 'for ${c.purpose}',
      'model ${c.model ?? '?'}',
      _plural(c.questions, 'question'),
      if (c.mode != null) 'mode ${c.mode}',
      latency(c.millis),
      if (c.inputTokens != null) _plural(c.inputTokens!, 'input token'),
      if (c.costUsd != null) usd(c.costUsd!),
      c.personalized ? 'personalized' : 'not personalized',
    ];
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 900, maxHeight: size.height * 0.85),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  HttpStatusChip(c.status),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'aityx call ${c.id} · ${c.decision ?? 'no decision'}',
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('aityx-call-close'),
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 20),
                  ),
                ],
              ),
              Text(
                'GET /api/aityx/calls/${c.id}',
                style: const TextStyle(color: Aityx.muted, fontFamily: 'monospace', fontSize: 12),
              ),
              const SizedBox(height: 6),
              Text(facts.join(' · '), style: const TextStyle(color: Aityx.fg, fontSize: 12)),
              if (c.error != null) ...[
                const SizedBox(height: 4),
                Text(c.error!, style: const TextStyle(color: Aityx.red, fontSize: 12)),
              ],
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_error != null)
                        Text(_error!, style: const TextStyle(color: Aityx.red))
                      else if (d == null)
                        const Text('Loading…', style: TextStyle(color: Aityx.muted))
                      else ...[
                        ..._body('Request', d.request, d.requestTruncated, 'none recorded'),
                        ..._body('Response', d.response, d.responseTruncated, 'none: aityx wasn\'t reached'),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Personalization: coming, not active (unless the API says it is). What
/// it will do: a profile's own Jev model, extra context, decision
/// variants, done in datyx's hook before a call goes to aityx.
class _Personalization extends StatelessWidget {
  const _Personalization({required this.personalization});

  /// The API's word on it; null before the account is read.
  final AityxPersonalization? personalization;

  @override
  Widget build(BuildContext context) {
    final p = personalization;
    final active = p?.active == true;
    final color = active ? Aityx.green : Aityx.muted;
    const plans = [
      ('Per-profile models', 'a profile\'s preferred Jev model for its calls, instead of the one the caller names'),
      ('Extra context', 'what datyx knows of the profile\'s data, added to the state aityx decides on'),
      ('Decision variants', 'a profile\'s own variant of a decision, such as its rules for the desk triage'),
    ];
    return Card(
      key: const ValueKey('aityx-personalization'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(child: CardTitle('Personalization', 'AityxPersonalizer, in datyx\'s gateway')),
                Container(
                  key: const ValueKey('aityx-personalization-state'),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: color)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(active ? Icons.check_circle_outline : Icons.pause_circle_outline, size: 12, color: color),
                      const SizedBox(width: 4),
                      Text(active ? 'active: ${p!.name}' : 'coming: not active', style: TextStyle(fontSize: 11, color: color)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              active
                  ? p!.note ?? 'Calls are personalized per profile before they go to aityx.'
                  : 'Not active yet: calls go to aityx exactly as their callers send them. '
                        'This is where datyx will personalize them per profile, before they go to aityx:',
              style: const TextStyle(color: Aityx.fg),
            ),
            const SizedBox(height: 8),
            for (final (name, what) in plans)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(Icons.tune, size: 14, color: Aityx.muted),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: '$name: ', style: const TextStyle(fontWeight: FontWeight.bold)),
                            TextSpan(text: what),
                          ],
                        ),
                        style: TextStyle(color: active ? Aityx.fg : Aityx.muted, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            Text(
              'A call whose body was changed this way will say personalized in the calls.',
              style: TextStyle(color: Aityx.muted.withValues(alpha: 0.8), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
