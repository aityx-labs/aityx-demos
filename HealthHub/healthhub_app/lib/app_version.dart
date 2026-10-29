/// The build's version, X.Y.Z, compiled in by the build scripts
/// (scripts/make.sh, and the dev server's scripts/flutter-web.sh). Empty for
/// a bare `flutter run` or a test.
abstract final class AppVersion {
  static const String version = String.fromEnvironment('HEALTHHUB_VERSION');

  /// The app's title (the browser tab's).
  static const String title = 'HealthHub';
}
