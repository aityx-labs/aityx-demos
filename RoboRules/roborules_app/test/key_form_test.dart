import 'package:aityx_web/aityx_web.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roborules_app/battle/controller.dart';
import 'package:roborules_app/main.dart';

Future<void> pumpApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final controller = BattleController()..randomRobots(3);
  addTearDown(controller.dispose);
  await tester.pumpWidget(RoboRulesApp(controller: controller));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('without an aityx key, asks for it above the controls', (
    tester,
  ) async {
    await pumpApp(tester);

    expect(find.byKey(const ValueKey('aityx-key-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('aityx-url-field')), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);
    expect(find.text('Get a key in the aityx console'), findsOneWidget);
    expect(
      tester.getBottomLeft(find.byType(AityxKeyPrompt)).dy,
      lessThanOrEqualTo(tester.getTopLeft(find.text('Next turn')).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('with an aityx key, shows no key form at all', (tester) async {
    AityxSettings.store = AityxKeyStore.memory(local: {'aityx.key': 'k'});
    addTearDown(() => AityxSettings.store = AityxKeyStore.memory());
    await pumpApp(tester);

    expect(find.byKey(const ValueKey('aityx-key-field')), findsNothing);
    expect(find.text('Get a key in the aityx console'), findsNothing);
    expect(tester.getSize(find.byType(AityxKeyPrompt)).height, 0);
  });
}
