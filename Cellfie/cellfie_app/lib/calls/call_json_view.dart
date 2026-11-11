import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'json_layout.dart';

/// A key part of one side of a call: exactly the value at [path]
/// (`state.situations`, `answers.fates`...), tinted with its [label], and
/// explained by [why] when jumped to.
class JsonAnchor {
  const JsonAnchor(this.path, this.label, this.why);

  final String path;
  final String label;
  final String why;
}

/// One side of an aityx call, pretty-printed with line numbers and colors
/// in a pane of its own, with a button that copies the exact JSON. The
/// [anchors] present in the JSON are tinted and labeled on their first
/// row; the "Jump to" chips above the pane, and the labels themselves,
/// scroll the pane to exactly that value, mark all of it and say what it
/// is.
class CallJsonView extends StatefulWidget {
  const CallJsonView({
    super.key,
    required this.title,
    required this.json,
    this.subtitle = '',
    this.anchors = const [],
    this.height = 320,
  });

  /// `REQUEST` or `RESPONSE`.
  final String title;
  final String subtitle;
  final Object? json;
  final List<JsonAnchor> anchors;
  final double height;

  @override
  State<CallJsonView> createState() => _CallJsonViewState();
}

/// Each row's height: fixed, so a row's offset is exactly
/// `_topPadding + index * _lineHeight` and a jump lands on it.
const _lineHeight = 22.0;
const _topPadding = 4.0;
const _fontSize = 14.0;
const _gutterWidth = 44.0;

const _style = TextStyle(
  fontFamily: 'RobotoMono',
  fontSize: _fontSize,
  height: 1.2,
);

class _CallJsonViewState extends State<CallJsonView> {
  late JsonLayout _layout;

  /// The anchors this JSON has, and the one last jumped to.
  late List<JsonAnchor> _anchors;
  JsonAnchor? _active;

  /// For each row, the anchor starting there, if any, and whether it's
  /// inside one.
  late List<JsonAnchor?> _starts;
  late List<bool> _tinted;
  final _vertical = ScrollController();
  final _horizontal = ScrollController();
  final _paneKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _lay();
  }

  @override
  void didUpdateWidget(CallJsonView old) {
    super.didUpdateWidget(old);
    if (old.json != widget.json || old.anchors != widget.anchors) _lay();
  }

  @override
  void dispose() {
    _vertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  void _lay() {
    _layout = layoutJson(widget.json);
    _anchors = [
      for (final a in widget.anchors)
        if (_layout.ranges.containsKey(a.path)) a,
    ];
    if (_active case final active? when !_anchors.contains(active)) {
      _active = null;
    }
    _starts = List.filled(_layout.lines.length, null);
    _tinted = List.filled(_layout.lines.length, false);
    for (final anchor in _anchors) {
      final range = _layout.ranges[anchor.path]!;
      _starts[range.first] = anchor;
      for (var i = range.first; i <= range.last; i++) {
        _tinted[i] = true;
      }
    }
  }

  /// Marks [anchor], brings the pane into view in the panel, and scrolls
  /// the pane so the value's first row is at the top, under one row of
  /// context.
  void _jump(JsonAnchor anchor) {
    final range = _layout.ranges[anchor.path];
    if (range == null) return;
    setState(() => _active = anchor);
    final pane = _paneKey.currentContext;
    if (pane != null) {
      Scrollable.ensureVisible(
        pane,
        duration: const Duration(milliseconds: 200),
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    }
    if (!_vertical.hasClients) return;
    final offset = math.max(0.0, _topPadding + (range.first - 1) * _lineHeight);
    _vertical.animateTo(
      math.min(offset, _vertical.position.maxScrollExtent),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
    if (_horizontal.hasClients) _horizontal.jumpTo(0);
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
    final active = _active;
    final activeRange = active == null ? null : _layout.ranges[active.path];
    // Room for the longest line, and for the widest label after it.
    var labelWidth = 0.0;
    for (final anchor in _anchors) {
      final painter = TextPainter(
        text: TextSpan(text: anchor.label, style: _AnchorLabel.style),
        textDirection: TextDirection.ltr,
      )..layout();
      if (painter.width > labelWidth) labelWidth = painter.width;
    }
    final contentWidth =
        _gutterWidth +
        16 +
        _layout.longestLine * _charWidth() +
        labelWidth +
        56;
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
                    text: const JsonEncoder.withIndent('  ')
                        .convert(widget.json),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_anchors.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 0, 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Jump to',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                for (final anchor in _anchors)
                  ChoiceChip(
                    label: Text(anchor.label),
                    tooltip: anchor.why,
                    selected: identical(anchor, active),
                    showCheckmark: false,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    labelStyle: theme.textTheme.labelSmall,
                    labelPadding: const EdgeInsets.only(left: 2, right: 4),
                    avatar: Icon(
                      Icons.my_location,
                      size: 14,
                      color: identical(anchor, active)
                          ? scheme.onPrimaryContainer
                          : scheme.primary,
                    ),
                    onSelected: (_) => _jump(anchor),
                  ),
              ],
            ),
          ),
        // What the marked part is, in words, above the code.
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: active == null
              ? const SizedBox(width: double.infinity)
              : Container(
                  key: ValueKey(active.path),
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(6),
                    border: Border(
                      left: BorderSide(color: scheme.primary, width: 3),
                    ),
                  ),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${active.label}  ',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        TextSpan(
                          text:
                              '${active.path}, line '
                              '${numbers.take(activeRange!.first + 1).where((s) => s.isNotEmpty).length}',
                          style: TextStyle(
                            fontFamily: 'RobotoMono',
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        TextSpan(text: '\n${active.why}'),
                      ],
                    ),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
        ),
        Container(
          key: _paneKey,
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
                  width: math.max(contentWidth, constraints.maxWidth),
                  child: ListView.builder(
                    controller: _vertical,
                    itemExtent: _lineHeight,
                    itemCount: _layout.lines.length,
                    // Room below the last row, so a value near the end can
                    // still scroll to the top like any other.
                    padding: EdgeInsets.only(
                      top: _topPadding,
                      bottom: math.max(
                        _topPadding,
                        constraints.maxHeight - 3 * _lineHeight,
                      ),
                    ),
                    itemBuilder: (context, i) {
                      final line = _layout.lines[i];
                      final marked =
                          activeRange != null &&
                          i >= activeRange.first &&
                          i <= activeRange.last;
                      final tinted = marked || _tinted[i];
                      return Container(
                        decoration: tinted
                            ? BoxDecoration(
                                color: scheme.primary.withValues(
                                  alpha: marked ? 0.18 : 0.08,
                                ),
                                border: Border(
                                  left: BorderSide(
                                    color: marked
                                        ? scheme.primary
                                        : scheme.primary.withValues(alpha: 0.5),
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
                                  color: marked
                                      ? scheme.primary
                                      : scheme.outlineVariant,
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
                            if (_starts[i] case final anchor?) ...[
                              const SizedBox(width: 12),
                              _AnchorLabel(
                                anchor,
                                active: identical(anchor, active),
                                onTap: () => _jump(anchor),
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

/// A key part's label at the end of its first row: tap it to mark the
/// value and read what it is.
class _AnchorLabel extends StatelessWidget {
  const _AnchorLabel(this.anchor, {required this.active, required this.onTap});

  static const style = TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600);

  final JsonAnchor anchor;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: anchor.why,
      waitDuration: const Duration(milliseconds: 300),
      constraints: const BoxConstraints(maxWidth: 360),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          decoration: BoxDecoration(
            color: active ? scheme.primary : scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: scheme.primary.withValues(alpha: 0.6)),
          ),
          child: Text(
            anchor.label,
            style: style.copyWith(
              color: active ? scheme.onPrimary : scheme.onPrimaryContainer,
            ),
          ),
        ),
      ),
    );
  }
}
