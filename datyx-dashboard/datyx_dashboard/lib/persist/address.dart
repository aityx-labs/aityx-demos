import 'address_memory.dart'
    if (dart.library.js_interop) 'address_web.dart'
    as impl;

/// The open tab, kept in the page's address as `?tab=<name>`, so a reload,
/// a bookmark or a shared link opens the same tab. Flutter's own route, in
/// the address's `#`, is left alone.
abstract final class Address {
  /// The tab the address names, or null.
  static String? get tab => Uri.base.queryParameters['tab'];

  /// Puts [tab] in the address, in place: no new history entry.
  static void showTab(String tab) => impl.replaceQuery({'tab': tab});
}
