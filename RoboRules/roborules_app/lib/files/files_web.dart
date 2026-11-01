import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'picked_file.dart';

/// The browser's downloads and file picker.
class Files {
  /// The largest file read, in bytes.
  static const maxBytes = 1 << 20;

  /// Saves [text] as a download named [name].
  void save(String name, String text) {
    final blob = web.Blob(
      [text.toJS].toJS,
      web.BlobPropertyBag(type: 'application/json'),
    );
    final url = web.URL.createObjectURL(blob);
    final link = web.HTMLAnchorElement()
      ..href = url
      ..download = name;
    web.document.body?.append(link);
    link.click();
    link.remove();
    // Give the download a moment to start before letting the URL go.
    Timer(const Duration(seconds: 10), () => web.URL.revokeObjectURL(url));
  }

  /// The JSON files the user picks, read as text; none if they cancel.
  Future<List<PickedFile>> pick() {
    final done = Completer<List<PickedFile>>();
    final input = web.HTMLInputElement()
      ..type = 'file'
      ..accept = '.json,application/json'
      ..multiple = true;
    input.onchange = (web.Event _) {
      unawaited(_read(input.files).then(done.complete));
    }.toJS;
    input.addEventListener(
      'cancel',
      (web.Event _) {
        if (!done.isCompleted) done.complete(const []);
      }.toJS,
    );
    input.click();
    return done.future;
  }

  Future<List<PickedFile>> _read(web.FileList? files) async {
    final picked = <PickedFile>[];
    for (var i = 0; i < (files?.length ?? 0); i++) {
      final file = files!.item(i)!;
      if (file.size > maxBytes) {
        picked.add(PickedFile(file.name, error: 'larger than 1 MB'));
        continue;
      }
      try {
        final text = (await file.text().toDart).toDart;
        picked.add(PickedFile(file.name, text: text));
      } catch (_) {
        picked.add(
          PickedFile(file.name, error: 'the browser could not read it'),
        );
      }
    }
    return picked;
  }
}
