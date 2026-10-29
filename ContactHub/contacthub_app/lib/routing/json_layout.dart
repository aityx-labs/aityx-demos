import 'dart:convert';

/// One printed row of JSON: its text, how deep it is, and the path of the
/// value it opens or holds (`decision.decisions.department.table.3`; list
/// indexes are segments too). A long string, or one with line breaks, is
/// printed on several rows: its first row opens the string and the
/// [continuation] rows follow it, unnumbered, the last closing it; on each,
/// the text from [stringStart] on is the string's, shown as written (no
/// escapes), so a prompt reads as the prose it is.
class JsonLine {
  const JsonLine(this.text, this.depth, this.path)
    : continuation = false,
      stringStart = null;

  const JsonLine.wrapped(
    this.text,
    this.depth,
    this.path, {
    required this.continuation,
    required this.stringStart,
  });

  final String text;
  final int depth;
  final String path;

  /// The second and later rows of a string printed on several rows: the
  /// same JSON line, so it gets no number of its own.
  final bool continuation;

  /// Where the string's own text starts in [text], on the rows of a
  /// string printed on several rows; null on an ordinary row.
  final int? stringStart;
}

/// [lines] as printed, and for every path the first and last line of its
/// value, so a viewer can scroll to exactly that value and mark all of it.
class JsonLayout {
  JsonLayout._(this.lines, this.ranges);

  final List<JsonLine> lines;
  final Map<String, ({int first, int last})> ranges;

  int get longestLine =>
      lines.fold(0, (max, l) => l.text.length > max ? l.text.length : max);
}

/// Lists of scalars shorter than this print on one line: a decision table's
/// header and rows stay readable as rows.
const _inlineListWidth = 110;

/// Strings longer than this, or with line breaks, print on several rows,
/// each at most this wide, broken at spaces.
const wrapWidth = 88;

/// [json] pretty-printed with two-space indents, like
/// `JsonEncoder.withIndent('  ')`, except that short lists of scalars stay
/// on one line and long strings wrap (see [JsonLine]).
JsonLayout layoutJson(Object? json) {
  final lines = <JsonLine>[];
  final ranges = <String, ({int first, int last})>{};

  void emit(Object? value, String path, int depth, String key, String comma) {
    final indent = '  ' * depth;
    final first = lines.length;
    if (value is String && (value.contains('\n') || value.length > wrapWidth)) {
      final segments = wrapString(value);
      for (var i = 0; i < segments.length; i++) {
        final firstRow = i == 0;
        final lastRow = i == segments.length - 1;
        final prefix = firstRow ? '$indent$key"' : '$indent  ';
        lines.add(
          JsonLine.wrapped(
            '$prefix${segments[i]}${lastRow ? '"$comma' : ''}',
            depth,
            path,
            continuation: !firstRow,
            stringStart: prefix.length,
          ),
        );
      }
    } else if (value is Map && value.isNotEmpty) {
      lines.add(JsonLine('$indent$key{', depth, path));
      final entries = value.entries.toList();
      for (var i = 0; i < entries.length; i++) {
        final name = '${entries[i].key}';
        emit(
          entries[i].value,
          path.isEmpty ? name : '$path.$name',
          depth + 1,
          '${jsonEncode(name)}: ',
          i < entries.length - 1 ? ',' : '',
        );
      }
      lines.add(JsonLine('$indent}$comma', depth, path));
    } else if (value is List && value.isNotEmpty && !_inline(value)) {
      lines.add(JsonLine('$indent$key[', depth, path));
      for (var i = 0; i < value.length; i++) {
        emit(
          value[i],
          path.isEmpty ? '$i' : '$path.$i',
          depth + 1,
          '',
          i < value.length - 1 ? ',' : '',
        );
      }
      lines.add(JsonLine('$indent]$comma', depth, path));
    } else {
      final text = value is List
          ? '[${value.map(jsonEncode).join(', ')}]'
          : jsonEncode(value);
      lines.add(JsonLine('$indent$key$text$comma', depth, path));
    }
    ranges[path] = (first: first, last: lines.length - 1);
  }

  emit(json, '', 0, '', '');
  return JsonLayout._(lines, ranges);
}

bool _inline(List<Object?> list) =>
    list.every((v) => v == null || v is String || v is num || v is bool) &&
    list.map(jsonEncode).join(', ').length <= _inlineListWidth;

/// [text] cut into rows: at its line breaks, and at the last space before
/// [wrapWidth] (or at [wrapWidth], in a word with no space to break at).
List<String> wrapString(String text) {
  final rows = <String>[];
  for (final paragraph in text.split('\n')) {
    var rest = paragraph;
    while (rest.length > wrapWidth) {
      var cut = rest.lastIndexOf(' ', wrapWidth);
      if (cut <= 0) cut = wrapWidth;
      rows.add(rest.substring(0, cut));
      rest = rest.substring(cut).trimLeft();
    }
    rows.add(rest);
  }
  return rows;
}

/// What a piece of a JSON line is, for coloring.
enum JsonToken { key, string, number, literal, punctuation, space }

/// [line] split into colored pieces: [tokenize]d, except that on the rows
/// of a wrapped string the string's own text is one piece.
List<(JsonToken, String)> tokenizeLine(JsonLine line) {
  final start = line.stringStart;
  if (start == null) return tokenize(line.text);
  return [
    ...tokenize(line.text.substring(0, start)),
    (JsonToken.string, line.text.substring(start)),
  ];
}

/// [line] split into colored pieces: keys, strings, numbers, literals
/// (`true`, `false`, `null`) and punctuation.
List<(JsonToken, String)> tokenize(String line) {
  final out = <(JsonToken, String)>[];
  final pattern = RegExp(
    r'(\s+)|("(?:[^"\\]|\\.)*")(\s*:)?|(-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)|(true|false|null)|([{}\[\],:])',
  );
  var at = 0;
  for (final m in pattern.allMatches(line)) {
    if (m.start > at) {
      out.add((JsonToken.punctuation, line.substring(at, m.start)));
    }
    if (m[1] != null) {
      out.add((JsonToken.space, m[1]!));
    } else if (m[2] != null) {
      final isKey = m[3] != null;
      out.add((isKey ? JsonToken.key : JsonToken.string, m[2]!));
      if (isKey) out.add((JsonToken.punctuation, m[3]!));
    } else if (m[4] != null) {
      out.add((JsonToken.number, m[4]!));
    } else if (m[5] != null) {
      out.add((JsonToken.literal, m[5]!));
    } else {
      out.add((JsonToken.punctuation, m[6]!));
    }
    at = m.end;
  }
  if (at < line.length) out.add((JsonToken.punctuation, line.substring(at)));
  return out;
}

/// One row of the call's single pane: a section's header, a blank line
/// between sections, or a line of one side's JSON.
class CallRow {
  const CallRow.header(this.title, this.subtitle, this.side) : line = null;
  const CallRow.gap() : title = null, subtitle = null, side = null, line = null;
  const CallRow.json(this.side, JsonLine this.line)
    : title = null,
      subtitle = null;

  final String? title;
  final String? subtitle;

  /// Which section it's in: `request` or `response`.
  final String? side;
  final JsonLine? line;
}

/// The request and the response in one list of rows, each side under its
/// header, with every value's rows by side and path.
class CallLayout {
  CallLayout._(this.rows, this._ranges);

  final List<CallRow> rows;
  final Map<String, Map<String, ({int first, int last})>> _ranges;

  /// The rows of the value at [path] on [side] (`request`, `response`).
  ({int first, int last})? range(String side, String path) =>
      _ranges[side]?[path];

  int get longestLine => rows.fold(
    0,
    (max, r) => (r.line?.text.length ?? 0) > max ? r.line!.text.length : max,
  );
}

/// [request] and [response] laid out one after the other, each under a
/// header with [requestTitle] or [responseTitle].
CallLayout layoutCall(
  Object? request,
  Object? response, {
  String requestTitle = 'REQUEST',
  String requestSubtitle = '',
  String responseTitle = 'RESPONSE',
  String responseSubtitle = '',
}) {
  final rows = <CallRow>[];
  final ranges = <String, Map<String, ({int first, int last})>>{};
  void add(String side, String title, String subtitle, Object? json) {
    rows.add(CallRow.header(title, subtitle, side));
    final layout = layoutJson(json);
    final start = rows.length;
    rows.addAll([for (final l in layout.lines) CallRow.json(side, l)]);
    ranges[side] = {
      for (final MapEntry(:key, :value) in layout.ranges.entries)
        key: (first: start + value.first, last: start + value.last),
    };
  }

  add('request', requestTitle, requestSubtitle, request);
  rows.add(const CallRow.gap());
  add('response', responseTitle, responseSubtitle, response);
  return CallLayout._(rows, ranges);
}
