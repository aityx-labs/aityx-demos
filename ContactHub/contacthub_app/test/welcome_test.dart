import 'package:aityx_web/aityx_web.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:contacthub_app/main.dart';

void main() {
  testWidgets('opens on the welcome screen', (tester) async {
    await tester.pumpWidget(const ContactHubApp());

    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(find.text('Welcome to Contact Hub'), findsOneWidget);
    expect(find.byType(RequestBox), findsOneWidget);
  });

  testWidgets('without an aityx key, asks for it above the request box', (
    tester,
  ) async {
    await tester.pumpWidget(const ContactHubApp(aityxLight: SizedBox()));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('aityx-key-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('aityx-url-field')), findsOneWidget);
    expect(find.text('Get a key in the aityx console'), findsOneWidget);
    expect(
      tester.getBottomLeft(find.byType(AityxKeyPrompt)).dy,
      lessThanOrEqualTo(tester.getTopLeft(find.byType(RequestBox)).dy),
    );
  });

  testWidgets('with an aityx key, shows no key form at all', (tester) async {
    AityxSettings.store = AityxKeyStore.memory(local: {'aityx.key': 'k'});
    addTearDown(() => AityxSettings.store = AityxKeyStore.memory());
    await tester.pumpWidget(const ContactHubApp(aityxLight: SizedBox()));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('aityx-key-field')), findsNothing);
    expect(find.text('Get a key in the aityx console'), findsNothing);
    expect(tester.getSize(find.byType(AityxKeyPrompt)).height, 0);
  });

  testWidgets('shows no version when the build sets none', (tester) async {
    await tester.pumpWidget(const ContactHubApp());

    // A test build has no CONTACTHUB_VERSION, so no X.Y.Z shows.
    expect(find.textContaining(RegExp(r'^\d+\.\d+\.\d+$')), findsNothing);
  });

  testWidgets('links back to the aityx demos, under the request box', (
    tester,
  ) async {
    await tester.pumpWidget(const ContactHubApp());

    final link = find.text('aityx demos');
    expect(link, findsOneWidget);
    expect(
      tester.getTopLeft(link).dy,
      greaterThan(tester.getBottomLeft(find.byType(RequestBox)).dy),
    );
  });
}
