import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:riverrace_app/aityx_status.dart';

Future<String> reasonFor(WidgetTester tester, MockClient client) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: AityxStatus(client: client, baseUrl: 'http://api'),
      ),
    ),
  );
  expect(
    tester.widget<Tooltip>(find.byType(Tooltip)).message,
    'aityx: checking',
  );
  await tester.pump();
  return tester.widget<Tooltip>(find.byType(Tooltip)).message!;
}

Color dotColor(WidgetTester tester) {
  final box = tester.widget<Container>(find.byType(Container));
  return (box.decoration! as BoxDecoration).color!;
}

void main() {
  test('the status URL follows the decide URL', () {
    final page = Uri.parse('https://host:8940/app/');
    expect(
      aityxStatusUrl('', web: true, page: page).toString(),
      'https://host:8940/api/aityx',
    );
    expect(
      aityxStatusUrl('', web: false, page: page).toString(),
      'http://localhost:8941/api/aityx',
    );
    expect(
      aityxStatusUrl('http://x', web: true, page: page).toString(),
      'http://x/api/aityx',
    );
  });

  testWidgets('green when aityx accepts the key', (tester) async {
    final client = MockClient((request) async {
      expect(request.url.toString(), 'http://api/api/aityx');
      return http.Response(
        '{"key": true, "ok": true, "url": "https://api.aityx.ai"}',
        200,
      );
    });
    expect(
      await reasonFor(tester, client),
      'aityx: ready — accepts the key (https://api.aityx.ai)',
    );
    expect(dotColor(tester), Colors.green.withValues(alpha: 0.8));
  });

  testWidgets('red without a key', (tester) async {
    final client = MockClient(
      (_) async => http.Response('{"key": false, "ok": false}', 200),
    );
    expect(
      await reasonFor(tester, client),
      'aityx: no key — AITYX_API_KEY is not set',
    );
    expect(dotColor(tester), Colors.red.withValues(alpha: 0.8));
  });

  testWidgets('red with why when aityx does not accept it', (tester) async {
    final client = MockClient(
      (_) async => http.Response(
        '{"key": true, "ok": false, "detail": "aityx answered HTTP 401"}',
        200,
      ),
    );
    expect(
      await reasonFor(tester, client),
      'aityx: not working — aityx answered HTTP 401',
    );
  });

  testWidgets('red when the API does not answer', (tester) async {
    final client = MockClient((_) async => http.Response('down', 502));
    expect(await reasonFor(tester, client), 'aityx: the API did not answer');
    expect(dotColor(tester), Colors.red.withValues(alpha: 0.8));
  });
}
