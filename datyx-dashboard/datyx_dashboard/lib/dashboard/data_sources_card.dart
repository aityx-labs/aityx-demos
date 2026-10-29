import 'package:flutter/material.dart';

import '../api/datyx_api.dart';
import '../theme.dart';
import 'add_data_source_dialog.dart';
import 'card_title.dart';

/// The data sources on record (`GET /api/datasources`): one row each with
/// its kind, name, where it points and who added it, a button to remove it
/// (`DELETE`), and a button to add one through [AddDataSourceDialog]
/// (`POST`). [locked] says the API wants a signed-in user first.
class DataSourcesCard extends StatelessWidget {
  const DataSourcesCard({
    super.key,
    required this.sources,
    required this.locked,
    required this.onAdd,
    required this.onRemove,
  });

  final List<DataSource> sources;
  final bool locked;
  final ValueChanged<NewDataSource> onAdd;
  final ValueChanged<DataSource> onRemove;

  Future<void> _add(BuildContext context) async {
    final source = await AddDataSourceDialog.show(context);
    if (source != null) onAdd(source);
  }

  Future<void> _remove(BuildContext context, DataSource source) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${source.name}?'),
        content: Text('The ${source.type.label.toLowerCase()} at ${source.summary} is forgotten; nothing else is touched.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(
            key: const Key('ds-remove-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (yes == true) onRemove(source);
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: CardTitle('Data sources', 'GET, POST and DELETE /api/datasources')),
              FilledButton.icon(
                key: const Key('ds-add'),
                onPressed: locked ? null : () => _add(context),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (locked)
            const Text('Sign in to see the data sources.', style: TextStyle(color: Aityx.muted))
          else if (sources.isEmpty)
            const Text('None yet. Add a database, an S3 bucket or a folder.', style: TextStyle(color: Aityx.muted))
          else
            for (final s in sources) _Row(source: s, onRemove: () => _remove(context, s)),
        ],
      ),
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row({required this.source, required this.onRemove});
  final DataSource source;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final by = source.createdByName ?? source.createdBy;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(iconForType(source.type), size: 20, color: Aityx.orangeLight),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(source.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    Text(source.type.label, style: const TextStyle(color: Aityx.muted, fontSize: 12)),
                  ],
                ),
                Text(
                  source.summary,
                  style: const TextStyle(color: Aityx.muted, fontFamily: 'monospace', fontSize: 12),
                ),
                if (source.description != null && source.description!.isNotEmpty)
                  Text(source.description!, style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (source.createdAt != null)
                Text(
                  source.createdAt!.toLocal().toString().substring(0, 19),
                  style: const TextStyle(color: Aityx.muted, fontSize: 12),
                ),
              if (by != null) Text('by $by', style: const TextStyle(color: Aityx.muted, fontSize: 12)),
            ],
          ),
          IconButton(
            key: Key('ds-remove-${source.id}'),
            tooltip: 'Remove',
            onPressed: onRemove,
            icon: const Icon(Icons.delete_outline, size: 18),
          ),
        ],
      ),
    );
  }
}
