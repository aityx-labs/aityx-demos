import 'dart:convert';

import 'package:aityx_web/aityx_web.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const panel = ValueKey('aityx-panel');
const status = ValueKey('aityx-panel-status');
const keyField = ValueKey('aityx-panel-key');
const urlField = ValueKey('aityx-panel-url');
const said = ValueKey('aityx-panel-said');
const saveButton = ValueKey('aityx-panel-save');
const forgetButton = ValueKey('aityx-panel-forget');
const closeButton = ValueKey('aityx-panel-close');
const barrier = ValueKey('aityx-panel-barrier');

final origin = Uri.parse('http://localhost:8800/demos/pokerface/');

/// aityx, as the empty check call sees it: 400 invalid_request for
/// [accepts], 401 for any other key; and the index server, which lends a
/// dev key or not ([dev]). [calls] gets each request.
MockClient aityx({
  String accepts = 'good-key-1234',
  bool dev = false,
  List<http.Request>? calls,
}) => MockClient((request) async {
  calls?.add(request);
  if (request.url.path.endsWith('/aityx/config')) {
    return http.Response(
      dev
          ? '{"available": true, "url": "https://api.aityx.ai", "source": ".env"}'
          : '{"available": false}',
      200,
    );
  }
  if (request.url.path.startsWith('/demos/aityx/')) {
    return http.Response(jsonEncode({'code': 'invalid_request'}), 400);
  }
  return request.headers['Authorization'] == 'Bearer $accepts'
      ? http.Response(jsonEncode({'code': 'invalid_request'}), 400)
      : http.Response(jsonEncode({'detail': 'invalid API key'}), 401);
});

/// An app with the light over it, on [store] and [client], and a button
/// in its screen that opens the key panel too.
Future<void> pumpApp(
  WidgetTester tester, {
  required AityxKeyStore store,
  required http.Client client,
  VoidCallback? onSaved,
}) async {
  tester.view.physicalSize = const Size(800, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => withAityxStatus(
        context,
        child,
        light: AityxStatusLight(client: client, store: store, origin: origin),
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => openAityxKey(
              context,
              client: client,
              store: store,
              origin: origin,
              onSaved: onSaved,
            ),
            child: const Text('Change key'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String text(WidgetTester tester, Key key) =>
    tester.widget<Text>(find.byKey(key)).data!;

Color lightColor(WidgetTester tester) =>
    (tester
                .widget<Container>(
                  find.descendant(
                    of: find.byType(AityxStatusLight),
                    matching: find.byType(Container),
                  ),
                )
                .decoration!
            as BoxDecoration)
        .color!;

void main() {
  testWidgets('a tap on the light opens the panel, over the app', (
    tester,
  ) async {
    final store = AityxKeyStore.memory();
    await pumpApp(tester, store: store, client: aityx());
    expect(find.byKey(panel), findsNothing);

    await tester.tap(find.byType(AityxStatusLight));
    await tester.pumpAndSettle();
    expect(find.byKey(panel), findsOneWidget);
    expect(find.text('Your aityx key'), findsWidgets);
    expect(text(tester, status), 'No key yet.');
    // The key field has the keyboard: paste, Enter.
    expect(
      tester.widget<TextField>(find.byKey(keyField)).focusNode!.hasFocus,
      isTrue,
    );
    // The app is still there, under it.
    expect(find.text('Change key'), findsOneWidget);
    // No key to forget.
    expect(
      tester.widget<TextButton>(find.byKey(forgetButton)).onPressed,
      isNull,
    );
  });

  testWidgets('a key aityx rejects is not saved, and the panel says so', (
    tester,
  ) async {
    final store = AityxKeyStore.memory();
    await pumpApp(tester, store: store, client: aityx());
    await tester.tap(find.byType(AityxStatusLight));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(keyField), 'bad-key');
    await tester.tap(find.byKey(saveButton));
    await tester.pumpAndSettle();
    expect(store.key, isNull);
    expect(text(tester, said), 'aityx rejected the key. Not saved.');
    expect(find.byKey(panel), findsOneWidget);
  });

  testWidgets('a key aityx accepts is saved, the panel closes and the light '
      'turns green', (tester) async {
    final store = AityxKeyStore.memory();
    var saved = 0;
    await pumpApp(
      tester,
      store: store,
      client: aityx(),
      onSaved: () => saved++,
    );
    expect(lightColor(tester), AityxStatusLight.red.withValues(alpha: 0.8));

    await tester.tap(find.text('Change key'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(keyField), '  good-key-1234 ');
    await tester.tap(find.byKey(saveButton));
    await tester.pumpAndSettle();
    expect(store.key, 'good-key-1234');
    expect(store.sessionOnly, isFalse);
    expect(saved, 1);
    expect(find.byKey(panel), findsNothing);
    expect(lightColor(tester), AityxStatusLight.green.withValues(alpha: 0.8));
  });

  testWidgets('with a key, shows its last four characters only, and takes a '
      'new one', (tester) async {
    final store = AityxKeyStore.memory(local: {'aityx.key': 'old-key-9876'});
    await pumpApp(
      tester,
      store: store,
      client: aityx(accepts: 'good-key-1234'),
    );
    await tester.tap(find.byType(AityxStatusLight));
    await tester.pumpAndSettle();
    expect(text(tester, status), 'Your key …9876 is set, on this device.');
    expect(find.textContaining('old-key'), findsNothing);
    expect(find.text('A new key'), findsOneWidget);
    // The field starts empty: the key in use is never put on the screen.
    expect(
      tester.widget<TextField>(find.byKey(keyField)).controller!.text,
      isEmpty,
    );

    await tester.enterText(find.byKey(keyField), 'good-key-1234');
    await tester.tap(find.byKey(saveButton));
    await tester.pumpAndSettle();
    expect(store.key, 'good-key-1234');
    expect(find.byKey(panel), findsNothing);
  });

  testWidgets('a key kept for this session only stays so', (tester) async {
    final store = AityxKeyStore.memory(session: {'aityx.key': 'old-key-9876'});
    await pumpApp(tester, store: store, client: aityx());
    await tester.tap(find.byType(AityxStatusLight));
    await tester.pumpAndSettle();
    expect(text(tester, status), 'Your key …9876 is set, for this session.');

    await tester.enterText(find.byKey(keyField), 'good-key-1234');
    await tester.tap(find.byKey(saveButton));
    await tester.pumpAndSettle();
    expect(store.key, 'good-key-1234');
    expect(store.sessionOnly, isTrue);
  });

  testWidgets('Forget key removes it, and the panel stays', (tester) async {
    final store = AityxKeyStore.memory(local: {'aityx.key': 'good-key-1234'});
    await pumpApp(tester, store: store, client: aityx());
    expect(lightColor(tester), AityxStatusLight.green.withValues(alpha: 0.8));
    await tester.tap(find.byType(AityxStatusLight));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(forgetButton));
    await tester.pumpAndSettle();
    expect(store.key, isNull);
    expect(text(tester, said), 'Forgotten: no key of yours in this browser.');
    expect(text(tester, status), 'No key yet.');
    expect(find.byKey(panel), findsOneWidget);
    expect(lightColor(tester), AityxStatusLight.red.withValues(alpha: 0.8));
  });

  testWidgets('says when the server lends its dev key', (tester) async {
    final store = AityxKeyStore.memory();
    await pumpApp(tester, store: store, client: aityx(dev: true));
    expect(lightColor(tester), AityxStatusLight.green.withValues(alpha: 0.8));
    await tester.tap(find.byType(AityxStatusLight));
    await tester.pumpAndSettle();
    expect(
      text(tester, status),
      'No key of yours: this server lends its dev key.',
    );
  });

  testWidgets('refuses an empty key, one with spaces and a URL off aityx.ai', (
    tester,
  ) async {
    final calls = <http.Request>[];
    final store = AityxKeyStore.memory();
    await pumpApp(
      tester,
      store: store,
      client: aityx(calls: calls),
    );
    await tester.tap(find.byType(AityxStatusLight));
    await tester.pumpAndSettle();
    calls.clear();

    await tester.tap(find.byKey(saveButton));
    await tester.pump();
    expect(text(tester, said), 'Paste your key first.');

    await tester.enterText(find.byKey(keyField), 'two words');
    await tester.tap(find.byKey(saveButton));
    await tester.pump();
    expect(text(tester, said), contains('spaces'));

    await tester.enterText(find.byKey(keyField), 'good-key-1234');
    await tester.enterText(find.byKey(urlField), 'https://evil.example');
    await tester.tap(find.byKey(saveButton));
    await tester.pump();
    expect(text(tester, said), contains('aityx.ai'));
    // Nothing went anywhere, and nothing was saved.
    expect(calls, isEmpty);
    expect(store.key, isNull);
  });

  testWidgets('saves the URL with the key, when it is not the default', (
    tester,
  ) async {
    final calls = <http.Request>[];
    final store = AityxKeyStore.memory();
    await pumpApp(
      tester,
      store: store,
      client: aityx(calls: calls),
    );
    await tester.tap(find.byType(AityxStatusLight));
    await tester.pumpAndSettle();
    calls.clear();

    await tester.enterText(find.byKey(keyField), 'good-key-1234');
    await tester.enterText(find.byKey(urlField), 'https://api-stage.aityx.ai');
    await tester.tap(find.byKey(saveButton));
    await tester.pumpAndSettle();
    expect(calls.first.url.host, 'api-stage.aityx.ai');
    expect(store.url, 'https://api-stage.aityx.ai');
  });

  testWidgets('Close, a tap outside and Escape close it; only one opens', (
    tester,
  ) async {
    final store = AityxKeyStore.memory();
    await pumpApp(tester, store: store, client: aityx());

    await tester.tap(find.byType(AityxStatusLight));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(closeButton));
    await tester.pumpAndSettle();
    expect(find.byKey(panel), findsNothing);

    await tester.tap(find.text('Change key'));
    await tester.pumpAndSettle();
    expect(find.byKey(panel), findsOneWidget);
    await tester.tapAt(const Offset(10, 690));
    await tester.pumpAndSettle();
    expect(find.byKey(panel), findsNothing);

    await tester.tap(find.byType(AityxStatusLight));
    await tester.pumpAndSettle();
    expect(find.byKey(panel), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(panel), findsNothing);
  });

  testWidgets('a light with its own onTap opens no panel', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => withAityxStatus(
          context,
          child,
          light: AityxStatusLight(
            store: AityxKeyStore.memory(),
            check: () async => AityxState.noKey,
            onTap: () => taps++,
          ),
        ),
        home: const Scaffold(),
      ),
    );
    await tester.pump();
    await tester.tap(find.byType(AityxStatusLight));
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(find.byKey(panel), findsNothing);
  });
}
