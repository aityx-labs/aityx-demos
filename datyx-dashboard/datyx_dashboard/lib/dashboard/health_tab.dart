import 'package:flutter/material.dart';

import '../api/datyx_api.dart';
import '../app_version.dart';
import '../auth/auth_controller.dart';
import '../persist/address.dart';
import '../theme.dart';

/// The Health tab: the system as `GET /api/health` reports it, in cards
/// (the API with its profile and mode, PostgreSQL, OpenMetadata), the
/// sign-in, and this dashboard build itself with its version. The API's
/// health check, OpenMetadata (at the address the API reports) and the
/// dashboard are links that open in a new tab; OpenMetadata's card also
/// links where datyx's tagging is seen there ([openMetadataLinks]).
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
                  ? const ['waiting for /api/health']
                  : [
                      '${s.name} ${s.version}',
                      if (s.profile != null)
                        '${s.profile} profile, ${s.launchMode}, ${s.image}',
                      'up ${_uptime(s.uptime)}',
                      if (s.startedAt != null)
                        'since ${s.startedAt!.toLocal().toString().substring(0, 19)}',
                    ],
              link: apiAddress('/api/health'),
            ),
            StatusCard(
              title: 'PostgreSQL',
              ok: s?.database.ok ?? false,
              lines: _dependency(s?.database),
            ),
            StatusCard(
              title: 'OpenMetadata',
              ok: s?.openMetadata.ok ?? false,
              lines: _dependency(s?.openMetadata),
              link: s?.openMetadata.url == null ? null : Uri.tryParse(s!.openMetadata.url!),
              links: s?.openMetadata.url == null ? const [] : openMetadataLinks(s!.openMetadata.url!),
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
              title: 'Dashboard',
              ok: true,
              lines: [
                AppVersion.version.isEmpty
                    ? 'no version: not built by the scripts'
                    : 'dash ${AppVersion.version}',
                'asks the API every ${refreshEvery.inSeconds} s, and on refresh',
              ],
              link: Address.page,
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

/// Where datyx's tagging is seen in OpenMetadata at [base]: the TimeSeries
/// classification, every tag (roles, groups, algorithms, Disabled) with
/// the tables and columns that carry it; and OpenMetadata's alerts, where
/// datyx-catalog-events tells datyx when a table's tags change (switching
/// a group on trains it).
List<(String, Uri)> openMetadataLinks(String base) {
  final root = Uri.tryParse(base);
  if (root == null) return const [];
  Uri at(String path) => root.replace(path: '${root.path.replaceAll(RegExp(r'/+$'), '')}$path');
  return [
    ('TimeSeries tags, and the tables that carry them', at('/tags/TimeSeries')),
    ('Alerts: datyx-catalog-events tells datyx of tag changes', at('/settings/notifications/alerts')),
  ];
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

/// One of the status cards: a title, a green or red dot, a few lines, and
/// a link to what it is about, opened in a new tab.
class StatusCard extends StatelessWidget {
  const StatusCard({
    super.key,
    required this.title,
    required this.ok,
    required this.lines,
    this.link,
    this.links = const [],
  });

  final String title;
  final bool ok;
  final List<String> lines;
  final Uri? link;

  /// More links, each with what it is.
  final List<(String, Uri)> links;

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
            if (link != null) _Link(key: ValueKey('link-$title'), url: link!),
            for (final (label, url) in links) _Link(key: ValueKey('link-$title-$label'), url: url, label: label),
          ],
        ),
      ),
    ),
  );
}

/// An address that opens in a new tab: underlined, in the accent, with the
/// open-in-new icon.
class _Link extends StatelessWidget {
  const _Link({super.key, required this.url, this.label});
  final Uri url;

  /// What it shows instead of the address, which the tooltip then names.
  final String? label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Tooltip(
      message: label == null ? 'Open in a new tab' : 'Open $url in a new tab',
      child: InkWell(
        onTap: () => Address.open(url),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label ?? '$url',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Aityx.orangeLight,
                  fontSize: 13,
                  decoration: TextDecoration.underline,
                  decorationColor: Aityx.orangeLight,
                ),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.open_in_new, size: 13, color: Aityx.orangeLight),
          ],
        ),
      ),
    ),
  );
}
