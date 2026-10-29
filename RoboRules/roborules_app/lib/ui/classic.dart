import 'package:flutter/material.dart';

/// The look of a Java Swing app of Robocode's day: light gray panels,
/// beveled buttons, a blue title bar and selection.
abstract final class Classic {
  static const panel = Color(0xFFD6D3CE);
  static const panelLight = Color(0xFFECE9E4);
  static const shadow = Color(0xFF808080);
  static const darkShadow = Color(0xFF404040);
  static const highlight = Color(0xFFFFFFFF);
  static const text = Color(0xFF111111);
  static const selection = Color(0xFF316AC5);
  static const titleStart = Color(0xFF0A246A);
  static const titleEnd = Color(0xFFA6CAF0);
}

ThemeData classicTheme() {
  const scheme = ColorScheme.light(
    primary: Classic.selection,
    onPrimary: Colors.white,
    surface: Classic.panel,
    onSurface: Classic.text,
    secondary: Classic.selection,
  );
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: Classic.panel,
    visualDensity: VisualDensity.compact,
    textTheme: Typography.blackMountainView.apply(
      bodyColor: Classic.text,
      displayColor: Classic.text,
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: Classic.panel,
      shape: RoundedRectangleBorder(),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: Classic.selection,
      thumbColor: Classic.panelLight,
      trackHeight: 3,
    ),
    tooltipTheme: const TooltipThemeData(
      decoration: BoxDecoration(
        color: Color(0xFFFFFFE1),
        border: Border.fromBorderSide(BorderSide(color: Classic.darkShadow)),
      ),
      textStyle: TextStyle(color: Classic.text, fontSize: 12),
    ),
  );
}

/// A raised (or, [pressed], sunken) 3D border, as Swing drew buttons and
/// panels.
class Bevel extends StatelessWidget {
  const Bevel({
    super.key,
    required this.child,
    this.pressed = false,
    this.color = Classic.panel,
    this.padding = const EdgeInsets.all(2),
  });

  final Widget child;
  final bool pressed;
  final Color color;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final light = pressed ? Classic.darkShadow : Classic.highlight;
    final dark = pressed ? Classic.highlight : Classic.darkShadow;
    return Container(
      decoration: BoxDecoration(
        color: color,
        border: Border(
          top: BorderSide(color: light),
          left: BorderSide(color: light),
          bottom: BorderSide(color: dark),
          right: BorderSide(color: dark),
        ),
      ),
      padding: padding,
      child: child,
    );
  }
}

/// A Swing-style push button.
class ClassicButton extends StatefulWidget {
  const ClassicButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.tooltip,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  State<ClassicButton> createState() => _ClassicButtonState();
}

class _ClassicButtonState extends State<ClassicButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final color = enabled ? Classic.text : Classic.shadow;
    final button = GestureDetector(
      onTapDown: enabled ? (_) => setState(() => _down = true) : null,
      onTapUp: enabled
          ? (_) {
              setState(() => _down = false);
              widget.onPressed!();
            }
          : null,
      onTapCancel: () => setState(() => _down = false),
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        child: Bevel(
          pressed: _down,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 15, color: color),
                const SizedBox(width: 5),
              ],
              Text(widget.label, style: TextStyle(fontSize: 13, color: color)),
            ],
          ),
        ),
      ),
    );
    return widget.tooltip == null
        ? button
        : Tooltip(message: widget.tooltip!, child: button);
  }
}

/// The window's title bar: a blue gradient with the title, as an old
/// desktop app had.
class TitleBar extends StatelessWidget {
  const TitleBar(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Classic.titleStart, Classic.titleEnd],
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.smart_toy, size: 16, color: Colors.white),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A dialog in the classic style: a title bar, a gray body, buttons below.
class ClassicDialog extends StatelessWidget {
  const ClassicDialog({
    super.key,
    required this.title,
    required this.child,
    required this.actions,
    this.width = 560,
  });

  final String title;
  final Widget child;
  final List<Widget> actions;
  final double width;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: Bevel(
        padding: EdgeInsets.zero,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: width,
            maxHeight: size.height - 32,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TitleBar(title),
              Flexible(
                child: Padding(padding: const EdgeInsets.all(12), child: child),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: actions,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
