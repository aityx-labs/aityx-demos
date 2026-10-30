import 'dart:convert';

import 'package:contacthub_app/main.dart';
import 'package:contacthub_app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// The app with its /api/aityx answering [answer] (or failing, when null).
Future<void> pumpWith(WidgetTester tester, Map<String, Object?>? answer) {
  final client = MockClient((request) async {
    expect(request.url.path, '/api/aityx');
    if (answer == null) throw http.ClientException('down');
    return http.Response(jsonEncode(answer), 200);
  });
  return tester.pumpWidget(ContactHubApp(aityxClient: client));
}

Color dotColor(WidgetTester tester) {
  final dot = tester.widget<Container>(
    find.byKey(const ValueKey('aityx-status-dot')),
  );
  return (dot.decoration! as BoxDecoration).color!;
}

String tooltip(WidgetTester tester) => tester
    .widget<Tooltip>(
      find.ancestor(
        of: find.byKey(const ValueKey('aityx-status-dot')),
        matching: find.byType(Tooltip),
      ),
    )
    .message!;

void main() {
  testWidgets('grey while checking, then green when aityx accepts the key', (
    tester,
  ) async {
    await pumpWith(tester, {
      'key': true,
      'ok': true,
      'url': 'https://api.aityx.ai',
      'detail': 'aityx accepts the key',
    });
    expect(dotColor(tester), Aityx.muted);

    await tester.pump();
    expect(dotColor(tester), Aityx.green);
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
    await pumpWith(tester, {
      'key': false,
      'ok': false,
      'detail': 'AITYX_API_KEY is not set',
    });
    await tester.pump();
    expect(dotColor(tester), Aityx.red);
    expect(tooltip(tester), 'aityx: no key — AITYX_API_KEY is not set');
  });

  testWidgets('red with why, when aityx does not accept the key', (
    tester,
  ) async {
    await pumpWith(tester, {
      'key': true,
      'ok': false,
      'url': 'https://api.aityx.ai',
      'detail': 'aityx answered HTTP 401',
    });
    await tester.pump();
    expect(dotColor(tester), Aityx.red);
    expect(tooltip(tester), 'aityx: not working — aityx answered HTTP 401');
  });

  testWidgets('red when the API does not answer', (tester) async {
    await pumpWith(tester, null);
    await tester.pump();
    expect(dotColor(tester), Aityx.red);
    expect(tooltip(tester), 'aityx: the API did not answer');
  });

  testWidgets('sits at the top right, on the welcome screen', (tester) async {
    await pumpWith(tester, {'key': false, 'ok': false});
    await tester.pump();
    final dot = tester.getRect(find.byKey(const ValueKey('aityx-status-dot')));
    final screen = tester.getRect(find.byType(WelcomeScreen));
    expect(dot.top, closeTo(screen.top + 6, 0.5));
    expect(dot.right, closeTo(screen.right - 6, 0.5));
    expect(dot.width, 8);
  });
}
