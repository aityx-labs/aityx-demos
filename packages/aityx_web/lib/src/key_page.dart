/// The index page's "Your aityx key" section.
library;

import 'platform/platform_vm.dart'
    if (dart.library.js_interop) 'platform/platform_web.dart'
    as platform;

/// The index page's key section: `/#aityx-key` at the root of [origin]
/// (the page's, Uri.base, unless given), whatever the app's base href.
Uri aityxKeyPage({Uri? origin}) => (origin ?? Uri.base).resolve('/#aityx-key');

/// Opens [aityxKeyPage] in the same tab; does nothing off the web.
void openAityxKeyPage({Uri? origin}) =>
    platform.openPage(aityxKeyPage(origin: origin));
