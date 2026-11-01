/// A file the user picked: its name, and its text, or why it couldn't be
/// read.
class PickedFile {
  const PickedFile(this.name, {this.text, this.error});

  final String name;
  final String? text;
  final String? error;
}
