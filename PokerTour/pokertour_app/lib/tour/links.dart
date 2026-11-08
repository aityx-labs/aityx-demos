import 'links_vm.dart' if (dart.library.js_interop) 'links_web.dart' as impl;

/// Opens [path], relative to the app's address (`privacy`, `tos`), in a
/// new tab in the browser; nothing elsewhere.
void openPage(String path) => impl.openPage(path);
