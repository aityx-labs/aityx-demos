import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cellfie_app/aityx_status.dart';

Color dotColor(WidgetTester tester) {
  final dot = tester.widget<Container>(
    find.byKey(const ValueKey('aityx-status-dot')),
  );
  return (dot.decoration! as BoxDecoration).color!;
}

String tooltip(WidgetTester tester) =>
    tester.widget<Tooltip>(find.byType(Tooltip)).message!;

Future<void> pumpStatus(WidgetTester tester, AityxChecker check) async {
  await tester.pumpWidget(
    MaterialApp(
      home: const Scaffold(body: Text('screen')),
      builder: (context, child) =>
          WithAityxStatus(check: check, child: child!),
    ),
  );
}

AityxChecker answering(int status, Object body) => apiAityxChecker(
  baseUrl: 'http://api.test',
  client: MockClient(
    (request) async {
      expect(request.url.toString(), 'http://api.test/api/aityx');
      return http.Response(jsonEncode(body), status);
    },
  ),
);

void main() {
  testWidgets('grey while checking, over the screen', (tester) async {
    final waiting = Completer<AityxState>();
    await pumpStatus(tester, () => waiting.future);
    expect(find.text('screen'), findsOneWidget);
    expect(dotColor(tester), Colors.grey);
    expect(tooltip(tester), 'aityx: checking…');
    waiting.complete(const AityxState.unreachable());
  });

  testWidgets('green when aityx accepts the key', (tester) async {
    await pumpStatus(
      tester,
      answering(200, {
        'key': true,
        'ok': true,
        'url': 'https://api.aityx.ai',
        'detail': 'aityx accepts the key',
      }),
    );
    await tester.pump();
    expect(dotColor(tester), Colors.green);
    expect(
      tooltip(tester),
      'aityx: ready — accepts the key (https://api.aityx.ai)',
    );
    expect(
      find.bySemanticsLabel(
        'aityx: ready — accepts the key (https://api.aityx.ai)',
      ),
      findsOneWidget,
    );
  });

  testWidgets('red without a key', (tester) async {
    await pumpStatus(
      tester,
      answering(200, {
        'key': false,
        'ok': false,
        'detail': 'AITYX_API_KEY is not set',
      }),
    );
    await tester.pump();
    expect(dotColor(tester), Colors.red);
    expect(tooltip(tester), 'aityx: no key — AITYX_API_KEY is not set');
  });

  testWidgets('red, with why, when aityx refuses', (tester) async {
    await pumpStatus(
      tester,
      answering(200, {
        'key': true,
        'ok': false,
        'detail': 'aityx answered HTTP 401: invalid key',
      }),
    );
    await tester.pump();
    expect(dotColor(tester), Colors.red);
    expect(
      tooltip(tester),
      'aityx: not working — aityx answered HTTP 401: invalid key',
    );
  });

  testWidgets('red when the API does not answer', (tester) async {
    await pumpStatus(tester, answering(502, {'error': 'api unreachable'}));
    await tester.pump();
    expect(dotColor(tester), Colors.red);
    expect(tooltip(tester), 'aityx: the API did not answer');
  });

  testWidgets('checks again every minute', (tester) async {
    var calls = 0;
    await pumpStatus(tester, () async {
      calls++;
      return calls == 1
          ? const AityxState.unreachable()
          : const AityxState(ok: true, url: 'https://api.aityx.ai');
    });
    await tester.pump();
    expect(dotColor(tester), Colors.red);
    await tester.pump(const Duration(minutes: 1));
    await tester.pump();
    expect(calls, 2);
    expect(dotColor(tester), Colors.green);
  });
}
