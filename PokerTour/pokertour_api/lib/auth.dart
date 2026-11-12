/// Who is calling: Google, through OpenID Connect. The app signs the user
/// in with the client id this server publishes (GET /api/config) and
/// sends the ID token as a bearer; this verifies it against Google's keys
/// (package:openid_client), reads the identity, and lets the tour's
/// domains through (any Google account by default). Without OIDC_CLIENT_ID nobody
/// can sign in: every call that needs a player answers 503.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:openid_client/openid_client.dart';

/// The settings, from the environment (scripts/serve.sh and compose.yaml):
///   OIDC_ISSUER              the provider (default https://accounts.google.com)
///   OIDC_CLIENT_ID           the OAuth client id the app signs in with
///   POKERTOUR_ALLOWED_DOMAINS  the email domains that may play, comma
///                            separated; * is any (default *)
/// The tour's admins, who can start a tournament now, are the aletyx.com
/// and aletyx.ai accounts ([adminDomains]), whatever the domains that
/// may play: no setting widens them.
class AuthSettings {
  const AuthSettings({
    required this.issuer,
    required this.clientId,
    this.domains = defaultDomains,
  });

  factory AuthSettings.fromEnvironment([Map<String, String>? env]) {
    env ??= Platform.environment;
    final issuer = env['OIDC_ISSUER'] ?? '';
    final domains = _domains(env['POKERTOUR_ALLOWED_DOMAINS']);
    return AuthSettings(
      issuer: issuer.isEmpty ? 'https://accounts.google.com' : issuer,
      clientId: env['OIDC_CLIENT_ID'] ?? '',
      domains: domains.isEmpty ? defaultDomains : domains,
    );
  }

  static List<String> _domains(String? text) =>
      (text ?? '').split(',').map((d) => d.trim().toLowerCase()).where((d) => d.isNotEmpty).toList();

  static const defaultDomains = ['*'];

  final String issuer;
  final String clientId;
  final List<String> domains;

  /// The admins' domains: an account in one can start a tournament now.
  static const adminDomains = ['aletyx.com', 'aletyx.ai'];

  bool get enabled => clientId.isNotEmpty;

  /// What GET /api/config says of the sign-in.
  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'issuer': issuer,
    'clientId': enabled ? clientId : null,
  };

  /// Whether any account may play: the domains are *.
  bool get anyDomain => domains.contains('*');

  /// Whether [email] is in one of the tour's domains.
  bool allows(String email) => anyDomain || domains.contains(_domainOf(email));

  /// Whether [email] is one of the tour's admins: it may play, and it is
  /// an aletyx.com or aletyx.ai account.
  bool isAdmin(String email) => allows(email) && adminDomains.contains(_domainOf(email));

  static String _domainOf(String email) {
    final at = email.lastIndexOf('@');
    return at < 0 ? '' : email.substring(at + 1).toLowerCase();
  }
}

/// The identity a verified token carries.
class Identity {
  const Identity({required this.subject, required this.email, this.name, this.picture});

  final String subject;
  final String email;
  final String? name;
  final String? picture;

  /// How the leaderboard names the owner without the email: a short hash.
  String get ownerId => ownerIdOf(email);

  /// The name to show on the leaderboard: the Google name, else the part
  /// of the email before the @.
  String get displayName => (name ?? '').trim().isNotEmpty ? name!.trim() : email.split('@').first;

  Map<String, Object?> toJson() => {
    'email': email,
    'name': name,
    'picture': picture,
    'ownerId': ownerId,
  };
}

/// A short, stable id for an email: the first 12 hex digits of its SHA-256.
String ownerIdOf(String email) =>
    sha256.convert(utf8.encode(email.trim().toLowerCase())).toString().substring(0, 12);

/// Why a token was refused.
enum Refusal {
  /// No token, or not a valid one for this client.
  invalid,

  /// A valid token for an account outside the tour's domains.
  domain,
}

/// Who a bearer token says is calling, or why it was refused.
class Verified {
  const Verified(this.identity, this.refusal);

  final Identity? identity;
  final Refusal? refusal;
}

/// Verifies bearer tokens for [settings]: the issuer's metadata and keys
/// are discovered on the first token, and a verified token is remembered
/// until it expires, so a call costs no network round trip to the issuer.
class TokenVerifier {
  TokenVerifier(this.settings);

  final AuthSettings settings;
  Client? _client;
  final _verified = <String, (Identity, DateTime)>{};

  Future<Client> _oidcClient() async {
    final existing = _client;
    if (existing != null) return existing;
    final issuer = await Issuer.discover(Uri.parse(settings.issuer));
    return _client = Client(issuer, settings.clientId);
  }

  /// The identity the token carries, when it is a token this server
  /// accepts and the account is in the tour's domains.
  Future<Verified> verify(String? token) async {
    if (!settings.enabled || token == null || token.isEmpty) {
      return const Verified(null, Refusal.invalid);
    }
    final now = DateTime.now();
    _verified.removeWhere((_, entry) => entry.$2.isBefore(now));
    final remembered = _verified[token];
    if (remembered != null) return _check(remembered.$1);
    try {
      final client = await _oidcClient();
      final credential = client.createCredential(idToken: token);
      final problems = await credential.validateToken().toList();
      if (problems.isNotEmpty) {
        stderr.writeln('auth: token refused: ${problems.map((e) => e.toString()).join('; ')}');
        return const Verified(null, Refusal.invalid);
      }
      final claims = credential.idToken.claims;
      final email = claims.email;
      if (email == null || claims['email_verified'] != true) {
        stderr.writeln('auth: token without a verified email');
        return const Verified(null, Refusal.invalid);
      }
      final identity = Identity(
        subject: claims.subject,
        email: email,
        name: claims.name,
        picture: claims.picture?.toString(),
      );
      final expiry = claims.expiry;
      _verified[token] = (identity, expiry.isAfter(now) ? expiry : now.add(const Duration(minutes: 1)));
      return _check(identity);
    } catch (error) {
      stderr.writeln('auth: token not verified: $error');
      return const Verified(null, Refusal.invalid);
    }
  }

  Verified _check(Identity identity) =>
      settings.allows(identity.email) ? Verified(identity, null) : const Verified(null, Refusal.domain);
}
