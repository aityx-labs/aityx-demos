import 'package:flutter_test/flutter_test.dart';
import 'package:contacthub_app/main.dart';

void main() {
  testWidgets('opens on the welcome screen', (tester) async {
    await tester.pumpWidget(const ContactHubApp());

    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(find.text('Welcome to Contact Hub'), findsOneWidget);
    expect(find.byType(RequestBox), findsOneWidget);
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
