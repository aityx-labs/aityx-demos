import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../api/health_hub_api.dart';
import '../persist/session_store.dart';

/// Who is signed in, as the identity provider says, and the ID token the
/// API verifies: an OpenID Connect token, sent as a bearer on every call.
class SignedInUser {
  const SignedInUser({this.name, this.email, this.picture});

  final String? name;
  final String? email;
  final String? picture;

  String get label => name ?? email ?? 'signed in';
}

/// Signs the user in with the provider the API names (`GET /api/auth/config`:
/// Google, through its OpenID Connect client id) and holds the ID token the
/// API wants as a bearer. While the API reports authentication off, nothing
/// is asked and every call goes out without a token.
///
/// The token is kept in the [store] (the browser tab's session storage on
/// the web) until it expires or the user signs out, so a reload of the page
/// stays signed in without asking Google again. It is read at once, so a
/// reload opens home straight away; once the API's answer comes, a token
/// issued for another client is dropped.
class AuthController extends ChangeNotifier {
  AuthController({GoogleSignIn? signIn, SessionStore? store})
    : _signIn = signIn ?? GoogleSignIn.instance,
      _store = store ?? SessionStore() {
    _restore();
  }

  static const _key = 'idToken';

  /// How long before its expiry a token counts as expired already.
  static const _margin = Duration(minutes: 1);

  final GoogleSignIn _signIn;
  final SessionStore _store;
  AuthConfig? _config;
  bool _ready = false;
  String? _error;
  String? _idToken;
  SignedInUser? _user;
  StreamSubscription<GoogleSignInAuthenticationEvent>? _events;

  /// The API's answer, once it came.
  AuthConfig? get config => _config;

  /// Whether the API wants a signed-in user.
  bool get enabled => _config?.enabled ?? false;

  /// Whether the sign-in client is initialized (the button can render).
  bool get ready => _ready;
  bool get signedIn => _idToken != null;
  String? get error => _error;
  SignedInUser? get user => _user;

  /// Whether this platform signs in from a button of ours ([signIn]); on the
  /// web the provider renders its own button instead (see GoogleSignInButton).
  bool get signsInFromOurButton => _signIn.supportsAuthenticate();

  /// Takes the API's answer and, when authentication is on, initializes the
  /// client and, without a kept token, tries to sign in without interaction
  /// (a previous session).
  Future<void> start(AuthConfig config) async {
    _config = config;
    final clientId = config.clientId;
    if (!config.enabled || clientId == null || clientId.isEmpty) {
      _forget();
      notifyListeners();
      return;
    }
    if (_idToken case final token? when _claims(token)?['aud'] != clientId) {
      _forget();
    }
    notifyListeners();
    try {
      await _signIn.initialize(
        clientId: clientId,
        // The ID token's audience on a phone; the web plugin takes none.
        serverClientId: kIsWeb ? null : clientId,
      );
      _events = _signIn.authenticationEvents.listen(
        _onEvent,
        onError: (Object e) {
          _error = _describe(e);
          notifyListeners();
        },
      );
      _ready = true;
      notifyListeners();
      // A token kept from before the reload signs in already; Google is
      // asked again only when it expires (see [token]).
      if (!signedIn) await _signIn.attemptLightweightAuthentication();
    } catch (e) {
      _error = _describe(e);
      notifyListeners();
    }
  }

  void _onEvent(GoogleSignInAuthenticationEvent event) {
    switch (event) {
      case GoogleSignInAuthenticationEventSignIn():
        _take(event.user);
      case GoogleSignInAuthenticationEventSignOut():
        _forget();
    }
    _error = null;
    notifyListeners();
  }

  /// Interactive sign-in, where the platform supports it.
  Future<void> signIn() async {
    try {
      await _signIn.authenticate();
    } catch (e) {
      if (e is GoogleSignInException && e.code == GoogleSignInExceptionCode.canceled) return;
      _error = _describe(e);
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    _forget();
    notifyListeners();
    try {
      await _signIn.signOut();
    } catch (_) {
      // Signed out here whatever Google says.
    }
  }

  /// The ID token for the API, or null when nobody is signed in. One that
  /// expired is renewed first ([refresh]).
  Future<String?> token() async {
    final token = _idToken;
    if (token == null) return null;
    if (_fresh(token)) return token;
    return refresh();
  }

  /// A fresh token after the API refused one, or once it expired: the
  /// provider signs in again without interaction when it can; when it
  /// can't, the user is signed out here, and the index shows the sign-in.
  Future<String?> refresh() async {
    GoogleSignInAccount? account;
    try {
      account = await _signIn.attemptLightweightAuthentication();
    } catch (_) {
      // As if it gave none.
    }
    if (account != null) {
      _take(account);
    } else {
      _forget();
    }
    notifyListeners();
    return _idToken;
  }

  /// Signed in as [account]: its token is kept for the next reload.
  void _take(GoogleSignInAccount account) {
    final token = account.authentication.idToken;
    if (token == null) return;
    _idToken = token;
    _user = SignedInUser(
      name: account.displayName,
      email: account.email,
      picture: account.photoUrl,
    );
    _store.write(_key, token);
  }

  void _forget() {
    _idToken = null;
    _user = null;
    _store.remove(_key);
  }

  /// Signs in with the token kept from before a reload, when it is still
  /// fresh; [start] checks its audience once the client id is known.
  void _restore() {
    final token = _store.read(_key);
    final claims = token == null ? null : _claims(token);
    if (token == null || claims == null || !_fresh(token)) {
      _forget();
      return;
    }
    _idToken = token;
    _user = SignedInUser(
      name: claims['name'] as String?,
      email: claims['email'] as String?,
      picture: claims['picture'] as String?,
    );
  }

  /// Whether [token] is still good for a while. The API checks its
  /// signature; this only reads when it expires.
  static bool _fresh(String token) {
    final exp = (_claims(token)?['exp'] as num?)?.toInt();
    if (exp == null) return false;
    final expires = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
    return DateTime.now().add(_margin).isBefore(expires);
  }

  /// A JWT's payload, unverified, or null when it isn't one.
  static Map<String, Object?>? _claims(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      final json = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      return (jsonDecode(json) as Map).cast<String, Object?>();
    } catch (_) {
      return null;
    }
  }

  static String _describe(Object e) =>
      e is GoogleSignInException ? (e.description ?? e.code.name) : e.toString();

  @override
  void dispose() {
    _events?.cancel();
    super.dispose();
  }
}
