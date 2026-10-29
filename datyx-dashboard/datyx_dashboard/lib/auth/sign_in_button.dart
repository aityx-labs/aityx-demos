import 'package:flutter/material.dart';

import 'auth_controller.dart';
import 'sign_in_button_default.dart'
    if (dart.library.js_interop) 'sign_in_button_web.dart' as platform;

/// The sign-in control: the provider's own button on the web (Google renders
/// it, as its sign-in SDK requires), a button of ours elsewhere.
class GoogleSignInButton extends StatelessWidget {
  const GoogleSignInButton({super.key, required this.auth});

  final AuthController auth;

  @override
  Widget build(BuildContext context) => platform.signInButton(auth);
}
