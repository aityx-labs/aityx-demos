import 'dart:convert';

import 'package:pokerface_app/calls/json_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final json = {
    'a': 1,
    'b': {
      'c': [true, null],
      'd': [
        {'e': 'x'},
      ],
    },
  };

  test('prints like JsonEncoder.withIndent, short lists inline', () {
    final text = layoutJson(json).lines.map((l) => l.text).join('\n');
    expect(
      text,
      const JsonEncoder.withIndent('  ')
          .convert(json)
          .replaceFirst('[\n      true,\n      null\n    ]', '[true, null]'),
    );
  });

  test('records the exact lines of every value', () {
    final layout = layoutJson(json);
    String lines(String path) {
      final r = layout.ranges[path]!;
      return layout.lines
          .sublist(r.first, r.last + 1)
          .map((l) => l.text.trim())
          .join(' ');
    }

    expect(lines('a'), '"a": 1,');
    expect(lines('b.c'), '"c": [true, null],');
    expect(lines('b.d'), '"d": [ { "e": "x" } ]');
    expect(lines('b.d.0'), '{ "e": "x" }');
    expect(lines('b.d.0.e'), '"e": "x"');
    expect(layout.ranges['']!.first, 0);
    expect(layout.ranges['']!.last, layout.lines.length - 1);
  });

  test('a long list of scalars gets a line per item', () {
    final layout = layoutJson({'long': List.filled(40, 'abcdef')});
    expect(layout.ranges['long.0'], isNotNull);
    expect(layout.lines.length, 40 + 4);
  });

  test('tokenize tells keys from strings, numbers and literals', () {
    final tokens = tokenize('  "rule": 3, "why": "A", "ok": true');
    String kinds(JsonToken kind) =>
        tokens.where((t) => t.$1 == kind).map((t) => t.$2).join(' ');
    expect(kinds(JsonToken.key), '"rule" "why" "ok"');
    expect(kinds(JsonToken.string), '"A"');
    expect(kinds(JsonToken.number), '3');
    expect(kinds(JsonToken.literal), 'true');
    expect(
      tokens.map((t) => t.$2).join(),
      '  "rule": 3, "why": "A", "ok": true',
    );
  });

  test(
    'layoutCall puts the response under the request, each with a header',
    () {
      final call = layoutCall({'a': 1}, {'b': 2}, responseTitle: 'RESPONSE');
      final rows = call.rows;
      expect(rows.first.title, 'REQUEST');
      final b = call.range('response', 'b')!;
      expect(rows[b.first].line!.text.trim(), '"b": 2');
      expect(b.first, greaterThan(call.range('request', '')!.last));
      expect(rows[call.range('response', '')!.first - 1].title, 'RESPONSE');
      expect(call.range('request', 'b'), isNull);
    },
  );
}
