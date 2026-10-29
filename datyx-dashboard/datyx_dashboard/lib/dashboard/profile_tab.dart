import 'package:flutter/material.dart';

import '../api/datyx_api.dart';
import '../theme.dart';
import 'card_title.dart';
import 'health_tab.dart';

/// The Profile tab: the caller's profile as `GET /api/profile` answers it,
/// made by the API the first time an identity signs in: its name, id and
/// age, how many data sources it owns (their access details encrypted
/// with the profile's own key), and the identities that sign in to it,
/// one row each. With authentication on and nobody signed in, it says to
/// sign in.
class ProfileTab extends StatelessWidget {
  const ProfileTab({
    super.key,
    required this.profile,
    required this.locked,
    required this.statusError,
  });

  final Profile? profile;
  final bool locked;
  final String? statusError;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (statusError != null) ApiDownLine(statusError!),
        Card(
          key: const Key('profile-card'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CardTitle('Profile', 'GET /api/profile'),
                const SizedBox(height: 12),
                if (locked)
                  const Text(
                    'Sign in to see your profile.',
                    style: TextStyle(color: Aityx.muted),
                  )
                else if (p == null)
                  const Text(
                    'Waiting for the API.',
                    style: TextStyle(color: Aityx.muted),
                  )
                else ...[
                  Text(
                    p.name ?? 'Profile ${p.id}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      'profile ${p.id}',
                      if (p.createdAt != null) 'since ${_day(p.createdAt!)}',
                      '${p.dataSources} data source${p.dataSources == 1 ? '' : 's'}',
                    ].join(' · '),
                    style: const TextStyle(color: Aityx.muted, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'The access details of its data sources are encrypted with a key of its own.',
                    style: TextStyle(color: Aityx.muted, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Identities',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'The sign-ins this profile answers to. More can join it, so it is not bound to one email.',
                    style: TextStyle(color: Aityx.muted, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  for (final identity in p.identities) _IdentityRow(identity),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  static String _day(DateTime t) => t.toLocal().toString().substring(0, 10);
}

class _IdentityRow extends StatelessWidget {
  const _IdentityRow(this.identity);
  final ProfileIdentity identity;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (identity.picture != null)
          CircleAvatar(
            radius: 16,
            backgroundImage: NetworkImage(identity.picture!),
          )
        else
          const CircleAvatar(radius: 16, child: Icon(Icons.person, size: 18)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(identity.label),
              Text(
                [
                  if (identity.name != null && identity.email != null)
                    identity.name!,
                  identity.provider,
                  if (identity.addedAt != null)
                    'added ${_when(identity.addedAt!)}',
                  if (identity.lastSeenAt != null)
                    'last seen ${_when(identity.lastSeenAt!)}',
                ].join(' · '),
                style: const TextStyle(color: Aityx.muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  static String _when(DateTime t) => t.toLocal().toString().substring(0, 16);
}
