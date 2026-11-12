import 'dart:convert';

import 'package:aityx_web/aityx_web.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const keyField = ValueKey('aityx-key-field');
const urlField = ValueKey('aityx-url-field');
const saveButton = ValueKey('aityx-key-save');

/// aityx, as the empty check call sees it: 400 invalid_request for
/// [accepts], 401 for any other key. [calls] gets each request.
MockClient aityx({String accepts = 'good-key', List<http.Request>? calls}) =>
    MockClient((request) async {
      calls?.add(request);
      if (request.url.path.endsWith('/aityx/config')) {
        return http.Response('{"available": false}', 200);
      }
      return request.headers['Authorization'] == 'Bearer $accepts'
          ? http.Response(jsonEncode({'code': 'invalid_request'}), 400)
          : http.Response(jsonEncode({'detail': 'invalid API key'}), 401);
    });

Future<void> pumpPrompt(
  WidgetTester tester, {
  required AityxKeyStore store,
  http.Client? client,
  Uri? origin,
  VoidCallback? onSaved,
  double width = 800,
}) async {
  tester.view.physicalSize = Size(width, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            const Text('the app'),
            AityxKeyPrompt(
              store: store,
              client: client ?? aityx(),
              origin: origin,
              onSaved: onSaved,
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('cleanAityxUrl', () {
    test('the default when empty', () {
      expect(cleanAityxUrl(''), aityxDefaultUrl);
      expect(cleanAityxUrl('  '), aityxDefaultUrl);
      expect(cleanAityxUrl(null), aityxDefaultUrl);
    });

    test('an https URL under aityx.ai, without trailing slashes', () {
      expect(
        cleanAityxUrl(' https://api-stage.aityx.ai/ '),
        'https://api-stage.aityx.ai',
      );
      expect(
        cleanAityxUrl('https://api.aityx.ai/base//'),
        'https://api.aityx.ai/base',
      );
    });

    test('nothing else', () {
      for (final url in [
        'http://api.aityx.ai',
        'https://aityx.ai.example.com',
        'https://example.com',
        'https://notaityx.ai',
        'https://api.aityx.ai?x=1',
        'https://api.aityx.ai#x',
        'https://user@api.aityx.ai',
        'api.aityx.ai',
        'not a url',
      ]) {
        expect(cleanAityxUrl(url), isNull, reason: url);
      }
    });
  });

  group('AityxKeyPrompt', () {
    testWidgets('shows nothing with a key in the store', (tester) async {
      final calls = <http.Request>[];
      await pumpPrompt(
        tester,
        store: AityxKeyStore.memory(local: {'aityx.key': 'set-before'}),
        client: aityx(calls: calls),
        origin: Uri.parse('http://localhost:8800/demos/cellfie/'),
      );
      expect(find.byKey(keyField), findsNothing);
      expect(find.text('Get a key in the aityx console'), findsNothing);
      expect(tester.getSize(find.byType(AityxKeyPrompt)), Size.zero);
      // Nothing was asked of the index server or of aityx.
      expect(calls, isEmpty);
    });

    testWidgets('shows nothing with the index server\'s dev key', (
      tester,
    ) async {
      final client = MockClient(
        (request) async => http.Response(
          '{"available": true, "url": "https://api.aityx.ai", "source": ".env"}',
          200,
        ),
      );
      await pumpPrompt(
        tester,
        store: AityxKeyStore.memory(),
        client: client,
        origin: Uri.parse('http://localhost:8800/demos/cellfie/'),
      );
      expect(find.byKey(keyField), findsNothing);
      expect(tester.getSize(find.byType(AityxKeyPrompt)), Size.zero);
    });

    testWidgets('without a key: the key, the URL, Save and the console link', (
      tester,
    ) async {
      await pumpPrompt(
        tester,
        store: AityxKeyStore.memory(),
        origin: Uri.parse('https://aityx.ai/demos/cellfie/'),
      );
      expect(find.byKey(keyField), findsOneWidget);
      expect(find.byKey(urlField), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);
      expect(find.text('Get a key in the aityx console'), findsOneWidget);
      // The key isn't shown as typed.
      expect(tester.widget<TextField>(find.byKey(keyField)).obscureText, true);
    });

    testWidgets('fits a phone', (tester) async {
      await pumpPrompt(tester, store: AityxKeyStore.memory(), width: 320);
      expect(find.byKey(keyField), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('saves a key aityx accepts, and goes away', (tester) async {
      final store = AityxKeyStore.memory();
      final calls = <http.Request>[];
      var saved = 0;
      await pumpPrompt(
        tester,
        store: store,
        client: aityx(calls: calls),
        onSaved: () => saved++,
      );
      await tester.enterText(find.byKey(keyField), '  good-key ');
      await tester.tap(find.byKey(saveButton));
      await tester.pumpAndSettle();

      expect(store.key, 'good-key');
      expect(store.sessionOnly, false);
      expect(store.url, isNull);
      expect(saved, 1);
      expect(find.byKey(keyField), findsNothing);
      expect(tester.getSize(find.byType(AityxKeyPrompt)), Size.zero);
      // One empty call, to the default aityx, with the key as a header.
      final check = calls.single;
      expect(check.url, Uri.parse('https://api.aityx.ai/v1/systemone'));
      expect(check.body, '{}');
    });

    testWidgets('Enter in the key field saves too', (tester) async {
      final store = AityxKeyStore.memory();
      await pumpPrompt(tester, store: store);
      await tester.enterText(find.byKey(keyField), 'good-key');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(store.key, 'good-key');
    });

    testWidgets('saves the URL with the key', (tester) async {
      final store = AityxKeyStore.memory();
      final calls = <http.Request>[];
      await pumpPrompt(
        tester,
        store: store,
        client: aityx(calls: calls),
      );
      await tester.enterText(find.byKey(keyField), 'good-key');
      await tester.enterText(
        find.byKey(urlField),
        'https://api-stage.aityx.ai/',
      );
      await tester.tap(find.byKey(saveButton));
      await tester.pumpAndSettle();

      expect(store.key, 'good-key');
      expect(store.url, 'https://api-stage.aityx.ai');
      expect(
        calls.single.url,
        Uri.parse('https://api-stage.aityx.ai/v1/systemone'),
      );
    });

    testWidgets('does not save a key aityx rejects', (tester) async {
      final store = AityxKeyStore.memory();
      var saved = 0;
      await pumpPrompt(tester, store: store, onSaved: () => saved++);
      await tester.enterText(find.byKey(keyField), 'bad-key');
      await tester.tap(find.byKey(saveButton));
      await tester.pumpAndSettle();

      expect(store.key, isNull);
      expect(saved, 0);
      expect(find.text('aityx rejected the key. Not saved.'), findsOneWidget);
      expect(find.byKey(keyField), findsOneWidget);
    });

    testWidgets('does not save when aityx does not answer', (tester) async {
      final store = AityxKeyStore.memory();
      await pumpPrompt(
        tester,
        store: store,
        client: MockClient((request) async => throw http.ClientException('x')),
      );
      await tester.enterText(find.byKey(keyField), 'good-key');
      await tester.tap(find.byKey(saveButton));
      await tester.pumpAndSettle();

      expect(store.key, isNull);
      expect(
        find.text(
          'aityx did not answer (the network, or the URL is wrong). '
          'Not saved.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('asks for a key, and for a URL on aityx.ai, before calling', (
      tester,
    ) async {
      final store = AityxKeyStore.memory();
      final calls = <http.Request>[];
      await pumpPrompt(
        tester,
        store: store,
        client: aityx(calls: calls),
      );

      await tester.tap(find.byKey(saveButton));
      await tester.pumpAndSettle();
      expect(find.text('Paste your key first.'), findsOneWidget);

      await tester.enterText(find.byKey(keyField), 'good key');
      await tester.tap(find.byKey(saveButton));
      await tester.pumpAndSettle();
      expect(
        find.text("That doesn't look like a key: it has spaces in it."),
        findsOneWidget,
      );

      await tester.enterText(find.byKey(keyField), 'good-key');
      await tester.enterText(find.byKey(urlField), 'https://example.com');
      await tester.tap(find.byKey(saveButton));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'The URL must be an https URL on aityx.ai, like https://api.aityx.ai.',
        ),
        findsOneWidget,
      );
      expect(store.key, isNull);
      // The key went nowhere.
      expect(calls, isEmpty);
    });

    testWidgets('goes away when the index page sets the key', (tester) async {
      final store = AityxKeyStore.memory();
      await pumpPrompt(tester, store: store);
      expect(find.byKey(keyField), findsOneWidget);

      store.save('set-on-the-index-page');
      await tester.pumpAndSettle();
      expect(find.byKey(keyField), findsNothing);

      // And comes back when it is forgotten there.
      store.forget();
      await tester.pumpAndSettle();
      expect(find.byKey(keyField), findsOneWidget);
    });
  });
}
