/// The way back from a demo to the index page, "aityx demos".
library;

import 'package:flutter/material.dart';

import 'key_page.dart' show aityxEmbedded;
import 'paths.dart';
import 'platform/platform_vm.dart'
    if (dart.library.js_interop) 'platform/platform_web.dart'
    as platform;

/// What the link says: the index page's title.
const aityxDemosLabel = 'aityx demos';

/// The index page: `/demos/` on [origin] (the page's, Uri.base, unless
/// given), whatever the app's base href. On the aityx website that is
/// https://aityx.ai/demos/.
Uri aityxDemosPage({Uri? origin}) =>
    (origin ?? Uri.base).resolve(aityxDemosPath);

/// Opens [aityxDemosPage] in the same tab. Does nothing embedded (the user
/// stays on the page around the app) and off the web.
void openAityxDemosPage({Uri? origin}) {
  if (aityxEmbedded) return;
  platform.openPage(aityxDemosPage(origin: origin));
}

/// A small link back to the index page: a left arrow and "aityx demos", in
/// the muted colour of the app's secondary text, the primary colour and
/// underlined under the pointer. A tap opens the index page in the same
/// tab. Embedded, it takes no room: the app keeps the user where they are.
class AityxDemosLink extends StatefulWidget {
  const AityxDemosLink({
    super.key,
    this.style,
    this.hoverColor,
    this.origin,
    this.onTap,
    this.embedded,
  });

  /// The text's style: the theme's bodySmall in onSurfaceVariant unless
  /// given. The arrow takes its colour and its size.
  final TextStyle? style;

  /// The colour under the pointer: the theme's primary unless given.
  final Color? hoverColor;

  /// The page's origin: Uri.base unless given.
  final Uri? origin;

  /// On tap: opens the index page unless given.
  final VoidCallback? onTap;

  /// Whether the app is inside another page: [aityxEmbedded] unless a test
  /// says.
  final bool? embedded;

  @override
  State<AityxDemosLink> createState() => _AityxDemosLinkState();
}

class _AityxDemosLinkState extends State<AityxDemosLink> {
  bool _hover = false;

  void _open() {
    final onTap = widget.onTap;
    if (onTap != null) {
      onTap();
    } else {
      openAityxDemosPage(origin: widget.origin);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded ?? aityxEmbedded) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final base =
        widget.style ??
        theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ) ??
        const TextStyle(fontSize: 12);
    final color = _hover
        ? widget.hoverColor ?? theme.colorScheme.primary
        : base.color;
    final style = base.copyWith(
      color: color,
      decoration: _hover ? TextDecoration.underline : TextDecoration.none,
      decorationColor: color,
    );
    return Semantics(
      container: true,
      link: true,
      label: aityxDemosLabel,
      onTap: _open,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _open,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.arrow_back,
                size: (style.fontSize ?? 12) + 1,
                color: color,
              ),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  aityxDemosLabel,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.fade,
                  style: style,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
