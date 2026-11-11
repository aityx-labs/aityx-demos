import 'dart:convert';
import 'dart:io';

import 'package:cellfie_app/calls/call_json_view.dart';
import 'package:cellfie_app/calls/calls_panel.dart';
import 'package:cellfie_app/calls/json_layout.dart';
import 'package:cellfie_app/calls/resizable_side_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher/link.dart';

/// A real call, request and response, as aityx answered it.
final fixture = jsonDecode(
  File('test/fixtures/generation-7.json').readAsStringSync(),
) as Map<String, Object?>;

/// The vertical scroll position of the JSON pane under [view].
ScrollPosition paneScroll(WidgetTester tester, Finder view) => tester
    .stateList<ScrollableState>(
      find.descendant(of: view, matching: find.byType(Scrollable)),
    )
    .firstWhere((s) => s.position.axis == Axis.vertical)
    .position;

void main() {
  testWidgets('before any call, the panel says what the demo is, in '
      'memory of Conway', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CallsPanel(calls: [], notes: []),
        ),
      ),
    );
    expect(
      find.textContaining('Game of Life on an infinite board'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Each generation is one aityx call'),
      findsOneWidget,
    );
    expect(
      find.textContaining('In memory of', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('John Horton Conway'), findsOneWidget);
    final link = tester.widget<Link>(find.byType(Link));
    expect(
      link.uri.toString(),
      'https://en.wikipedia.org/wiki/John_Horton_Conway',
    );
    expect(link.target, LinkTarget.blank);
  });

  test('every anchor points at a value the real call has', () {
    final request = layoutJson(fixture['request']);
    final response = layoutJson(fixture['response']);
    for (final a in requestAnchors) {
      expect(request.ranges, contains(a.path), reason: a.path);
    }
    for (final a in responseAnchors) {
      expect(response.ranges, contains(a.path), reason: a.path);
    }
  });

  for (final (side, anchors) in [
    ('request', requestAnchors),
    ('response', responseAnchors),
  ]) {
    testWidgets('the $side chips jump to exactly their value', (tester) async {
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final json = fixture[side];
      final layout = layoutJson(json);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CallJsonView(
                title: side.toUpperCase(),
                json: json,
                anchors: anchors,
              ),
            ),
          ),
        ),
      );
      final view = find.byType(CallJsonView);
      for (final anchor in anchors) {
        await tester.tap(
          find.descendant(
            of: find.byType(ChoiceChip),
            matching: find.text(anchor.label),
          ),
        );
        await tester.pumpAndSettle();
        // The value's first row sits one row under the top of the pane.
        final first = layout.ranges[anchor.path]!.first;
        expect(
          paneScroll(tester, view).pixels,
          4 + (first - 1) * 22.0,
          reason: anchor.path,
        );
        // What it is, and where, above the pane.
        expect(find.textContaining(anchor.why), findsOneWidget);
        expect(
          find.textContaining('${anchor.path}, line ', findRichText: true),
          findsOneWidget,
        );
      }
    });
  }

  testWidgets('a label in the code jumps to its value too', (tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final json = fixture['response'];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CallJsonView(
            title: 'RESPONSE',
            json: json,
            anchors: responseAnchors,
          ),
        ),
      ),
    );
    // answers.fates is near the top: its label shows in the code.
    final inCode = find.descendant(
      of: find.byType(ListView),
      matching: find.text('The fate of each situation'),
    );
    expect(inCode, findsOneWidget);
    await tester.tap(inCode);
    await tester.pumpAndSettle();
    expect(find.textContaining(responseAnchors.first.why), findsOneWidget);
  });

  testWidgets('the panel widens and narrows by its edge', (tester) async {
    tester.view.physicalSize = const Size(1400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const panel = Key('panel');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              const Expanded(child: SizedBox()),
              ResizableSidePanel(
                availableWidth: 1400,
                child: Container(key: panel),
              ),
            ],
          ),
        ),
      ),
    );
    double width() => tester.getSize(find.byKey(panel)).width;
    final handle = find.byKey(const ValueKey('calls-panel-handle'));
    expect(width(), 440);

    // The edge follows the pointer from where it went down.
    await tester.drag(handle, const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(width(), 740);

    // Never less than 360, never leaving less than 320 for the board.
    await tester.drag(handle, const Offset(2000, 0));
    await tester.pumpAndSettle();
    expect(width(), 360);
    await tester.drag(handle, const Offset(-2000, 0));
    await tester.pumpAndSettle();
    expect(width(), 1400 - 320);

    // A double-click goes back to the default.
    await tester.tap(handle);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(handle);
    await tester.pumpAndSettle();
    expect(width(), 440);
  });
}
