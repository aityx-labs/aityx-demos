import 'package:flutter/material.dart';

import '../api/datyx_api.dart';
import '../theme.dart';
import 'card_title.dart';
import 'add_data_source_dialog.dart' show iconForType;
import 'health_tab.dart' show ApiDownLine;

/// The Catalog tab: datyx's reading of the data in each data source, the
/// datasets it finds and what it makes of them. The API doesn't read the
/// sources yet, so for now each source on record shows as not catalogued.
class CatalogTab extends StatelessWidget {
  const CatalogTab({
    super.key,
    required this.sources,
    required this.locked,
    required this.statusError,
  });

  final List<DataSource> sources;
  final bool locked;
  final String? statusError;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      if (statusError != null) ApiDownLine(statusError!),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CardTitle(
                'Catalog',
                'what datyx makes of the data in each source',
              ),
              const SizedBox(height: 8),
              const Text(
                'The API does not read the data sources yet. Once it does, each '
                'source lists here the datasets it holds (tables, files, '
                'objects), their fields and types, and what datyx makes of '
                'them, as OpenMetadata records it.',
                style: TextStyle(color: Aityx.muted),
              ),
              const SizedBox(height: 12),
              if (locked)
                const Text(
                  'Sign in to see the data sources.',
                  style: TextStyle(color: Aityx.muted),
                )
              else if (sources.isEmpty)
                const Text(
                  'No data sources yet: add one on the Data sources tab.',
                  style: TextStyle(color: Aityx.muted),
                )
              else
                for (final s in sources) _Row(source: s),
            ],
          ),
        ),
      ),
    ],
  );
}

class _Row extends StatelessWidget {
  const _Row({required this.source});
  final DataSource source;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Icon(iconForType(source.type), size: 20, color: Aityx.orangeLight),
        const SizedBox(width: 10),
        Text(source.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            source.summary,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Aityx.muted,
              fontFamily: 'monospace',
              fontSize: 12,
            ),
          ),
        ),
        const Text(
          'not catalogued yet',
          style: TextStyle(color: Aityx.amber, fontSize: 12),
        ),
      ],
    ),
  );
}
