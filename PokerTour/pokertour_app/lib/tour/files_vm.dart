/// Off the web: no files.
library;

bool get filesSupported => false;

void saveTextFile(String name, String text) {}

Future<({String name, String text})?> pickTextFile() async => null;
