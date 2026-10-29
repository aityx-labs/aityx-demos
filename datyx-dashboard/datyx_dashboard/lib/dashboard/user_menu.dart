import 'package:flutter/material.dart';

import '../auth/auth_controller.dart';
import '../auth/sign_in_button.dart';
import '../theme.dart';

/// The app bar's account corner: nothing while the API has authentication
/// off; the sign-in button while nobody is signed in; the user's picture,
/// name and a sign-out button once someone is.
class UserMenu extends StatelessWidget {
  const UserMenu({super.key, required this.auth});

  final AuthController auth;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: auth,
    builder: (context, _) {
      if (!auth.enabled) return const SizedBox.shrink();
      final user = auth.user;
      if (user == null) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (auth.error != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Tooltip(
                  message: auth.error!,
                  child: const Icon(Icons.error_outline, color: Aityx.red, size: 18),
                ),
              ),
            if (auth.ready) GoogleSignInButton(auth: auth),
          ],
        );
      }
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (user.picture != null)
            CircleAvatar(radius: 14, backgroundImage: NetworkImage(user.picture!))
          else
            const CircleAvatar(radius: 14, child: Icon(Icons.person, size: 16)),
          const SizedBox(width: 8),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(user.label, style: const TextStyle(fontSize: 13)),
              if (user.email != null && user.name != null)
                Text(user.email!, style: const TextStyle(color: Aityx.muted, fontSize: 11)),
            ],
          ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: auth.signOut,
            icon: const Icon(Icons.logout, size: 18),
          ),
        ],
      );
    },
  );
}
