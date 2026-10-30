import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mortgagehub_app/aityx_status.dart';
import 'package:mortgagehub_app/theme.dart';

/// The light over a blank screen, its API answering [answer] (or failing).
Future<void> pumpLight(
  WidgetTester tester,
  Future<http.Response> Function(http.Request) answer,
) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) =>
          WithAityxStatus(client: MockClient(answer), child: child),
      home: const Scaffold(),
    ),
  );
  await tester.pump();
}

Color dotColor(WidgetTester tester) {
  final box = tester.widget<Container>(
    find.descendant(
      of: find.byType(AityxStatus),
      matching: find.byType(Container),
    ),
  );
  return (box.decoration! as BoxDecoration).color!;
}

String tip(WidgetTester tester) =>
    tester.widget<Tooltip>(find.byType(Tooltip)).message!;

http.Response json(Object body) => http.Response(jsonEncode(body), 200);

void main() {
  testWidgets('green when aityx accepts the key', (tester) async {
    await pumpLight(
      tester,
      (call) async => json({
        'key': true,
        'ok': true,
        'url': 'https://api.aityx.ai',
        'detail': 'aityx accepts the key',
      }),
    );
    expect(dotColor(tester), Aityx.green.withValues(alpha: 0.8));
    expect(
      tip(tester),
      'aityx: ready — accepts the key (https://api.aityx.ai)',
    );
  });

  testWidgets('red without a key', (tester) async {
    await pumpLight(
      tester,
      (call) async => json({
        'key': false,
        'ok': false,
        'detail': 'AITYX_API_KEY is not set',
      }),
    );
    expect(dotColor(tester), Aityx.red.withValues(alpha: 0.8));
    expect(tip(tester), 'aityx: no key — AITYX_API_KEY is not set');
  });

  testWidgets('red, with why, when aityx refuses', (tester) async {
    await pumpLight(
      tester,
      (call) async =>
          json({'key': true, 'ok': false, 'detail': 'aityx answered HTTP 401'}),
    );
    expect(dotColor(tester), Aityx.red.withValues(alpha: 0.8));
    expect(tip(tester), 'aityx: not working — aityx answered HTTP 401');
  });

  testWidgets('red when the API does not answer', (tester) async {
    await pumpLight(tester, (call) async => http.Response('', 502));
    expect(tip(tester), 'aityx: the API did not answer');
  });

  testWidgets('grey while checking, and asks /api/aityx', (tester) async {
    Uri? asked;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => WithAityxStatus(
          client: MockClient((call) async {
            asked = call.url;
            return json({'key': true, 'ok': true, 'url': 'x'});
          }),
          child: child,
        ),
        home: const Scaffold(),
      ),
    );
    expect(dotColor(tester), Aityx.dim.withValues(alpha: 0.8));
    expect(tip(tester), 'aityx: checking');
    await tester.pump();
    expect(asked?.path, '/api/aityx');
  });
}
