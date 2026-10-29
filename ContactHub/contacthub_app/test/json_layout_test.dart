import 'dart:convert';

import 'package:contacthub_app/routing/json_layout.dart';
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

  group('a long string wraps', () {
    final prompt =
        'First line.\n'
        '${'word ' * 30}end.\n'
        '\n'
        'Last.';
    final layout = layoutJson({'k': 'short', 'p': prompt, 'z': 0});

    test('at line breaks and at the last space before the width', () {
      final rows = layout.lines.where((l) => l.path == 'p').toList();
      expect(rows.first.text, '  "p": "First line.');
      expect(rows.first.continuation, isFalse);
      expect(rows.first.stringStart, '  "p": "'.length);
      expect(rows[1].continuation, isTrue);
      expect(rows[1].text.length, lessThanOrEqualTo(4 + wrapWidth));
      expect(rows[1].text, endsWith('word'));
      expect(rows[2].text.trim(), startsWith('word'));
      expect(rows[3].text, '    ');
      expect(rows.last.text, '    Last.",');
      expect(layout.ranges['p'], (first: 2, last: 2 + rows.length - 1));
      expect(layout.lines.last.text, '}');
      expect(layout.lines[layout.lines.length - 2].text, '  "z": 0');
    });

    test('a short string with no breaks stays on one row', () {
      expect(layout.lines[0].text, '{');
      expect(layout.lines[1].text, '  "k": "short",');
      expect(layout.lines[1].stringStart, isNull);
    });

    test('wrapString cuts a word with no space at the width', () {
      final rows = wrapString('x' * (wrapWidth + 5));
      expect(rows, ['x' * wrapWidth, 'xxxxx']);
      expect(wrapString('a\nb'), ['a', 'b']);
    });

    test('tokenizeLine colors the wrapped text as a string', () {
      final first = layout.lines.firstWhere((l) => l.path == 'p');
      final tokens = tokenizeLine(first);
      expect(tokens.first.$1, JsonToken.space);
      expect(tokens.map((t) => t.$2).join(), first.text);
      expect(tokens.last, (JsonToken.string, 'First line.'));
      final second = layout.lines[3];
      expect(tokenizeLine(second).last.$1, JsonToken.string);
    });
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
