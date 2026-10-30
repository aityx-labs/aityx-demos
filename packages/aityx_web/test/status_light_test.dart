import 'dart:async';
import 'dart:convert';

import 'package:aityx_web/aityx_web.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const ready = AityxState(
  ok: true,
  key: true,
  source: AityxSource.user,
  url: 'https://api.aityx.ai',
  detail: 'aityx accepts the key',
  kind: AityxStateKind.ready,
  whose: 'your key',
);

const rejected = AityxState(
  ok: false,
  key: true,
  source: AityxSource.user,
  url: 'https://api.aityx.ai',
  detail: 'aityx answered HTTP 401',
  kind: AityxStateKind.rejected,
  whose: 'your key',
);

/// [light] over a blank screen, through withAityxStatus.
Future<void> pumpLight(WidgetTester tester, Widget light) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) =>
          withAityxStatus(context, child, light: light),
      home: const Scaffold(body: Text('the app')),
    ),
  );
  await tester.pump();
}

Color dotColor(WidgetTester tester) {
  final box = tester.widget<Container>(
    find.descendant(
      of: find.byType(AityxStatusLight),
      matching: find.byType(Container),
    ),
  );
  return (box.decoration! as BoxDecoration).color!;
}

String tip(WidgetTester tester) => tester
    .widget<Tooltip>(
      find.descendant(
        of: find.byType(AityxStatusLight),
        matching: find.byType(Tooltip),
      ),
    )
    .message!;

/// Lets a finished check's result reach the screen.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

Color shown(Color color) => color.withValues(alpha: 0.8);

/// A check that counts its runs and answers [state].
class Checks {
  Checks(this.state);

  AityxState state;
  int runs = 0;

  Future<AityxState> call() async {
    runs++;
    return state;
  }
}

void main() {
  testWidgets('grey while it checks, then green', (tester) async {
    final answer = Completer<AityxState>();
    await pumpLight(
      tester,
      AityxStatusLight(
        store: AityxKeyStore.memory(),
        check: () => answer.future,
      ),
    );
    expect(dotColor(tester), shown(AityxStatusLight.grey));
    expect(tip(tester), 'aityx: checking');
    answer.complete(ready);
    await settle(tester);
    expect(dotColor(tester), shown(AityxStatusLight.green));
    expect(tip(tester), 'aityx: ready (your key, https://api.aityx.ai)');
  });

  testWidgets('red, with why', (tester) async {
    await pumpLight(
      tester,
      AityxStatusLight(
        store: AityxKeyStore.memory(),
        check: Checks(rejected).call,
      ),
    );
    expect(dotColor(tester), shown(AityxStatusLight.red));
    expect(tip(tester), 'aityx: key rejected — aityx answered HTTP 401');
  });

  testWidgets('a check that throws is red, not a crash', (tester) async {
    await pumpLight(
      tester,
      AityxStatusLight(
        store: AityxKeyStore.memory(),
        check: () async => throw StateError('x'),
      ),
    );
    expect(dotColor(tester), shown(AityxStatusLight.red));
    expect(tip(tester), 'aityx: not working — the check failed: StateError');
  });

  testWidgets('the reason, for screen readers, as a button', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpLight(
      tester,
      AityxStatusLight(
        store: AityxKeyStore.memory(),
        check: Checks(ready).call,
      ),
    );
    expect(
      find.bySemanticsLabel('aityx: ready (your key, https://api.aityx.ai)'),
      findsOneWidget,
    );
    final node = tester.getSemantics(find.byType(AityxStatusLight));
    expect(node.flagsCollection.isButton, isTrue);
    semantics.dispose();
  });

  testWidgets('a tap opens the key page', (tester) async {
    var taps = 0;
    await pumpLight(
      tester,
      AityxStatusLight(
        store: AityxKeyStore.memory(),
        check: Checks(rejected).call,
        onTap: () => taps++,
      ),
    );
    await tester.tap(find.byType(AityxStatusLight));
    expect(taps, 1);
  });

  testWidgets('top right, 6 px from the edges, over the app', (tester) async {
    await pumpLight(
      tester,
      AityxStatusLight(
        store: AityxKeyStore.memory(),
        check: Checks(ready).call,
      ),
    );
    expect(find.text('the app'), findsOneWidget);
    final screen = tester.getSize(find.byType(MaterialApp));
    final dot = tester.getRect(
      find.descendant(
        of: find.byType(AityxStatusLight),
        matching: find.byType(Container),
      ),
    );
    expect(dot.size, const Size(8, 8));
    expect(dot.top, 6);
    expect(screen.width - dot.right, 6);
  });

  testWidgets('checks again, now, when the key changes', (tester) async {
    final store = AityxKeyStore.memory();
    final checks = Checks(AityxState.noKey);
    await pumpLight(tester, AityxStatusLight(store: store, check: checks.call));
    expect(checks.runs, 1);
    expect(dotColor(tester), shown(AityxStatusLight.red));

    checks.state = ready;
    store.save('sk-new');
    await tester.pump();
    await tester.pump();
    expect(checks.runs, 2);
    expect(dotColor(tester), shown(AityxStatusLight.green));
  });

  testWidgets('a change during a check runs one more, showing only it', (
    tester,
  ) async {
    final store = AityxKeyStore.memory();
    final answers = <Completer<AityxState>>[];
    await pumpLight(
      tester,
      AityxStatusLight(
        store: store,
        check: () {
          answers.add(Completer());
          return answers.last.future;
        },
      ),
    );
    expect(answers, hasLength(1));
    store.save('sk-new');
    await tester.pump();
    expect(answers, hasLength(1));
    answers.first.complete(AityxState.noKey);
    await settle(tester);
    expect(answers, hasLength(2));
    expect(dotColor(tester), shown(AityxStatusLight.grey));
    answers.last.complete(ready);
    await settle(tester);
    expect(dotColor(tester), shown(AityxStatusLight.green));
  });

  Future<void> regainFocus(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
  }

  testWidgets('checks again when the window regains focus', (tester) async {
    final checks = Checks(ready);
    await pumpLight(
      tester,
      AityxStatusLight(
        store: AityxKeyStore.memory(),
        check: checks.call,
        minInterval: Duration.zero,
      ),
    );
    expect(checks.runs, 1);
    await regainFocus(tester);
    expect(checks.runs, 2);
  });

  testWidgets('but not more than once every 30 s', (tester) async {
    final checks = Checks(ready);
    await pumpLight(
      tester,
      AityxStatusLight(store: AityxKeyStore.memory(), check: checks.call),
    );
    await regainFocus(tester);
    await regainFocus(tester);
    expect(checks.runs, 1);
  });

  testWidgets('no timer polling', (tester) async {
    final checks = Checks(ready);
    await pumpLight(
      tester,
      AityxStatusLight(store: AityxKeyStore.memory(), check: checks.call),
    );
    await tester.pump(const Duration(minutes: 10));
    expect(checks.runs, 1);
  });

  testWidgets('the real check, against a MockClient', (tester) async {
    final store = AityxKeyStore.memory(local: {'aityx.key': 'sk-test'});
    final sent = <http.Request>[];
    await pumpLight(
      tester,
      AityxStatusLight(
        store: store,
        client: MockClient((request) async {
          sent.add(request);
          return http.Response(jsonEncode({'code': 'invalid_request'}), 400);
        }),
      ),
    );
    await tester.pump();
    expect(sent.single.url, Uri.parse('https://api.aityx.ai/v1/systemone'));
    expect(sent.single.headers['Authorization'], 'Bearer sk-test');
    expect(dotColor(tester), shown(AityxStatusLight.green));
  });

  // Off the web only: in a browser, Uri.base is the test server, and the
  // light would really ask its /aityx/config.
  testWidgets('the default light, with no key anywhere', skip: kIsWeb, (
    tester,
  ) async {
    final before = AityxSettings.store;
    AityxSettings.store = AityxKeyStore.memory();
    try {
      await tester.pumpWidget(
        const MaterialApp(builder: withAityxStatus, home: Scaffold()),
      );
      // Off the web, Uri.base is a file: URL: no dev proxy to ask.
      await tester.pump();
      expect(dotColor(tester), shown(AityxStatusLight.red));
      expect(tip(tester), 'aityx: no key — set yours on the index page');
    } finally {
      AityxSettings.store = before;
    }
  });

  testWidgets('the tooltip shows above the app', (tester) async {
    await pumpLight(
      tester,
      AityxStatusLight(
        store: AityxKeyStore.memory(),
        check: Checks(ready).call,
      ),
    );
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    await gesture.moveTo(tester.getCenter(find.byType(AityxStatusLight)));
    await tester.pumpAndSettle();
    expect(
      find.text('aityx: ready (your key, https://api.aityx.ai)'),
      findsOneWidget,
    );
    await gesture.removePointer();
  });

  test('the key page is /#aityx-key at the root of the origin', () {
    expect(
      aityxKeyPage(origin: Uri.parse('http://localhost:8800/pokerface/')),
      Uri.parse('http://localhost:8800/#aityx-key'),
    );
  });
}
