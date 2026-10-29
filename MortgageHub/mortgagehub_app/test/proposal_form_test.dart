import 'package:faker/faker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mortgagehub_app/main.dart';
import 'package:mortgagehub_app/proposal/proposal_check.dart';
import 'package:mortgagehub_app/proposal/proposal_form_screen.dart';
import 'package:mortgagehub_app/proposal/proposal_summary_screen.dart';

import 'fake_checker.dart';

Future<void> openForm(WidgetTester tester) async {
  tester.view.physicalSize = const Size(900, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MortgageHubApp(checker: FakeChecker()));
  await tester.tap(find.text('Request a mortgage proposal'));
  await tester.pumpAndSettle();
}

Future<void> enter(WidgetTester tester, String label, String text) async {
  await tester.enterText(find.widgetWithText(TextFormField, label), text);
}

Future<void> choose(WidgetTester tester, String label, String option) async {
  final field = find.ancestor(
    of: find.text(label),
    matching: find.byWidgetPredicate((w) => w is DropdownButtonFormField),
  );
  await tester.ensureVisible(field);
  await tester.tap(field);
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

Future<void> submit(WidgetTester tester) async {
  final button = find.text('Request proposal');
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the welcome page opens the proposal form', (tester) async {
    await openForm(tester);
    expect(find.byType(ProposalFormScreen), findsOneWidget);
  });

  testWidgets('an empty form shows what is required', (tester) async {
    await openForm(tester);
    await submit(tester);

    expect(find.byType(ProposalSummaryScreen), findsNothing);
    expect(find.text('Required'), findsWidgets);
    expect(find.text('Enter a 5-digit ZIP code'), findsOneWidget);
    expect(
      find.text('Please agree so we can send you the proposal'),
      findsOneWidget,
    );
  });

  testWidgets('a down payment must be less than the price', (tester) async {
    await openForm(tester);
    await enter(tester, 'Purchase price', '300000');
    await enter(tester, 'Down payment', '300000');
    await submit(tester);

    expect(find.text('Must be less than the purchase price'), findsOneWidget);
  });

  testWidgets('VA loans need military service and a primary residence', (
    tester,
  ) async {
    await openForm(tester);
    await choose(tester, 'Loan program', 'VA');
    await submit(tester);
    expect(
      find.text('VA loans need military service (answer below)'),
      findsOneWidget,
    );

    await choose(tester, 'How will you use it?', 'Investment property');
    await submit(tester);
    expect(
      find.text('VA loans are only for a primary residence'),
      findsOneWidget,
    );
  });

  testWidgets('a refinance asks for the balance, not a down payment', (
    tester,
  ) async {
    await openForm(tester);
    await choose(tester, 'What do you want to do?', 'Cash-out refinance');

    expect(find.widgetWithText(TextFormField, 'Down payment'), findsNothing);
    expect(
      find.widgetWithText(TextFormField, 'Current mortgage balance'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(TextFormField, 'Cash you want to take out'),
      findsOneWidget,
    );
    expect(find.text("I've found the home"), findsNothing);
  });

  testWidgets('a complete purchase request shows its summary', (tester) async {
    await openForm(tester);
    await enter(tester, 'Purchase price', '500000');
    await enter(tester, 'Down payment', '100000');
    await choose(tester, 'When do you plan to close?', 'In 30 to 60 days');
    await choose(tester, 'Property type', 'Condominium');
    await enter(tester, 'Street address', '1 Main St');
    await enter(tester, 'City', 'Austin');
    await choose(tester, 'State', 'Texas');
    await enter(tester, 'ZIP code', '78701');
    await enter(tester, 'First name', 'Ana');
    await enter(tester, 'Last name', 'Lee');
    await enter(tester, 'Email', 'ana@example.com');
    await enter(tester, 'Phone', '5125550100');
    await choose(tester, 'Estimated credit score', '740 to 759');
    await choose(tester, 'Employment', 'Employed (W-2)');
    await enter(tester, 'Annual income before taxes', '120000');
    await enter(tester, 'Monthly debt payments', '500');
    await tester.ensureVisible(find.byKey(const Key('consent')));
    await tester.tap(find.byKey(const Key('consent')));
    await submit(tester);

    expect(find.byType(ProposalSummaryScreen), findsOneWidget);
    expect(find.text(r'$400,000'), findsOneWidget);
    expect(find.text('80.0%'), findsWidgets);
    expect(find.text('5.0%'), findsOneWidget);
    expect(find.text('Requires review'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome to Mortgage Hub'), findsOneWidget);
  });

  testWidgets('Fill random fills a form that submits', (tester) async {
    tester.view.physicalSize = const Size(900, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final seed in [1, 2, 3, 4, 5, 6, 7, 8]) {
      await tester.pumpWidget(
        MaterialApp(
          home: ProposalFormScreen(faker: Faker(seed: seed)),
        ),
      );
      await submit(tester);
      expect(find.text('Required'), findsWidgets);

      await tester.tap(find.text('Fill random'));
      await tester.pumpAndSettle();
      expect(find.text('Required'), findsNothing);
      await submit(tester);
      expect(
        find.byType(ProposalSummaryScreen),
        findsOneWidget,
        reason: 'seed $seed',
      );
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('uncommon fields explain themselves, common ones don\'t', (
    tester,
  ) async {
    await openForm(tester);
    final tooltips = tester
        .widgetList<Tooltip>(find.byType(Tooltip))
        .map((tooltip) => tooltip.message)
        .join('\n');
    expect(tooltips, contains('debt-to-income ratio (DTI)'));
    expect(tooltips, contains('adjustable rate (ARM)'));
    expect(tooltips, contains('FICO'));
    expect(
      find.descendant(
        of: find.widgetWithText(TextFormField, 'First name'),
        matching: find.byType(Tooltip),
      ),
      findsNothing,
    );
  });

  testWidgets('Fill random\'s menu fills a request for each verdict', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final status in CheckStatus.values) {
      await tester.pumpWidget(
        MaterialApp(
          home: ProposalFormScreen(
            faker: Faker(seed: status.index),
            checker: FakeChecker(),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('fillRandomMenu')));
      await tester.pumpAndSettle();
      expect(find.text('Processable'), findsOneWidget);
      expect(find.text('Requires review'), findsOneWidget);
      expect(find.text('Not processable'), findsOneWidget);

      await tester.tap(find.text(status.label));
      await tester.pumpAndSettle();
      expect(find.text('Required'), findsNothing);
      await submit(tester);
      expect(
        find.byType(ProposalSummaryScreen),
        findsOneWidget,
        reason: status.label,
      );
      await tester.pumpWidget(const SizedBox());
    }
  });
}
