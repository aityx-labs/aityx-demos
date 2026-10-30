/// Where aityx calls go, and on whose key.
library;

/// The production aityx: where a user's key goes unless they set a URL.
const aityxDefaultUrl = 'https://api.aityx.ai';

/// The storage entries the index page writes (localStorage, or
/// sessionStorage for "only this session").
const aityxKeyName = 'aityx.key';
const aityxUrlName = 'aityx.url';

/// Whose key a call uses.
enum AityxSource {
  /// The user's own key, set on the index page: the app calls aityx
  /// directly, with an Authorization header.
  user,

  /// The dev key: the index server's proxy (`<origin>/aityx/`) adds it, so
  /// the key never reaches the browser.
  dev,

  /// No key at all.
  none,
}

/// Where aityx calls go, and on whose key.
class AityxConnection {
  const AityxConnection({
    required this.endpoint,
    required this.source,
    required this.url,
    this.key,
    this.devKeyFrom,
  });

  /// The user's [key], sent to [url] (the default aityx unless the user
  /// set one). A [url] that isn't an http(s) URL with a host falls back to
  /// the default.
  factory AityxConnection.user(String key, {String? url}) {
    final shown = normalizeAityxUrl(url);
    return AityxConnection(
      endpoint: Uri.parse(shown),
      source: AityxSource.user,
      url: shown,
      key: key,
    );
  }

  /// The index server's dev proxy at [origin]'s `/aityx/`, which forwards
  /// to [url] (as its `/aityx/config` says) with the key from [devKeyFrom]
  /// (".env" or "environment").
  factory AityxConnection.dev(
    Uri origin, {
    String url = '',
    String? devKeyFrom,
  }) => AityxConnection(
    endpoint: origin.resolve('/aityx/'),
    source: AityxSource.dev,
    url: url,
    devKeyFrom: devKeyFrom,
  );

  /// No key anywhere: calls throw AityxNoKey.
  static final none = AityxConnection(
    endpoint: Uri.parse(aityxDefaultUrl),
    source: AityxSource.none,
    url: '',
  );

  /// The base: https://api.aityx.ai, or `<origin>/aityx/` in dev mode.
  final Uri endpoint;

  /// The user's key; null in dev mode (the server adds it) and with none.
  final String? key;

  final AityxSource source;

  /// The aityx URL to show: the user's URL, or the dev config's URL.
  final String url;

  /// In dev mode, where the index server found the key: ".env" or
  /// "environment" (from /aityx/config); null otherwise.
  final String? devKeyFrom;

  /// `<endpoint>/v1/systemone`, whether or not [endpoint]'s path ends in a
  /// slash (`https://api.aityx.ai`, `http://localhost:8800/aityx`).
  Uri get systemone {
    final base = endpoint.path.endsWith('/')
        ? endpoint
        : endpoint.replace(path: '${endpoint.path}/');
    return base.resolve('v1/systemone');
  }

  /// The headers for a call: Content-Type (unless [json] is false) and,
  /// with a user key, Authorization. Never log these.
  Map<String, String> headers({bool json = true}) => {
    if (json) 'Content-Type': 'application/json',
    if (key != null) 'Authorization': 'Bearer $key',
  };

  /// Whose key, for people: "your key", "dev key from .env", "dev key from
  /// the environment", "no key".
  String get whose => switch (source) {
    AityxSource.user => 'your key',
    AityxSource.dev => switch (devKeyFrom) {
      '.env' => 'dev key from .env',
      'environment' => 'dev key from the environment',
      _ => 'dev key',
    },
    AityxSource.none => 'no key',
  };

  /// For debugging: never shows the key.
  @override
  String toString() => 'AityxConnection(${source.name}, $systemone)';
}

/// [url] trimmed and without trailing slashes, or the default aityx when
/// it's empty or not an http(s) URL with a host.
String normalizeAityxUrl(String? url) {
  var trimmed = (url ?? '').trim();
  while (trimmed.endsWith('/')) {
    trimmed = trimmed.substring(0, trimmed.length - 1);
  }
  final parsed = Uri.tryParse(trimmed);
  if (parsed == null ||
      !(parsed.isScheme('https') || parsed.isScheme('http')) ||
      parsed.host.isEmpty) {
    return aityxDefaultUrl;
  }
  return trimmed;
}
