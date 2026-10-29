/// Who is calling: OpenID Connect, Google first. The app signs the user in
/// with the client id this API publishes (GET /api/auth/config) and sends
/// the ID token as a bearer; this verifies it against the issuer's keys,
/// through package:openid_client, and reads the identity claims. Without
/// OIDC_CLIENT_ID authentication is off and every call is anonymous.
library;

import 'dart:io';

import 'package:openid_client/openid_client.dart';

/// The settings, from the environment (scripts/api.sh and compose.yaml):
///   OIDC_ISSUER     the provider (default https://accounts.google.com)
///   OIDC_CLIENT_ID  the OAuth client id the app signs in with; empty: off
class AuthSettings {
  const AuthSettings({required this.issuer, required this.clientId});

  factory AuthSettings.fromEnvironment([Map<String, String>? env]) {
    env ??= Platform.environment;
    final issuer = env['OIDC_ISSUER'] ?? '';
    return AuthSettings(
      issuer: issuer.isEmpty ? 'https://accounts.google.com' : issuer,
      clientId: env['OIDC_CLIENT_ID'] ?? '',
    );
  }

  final String issuer;
  final String clientId;

  bool get enabled => clientId.isNotEmpty;

  /// What GET /api/auth/config answers.
  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'issuer': issuer,
    'clientId': enabled ? clientId : null,
  };
}

/// The identity a verified token carries.
class Identity {
  const Identity({required this.subject, this.email, this.name, this.picture});

  final String subject;
  final String? email;
  final String? name;
  final String? picture;

  /// The email, else the subject: how records and logs name the user.
  String get id => email ?? subject;

  Map<String, Object?> toJson() => {
    'subject': subject,
    'email': email,
    'name': name,
    'picture': picture,
  };
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

  /// The identity the token carries, or null when it isn't a token this
  /// API accepts (the reason is logged). Null too while authentication is
  /// off.
  Future<Identity?> verify(String? token) async {
    if (!settings.enabled || token == null || token.isEmpty) return null;
    final now = DateTime.now();
    _verified.removeWhere((_, entry) => entry.$2.isBefore(now));
    final remembered = _verified[token];
    if (remembered != null) return remembered.$1;
    try {
      final client = await _oidcClient();
      final credential = client.createCredential(idToken: token);
      final problems = await credential.validateToken().toList();
      if (problems.isNotEmpty) {
        stderr.writeln('auth: token refused: ${problems.map((e) => e.toString()).join('; ')}');
        return null;
      }
      final claims = credential.idToken.claims;
      final identity = Identity(
        subject: claims.subject,
        email: claims.email,
        name: claims.name,
        picture: claims.picture?.toString(),
      );
      final expiry = claims.expiry;
      _verified[token] = (identity, expiry.isAfter(now) ? expiry : now.add(const Duration(minutes: 1)));
      return identity;
    } catch (error) {
      stderr.writeln('auth: token not verified: $error');
      return null;
    }
  }
}
