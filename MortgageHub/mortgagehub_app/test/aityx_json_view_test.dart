import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mortgagehub_app/proposal/aityx_json_view.dart';

/// The body the API sends: the real model, and a state.
final request = {
  'decision': jsonDecode(
    File('../mortgagehub_api/models/proposal-check.json').readAsStringSync(),
  ),
  'state': {
    'loan_purpose': 'purchase',
    'loan_program': 'fha',
    'property_value': 450000,
    'down_payment': 15750,
    'annual_taxes': null,
    'credit_score': 's660',
    'annual_income': 110000,
    'monthly_debts': 900,
    'first_time_buyer': true,
    'assumed_rate': 6.5,
  },
};

/// An answer in aityx's shape (answers, receipt, usage).
const response = {
  'answers': {
    'status': {'choice': 'needs_review'},
    'ltv': {'number': 96.5},
    'dti': {'number': 41.2},
    'dti_check': {
      'value': {'result': 'review', 'reason': "Above FHA's 43% standard."},
    },
    'program': {'choice': 'fha'},
  },
  'receipt': {
    'read': {},
    'provenance': {'loan_program': 'state'},
    'decisions': {'program': 'fha'},
    'functions': {},
  },
  'usage': {'input_tokens': 6012, 'output_tokens': 0},
};

String labelAt(List<AnnotatedLine> lines, String text) =>
    lines.firstWhere((line) => line.text.trim() == text).note?.label ?? '';

void main() {
  test('prints exactly what JsonEncoder prints', () {
    for (final json in [request, response, <String, Object?>{}, [], 3, null]) {
      expect(
        annotateJson(json, requestNotes).map((line) => line.text).join('\n'),
        const JsonEncoder.withIndent('  ').convert(json),
      );
    }
  });

  test('highlights the parts of the request that matter', () {
    final lines = annotateJson(request, requestNotes);
    expect(labelAt(lines, '"decision": {'), 'The rules');
    // The model has an input called state too: the request's comes last.
    expect(
      lines.lastWhere((line) => line.text == '  "state": {').note?.label,
      'The facts',
    );
    expect(labelAt(lines, '"state": {'), '');
    expect(labelAt(lines, '"loan_program": "fha",'), 'Picks the rules');
    expect(labelAt(lines, '"credit_score": "s660",'), 'Credit');
    expect(labelAt(lines, '"assumed_rate": 6.5'), 'Assumed rate');
    // This state is short, so it's tinted whole; its own notes win.
    expect(labelAt(lines, '"first_time_buyer": true,'), 'The facts');
    expect(labelAt(lines, '"# why"'), 'Cited rules');
    // The model is long: only its first line is highlighted.
    final model = lines.where((line) => line.note?.label == 'The rules');
    expect(model, hasLength(1));
  });

  test('highlights a small value whole, and the innermost note wins', () {
    final lines = annotateJson(response, responseNotes);
    final verdict = [
      for (final line in lines)
        if (line.note?.label == 'The verdict') line.text.trim(),
    ];
    expect(verdict, ['"status": {', '"choice": "needs_review"', '},']);
    expect(labelAt(lines, '"dti_check": {'), 'Check & reason');
    expect(labelAt(lines, '"ltv": {'), 'Figure shown');
    expect(labelAt(lines, '"program": {'), '');
    expect(labelAt(lines, '"provenance": {'), 'Provenance');
    expect(labelAt(lines, '"usage": {'), 'Cost');
    expect(
      lines.where((line) => line.start && line.note?.label == 'Cost'),
      hasLength(1),
    );
  });

  test('marks where a Not processable verdict is asserted in red', () {
    const rejected = {
      'answers': {
        'status': {'choice': 'not_processable'},
        'program_check': {
          'value': {'result': 'fail', 'reason': 'Second homes: 1 unit only.'},
        },
        'limit_check': {
          'value': {'result': 'pass', 'reason': 'Within the limit.'},
        },
      },
      'receipt': {
        'decisions': {
          'status': {'value': 'not_processable', 'branches': {}},
        },
      },
    };
    final lines = annotateJson(rejected, responseNotes);
    AnnotatedLine at(String text) =>
        lines.firstWhere((line) => line.text.trim() == text);

    final verdict = at('"choice": "not_processable"');
    expect(verdict.note?.label, 'Not processable');
    expect(verdict.note?.alarm, isTrue);
    expect(at('"status": {').note?.label, 'The verdict');
    final failed = at('"result": "fail",');
    expect(failed.note?.label, 'Failed check');
    expect(failed.note?.alarm, isTrue);
    expect(at('"result": "pass",').note?.label, 'Check & reason');
    expect(at('"value": "not_processable",').note?.label, 'Verdict computed');

    // Other verdicts keep the usual highlight.
    final review = annotateJson(response, responseNotes);
    expect(review.where((line) => line.note?.alarm ?? false), isEmpty);
  });

  test('records where every value starts and ends', () {
    final lines = annotateJson(response, responseNotes);
    final status = lines.indexWhere((l) => l.text == '    "status": {');
    expect(lines[status].path, 'answers.status');
    expect(lines[lines[status].end!].text, '    },');
    expect(lines.first.path, '');
    expect(lines.first.end, lines.length - 1);
  });

  testWidgets('numbers the lines, and jumps exactly to a part', (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AityxJsonView('Request', request, notes: requestNotes),
          ),
        ),
      ),
    );

    expect(find.byType(ChoiceChip), findsNWidgets(requestNotes.length));
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);

    final lines = annotateJson(request, requestNotes);
    final rate = lines.indexWhere((l) => l.path == 'state.assumed_rate');
    await tester.tap(find.widgetWithText(ChoiceChip, 'Assumed rate'));
    await tester.pumpAndSettle();

    // Its line is numbered, and lands one line below the pane's top: rows
    // are 22 px, so its middle is 22 + 11 px down.
    final number = find.text('${rate + 1}');
    expect(number, findsOneWidget);
    final pane = tester.getTopLeft(find.byType(ListView));
    expect(tester.getCenter(number).dy - pane.dy, closeTo(33, 0.5));
    // Above the code: what it is, where, and why.
    expect(find.textContaining('state.assumed_rate'), findsOneWidget);
    expect(find.textContaining('not a priced rate'), findsWidgets);
  });

  testWidgets('a label marks its own value among its note\'s matches', (
    tester,
  ) async {
    final notes = [JsonNote(RegExp(r'^items\.\d+$'), 'Item', 'One item.')];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AityxJsonView('Items', const {
              'items': [
                {'a': 1},
                {'a': 2},
              ],
            }, notes: notes),
          ),
        ),
      ),
    );
    final labels = find.descendant(
      of: find.byType(ListView),
      matching: find.text('Item'),
    );
    expect(labels, findsNWidgets(2));
    await tester.tap(labels.at(1));
    await tester.pumpAndSettle();
    expect(find.textContaining('items.1'), findsOneWidget);
    // The chip goes to the first.
    await tester.tap(find.widgetWithText(ChoiceChip, 'Item'));
    await tester.pumpAndSettle();
    expect(find.textContaining('items.0'), findsOneWidget);
  });
}
