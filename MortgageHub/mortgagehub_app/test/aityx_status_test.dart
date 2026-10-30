import 'package:aityx_web/aityx_web.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mortgagehub_app/main.dart';

/// The app with its status light on [store], aityx answering [answer].
Future<void> pumpApp(
  WidgetTester tester,
  AityxKeyStore store, [
  Future<http.Response> Function(http.Request)? answer,
]) async {
  await tester.pumpWidget(
    MortgageHubApp(
      aityxLight: AityxStatusLight(
        client: MockClient(answer ?? (_) async => http.Response('', 500)),
        store: store,
      ),
    ),
  );
  // The check, then the light's rebuild.
  await tester.pump();
  await tester.pump();
}

String tip(WidgetTester tester) => tester
    .widget<Tooltip>(
      find.descendant(
        of: find.byType(AityxStatusLight),
        matching: find.byType(Tooltip),
      ),
    )
    .message!;

void main() {
  testWidgets('red, saying where to set the key, without one', (tester) async {
    await pumpApp(tester, AityxKeyStore.memory());
    expect(find.byType(AityxStatusLight), findsOneWidget);
    expect(tip(tester), 'aityx: no key — set yours on the index page');
  });

  testWidgets('green when aityx accepts the user\'s key', (tester) async {
    Uri? asked;
    String? auth;
    await pumpApp(
      tester,
      AityxKeyStore.memory(local: {'aityx.key': 'test-key'}),
      (call) async {
        asked = call.url;
        auth = call.headers['Authorization'];
        return http.Response('{"code":"invalid_request"}', 400);
      },
    );
    expect(asked.toString(), 'https://api.aityx.ai/v1/systemone');
    expect(auth, 'Bearer test-key');
    expect(tip(tester), 'aityx: ready (your key, https://api.aityx.ai)');
  });

  testWidgets('red when aityx rejects the key', (tester) async {
    await pumpApp(
      tester,
      AityxKeyStore.memory(local: {'aityx.key': 'bad-key'}),
      (_) async => http.Response('{"detail":"invalid API key"}', 401),
    );
    expect(tip(tester), startsWith('aityx: key rejected'));
  });
}
