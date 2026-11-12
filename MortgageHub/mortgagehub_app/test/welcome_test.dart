import 'package:flutter_test/flutter_test.dart';
import 'package:mortgagehub_app/main.dart';

void main() {
  testWidgets('opens on the welcome screen', (tester) async {
    await tester.pumpWidget(const MortgageHubApp());

    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(find.text('Welcome to Mortgage Hub'), findsOneWidget);
  });

  testWidgets('shows no version when the build sets none', (tester) async {
    await tester.pumpWidget(const MortgageHubApp());

    // A test build has no MORTGAGEHUB_VERSION, so only the two texts show.
    expect(find.textContaining(RegExp(r'^\d+\.\d+\.\d+$')), findsNothing);
  });

  testWidgets('links back to the aityx demos, under the button', (
    tester,
  ) async {
    await tester.pumpWidget(const MortgageHubApp());

    final link = find.text('aityx demos');
    expect(link, findsOneWidget);
    expect(
      tester.getTopLeft(link).dy,
      greaterThan(
        tester.getBottomLeft(find.text('Request a mortgage proposal')).dy,
      ),
    );
  });
}
