import 'package:flutter/material.dart';

import '../api/datyx_api.dart';
import '../theme.dart';
import 'card_title.dart';
import 'add_data_source_dialog.dart' show iconForType;
import 'health_tab.dart' show ApiDownLine;
import 'time_series_dialog.dart';

/// The Catalog tab: each database source as the catalogue (OpenMetadata)
/// has it, after the API reads its schema ("Read schema": tables, columns,
/// types, keys), and the time series in it: a table's columns tagged with
/// their roles for a forecast (DeepAR), set with "Tag for DeepAR". What is
/// shown, the readiness and the problems are the API's; the tab asks and
/// shows.
class CatalogTab extends StatelessWidget {
  const CatalogTab({
    super.key,
    required this.api,
    required this.sources,
    required this.locked,
    required this.statusError,
  });

  final DatyxApi api;
  final List<DataSource> sources;
  final bool locked;
  final String? statusError;

  @override
  Widget build(BuildContext context) {
    final databases = [
      for (final s in sources)
        if (s.type == DataSourceType.database) s,
    ];
    final others = [
      for (final s in sources)
        if (s.type != DataSourceType.database) s,
    ];
    return ListView(
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
                  'Read a database source\'s schema into OpenMetadata, then tag '
                  'a table\'s columns for forecasting: the time index, the value '
                  'to forecast, what tells series apart and the features DeepAR '
                  'takes. The tags live in OpenMetadata, where they can be edited '
                  'too; the source itself never changes.',
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
                  ),
              ],
            ),
          ),
        ),
        if (!locked)
          for (final s in databases)
            SourceCatalog(key: ValueKey('catalog-${s.id}'), api: api, source: s),
        if (!locked)
          for (final s in others) _Row(source: s),
      ],
    );
  }
}

/// One database source: its tables in the catalogue, and its time series.
class SourceCatalog extends StatefulWidget {
  const SourceCatalog({super.key, required this.api, required this.source});

  final DatyxApi api;
  final DataSource source;

  @override
  State<SourceCatalog> createState() => _SourceCatalogState();
}

class _SourceCatalogState extends State<SourceCatalog> {
  List<CatalogTable>? _tables;
  Map<String, TimeSeriesSpec> _series = const {};
  String? _error;
  String? _note;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final tables = await widget.api.catalog(widget.source.id);
      final series = await widget.api.timeSeries(widget.source.id);
      if (!mounted) return;
      setState(() {
        _tables = tables;
        _series = {for (final s in series) s.table: s};
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _sync() async {
    setState(() {
      _busy = true;
      _error = null;
      _note = null;
    });
    try {
      final synced = await widget.api.syncCatalog(widget.source.id);
      _note =
          'Read ${synced.tables} tables, ${synced.columns} columns'
          '${synced.removed.isEmpty ? '' : '; ${synced.removed.length} gone from the source'}.';
      await _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _tag(CatalogTable table) async {
    final saved = await showDialog<TimeSeriesSpec>(
      context: context,
      builder: (_) => TimeSeriesDialog(
        api: widget.api,
        sourceId: widget.source.id,
        table: table,
      ),
    );
    if (saved != null) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final tables = _tables;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(iconForType(widget.source.type), size: 20, color: Aityx.orangeLight),
                const SizedBox(width: 10),
                Text(widget.source.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.source.summary,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Aityx.muted, fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : _sync,
                  icon: _busy
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.sync, size: 18),
                  label: Text(tables == null || tables.isEmpty ? 'Read schema' : 'Read again'),
                ),
              ],
            ),
            if (_note != null) ...[
              const SizedBox(height: 8),
              Text(_note!, style: const TextStyle(color: Aityx.green, fontSize: 12)),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Aityx.red, fontSize: 12)),
            ],
            const SizedBox(height: 8),
            if (tables == null && _error == null)
              const Text('Loading the catalogue…', style: TextStyle(color: Aityx.muted))
            else if (tables != null && tables.isEmpty)
              const Text(
                'Not catalogued yet: Read schema reads its tables into OpenMetadata.',
                style: TextStyle(color: Aityx.amber),
              )
            else if (tables != null)
              for (final t in tables)
                _TableTile(table: t, series: _series[t.fqn], onTag: () => _tag(t)),
          ],
        ),
      ),
    );
  }
}

class _TableTile extends StatelessWidget {
  const _TableTile({required this.table, required this.series, required this.onTag});

  final CatalogTable table;
  final TimeSeriesSpec? series;
  final VoidCallback onTag;

  @override
  Widget build(BuildContext context) {
    final s = series;
    return ExpansionTile(
      key: PageStorageKey(table.fqn),
      tilePadding: EdgeInsets.zero,
      leading: Icon(
        table.type == 'View' ? Icons.visibility_outlined : Icons.table_chart_outlined,
        size: 20,
        color: Aityx.muted,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              table.qualifiedName,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
          const SizedBox(width: 8),
          Text('${table.columns.length} columns', style: const TextStyle(color: Aityx.muted, fontSize: 12)),
          const SizedBox(width: 8),
          if (s != null) _Badge(ready: s.ready),
        ],
      ),
      childrenPadding: const EdgeInsets.only(left: 40, bottom: 12),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (table.description != null && table.description!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(table.description!, style: const TextStyle(color: Aityx.muted)),
          ),
        for (final c in table.columns) _ColumnRow(column: c, inKey: table.primaryKey.contains(c.name)),
        const SizedBox(height: 8),
        if (s != null) _SeriesSummary(spec: s),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: onTag,
            icon: const Icon(Icons.sell_outlined, size: 18),
            label: Text(s == null ? 'Tag for DeepAR' : 'Edit DeepAR tags'),
          ),
        ),
      ],
    );
  }
}

class _ColumnRow extends StatelessWidget {
  const _ColumnRow({required this.column, required this.inKey});

  final CatalogColumn column;
  final bool inKey;

  @override
  Widget build(BuildContext context) {
    final key = inKey || column.constraint == 'PRIMARY_KEY';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: [
          SizedBox(
            width: 180,
            child: Row(
              children: [
                if (key) const Icon(Icons.key, size: 14, color: Aityx.amber),
                if (key) const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    column.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 100,
            child: Text(
              column.dataType ?? '?',
              style: const TextStyle(color: Aityx.muted, fontFamily: 'monospace', fontSize: 12),
            ),
          ),
          for (final tag in column.tags) _TagChip(tag),
        ],
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip(this.tag);
  final String tag;

  @override
  Widget build(BuildContext context) {
    final role = TimeSeriesRole.ofTag(tag);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: role == null ? Aityx.bg2 : Aityx.orange.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: role == null ? Aityx.border : Aityx.orange),
      ),
      child: Text(
        role == null ? tag : '${role.tag} · ${role.deepAr}',
        style: TextStyle(fontSize: 11, color: role == null ? Aityx.muted : Aityx.fg),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.ready});
  final bool ready;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: ready ? Aityx.green : Aityx.amber),
    ),
    child: Text(
      ready ? 'time series: ready' : 'time series: needs work',
      style: TextStyle(fontSize: 11, color: ready ? Aityx.green : Aityx.amber),
    ),
  );
}

/// The table as a time series, as the API reads it: the DeepAR inputs it
/// gives, and its problems.
class _SeriesSummary extends StatelessWidget {
  const _SeriesSummary({required this.spec});
  final TimeSeriesSpec spec;

  @override
  Widget build(BuildContext context) {
    final lines = <String>[
      for (final role in TimeSeriesRole.values)
        if (spec.of(role).isNotEmpty) '${role.deepAr} = ${spec.of(role).join(' + ')}',
      'freq = ${spec.frequency ?? '?'}',
      'a missing row = ${spec.missing == 'zero' ? '0' : 'unknown (a gap)'}',
    ];
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Aityx.bg0,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Aityx.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('DeepAR', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          for (final l in lines)
            Text(l, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          for (final p in spec.problems)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('• $p', style: const TextStyle(color: Aityx.amber, fontSize: 12)),
            ),
        ],
      ),
    );
  }
}

/// A source the catalogue doesn't read (S3, a folder).
class _Row extends StatelessWidget {
  const _Row({required this.source});
  final DataSource source;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
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
              style: const TextStyle(color: Aityx.muted, fontFamily: 'monospace', fontSize: 12),
            ),
          ),
          const Text(
            'not read yet: only databases so far',
            style: TextStyle(color: Aityx.amber, fontSize: 12),
          ),
        ],
      ),
    ),
  );
}
