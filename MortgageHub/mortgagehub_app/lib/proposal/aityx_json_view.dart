import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Why a part of the aityx JSON matters: shown as a highlight on its lines,
/// a short [label] beside it, and [why] in a tooltip.
class JsonNote {
  const JsonNote(
    this.path,
    this.label,
    this.why, {
    this.when,
    this.alarm = false,
  });

  /// Matches the dotted path of the value, from the block's root (list
  /// indexes are segments too: `decision.decisions.ltv_check.table.0`).
  final RegExp path;
  final String label;
  final String why;

  /// When set, the note applies only to values it accepts; a value it
  /// rejects falls through to the next note whose [path] matches.
  final bool Function(Object? value)? when;

  /// Drawn in the theme's error color (red) instead of its primary: for
  /// what makes a proposal Not processable.
  final bool alarm;

  bool matches(String path, Object? value) =>
      this.path.hasMatch(path) && (when?.call(value) ?? true);
}

/// The red of the [JsonNote.alarm] highlights: the theme's error color,
/// lightened so it reads clearly without shouting.
Color _alarmColor(ColorScheme scheme) =>
    Color.lerp(scheme.error, Colors.white, 0.35)!;

bool _failed(Object? check) => check is Map && check['result'] == 'fail';

/// The parts of the body the app sends to aityx worth pointing out.
final requestNotes = [
  JsonNote(
    RegExp(r'^decision$'),
    'The rules',
    'The whole decision model: inputs, decision tables and expressions. '
        'aityx stores no models, so the rules travel with every call, and '
        'what you see here is exactly what was executed.',
  ),
  JsonNote(
    RegExp(r'^decision\.decisions\.[a-z_]+\.table\.0$'),
    'Cited rules',
    "A decision table's header. The first matching row wins, and its "
        "'# why' column cites the source of the rule (Fannie Mae's matrix, "
        'the HUD Handbook, the CFR), so every reason can be traced back.',
  ),
  JsonNote(
    RegExp(r'^decision\.decisions\.status$'),
    'Verdict rule',
    'How the verdict is reached: any failed check makes it Not '
        'processable, else any review makes it Requires review, else '
        "it's Processable.",
  ),
  JsonNote(
    RegExp(r'^state$'),
    'The facts',
    "The borrower's answers, mapped to the model's inputs. The name, email "
        'and phone are left out: aityx gets only what the rules need.',
  ),
  JsonNote(
    RegExp(r'^state\.(loan_program|occupancy|loan_purpose)$'),
    'Picks the rules',
    'The program, occupancy and purpose decide which rows of the tables '
        'apply: each program has its own maximum LTV and ratio limits.',
  ),
  JsonNote(
    RegExp(r'^state\.(property_value|down_payment|current_balance|cash_out)$'),
    'Loan & LTV',
    'Give the loan amount, and with the value the loan-to-value ratio, '
        'compared against the program maximum.',
  ),
  JsonNote(
    RegExp(r'^state\.credit_score$'),
    'Credit',
    'Self-reported band; below 620, or unknown, sends the proposal to '
        'review.',
  ),
  JsonNote(
    RegExp(r'^state\.(annual_income|monthly_debts)$'),
    'Debt-to-income',
    'With the estimated payment, give the debt-to-income ratio, checked '
        "against the program's limits.",
  ),
  JsonNote(
    RegExp(r'^state\.assumed_rate$'),
    'Assumed rate',
    'The annual rate the payment is estimated with: an assumption, not a '
        'priced rate.',
  ),
];

/// The parts of aityx's answer worth pointing out. The red ones come first,
/// so they win over the general note for the same value.
final responseNotes = [
  JsonNote(
    RegExp(r'^answers\.status\.choice$'),
    'Not processable',
    "Where aityx asserts the verdict: a lender can't process this proposal "
        'as asked. At least one check failed (the red Failed check '
        'highlights below), and one failure is enough.',
    when: (value) => value == 'not_processable',
    alarm: true,
  ),
  JsonNote(
    RegExp(r'^answers\.[a-z_]+_check\.value$'),
    'Failed check',
    'This check failed, which alone makes the proposal Not processable. '
        'The reason beside it, from the table row that matched, says why.',
    when: _failed,
    alarm: true,
  ),
  JsonNote(
    RegExp(r'^receipt\.decisions\.status\.value$'),
    'Verdict computed',
    "The receipt's record of the verdict: the status rule found a failed "
        'check, so it computed Not processable. Its branches, next to it, '
        'show the rule that fired.',
    when: (value) => value == 'not_processable',
    alarm: true,
  ),
  JsonNote(
    RegExp(r'^answers$'),
    'Answers',
    'Every decision the model computed. The verdict, the figures and the '
        'reasons above are read straight from here.',
  ),
  JsonNote(
    RegExp(r'^answers\.status$'),
    'The verdict',
    'Processable, Requires review or Not processable: the status shown at '
        'the top of the check.',
  ),
  JsonNote(
    RegExp(r'^answers\.(program|ltv|limit|credit|dti)_check$'),
    'Check & reason',
    "One check's result (pass, review, fail) and its reason, from the "
        'table row that matched. The app shows this reason as is.',
  ),
  JsonNote(
    RegExp(r'^answers\.(ltv|max_ltv|dti|housing_payment)$'),
    'Figure shown',
    'A figure shown above. LTV and DTI stay unrounded here, since the '
        'rules compare exact values (97.0002% is above 97%).',
  ),
  JsonNote(
    RegExp(r'^receipt$'),
    'Audit trail',
    'The receipt: the computed values and where each input came from, '
        'enough to explain the verdict later.',
  ),
  JsonNote(
    RegExp(r'^receipt\.decisions$'),
    'Computed',
    'The value of every decision, helpers included: how the model got '
        'from the facts to the verdict.',
  ),
  JsonNote(
    RegExp(r'^receipt\.provenance$'),
    'Provenance',
    'Where each input came from. "state" means it was supplied in the '
        'request, not inferred by a language model.',
  ),
  JsonNote(
    RegExp(r'^usage$'),
    'Cost',
    "The call's tokens. System One is deterministic: the same facts always "
        'give the same answer.',
  ),
  JsonNote(
    RegExp(r'^decision_error$'),
    'Error',
    'Present only when the model failed to run; the app then reports the '
        'check as failed.',
  ),
];

/// Values printed on more lines than this are highlighted on their first
/// line only, so a large one doesn't tint the whole block.
const _maxHighlightLines = 15;

@visibleForTesting
class AnnotatedLine {
  AnnotatedLine(this.text);

  final String text;
  JsonNote? note;

  /// The first line of a highlighted value: it carries the label.
  bool start = false;

  /// On the first line of a value: its dotted path, and the index of its
  /// last line, so a jump can mark the whole value.
  String? path;
  int? end;
}

/// [json] as `JsonEncoder.withIndent('  ')` prints it, line by line, with
/// [notes] attached to the lines of the values they match. Where notes
/// nest, the innermost wins.
@visibleForTesting
List<AnnotatedLine> annotateJson(Object? json, List<JsonNote> notes) {
  final lines = <AnnotatedLine>[];
  final spans = <(int depth, int first, int last, JsonNote note)>[];

  void emit(Object? value, String path, int depth, String key, String comma) {
    final indent = '  ' * depth;
    final first = lines.length;
    void children(String open, String close, Iterable<(String, Object?)> kids) {
      lines.add(AnnotatedLine('$indent$key$open'));
      final all = kids.toList();
      for (var i = 0; i < all.length; i++) {
        final (name, kid) = all[i];
        emit(
          kid,
          path.isEmpty ? name : '$path.$name',
          depth + 1,
          value is Map ? '${jsonEncode(name)}: ' : '',
          i < all.length - 1 ? ',' : '',
        );
      }
      lines.add(AnnotatedLine('$indent$close$comma'));
    }

    if (value is Map && value.isNotEmpty) {
      children('{', '}', [
        for (final e in value.entries) ('${e.key}', e.value),
      ]);
    } else if (value is List && value.isNotEmpty) {
      children('[', ']', [
        for (var i = 0; i < value.length; i++) ('$i', value[i]),
      ]);
    } else {
      lines.add(AnnotatedLine('$indent$key${jsonEncode(value)}$comma'));
    }
    lines[first]
      ..path = path
      ..end = lines.length - 1;
    if (path.isEmpty) return;
    for (final note in notes) {
      if (note.matches(path, value)) {
        spans.add((depth, first, lines.length - 1, note));
        break;
      }
    }
  }

  emit(json, '', 0, '', '');
  spans.sort((a, b) => a.$1.compareTo(b.$1));
  for (final (_, first, last, note) in spans) {
    final end = last - first < _maxHighlightLines ? last : first;
    for (var i = first; i <= end; i++) {
      lines[i]
        ..note = note
        ..start = i == first;
    }
  }
  return lines;
}

/// Each line's height at the default text size: fixed, so a line's offset
/// is exactly `8 + index * rowHeight` and a jump lands on it. The rows and
/// the text follow the user's text size together (see [_rowHeight]).
const _lineHeight = 22.0;
const _gutterWidth = 52.0;
const _mono = TextStyle(fontFamily: 'RobotoMono', fontSize: 14, height: 1.2);

/// [_lineHeight] at the text size in [context]: the rows grow with larger
/// accessibility text, as the text they hold does.
double _rowHeight(BuildContext context) =>
    _lineHeight *
    MediaQuery.textScalerOf(context).scale(_mono.fontSize!) /
    _mono.fontSize!;

/// [json], pretty-printed with numbered lines under [title], with the
/// parts [notes] match highlighted and labeled. "Jump to" chips, and the
/// labels themselves, scroll exactly to a part's first line, mark the whole
/// value, and say above the code what it is and why it matters.
class AityxJsonView extends StatefulWidget {
  const AityxJsonView(
    this.title,
    this.json, {
    super.key,
    this.notes = const [],
  });

  final String title;
  final Object? json;
  final List<JsonNote> notes;

  @override
  State<AityxJsonView> createState() => _AityxJsonViewState();
}

class _AityxJsonViewState extends State<AityxJsonView> {
  final _vertical = ScrollController();
  final _horizontal = ScrollController();
  final _viewKey = GlobalKey();
  late List<AnnotatedLine> _lines;
  late int _longestLine;

  /// The first line of each note's first highlight, in the order they
  /// appear: where its "Jump to" chip goes.
  final _anchors = <JsonNote, int>{};

  /// The first line of the part last jumped to, marked whole in the code
  /// and explained above it.
  int? _active;

  @override
  void initState() {
    super.initState();
    _build();
  }

  @override
  void didUpdateWidget(AityxJsonView old) {
    super.didUpdateWidget(old);
    if (old.json != widget.json || old.notes != widget.notes) _build();
  }

  @override
  void dispose() {
    _vertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  void _build() {
    _lines = annotateJson(widget.json, widget.notes);
    _longestLine = _lines.fold(0, (max, l) => math.max(max, l.text.length));
    _anchors.clear();
    for (var i = 0; i < _lines.length; i++) {
      final line = _lines[i];
      if (line.start) _anchors.putIfAbsent(line.note!, () => i);
    }
    if (_active case final a? when a >= _lines.length || !_lines[a].start) {
      _active = null;
    }
  }

  /// Marks the part whose first line is [first], brings the whole view
  /// (chips, explanation and code) to the top of the page, and scrolls that
  /// line to the top of the code, one line of context above it.
  void _jumpTo(int first) {
    setState(() => _active = first);
    // After the frame, so the page scrolls to the view with its explanation.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_viewKey.currentContext case final view?) {
        Scrollable.ensureVisible(
          view,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
      if (!_vertical.hasClients) return;
      final offset = math.max(0.0, 8 + (first - 1) * _rowHeight(context));
      _vertical.animateTo(
        math.min(offset, _vertical.position.maxScrollExtent),
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
      if (_horizontal.hasClients) _horizontal.jumpTo(0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final active = _active == null ? null : _lines[_active!];
    final height = (MediaQuery.sizeOf(context).height * 0.55).clamp(
      320.0,
      640.0,
    );
    return Padding(
      key: _viewKey,
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(widget.title, style: theme.textTheme.titleSmall),
              ),
              IconButton(
                tooltip: 'Copy JSON',
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                icon: const Icon(Icons.copy),
                onPressed: () => Clipboard.setData(
                  ClipboardData(
                    text: const JsonEncoder.withIndent('  ')
                        .convert(widget.json),
                  ),
                ),
              ),
            ],
          ),
          if (_anchors.isNotEmpty) ...[
            Text(
              'Highlighted parts matter most: pick one to go to it and read '
              'why. Jump to:',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final MapEntry(key: note, value: first)
                    in _anchors.entries)
                  ChoiceChip(
                    visualDensity: VisualDensity.compact,
                    showCheckmark: false,
                    selected: note == active?.note,
                    avatar: Icon(
                      note.alarm ? Icons.error_outline : Icons.my_location,
                      size: 14,
                      color: _accent(scheme, note),
                    ),
                    side: note.alarm
                        ? BorderSide(color: _alarmColor(scheme))
                        : null,
                    label: Text(note.label),
                    tooltip: note.why,
                    onSelected: (_) => _jumpTo(first),
                  ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          // What the marked part is, in words, above the code.
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: active == null
                ? const SizedBox(width: double.infinity)
                : _Explanation(
                    key: ValueKey(_active),
                    note: active.note!,
                    path: active.path!,
                  ),
          ),
          Container(
            height: height,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            clipBehavior: Clip.antiAlias,
            child: _CodePane(
              lines: _lines,
              longestLine: _longestLine,
              vertical: _vertical,
              horizontal: _horizontal,
              active: _active,
              onLabel: _jumpTo,
            ),
          ),
        ],
      ),
    );
  }
}

Color _accent(ColorScheme scheme, JsonNote note) =>
    note.alarm ? _alarmColor(scheme) : scheme.primary;

/// The marked part: its label, where it is in the JSON, and why it matters.
class _Explanation extends StatelessWidget {
  const _Explanation({super.key, required this.note, required this.path});

  final JsonNote note;
  final String path;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = _accent(scheme, note);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: accent, width: 3)),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '${note.label}  ',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            TextSpan(
              text: path,
              style: _mono.copyWith(
                fontSize: 13,
                color: scheme.onSurfaceVariant,
              ),
            ),
            TextSpan(text: '\n${note.why}'),
          ],
        ),
        style: theme.textTheme.bodyMedium,
      ),
    );
  }
}

/// The code: one fixed-height, numbered row per line; highlighted parts
/// tinted with their label on their first row, the marked one strongly.
class _CodePane extends StatelessWidget {
  const _CodePane({
    required this.lines,
    required this.longestLine,
    required this.vertical,
    required this.horizontal,
    required this.active,
    required this.onLabel,
  });

  final List<AnnotatedLine> lines;
  final int longestLine;
  final ScrollController vertical;
  final ScrollController horizontal;

  /// The first line of the marked part.
  final int? active;
  final ValueChanged<int> onLabel;

  /// A character's width as the rows draw it, at [context]'s text size.
  double _charWidth(BuildContext context) {
    final painter = TextPainter(
      text: const TextSpan(text: '0000000000', style: _mono),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    return painter.width / 10;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = this.active;
    final markedNote = active == null ? null : lines[active].note;
    final markedEnd = active == null ? -1 : lines[active].end!;
    final rowHeight = _rowHeight(context);
    final contentWidth =
        _gutterWidth + 28 + longestLine * _charWidth(context) + 200;
    // The vertical scrollbar stays at the pane's edge, outside the box
    // that scrolls sideways; each scrollbar follows its own axis.
    return LayoutBuilder(
      builder: (context, constraints) => Scrollbar(
        controller: vertical,
        notificationPredicate: (n) => n.metrics.axis == Axis.vertical,
        child: Scrollbar(
          controller: horizontal,
          notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
          child: SingleChildScrollView(
            controller: horizontal,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: math.max(constraints.maxWidth, contentWidth),
              height: constraints.maxHeight,
              child: SelectionArea(
                child: ListView.builder(
                  controller: vertical,
                  // Room below the last line, so a part near the end can
                  // still scroll to the top like any other.
                  padding: EdgeInsets.only(
                    top: 8,
                    bottom: math.max(8, constraints.maxHeight - 3 * rowHeight),
                  ),
                  itemExtent: rowHeight,
                  itemCount: lines.length,
                  itemBuilder: (context, i) => _Row(
                    number: i + 1,
                    line: lines[i],
                    marked: active != null && i >= active && i <= markedEnd,
                    markedNote: markedNote,
                    isActive: i == active,
                    onLabel: () => onLabel(i),
                    scheme: scheme,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.number,
    required this.line,
    required this.marked,
    required this.markedNote,
    required this.isActive,
    required this.onLabel,
    required this.scheme,
  });

  final int number;
  final AnnotatedLine line;

  /// Inside the part last jumped to, and that part's first line.
  final bool marked;
  final JsonNote? markedNote;
  final bool isActive;
  final VoidCallback onLabel;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final note = line.note;
    // A marked row takes the marked part's color, even where an inner
    // part's highlight covers it.
    final shown = marked ? markedNote : note;
    final accent = shown == null ? null : _accent(scheme, shown);
    final strength = marked
        ? 0.24
        : (shown?.alarm ?? false)
        ? 0.18
        : 0.10;
    return Container(
      decoration: accent == null
          ? null
          : BoxDecoration(
              color: accent.withValues(alpha: strength),
              border: Border(
                left: BorderSide(
                  color: marked ? accent : accent.withValues(alpha: 0.6),
                  width: 3,
                ),
              ),
            ),
      child: Row(
        children: [
          SelectionContainer.disabled(
            child: SizedBox(
              width: _gutterWidth - (accent == null ? 0 : 3),
              child: Text(
                '$number',
                textAlign: TextAlign.right,
                style: _mono.copyWith(
                  color: marked
                      ? accent
                      : scheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Text(
            line.text,
            style: _mono.copyWith(color: scheme.onSurface),
            softWrap: false,
          ),
          if (line.start && note != null) ...[
            const SizedBox(width: 12),
            _Label(note, active: isActive, onTap: onLabel),
          ],
        ],
      ),
    );
  }
}

/// A part's label at the end of its first line: hover for why it matters,
/// tap to mark it and read the explanation above the code.
class _Label extends StatelessWidget {
  const _Label(this.note, {required this.active, required this.onTap});

  final JsonNote note;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = _accent(scheme, note);
    final onAccent = note.alarm ? scheme.onError : scheme.onPrimary;
    return SelectionContainer.disabled(
      child: Tooltip(
        message: note.why,
        waitDuration: const Duration(milliseconds: 300),
        constraints: const BoxConstraints(maxWidth: 360),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
            decoration: BoxDecoration(
              color: active ? accent : accent.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(10),
              border: active ? Border.all(color: scheme.onSurface) : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  note.alarm ? Icons.error_outline : Icons.info_outline,
                  size: 12,
                  color: onAccent,
                ),
                const SizedBox(width: 3),
                Text(
                  note.label,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: onAccent,
                    fontWeight: FontWeight.w600,
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
