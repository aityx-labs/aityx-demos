import 'package:flutter/material.dart';

import 'auth_controller.dart';

/// Phones and desktops: a button that starts the provider's sign-in flow.
Widget signInButton(AuthController auth) => FilledButton.icon(
  onPressed: auth.signIn,
  icon: const Icon(Icons.login, size: 18),
  label: const Text('Sign in with Google'),
);
