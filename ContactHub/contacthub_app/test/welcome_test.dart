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
}
