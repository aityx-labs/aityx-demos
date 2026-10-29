import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../api/health_hub_api.dart';

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
class AuthController extends ChangeNotifier {
  AuthController({GoogleSignIn? signIn}) : _signIn = signIn ?? GoogleSignIn.instance;

  final GoogleSignIn _signIn;
  AuthConfig? _config;
  bool _ready = false;
  String? _error;
  GoogleSignInAccount? _account;
  StreamSubscription<GoogleSignInAuthenticationEvent>? _events;

  /// The API's answer, once it came.
  AuthConfig? get config => _config;

  /// Whether the API wants a signed-in user.
  bool get enabled => _config?.enabled ?? false;

  /// Whether the sign-in client is initialized (the button can render).
  bool get ready => _ready;
  bool get signedIn => _account != null;
  String? get error => _error;

  SignedInUser? get user {
    final account = _account;
    if (account == null) return null;
    return SignedInUser(
      name: account.displayName,
      email: account.email,
      picture: account.photoUrl,
    );
  }

  /// Whether this platform signs in from a button of ours ([signIn]); on the
  /// web the provider renders its own button instead (see GoogleSignInButton).
  bool get signsInFromOurButton => _signIn.supportsAuthenticate();

  /// Takes the API's answer and, when authentication is on, initializes the
  /// client and tries to sign in without interaction (a previous session).
  Future<void> start(AuthConfig config) async {
    _config = config;
    notifyListeners();
    final clientId = config.clientId;
    if (!config.enabled || clientId == null || clientId.isEmpty) return;
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
      await _signIn.attemptLightweightAuthentication();
    } catch (e) {
      _error = _describe(e);
      notifyListeners();
    }
  }

  void _onEvent(GoogleSignInAuthenticationEvent event) {
    switch (event) {
      case GoogleSignInAuthenticationEventSignIn():
        _account = event.user;
      case GoogleSignInAuthenticationEventSignOut():
        _account = null;
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

  Future<void> signOut() => _signIn.signOut();

  /// The ID token for the API, or null when nobody is signed in.
  Future<String?> token() async => _account?.authentication.idToken;

  /// A fresh token after the API refused one (expired): the provider signs
  /// in again without interaction when it can.
  Future<String?> refresh() async {
    try {
      final account = await _signIn.attemptLightweightAuthentication();
      if (account != null) _account = account;
    } catch (_) {
      // The next call will show the 401 in the panel.
    }
    return _account?.authentication.idToken;
  }

  static String _describe(Object e) =>
      e is GoogleSignInException ? (e.description ?? e.code.name) : e.toString();

  @override
  void dispose() {
    _events?.cancel();
    super.dispose();
  }
}
