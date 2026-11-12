import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A panel on the right of the screen whose left edge is a handle: drag it
/// to widen or narrow the panel, double-click it to go back to
/// [defaultWidth], or focus it and use the arrow keys. The panel never
/// takes less than [minWidth], nor leaves less than [minRest] for what is
/// on its left.
class ResizableSidePanel extends StatefulWidget {
  const ResizableSidePanel({
    super.key,
    required this.child,
    required this.availableWidth,
    this.defaultWidth = 440,
    this.minWidth = 360,
    this.minRest = 320,
  });

  final Widget child;

  /// The width the panel and what is on its left share.
  final double availableWidth;
  final double defaultWidth;
  final double minWidth;
  final double minRest;

  /// How far an arrow key moves the edge.
  static const keyStep = 40.0;

  @override
  State<ResizableSidePanel> createState() => _ResizableSidePanelState();
}

class _ResizableSidePanelState extends State<ResizableSidePanel> {
  late double _width = widget.defaultWidth;
  bool _hovered = false;
  bool _dragging = false;
  bool _focused = false;

  /// Where a drag started, and the width then: the edge follows the
  /// pointer's position, not the sum of its moves, so it stays under the
  /// pointer however the moves arrive.
  double _dragStartX = 0;
  double _dragStartWidth = 0;

  double get _maxWidth =>
      math.max(widget.minWidth, widget.availableWidth - widget.minRest);

  double _clamp(double width) => width.clamp(widget.minWidth, _maxWidth);

  void _resizeTo(double width) => setState(() => _width = _clamp(width));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final width = _clamp(_width);
    final active = _hovered || _dragging || _focused;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          label: 'Resize the calls panel',
          hint: 'Drag, or use the left and right arrow keys',
          value: '${width.round()} pixels',
          child: FocusableActionDetector(
            mouseCursor: SystemMouseCursors.resizeColumn,
            onShowHoverHighlight: (on) => setState(() => _hovered = on),
            onShowFocusHighlight: (on) => setState(() => _focused = on),
            shortcuts: const {
              SingleActivator(LogicalKeyboardKey.arrowLeft): _WidenIntent(),
              SingleActivator(LogicalKeyboardKey.arrowRight): _NarrowIntent(),
            },
            actions: {
              _WidenIntent: CallbackAction<_WidenIntent>(
                onInvoke: (_) => _resizeTo(width + ResizableSidePanel.keyStep),
              ),
              _NarrowIntent: CallbackAction<_NarrowIntent>(
                onInvoke: (_) => _resizeTo(width - ResizableSidePanel.keyStep),
              ),
            },
            child: GestureDetector(
              key: const ValueKey('calls-panel-handle'),
              behavior: HitTestBehavior.opaque,
              dragStartBehavior: DragStartBehavior.down,
              onHorizontalDragStart: (details) => setState(() {
                _dragging = true;
                _dragStartX = details.globalPosition.dx;
                _dragStartWidth = width;
              }),
              onHorizontalDragUpdate: (details) => _resizeTo(
                _dragStartWidth + _dragStartX - details.globalPosition.dx,
              ),
              onHorizontalDragEnd: (_) => setState(() => _dragging = false),
              onHorizontalDragCancel: () => setState(() => _dragging = false),
              onDoubleTap: () => _resizeTo(widget.defaultWidth),
              child: SizedBox(
                width: 9,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // The divider, thicker and colored while it's in use.
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      width: active ? 3 : 1,
                      color: active ? scheme.primary : scheme.outlineVariant,
                    ),
                    // The grip, so the edge reads as something to drag.
                    Container(
                      width: 7,
                      height: 36,
                      decoration: BoxDecoration(
                        color: active
                            ? scheme.primary
                            : scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: active ? scheme.primary : scheme.outline,
                        ),
                      ),
                      child: Icon(
                        Icons.more_vert,
                        size: 7,
                        color: active ? scheme.onPrimary : scheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        SizedBox(width: width, child: widget.child),
      ],
    );
  }
}

class _WidenIntent extends Intent {
  const _WidenIntent();
}

class _NarrowIntent extends Intent {
  const _NarrowIntent();
}
