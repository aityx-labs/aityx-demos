import 'package:flutter/material.dart';
import 'package:google_sign_in_web/web_only.dart' as web;

import 'auth_controller.dart';

/// The web: Google's own "Sign in with Google" button, rendered by its SDK.
Widget signInButton(AuthController auth) => SizedBox(
  height: 40,
  child: web.renderButton(
    configuration: web.GSIButtonConfiguration(
      theme: web.GSIButtonTheme.filledBlack,
      size: web.GSIButtonSize.medium,
      text: web.GSIButtonText.signinWith,
    ),
  ),
);
