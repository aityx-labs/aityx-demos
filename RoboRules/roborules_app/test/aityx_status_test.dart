import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:roborules_app/aityx/aityx_status.dart';

void main() {
  /// The light over a blank screen, its API answering through [client].
  Future<void> show(WidgetTester tester, http.Client client) async {
    await tester.pumpWidget(
      MaterialApp(
        home: const SizedBox(),
        builder: (context, child) => AityxStatus.over(
          child,
          light: AityxStatus(client: client, baseUrl: 'http://api'),
        ),
      ),
    );
  }

  Color dot(WidgetTester tester) {
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

  MockClient answering(int status, String body) => MockClient((request) async {
    expect(request.url.toString(), 'http://api/api/aityx');
    return http.Response(body, status);
  });

  testWidgets('grey while checking, green when aityx accepts the key', (
    tester,
  ) async {
    await show(
      tester,
      answering(
        200,
        '{"key": true, "ok": true, "url": "https://api.aityx.ai", '
        '"detail": "aityx accepts the key"}',
      ),
    );
    expect(dot(tester), Colors.grey);
    await tester.pump();
    expect(dot(tester), Colors.green);
    expect(
      tip(tester),
      'aityx: ready — accepts the key (https://api.aityx.ai)',
    );
  });

  testWidgets('red without a key', (tester) async {
    await show(
      tester,
      answering(
        200,
        '{"key": false, "ok": false, "detail": "AITYX_API_KEY is not set"}',
      ),
    );
    await tester.pump();
    expect(dot(tester), Colors.red);
    expect(tip(tester), 'aityx: no key — AITYX_API_KEY is not set');
  });

  testWidgets('red when aityx refuses, with why', (tester) async {
    await show(
      tester,
      answering(
        200,
        '{"key": true, "ok": false, "detail": "aityx answered HTTP 401"}',
      ),
    );
    await tester.pump();
    expect(dot(tester), Colors.red);
    expect(tip(tester), 'aityx: not working — aityx answered HTTP 401');
  });

  testWidgets('red when the API does not answer', (tester) async {
    await show(tester, answering(502, 'Bad Gateway'));
    await tester.pump();
    expect(dot(tester), Colors.red);
    expect(tip(tester), 'aityx: the API did not answer');
  });
}
