/// The index page's "Your aityx key" section.
library;

import 'paths.dart';
import 'platform/platform_vm.dart'
    if (dart.library.js_interop) 'platform/platform_web.dart'
    as platform;

/// The index page's key section: `/demos/#aityx-key` on [origin] (the
/// page's, Uri.base, unless given), whatever the app's base href.
Uri aityxKeyPage({Uri? origin}) =>
    (origin ?? Uri.base).resolve(demosPath('#aityx-key'));

/// The message an embedded app posts to the page around it when it wants
/// the user's key: the aityx website's blueprint page shows its own key
/// panel, beside the app, instead of the app leaving for the index page.
const aityxKeyMessage = 'aityx:key';

/// Whether the app runs inside another page (the aityx website's blueprint
/// page opens it at `/demos/<slug>/?embed=1`). An embedded app keeps the
/// user where they are: no links out to the index page.
bool get aityxEmbedded => platform.embedded();

/// Opens [aityxKeyPage] in the same tab; embedded, asks the page around
/// the app for the key instead ([aityxKeyMessage]). Does nothing off the
/// web.
void openAityxKeyPage({Uri? origin}) {
  if (aityxEmbedded) return platform.postToParent(aityxKeyMessage);
  platform.openPage(aityxKeyPage(origin: origin));
}
