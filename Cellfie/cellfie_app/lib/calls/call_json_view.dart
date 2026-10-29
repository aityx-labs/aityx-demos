import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'json_layout.dart';

/// One side of an aityx call, pretty-printed with line numbers and colors
/// in a pane of its own, the key parts (by path) tinted and labeled on
/// their first row, with a button that copies the exact JSON.
class CallJsonView extends StatefulWidget {
  const CallJsonView({
    super.key,
    required this.title,
    required this.json,
    this.subtitle = '',
    this.highlights = const {},
    this.height = 320,
  });

  /// `REQUEST` or `RESPONSE`.
  final String title;
  final String subtitle;
  final Object? json;

  /// Paths of the key parts (`state.situations`, `answers.fates`...) and
  /// their labels.
  final Map<String, String> highlights;
  final double height;

  @override
  State<CallJsonView> createState() => _CallJsonViewState();
}

const _lineHeight = 22.0;
const _fontSize = 14.0;
const _gutterWidth = 44.0;

const _style = TextStyle(
  fontFamily: 'RobotoMono',
  fontSize: _fontSize,
  height: 1.2,
);

class _CallJsonViewState extends State<CallJsonView> {
  late JsonLayout _layout;

  /// For each row, the label of the key part starting there, if any, and
  /// whether it's inside a key part.
  late List<String?> _labels;
  late List<bool> _tinted;
  final _vertical = ScrollController();
  final _horizontal = ScrollController();

  @override
  void initState() {
    super.initState();
    _lay();
  }

  @override
  void didUpdateWidget(CallJsonView old) {
    super.didUpdateWidget(old);
    if (old.json != widget.json || old.highlights != widget.highlights) _lay();
  }

  @override
  void dispose() {
    _vertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  void _lay() {
    _layout = layoutJson(widget.json);
    _labels = List.filled(_layout.lines.length, null);
    _tinted = List.filled(_layout.lines.length, false);
    for (final MapEntry(key: path, value: label) in widget.highlights.entries) {
      final range = _layout.ranges[path];
      if (range == null) continue;
      _labels[range.first] = label;
      for (var i = range.first; i <= range.last; i++) {
        _tinted[i] = true;
      }
    }
  }

  double _charWidth() {
    final painter = TextPainter(
      text: const TextSpan(text: '0000000000', style: _style),
      textDirection: TextDirection.ltr,
    )..layout();
    return painter.width / 10;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = {
      JsonToken.key: scheme.tertiary,
      JsonToken.string: scheme.secondary,
      JsonToken.number: scheme.onPrimaryContainer,
      JsonToken.literal: scheme.onPrimaryContainer,
      JsonToken.punctuation: scheme.onSurfaceVariant,
      JsonToken.space: scheme.onSurface,
    };
    // Room for the longest line, and for the widest label after it.
    var labelWidth = 0.0;
    for (final label in widget.highlights.values) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: theme.textTheme.labelSmall),
        textDirection: TextDirection.ltr,
      )..layout();
      if (painter.width > labelWidth) labelWidth = painter.width;
    }
    final contentWidth =
        _gutterWidth + 16 + _layout.longestLine * _charWidth() + labelWidth + 48;
    // Line numbers; the continuation rows of a wrapped string share their
    // line's number, and show none.
    final numbers = <String>[];
    var n = 0;
    for (final line in _layout.lines) {
      numbers.add(line.continuation ? '' : '${++n}');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 0, 4),
          child: Row(
            children: [
              Text(
                widget.title,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.subtitle,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Copy the ${widget.title.toLowerCase()}',
                icon: const Icon(Icons.copy_outlined, size: 18),
                onPressed: () => Clipboard.setData(
                  ClipboardData(
                    text: const JsonEncoder.withIndent(
                      '  ',
                    ).convert(widget.json),
                  ),
                ),
              ),
            ],
          ),
        ),
        Container(
          height: widget.height,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLowest,
            border: Border.all(color: scheme.outline),
            borderRadius: BorderRadius.circular(6),
          ),
          clipBehavior: Clip.antiAlias,
          child: LayoutBuilder(
            builder: (context, constraints) => Scrollbar(
              controller: _horizontal,
              child: SingleChildScrollView(
                controller: _horizontal,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: contentWidth > constraints.maxWidth
                      ? contentWidth
                      : constraints.maxWidth,
                  child: ListView.builder(
                    controller: _vertical,
                    itemExtent: _lineHeight,
                    itemCount: _layout.lines.length,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemBuilder: (context, i) {
                      final line = _layout.lines[i];
                      final tinted = _tinted[i];
                      return Container(
                        decoration: tinted
                            ? BoxDecoration(
                                color: scheme.primary.withValues(alpha: 0.08),
                                border: Border(
                                  left: BorderSide(
                                    color: scheme.primary.withValues(alpha: 0.5),
                                    width: 3,
                                  ),
                                ),
                              )
                            : null,
                        child: Row(
                          children: [
                            SizedBox(
                              width: _gutterWidth - (tinted ? 3 : 0),
                              child: Text(
                                numbers[i],
                                textAlign: TextAlign.right,
                                style: _style.copyWith(
                                  color: scheme.outlineVariant,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text.rich(
                              TextSpan(
                                children: [
                                  for (final (kind, text) in tokenizeLine(line))
                                    TextSpan(
                                      text: text,
                                      style: TextStyle(color: colors[kind]),
                                    ),
                                ],
                              ),
                              style: _style,
                              softWrap: false,
                            ),
                            if (_labels[i] case final label?) ...[
                              const SizedBox(width: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: scheme.primary.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  label,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: scheme.onPrimaryContainer,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
