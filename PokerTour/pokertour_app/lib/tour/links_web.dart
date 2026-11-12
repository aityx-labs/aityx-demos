/// The browser: a new tab, the path resolved against the page's base
/// (/pokertour/).
library;

import 'package:web/web.dart' as web;

void openPage(String path) => web.window.open(path, '_blank', 'noopener');
