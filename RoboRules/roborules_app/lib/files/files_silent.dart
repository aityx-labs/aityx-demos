import 'picked_file.dart';

/// No files: the app outside a browser.
class Files {
  /// Saves [text] as a download named [name].
  void save(String name, String text) {}

  /// The JSON files the user picks; none.
  Future<List<PickedFile>> pick() async => const [];
}
