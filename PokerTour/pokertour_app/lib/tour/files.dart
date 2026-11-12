import 'files_vm.dart' if (dart.library.js_interop) 'files_web.dart' as impl;

/// Saves [text] as a file named [name] on the user's device: a download in
/// the browser; nowhere else (yet).
void saveTextFile(String name, String text) => impl.saveTextFile(name, text);

/// Asks the user for a text file (a strategy's JSON) and gives its name
/// and text, or null when they chose none; null off the web too.
Future<({String name, String text})?> pickTextFile() => impl.pickTextFile();

/// Whether this platform can save and pick files.
bool get filesSupported => impl.filesSupported;
