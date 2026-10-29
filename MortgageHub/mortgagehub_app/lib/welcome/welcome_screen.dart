import 'package:flutter/material.dart';

import '../app_version.dart';
import '../proposal/proposal_check.dart';
import '../proposal/proposal_form_screen.dart';

/// The app's home: the name, a one-line welcome, the button to request a
/// mortgage proposal and, when the build sets it, the version.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key, this.checker});

  /// Passed on to the proposal form.
  final ProposalChecker? checker;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.home_work_outlined,
                    size: 72,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Welcome to Mortgage Hub',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Your mortgage, from application to closing, in one place.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 32),
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ProposalFormScreen(checker: checker),
                      ),
                    ),
                    icon: const Icon(Icons.request_quote_outlined),
                    label: const Text('Request a mortgage proposal'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                    ),
                  ),
                  if (AppVersion.version.isNotEmpty) ...[
                    const SizedBox(height: 32),
                    Text(
                      AppVersion.version,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
