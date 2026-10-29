import 'package:flutter/material.dart';

import '../api/datyx_api.dart';
import '../app_version.dart';
import '../auth/auth_controller.dart';
import '../theme.dart';

/// The Health tab: the system as `GET /api/status` reports it, in cards
/// (the API, PostgreSQL, OpenMetadata), the sign-in, the records on file,
/// and this dashboard build itself with its version.
class HealthTab extends StatelessWidget {
  const HealthTab({
    super.key,
    required this.status,
    required this.statusError,
    required this.auth,
    required this.me,
    required this.refreshEvery,
  });

  final SystemStatus? status;
  final String? statusError;
  final AuthController auth;
  final Me? me;
  final Duration refreshEvery;

  @override
  Widget build(BuildContext context) {
    final s = status;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (statusError != null) ApiDownLine(statusError!),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            StatusCard(
              title: 'API',
              ok: s != null,
              lines: s == null
                  ? const ['waiting for /api/status']
                  : [
                      '${s.name} ${s.version}',
                      'up ${_uptime(s.uptime)}',
                      if (s.startedAt != null)
                        'since ${s.startedAt!.toLocal().toString().substring(0, 19)}',
                    ],
            ),
            StatusCard(
              title: 'PostgreSQL',
              ok: s?.database.ok ?? false,
              lines: _dependency(s?.database),
            ),
            StatusCard(
              title: 'OpenMetadata',
              ok: s?.openMetadata.ok ?? false,
              lines: [
                ..._dependency(s?.openMetadata),
                if (s?.openMetadata.url != null) s!.openMetadata.url!,
              ],
            ),
            ListenableBuilder(
              listenable: auth,
              builder: (context, _) => StatusCard(
                title: 'Sign-in',
                ok: auth.config != null && (!auth.enabled || auth.signedIn),
                lines: auth.config == null
                    ? const ['waiting for /api/auth/config']
                    : !auth.enabled
                    ? const [
                        'off: no OIDC_CLIENT_ID on the API',
                        'every call is anonymous',
                      ]
                    : auth.signedIn
                    ? [
                        'OpenID Connect, ${Uri.tryParse(auth.config!.issuer)?.host ?? auth.config!.issuer}',
                        me == null
                            ? 'the API has not confirmed yet'
                            : 'the API sees ${me!.email ?? me!.subject}',
                        if (me?.profileId != null) 'profile ${me!.profileId}',
                      ]
                    : [
                        'on: ${Uri.tryParse(auth.config!.issuer)?.host ?? auth.config!.issuer}',
                        'nobody signed in',
                      ],
              ),
            ),
            StatusCard(
              title: 'Records',
              ok: s != null,
              lines: s == null
                  ? const ['…']
                  : ['${s.dataSources} data sources', '${s.profiles} profiles'],
            ),
            StatusCard(
              title: 'Dashboard',
              ok: true,
              lines: [
                AppVersion.version.isEmpty
                    ? 'no version: not built by the scripts'
                    : 'dash ${AppVersion.version}',
                'asks the API every ${refreshEvery.inSeconds} s, and on refresh',
              ],
            ),
          ],
        ),
      ],
    );
  }

  static List<String> _dependency(Dependency? d) => d == null
      ? const ['…']
      : d.ok
      ? [d.version ?? 'ok']
      : [d.error ?? 'not answering'];

  static String _uptime(Duration d) {
    if (d.inHours > 0) return '${d.inHours} h ${d.inMinutes % 60} min';
    if (d.inMinutes > 0) return '${d.inMinutes} min ${d.inSeconds % 60} s';
    return '${d.inSeconds} s';
  }
}

/// The line, in red, that says the API itself didn't answer.
class ApiDownLine extends StatelessWidget {
  const ApiDownLine(this.error, {super.key});
  final String error;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(
      'The API did not answer: $error',
      style: const TextStyle(color: Aityx.red),
    ),
  );
}

/// One of the status cards: a title, a green or red dot, a few lines.
class StatusCard extends StatelessWidget {
  const StatusCard({
    super.key,
    required this.title,
    required this.ok,
    required this.lines,
  });

  final String title;
  final bool ok;
  final List<String> lines;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 260,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: ok ? Aityx.green : Aityx.red,
                  ),
                ),
                const SizedBox(width: 8),
                Text(title, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            for (final line in lines)
              Text(
                line,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Aityx.muted, fontSize: 13),
              ),
          ],
        ),
      ),
    ),
  );
}
