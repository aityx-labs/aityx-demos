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
/// their roles for a forecast, set with "Tag for training", in one or more
/// groups, each a series of its own ("Add a group") trained by its own
/// algorithm (DeepAR, or XGBoost with a horizon), a tag on the table. What
/// is shown, the readiness and the problems are the API's; the tab asks
/// and shows.
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
                const CardTitle('Catalog', 'what datyx makes of the data in each source'),
                const SizedBox(height: 8),
                const Text(
                  'Read a database source\'s schema into OpenMetadata, then tag '
                  'a table\'s columns for training: the time index, the value '
                  'to forecast, what tells series apart and the features, in '
                  'groups, each trained by DeepAR or by XGBoost, which scores '
                  'the value summed over a horizon. The tags live in '
                  'OpenMetadata, where they can be edited too; the source itself '
                  'never changes.',
                  style: TextStyle(color: Aityx.muted),
                ),
                const SizedBox(height: 12),
                if (locked)
                  const Text('Sign in to see the data sources.', style: TextStyle(color: Aityx.muted))
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
          for (final s in databases) SourceCatalog(key: ValueKey('catalog-${s.id}'), api: api, source: s),
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
  Map<String, List<TimeSeriesSpec>> _series = const {};
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
        _series = {};
        for (final s in series) {
          _series.putIfAbsent(s.table, () => []).add(s);
        }
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

  /// Edits [spec]'s group of [table], or adds one starting from [startFrom].
  Future<void> _tag(CatalogTable table, {TimeSeriesSpec? spec, TimeSeriesSpec? startFrom}) async {
    final saved = await showDialog<TimeSeriesSpec>(
      context: context,
      builder: (_) => TimeSeriesDialog(
        api: widget.api,
        sourceId: widget.source.id,
        table: table,
        spec: spec,
        startFrom: startFrom,
        groups: [for (final s in _series[table.fqn] ?? const <TimeSeriesSpec>[]) s.group],
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
                _TableTile(
                  table: t,
                  series: _series[t.fqn] ?? const [],
                  onEdit: (spec) => _tag(t, spec: spec),
                  onAdd: (from) => _tag(t, startFrom: from),
                ),
          ],
        ),
      ),
    );
  }
}

/// The colors of a table's groups of tags: the brand's orange, a blue and
/// an aqua, checked to stay apart side by side, for color blindness too
/// (the dataviz skill's validator, on the dark surface). Group colors are
/// never status colors (green, amber, red), so a group doesn't read as
/// ready or not.
const groupPalette = [Aityx.orange, Color(0xFF3987E5), Color(0xFF199E70)];

/// A group past the palette's: a neutral gray, its name telling it apart.
const otherGroupColor = Aityx.muted;

/// Each group's color in a table: the default group first, then the others
/// by name, so a group keeps its color however its columns are tagged.
/// Every chip and box also names its group, so the color is never alone.
Map<String, Color> groupColors(Iterable<String> groups) {
  final names = groups.toSet().toList()
    ..sort((a, b) => a == defaultGroup ? -1 : (b == defaultGroup ? 1 : a.compareTo(b)));
  return {for (var i = 0; i < names.length; i++) names[i]: i < groupPalette.length ? groupPalette[i] : otherGroupColor};
}

class _TableTile extends StatelessWidget {
  const _TableTile({required this.table, required this.series, required this.onEdit, required this.onAdd});

  final CatalogTable table;

  /// Its groups as the API reads them, the default first; none: not tagged.
  final List<TimeSeriesSpec> series;
  final void Function(TimeSeriesSpec spec) onEdit;
  final void Function(TimeSeriesSpec? from) onAdd;

  @override
  Widget build(BuildContext context) {
    final colors = groupColors([
      for (final s in series) s.group,
      for (final c in table.columns)
        for (final t in c.tags) ?TimeSeriesTag.parse(t)?.group,
      for (final t in table.tags) ?AlgorithmTag.parse(t)?.group,
    ]);
    final algorithmOf = {for (final s in series) s.group: s.algorithm};
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
          if (series.isNotEmpty) _Badge(series: series),
        ],
      ),
      subtitle: series.isEmpty
          ? null
          : Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [for (final s in series) _TrainedBy(spec: s, color: colors[s.group]!)],
              ),
            ),
      childrenPadding: const EdgeInsets.only(left: 40, bottom: 12),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (table.description != null && table.description!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(table.description!, style: const TextStyle(color: Aityx.muted)),
          ),
        if (table.tags.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                const SizedBox(
                  width: 288,
                  child: Text('on the table', style: TextStyle(color: Aityx.muted, fontSize: 12)),
                ),
                for (final tag in table.tags) _TagChip(tag, colors: colors, algorithms: algorithmOf),
              ],
            ),
          ),
        for (final c in table.columns)
          _ColumnRow(
            column: c,
            inKey: table.primaryKey.contains(c.name),
            colors: colors,
            algorithms: algorithmOf,
          ),
        const SizedBox(height: 8),
        for (final s in series) _SeriesSummary(spec: s, color: colors[s.group]!, onEdit: () => onEdit(s)),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: ValueKey('add-group-${table.fqn}'),
            onPressed: () => onAdd(series.isEmpty ? null : series.first),
            icon: Icon(series.isEmpty ? Icons.sell_outlined : Icons.add, size: 18),
            label: Text(series.isEmpty ? 'Tag for training' : 'Add a group'),
          ),
        ),
      ],
    );
  }
}

class _ColumnRow extends StatelessWidget {
  const _ColumnRow({required this.column, required this.inKey, required this.colors, required this.algorithms});

  final CatalogColumn column;
  final bool inKey;

  /// The table's groups' colors, for its TimeSeries tags.
  final Map<String, Color> colors;

  /// What trains each of the table's groups, to say what a role is to it.
  final Map<String, String> algorithms;

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
          for (final tag in column.tags) _TagChip(tag, colors: colors, algorithms: algorithms),
        ],
      ),
    );
  }
}

/// A tag: a column's TimeSeries role, or the table's algorithm for a group,
/// in its group's color, named with its group but the default's, a role
/// with what it is to the group's algorithm; any other tag in gray.
class _TagChip extends StatelessWidget {
  const _TagChip(this.tag, {required this.colors, required this.algorithms});
  final String tag;
  final Map<String, Color> colors;
  final Map<String, String> algorithms;

  @override
  Widget build(BuildContext context) {
    final role = TimeSeriesTag.parse(tag);
    final trained = role == null ? AlgorithmTag.parse(tag) : null;
    final group = role?.group ?? trained?.group;
    final color = group == null ? null : colors[group] ?? otherGroupColor;
    final prefix = group == null || group == defaultGroup ? '' : '$group: ';
    return Container(
      key: role != null
          ? ValueKey('tag-${role.group}-${role.role.tag}')
          : (trained != null ? ValueKey('algorithm-tag-${trained.group}') : null),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color == null ? Aityx.bg2 : color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color ?? Aityx.border),
      ),
      child: Text(
        role != null
            ? '$prefix${role.role.tag} · ${role.role.to(algorithms[role.group] ?? deepArAlgorithm)}'
            : (trained != null ? '${prefix}trained by ${trained.algorithm}' : tag),
        style: TextStyle(fontSize: 11, color: group == null ? Aityx.muted : Aityx.fg),
      ),
    );
  }
}

/// A table's time series at a glance: ready or needs work, one group; how
/// many are ready, several.
class _Badge extends StatelessWidget {
  const _Badge({required this.series});
  final List<TimeSeriesSpec> series;

  @override
  Widget build(BuildContext context) {
    final ready = series.where((s) => s.ready).length;
    final all = ready == series.length;
    final text = series.length == 1
        ? (all ? 'time series: ready' : 'time series: needs work')
        : '${series.length} time series: ${all ? 'all' : '$ready'} ready';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: all ? Aityx.green : Aityx.amber),
      ),
      child: Text(text, style: TextStyle(fontSize: 11, color: all ? Aityx.green : Aityx.amber)),
    );
  }
}

/// What trains one group of the table, in the group's color: the API's
/// algorithm for it and, when the table has one, its horizon.
class _TrainedBy extends StatelessWidget {
  const _TrainedBy({required this.spec, required this.color});
  final TimeSeriesSpec spec;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    key: ValueKey('trained-by-${spec.group}'),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(spec.algorithm == xgBoostAlgorithm ? Icons.account_tree_outlined : Icons.show_chart, size: 12, color: Aityx.fg),
        const SizedBox(width: 4),
        Text(
          '${spec.group}: ${spec.algorithm}${spec.horizon == null ? '' : ', ${spec.horizon} ahead'}',
          style: const TextStyle(fontSize: 11, color: Aityx.fg),
        ),
      ],
    ),
  );
}

/// One group of the table as a time series, as the API reads it: what its
/// algorithm makes of each role (DeepAR's inputs, XGBoost's dataset), the
/// horizon, and its problems; Edit opens it in the dialog.
class _SeriesSummary extends StatelessWidget {
  const _SeriesSummary({required this.spec, required this.color, required this.onEdit});
  final TimeSeriesSpec spec;

  /// Its group's color, as on the group's tags.
  final Color color;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final xgb = spec.algorithm == xgBoostAlgorithm;
    final lines = <String>[
      if (xgb)
        'scores ${spec.target ?? '?'} summed over the next ${spec.horizon ?? '?'}, '
            'per ${spec.seriesKey.isEmpty ? 'table' : spec.seriesKey.join(' + ')}',
      for (final role in TimeSeriesRole.values)
        if (spec.of(role).isNotEmpty) '${role.to(spec.algorithm)} = ${spec.of(role).join(' + ')}',
      'freq = ${spec.frequency ?? '?'}',
      'horizon = ${spec.horizon ?? (xgb ? '?' : 'the trainer\'s choice')}',
      'a missing row = ${spec.missing == 'zero' ? '0' : 'unknown (a gap)'}',
    ];
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Aityx.bg0,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                key: ValueKey('group-color-${spec.group}'),
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              Text('${spec.algorithm} · ${spec.group}', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Icon(
                spec.ready ? Icons.check_circle_outline : Icons.error_outline,
                size: 16,
                color: spec.ready ? Aityx.green : Aityx.amber,
              ),
              const Spacer(),
              TextButton.icon(
                key: ValueKey('edit-group-${spec.table}-${spec.group}'),
                onPressed: onEdit,
                icon: const Icon(Icons.sell_outlined, size: 16),
                label: const Text('Edit'),
              ),
            ],
          ),
          for (final l in lines) Text(l, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
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
          const Text('not read yet: only databases so far', style: TextStyle(color: Aityx.amber, fontSize: 12)),
        ],
      ),
    ),
  );
}
