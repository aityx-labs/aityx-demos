import 'package:aityx_web/aityx_web.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cellfie_app/main.dart';

import 'life_screen_test.dart' show FakeStepper;

String tooltip(WidgetTester tester) => tester
    .widget<Tooltip>(
      find.descendant(
        of: find.byType(AityxStatusLight),
        matching: find.byType(Tooltip),
      ),
    )
    .message!;

void main() {
  testWidgets('the light is over the app, red without a key', (tester) async {
    await tester.pumpWidget(
      CellfieApp(
        stepper: FakeStepper(),
        aityxLight: AityxStatusLight(check: () async => AityxState.noKey),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byType(AityxStatusLight), findsOneWidget);
    expect(find.text('Cellfie'), findsOneWidget);
    expect(tooltip(tester), 'aityx: no key — set yours on the index page');
  });

  testWidgets('green when aityx accepts the user\'s key', (tester) async {
    final aityx = MockClient((request) async {
      // The check: an empty request, which aityx refuses as invalid
      // only once it has accepted the key.
      expect(request.url.toString(), 'https://api.aityx.ai/v1/systemone');
      expect(request.body, '{}');
      return http.Response('{"code": "invalid_request"}', 400);
    });
    await tester.pumpWidget(
      CellfieApp(
        stepper: FakeStepper(),
        aityxLight: AityxStatusLight(
          client: aityx,
          store: AityxKeyStore.memory(local: {'aityx.key': 'test-key'}),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(tooltip(tester), 'aityx: ready — the key works with https://api.aityx.ai');
    expect(
      find.bySemanticsLabel('aityx: ready — the key works with https://api.aityx.ai'),
      findsOneWidget,
    );
  });
}
