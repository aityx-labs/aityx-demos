/// Saving and opening files: the browser's downloads and file picker, or
/// nothing elsewhere (tests, native builds).
library;

export 'files_silent.dart' if (dart.library.js_interop) 'files_web.dart';
export 'picked_file.dart';
