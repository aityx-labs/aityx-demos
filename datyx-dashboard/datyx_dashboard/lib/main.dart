import 'package:flutter/material.dart';

import 'api/datyx_api.dart';
import 'app_version.dart';
import 'auth/auth_controller.dart';
import 'dashboard/dashboard_screen.dart';
import 'persist/session_store.dart';
import 'theme.dart';

void main() {
  runApp(const DatyxDashApp());
}

/// The datyx dashboard: shows what the API answers. The logic and the
/// data live in the API (datyx/); this app only asks and shows. It signs
/// the user in the way the API says (GET /api/auth/config) and sends the ID
/// token with every call.
class DatyxDashApp extends StatefulWidget {
  const DatyxDashApp({super.key, this.api, this.auth});

  /// The API, unless a test passes a fake.
  final DatyxApi? api;

  /// The sign-in, unless a test passes its own.
  final AuthController? auth;

  @override
  State<DatyxDashApp> createState() => _DatyxDashAppState();
}

class _DatyxDashAppState extends State<DatyxDashApp> {
  late final AuthController _auth = widget.auth ?? AuthController();
  late final DatyxApi _api =
      widget.api ??
      HttpDatyxApi(
        token: _auth.token,
        refreshToken: _auth.refresh,
        // The audit outlives a reload of the page.
        log: CallLog(store: SessionStore()),
      );

  @override
  void initState() {
    super.initState();
    _startAuth();
  }

  /// Asks the API how to sign in, again and again while it doesn't answer
  /// (it may still be starting), backing off up to half a minute, so the
  /// sign-in comes up without a reload once the API is there.
  Future<void> _startAuth() async {
    var delay = const Duration(seconds: 3);
    while (mounted) {
      try {
        final config = await _api.authConfig();
        if (mounted) await _auth.start(config);
        return;
      } catch (_) {
        await Future<void>.delayed(delay);
        if (delay < const Duration(seconds: 30)) delay *= 2;
      }
    }
  }

  @override
  void dispose() {
    if (widget.auth == null) _auth.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: AppVersion.title,
    debugShowCheckedModeBanner: false,
    theme: aityxDarkTheme(),
    home: DashboardScreen(api: _api, auth: _auth),
  );
}
