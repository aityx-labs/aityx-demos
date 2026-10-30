import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pokerface_app/aityx_status.dart';

void main() {
  /// The light over a plain page, asking [client].
  Future<void> show(WidgetTester tester, http.Client client) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => WithAityxStatus(
          status: AityxStatus(client: client, baseUrl: 'http://api'),
          child: child!,
        ),
        home: const Scaffold(body: Text('page')),
      ),
    );
  }

  Color dotColor(WidgetTester tester) {
    final dot = tester.widget<Container>(
      find.byKey(const ValueKey('aityx-status-dot')),
    );
    return (dot.decoration! as BoxDecoration).color!;
  }

  String tooltip(WidgetTester tester) =>
      tester.widget<Tooltip>(find.byType(Tooltip)).message!;

  testWidgets('grey while checking, green when aityx accepts the key', (
    tester,
  ) async {
    Uri? asked;
    await show(
      tester,
      MockClient((request) async {
        asked = request.url;
        return http.Response(
          '{"key": true, "ok": true, "url": "https://api.aityx.ai", '
          '"detail": "aityx accepts the key"}',
          200,
        );
      }),
    );
    expect(dotColor(tester), Colors.grey);
    await tester.pump();
    expect(asked, Uri.parse('http://api/api/aityx'));
    expect(dotColor(tester), Colors.green);
    expect(
      tooltip(tester),
      'aityx: ready — accepts the key (https://api.aityx.ai)',
    );
    expect(find.text('page'), findsOneWidget);
  });

  testWidgets('red without a key', (tester) async {
    await show(
      tester,
      MockClient(
        (_) async => http.Response(
          '{"key": false, "ok": false, "detail": "AITYX_API_KEY is not set"}',
          200,
        ),
      ),
    );
    await tester.pump();
    expect(dotColor(tester), Colors.red);
    expect(tooltip(tester), 'aityx: no key — AITYX_API_KEY is not set');
  });

  testWidgets('red with the reason when aityx refuses', (tester) async {
    await show(
      tester,
      MockClient(
        (_) async => http.Response(
          '{"key": true, "ok": false, "url": "https://api.aityx.ai", '
          '"detail": "aityx answered HTTP 401"}',
          200,
        ),
      ),
    );
    await tester.pump();
    expect(dotColor(tester), Colors.red);
    expect(tooltip(tester), 'aityx: not working — aityx answered HTTP 401');
  });

  testWidgets('red when the API does not answer', (tester) async {
    await show(
      tester,
      MockClient((_) async => throw http.ClientException('refused')),
    );
    await tester.pump();
    expect(dotColor(tester), Colors.red);
    expect(tooltip(tester), 'aityx: the API did not answer');
  });

  testWidgets('checks again every minute', (tester) async {
    var calls = 0;
    await show(
      tester,
      MockClient((_) async {
        calls++;
        return http.Response('{"key": true, "ok": true, "url": "u"}', 200);
      }),
    );
    await tester.pump();
    expect(calls, 1);
    await tester.pump(AityxStatus.every);
    expect(calls, 2);
  });
}
