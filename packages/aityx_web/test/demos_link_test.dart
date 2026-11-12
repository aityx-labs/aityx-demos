import 'package:aityx_web/aityx_web.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpLink(WidgetTester tester, Widget link) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(body: Center(child: link)),
  ),
);

TextStyle labelStyle(WidgetTester tester) =>
    tester.widget<Text>(find.text(aityxDemosLabel)).style!;

void main() {
  test('the index page is /demos/ on the origin, whatever the app\'s path', () {
    expect(
      aityxDemosPage(origin: Uri.parse('https://aityx.ai/demos/cellfie/')),
      Uri.parse('https://aityx.ai/demos/'),
    );
    expect(
      aityxDemosPage(
        origin: Uri.parse('http://localhost:8800/demos/pokerface/?x=1#/table'),
      ),
      Uri.parse('http://localhost:8800/demos/'),
    );
  });

  testWidgets('says "aityx demos", as a link, and a tap opens the index', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var taps = 0;
    await pumpLink(tester, AityxDemosLink(onTap: () => taps++));

    expect(find.text('aityx demos'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    expect(
      tester.getSemantics(find.byType(AityxDemosLink)),
      isSemantics(label: 'aityx demos', isLink: true, hasTapAction: true),
    );

    await tester.tap(find.byType(AityxDemosLink));
    expect(taps, 1);
    semantics.dispose();
  });

  testWidgets('muted until the pointer is over it, then primary, underlined', (
    tester,
  ) async {
    await pumpLink(tester, AityxDemosLink(onTap: () {}));
    final scheme = Theme.of(tester.element(find.byType(AityxDemosLink)))
        .colorScheme;
    expect(labelStyle(tester).color, scheme.onSurfaceVariant);
    expect(labelStyle(tester).decoration, TextDecoration.none);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byType(AityxDemosLink)));
    await tester.pump();
    expect(labelStyle(tester).color, scheme.primary);
    expect(labelStyle(tester).decoration, TextDecoration.underline);
  });

  testWidgets('takes its style and its hover colour when given', (
    tester,
  ) async {
    const style = TextStyle(fontSize: 13, color: Color(0xFF111111));
    await pumpLink(
      tester,
      AityxDemosLink(
        style: style,
        hoverColor: const Color(0xFF316AC5),
        onTap: () {},
      ),
    );
    expect(labelStyle(tester).fontSize, 13);
    expect(labelStyle(tester).color, const Color(0xFF111111));
    expect(tester.widget<Icon>(find.byIcon(Icons.arrow_back)).size, 14);
  });

  testWidgets('embedded, it shows nothing and takes no room', (tester) async {
    await pumpLink(tester, AityxDemosLink(embedded: true, onTap: () {}));
    expect(find.text('aityx demos'), findsNothing);
    expect(tester.getSize(find.byType(AityxDemosLink)), Size.zero);
  });
}
