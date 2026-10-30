/// Reading an answer's body.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

/// [response]'s body as UTF-8 (http's `body` falls back to Latin-1 when
/// the Content-Type names no charset, which garbles JSON).
String bodyText(http.Response response) =>
    utf8.decode(response.bodyBytes, allowMalformed: true);

/// [text] as JSON, or null when it isn't JSON.
Object? tryJson(String text) {
  try {
    return jsonDecode(text);
  } on FormatException {
    return null;
  }
}

/// [duration] for people: "90 s", or "250 ms" when not whole seconds.
String spoken(Duration duration) => duration.inMilliseconds % 1000 == 0
    ? '${duration.inSeconds} s'
    : '${duration.inMilliseconds} ms';
