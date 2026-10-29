import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'json_layout.dart';

/// Which half of the aityx call.
enum CallSide {
  request('Request', 'What the API sent to aityx'),
  response('Response', "aityx's answer");

  const CallSide(this.label, this.description);

  final String label;
  final String description;
}

/// A key part of the call: exactly the value at [path] on [side], always
/// highlighted with its [label], and explained by [why] when jumped to.
class JsonTarget {
  const JsonTarget(this.side, this.path, this.label, this.why);

  final CallSide side;
  final String path;
  final String label;
  final String why;

  /// The same part of the call: the page rebuilds its targets, so they are
  /// compared by where they point, not by identity.
  bool sameAs(JsonTarget? other) =>
      other != null && other.side == side && other.path == path;
}

/// Lets the page around an [AityxCallView] show a part of the call: the
/// view scrolls [path]'s first line on [side] to the top and marks the
/// whole value.
class AityxCallController extends ChangeNotifier {
  CallSide side = CallSide.request;
  String? path;

  void reveal(CallSide side, String path) {
    this.side = side;
    this.path = path;
    notifyListeners();
  }
}

/// The aityx call behind a routing, in one pane: the request, then the
/// response, each under its header, pretty-printed with line numbers and
/// colors. Every one of [targets] is highlighted with its label, as Mortgage
/// Hub's view does; the "Jump to" bar and the page's links scroll to exactly
/// one and mark it. [response] is what the pane shows of aityx's answer;
/// [fullResponse], when given, is what "Copy full response" copies.
class AityxCallView extends StatefulWidget {
  const AityxCallView({
    super.key,
    required this.request,
    required this.response,
    required this.targets,
    this.fullResponse,
    this.responseSubtitle = '',
    this.controller,
    this.height = 600,
    this.fullScreen = false,
    this.initialOffset = 0,
    this.initialMark,
  });

  final Object? request;
  final Object? response;
  final Object? fullResponse;
  final String responseSubtitle;
  final List<JsonTarget> targets;
  final AityxCallController? controller;

  /// The pane's height; ignored in [fullScreen], which fills.
  final double height;
  final bool fullScreen;

  /// Where the pane starts scrolled, and the part it starts with marked:
  /// full screen opens where the page's view was.
  final double initialOffset;
  final JsonTarget? initialMark;

  @override
  State<AityxCallView> createState() => _AityxCallViewState();
}

/// Each row's height: fixed, so a row's offset is exactly
/// `8 + index * _lineHeight` and a jump lands on it.
const _lineHeight = 22.0;
const _fontSize = 14.0;
const _gutterWidth = 52.0;

/// Values printed on more rows than this are highlighted on their first
/// row only, so a large one doesn't tint the whole pane.
const _maxHighlightRows = 12;

String _sideName(CallSide side) =>
    side == CallSide.request ? 'request' : 'response';

class _AityxCallViewState extends State<AityxCallView> {
  late final AityxCallController _controller =
      widget.controller ?? AityxCallController();
  late final _vertical = ScrollController(
    initialScrollOffset: widget.initialOffset,
  );
  final _horizontal = ScrollController();
  final _paneKey = GlobalKey();
  late CallLayout _layout;

  /// The key parts present in this call, and the one last jumped to.
  late List<JsonTarget> _targets;
  late JsonTarget? _active = widget.initialMark;

  /// For each row, the innermost key part it's in, and whether it's that
  /// part's first row.
  late List<(JsonTarget, bool)?> _highlight;

  @override
  void initState() {
    super.initState();
    _build();
    _controller.addListener(_onReveal);
    if (_controller.path != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _onReveal());
    }
  }

  @override
  void didUpdateWidget(AityxCallView old) {
    super.didUpdateWidget(old);
    if (old.request != widget.request ||
        old.response != widget.response ||
        old.targets != widget.targets) {
      _build();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onReveal);
    if (widget.controller == null) _controller.dispose();
    _vertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  void _build() {
    _layout = layoutCall(
      widget.request,
      widget.response,
      requestTitle: 'REQUEST',
      requestSubtitle: 'POST /v1/systemone, as the API sent it',
      responseTitle: 'RESPONSE',
      responseSubtitle: widget.responseSubtitle,
    );
    _targets = [
      for (final t in widget.targets)
        if (_range(t) != null) t,
    ];
    // Keep the marked part, now as one of the rebuilt targets.
    if (_active case final active?) {
      _active = _targets.where(active.sameAs).firstOrNull ?? active;
    }
    // Outer parts first, so inner ones overwrite them: the innermost wins.
    final sorted = [..._targets]
      ..sort((a, b) {
        final ra = _range(a)!, rb = _range(b)!;
        return (rb.last - rb.first).compareTo(ra.last - ra.first);
      });
    _highlight = List.filled(_layout.rows.length, null);
    for (final t in sorted) {
      final r = _range(t)!;
      final last = r.last - r.first < _maxHighlightRows ? r.last : r.first;
      for (var i = r.first; i <= last; i++) {
        _highlight[i] = (t, i == r.first);
      }
    }
  }

  ({int first, int last})? _range(JsonTarget t) =>
      _layout.range(_sideName(t.side), t.path);

  /// The controller asked for a part: bring the pane into view on the page,
  /// then scroll to the part and mark it.
  void _onReveal() {
    final path = _controller.path;
    if (!mounted || path == null) return;
    final side = _controller.side;
    final found = _resolve(side, path);
    if (found == null) return;
    setState(() {
      _active =
          _targets
              .where((t) => t.side == side && t.path == found)
              .firstOrNull ??
          JsonTarget(side, found, found.split('.').last, '');
    });
    if (!widget.fullScreen) {
      final pane = _paneKey.currentContext;
      if (pane != null) {
        Scrollable.ensureVisible(
          pane,
          alignment: 0.02,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollTo(side, found));
  }

  /// [path] if the side shows it, else its nearest parent that it shows.
  String? _resolve(CallSide side, String path) {
    var p = path;
    while (_layout.range(_sideName(side), p) == null) {
      final dot = p.lastIndexOf('.');
      if (dot < 0) return null;
      p = p.substring(0, dot);
    }
    return p;
  }

  void _scrollTo(CallSide side, String path) {
    final range = _layout.range(_sideName(side), path);
    if (range == null || !_vertical.hasClients) return;
    // One row of context above the value's first row.
    final offset = math.max(0.0, 8 + (range.first - 1) * _lineHeight);
    _vertical.animateTo(
      math.min(offset, _vertical.position.maxScrollExtent),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
    if (_horizontal.hasClients) _horizontal.jumpTo(0);
  }

  void _jump(JsonTarget target) => _controller.reveal(target.side, target.path);

  Future<void> _openFullScreen() {
    final controller = AityxCallController();
    return showDialog<void>(
      context: context,
      builder: (context) => Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: const Text('The aityx call'),
            leading: IconButton(
              tooltip: 'Close',
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          body: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: AityxCallView(
              request: widget.request,
              response: widget.response,
              fullResponse: widget.fullResponse,
              responseSubtitle: widget.responseSubtitle,
              targets: widget.targets,
              controller: controller,
              fullScreen: true,
              initialOffset: _vertical.hasClients ? _vertical.offset : 0,
              initialMark: _active,
            ),
          ),
        ),
      ),
    ).whenComplete(controller.dispose);
  }

  void _copy(Object? json) => Clipboard.setData(
    ClipboardData(text: const JsonEncoder.withIndent('  ').convert(json)),
  );

  Object? _valueAt(CallSide side, String path) {
    Object? value = side == CallSide.request ? widget.request : widget.response;
    for (final segment in path.split('.')) {
      value = switch (value) {
        Map map => map[segment],
        List list => list[int.parse(segment)],
        _ => null,
      };
    }
    return value;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final active = _active;
    final activeRange = active == null ? null : _range(active);
    Widget chips(CallSide side) => Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final t in _targets)
          if (t.side == side)
            ChoiceChip(
              label: Text(t.label),
              tooltip: t.why,
              selected: t.sameAs(active),
              showCheckmark: false,
              avatar: Icon(
                Icons.my_location,
                size: 16,
                color: t.sameAs(active)
                    ? scheme.onPrimaryContainer
                    : scheme.primary,
              ),
              onSelected: (_) => _jump(t),
            ),
      ],
    );
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: theme.textTheme.labelLarge?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
    );

    final pane = Container(
      key: _paneKey,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: _CodePane(
        layout: _layout,
        vertical: _vertical,
        horizontal: _horizontal,
        highlight: _highlight,
        active: activeRange,
        activeTarget: active,
        onAnchor: _jump,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: widget.fullScreen ? MainAxisSize.max : MainAxisSize.min,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.end,
          children: [
            if (active != null && active.why.isNotEmpty)
              TextButton.icon(
                onPressed: () => _copy(_valueAt(active.side, active.path)),
                icon: const Icon(Icons.content_copy, size: 18),
                label: const Text('Copy section'),
              ),
            TextButton.icon(
              onPressed: () => _copy(widget.request),
              icon: const Icon(Icons.copy_all, size: 18),
              label: const Text('Copy request'),
            ),
            TextButton.icon(
              onPressed: () => _copy(widget.fullResponse ?? widget.response),
              icon: const Icon(Icons.copy_all, size: 18),
              label: Text(
                widget.fullResponse == null
                    ? 'Copy response'
                    : 'Copy full response',
              ),
            ),
            if (!widget.fullScreen)
              IconButton(
                tooltip: 'Full screen',
                onPressed: _openFullScreen,
                icon: const Icon(Icons.open_in_full),
              ),
          ],
        ),
        const SizedBox(height: 8),
        // The chips and the explanation; in full screen they get at most
        // 40% of the height, scrolling, so a short window keeps room for
        // the code.
        _Controls(
          limit: widget.fullScreen
              ? MediaQuery.sizeOf(context).height * 0.4
              : null,
          children: [
            if (_targets.any((t) => t.side == CallSide.request)) ...[
              heading('Jump to, in the request'),
              chips(CallSide.request),
              const SizedBox(height: 10),
            ],
            if (_targets.any((t) => t.side == CallSide.response)) ...[
              heading('In the response'),
              chips(CallSide.response),
              const SizedBox(height: 10),
            ],
            // What the marked part is, in words, above the code.
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: active == null || active.why.isEmpty
                  ? const SizedBox(width: double.infinity)
                  : Container(
                      key: ValueKey('${active.side}:${active.path}'),
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(8),
                        border: Border(
                          left: BorderSide(color: scheme.primary, width: 3),
                        ),
                      ),
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '${active.label}  ',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            TextSpan(
                              text:
                                  '${active.side.label.toLowerCase()} · '
                                  '${active.path}',
                              style: TextStyle(
                                fontFamily: 'RobotoMono',
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            TextSpan(text: '\n${active.why}'),
                          ],
                        ),
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
            ),
          ],
        ),
        if (widget.fullScreen)
          Expanded(child: pane)
        else
          SizedBox(height: widget.height, child: pane),
      ],
    );
  }
}

/// The view's controls, in a column; with a [limit], at most that high and
/// scrolling.
class _Controls extends StatelessWidget {
  const _Controls({required this.limit, required this.children});

  final double? limit;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
    final limit = this.limit;
    if (limit == null) return column;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: limit),
      child: SingleChildScrollView(child: column),
    );
  }
}

/// The code: one fixed-height row per line, numbered per section and
/// colored; key parts tinted with their label on their first row, the
/// active one marked strongly.
class _CodePane extends StatelessWidget {
  const _CodePane({
    required this.layout,
    required this.vertical,
    required this.horizontal,
    required this.highlight,
    required this.active,
    required this.activeTarget,
    required this.onAnchor,
  });

  final CallLayout layout;
  final ScrollController vertical;
  final ScrollController horizontal;
  final List<(JsonTarget, bool)?> highlight;
  final ({int first, int last})? active;
  final JsonTarget? activeTarget;
  final ValueChanged<JsonTarget> onAnchor;

  static const _style = TextStyle(
    fontFamily: 'RobotoMono',
    fontSize: _fontSize,
    height: 1.2,
  );

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
    final contentWidth =
        _gutterWidth + 24 + layout.longestLine * _charWidth() + 240;
    // Line numbers count within each section, from 1.
    final numbers = <int>[];
    var n = 0;
    for (final row in layout.rows) {
      n = row.line == null ? 0 : n + 1;
      numbers.add(n);
    }
    return LayoutBuilder(
      builder: (context, constraints) => Scrollbar(
        controller: horizontal,
        child: SingleChildScrollView(
          controller: horizontal,
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: math.max(constraints.maxWidth, contentWidth),
            height: constraints.maxHeight,
            child: Scrollbar(
              controller: vertical,
              child: ListView.builder(
                controller: vertical,
                // Room below the last row, so a value near the end can
                // still scroll to the top like any other.
                padding: EdgeInsets.only(
                  top: 8,
                  bottom: math.max(8, constraints.maxHeight - 3 * _lineHeight),
                ),
                itemExtent: _lineHeight,
                itemCount: layout.rows.length,
                itemBuilder: (context, i) {
                  final row = layout.rows[i];
                  if (row.line == null) {
                    if (row.title == null) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: Row(
                        children: [
                          Icon(
                            row.side == 'request'
                                ? Icons.north_east
                                : Icons.south_west,
                            size: 14,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            row.title!,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: scheme.primary,
                              letterSpacing: 1.2,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            row.subtitle!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  final marked =
                      active != null && i >= active!.first && i <= active!.last;
                  final key = highlight[i];
                  final tinted = marked || key != null;
                  final accent = marked
                      ? scheme.primary
                      : scheme.primary.withValues(alpha: 0.45);
                  return Container(
                    decoration: tinted
                        ? BoxDecoration(
                            color: scheme.primary.withValues(
                              alpha: marked ? 0.18 : 0.06,
                            ),
                            border: Border(
                              left: BorderSide(color: accent, width: 3),
                            ),
                          )
                        : null,
                    child: Row(
                      children: [
                        SizedBox(
                          width: _gutterWidth - (tinted ? 3 : 0),
                          child: Text(
                            '${numbers[i]}',
                            textAlign: TextAlign.right,
                            style: _style.copyWith(
                              color: marked
                                  ? scheme.primary
                                  : scheme.outlineVariant,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Text.rich(
                          TextSpan(
                            children: [
                              for (final (kind, text) in tokenize(
                                row.line!.text,
                              ))
                                TextSpan(
                                  text: text,
                                  style: TextStyle(color: colors[kind]),
                                ),
                            ],
                          ),
                          style: _style,
                          softWrap: false,
                        ),
                        if (key case (final target, true)) ...[
                          const SizedBox(width: 12),
                          _AnchorLabel(
                            target,
                            active: target.sameAs(activeTarget),
                            onTap: () => onAnchor(target),
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
    );
  }
}

/// A key part's label at the end of its first row: tap it to mark the
/// value and read why it matters.
class _AnchorLabel extends StatelessWidget {
  const _AnchorLabel(this.target, {required this.active, required this.onTap});

  final JsonTarget target;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: target.why,
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
            target.label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: active ? scheme.onPrimary : scheme.onPrimaryContainer,
            ),
          ),
        ),
      ),
    );
  }
}
