import 'package:flutter/material.dart';

import '../care_centers/care_center_screen.dart' show CareCenterOpener;
import '../people/person_screen.dart' show PersonOpener;
import '../theme.dart';

/// Text that opens something on a tap: in its usual style, underlined on
/// hover, with a hand cursor. The person and care center links.
class LinkText extends StatefulWidget {
  const LinkText(this.text, {super.key, required this.onTap, this.style, this.overflow});

  final String text;
  final VoidCallback onTap;
  final TextStyle? style;
  final TextOverflow? overflow;

  @override
  State<LinkText> createState() => _LinkTextState();
}

class _LinkTextState extends State<LinkText> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final style = (widget.style ?? const TextStyle()).copyWith(
      decoration: _hover ? TextDecoration.underline : TextDecoration.none,
      decorationColor: Aityx.orangeLight,
    );
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Text(widget.text, style: style, overflow: widget.overflow),
      ),
    );
  }
}

/// [child] under the openers that [from] is under: a page pushed or a
/// dialog shown from home sits on the app's navigator, above home, so it
/// needs them given again for its own people and care centers to be links.
Widget withOpeners(BuildContext from, Widget child) {
  final person = PersonOpener.of(from);
  final careCenter = CareCenterOpener.of(from);
  var wrapped = child;
  if (careCenter != null) {
    wrapped = CareCenterOpener(
      load: careCenter.load,
      occupancy: careCenter.occupancy,
      forecast: careCenter.forecast,
      showTiles: careCenter.showTiles,
      child: wrapped,
    );
  }
  if (person != null) {
    wrapped = PersonOpener(person: person.person, prediction: person.prediction, child: wrapped);
  }
  return wrapped;
}
