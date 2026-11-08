/// The browser: a download through a blob and an anchor, and a file
/// picker through a hidden file input.
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

bool get filesSupported => true;

void saveTextFile(String name, String text) {
  final blob = web.Blob(
    [text.toJS].toJS,
    web.BlobPropertyBag(type: 'application/json'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = name
    ..style.display = 'none';
  web.document.body!.append(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
}

Future<({String name, String text})?> pickTextFile() async {
  final input = web.document.createElement('input') as web.HTMLInputElement
    ..type = 'file'
    ..accept = '.json,application/json'
    ..style.display = 'none';
  web.document.body!.append(input);
  final done = Completer<({String name, String text})?>();
  input.onchange = (web.Event _) {
    final file = input.files?.item(0);
    if (file == null) {
      done.complete(null);
      return;
    }
    final reader = web.FileReader();
    reader.onload = (web.Event _) {
      final result = reader.result;
      done.complete((name: file.name, text: result.isA<JSString>() ? (result as JSString).toDart : ''));
    }.toJS;
    reader.onerror = (web.Event _) {
      done.complete(null);
    }.toJS;
    reader.readAsText(file);
  }.toJS;
  // The dialog closed without a file: no change event comes, so the
  // picker just stays open for the next try.
  input.click();
  final picked = await done.future;
  input.remove();
  return picked;
}
