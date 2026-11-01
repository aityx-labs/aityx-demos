import 'package:flutter/material.dart';

import '../api/datyx_api.dart';
import '../theme.dart';
import 'card_title.dart';
import 'add_data_source_dialog.dart' show iconForType;
import 'health_tab.dart' show ApiDownLine;
import 'time_series_dialog.dart';

/// The Catalog tab, in sections: Databases, each database source as the
/// catalogue (OpenMetadata) has it, after the API reads its schema ("Read
/// schema": tables, columns, types, keys), and the time series in it: a
/// table's columns tagged with their roles for a forecast, set with "Tag
/// for training", in one or more groups, each a series of its own ("Add a
/// group") trained by its own algorithms (DeepAR, XGBoost with a
/// horizon, or both), a tag each on the table, and each enabled or
/// disabled (its `TimeSeries.<group>.Disabled` tag on the table, which
/// enabling removes and so has datyx queue a run for each of the group's
/// algorithms); Streams, each Kafka source's topics after
/// the API reads them ("Read topics": partitions, retention, the fields of
/// their records); and the sources nothing reads yet. What is shown, the
/// readiness and the problems are the API's; the tab asks and shows.
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
    final streams = [
      for (final s in sources)
        if (s.type == DataSourceType.kafka) s,
    ];
    final others = [
      for (final s in sources)
        if (s.type != DataSourceType.database && s.type != DataSourceType.kafka) s,
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
                  'the value summed over a horizon. Read a Kafka source\'s topics '
                  'too, with the fields of their latest records. The tags live in '
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
        if (!locked && databases.isNotEmpty) ...[
          const _SectionTitle(
            Icons.storage,
            'Databases',
            'tables, columns and the time series in them',
            help:
                'Database sources: the tables and views their schema has, as OpenMetadata '
                'keeps them, and the columns tagged for a forecast',
          ),
          for (final s in databases) _Spaced(SourceCatalog(key: ValueKey('catalog-${s.id}'), api: api, source: s)),
        ],
        if (!locked && streams.isNotEmpty) ...[
          const _SectionTitle(
            Icons.stream,
            'Streams',
            'Kafka topics and the fields of their records',
            help:
                'Kafka sources: their topics, as OpenMetadata keeps them, with the fields '
                'learnt from each topic\'s latest records',
          ),
          for (final s in streams) _Spaced(StreamCatalog(key: ValueKey('catalog-${s.id}'), api: api, source: s)),
        ],
        if (!locked && others.isNotEmpty) ...[
          const _SectionTitle(
            Icons.hourglass_empty,
            'Not read yet',
            'S3 buckets and folders',
            help: 'Sources datyx can\'t read into the catalogue yet: only databases and Kafka so far',
          ),
          for (final s in others) _Spaced(_Row(source: s)),
        ],
      ],
    );
  }
}

/// A section of the tab: its icon, name and what its cards show, with room
/// above it to set it apart from the section before; [help], on hover, says
/// which sources it holds.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.icon, this.title, this.subtitle, {required this.help});
  final IconData icon;
  final String title;
  final String subtitle;
  final String help;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 28, bottom: 12, left: 4),
    child: Tooltip(
      message: help,
      child: Row(
        children: [
          Icon(icon, size: 18, color: Aityx.orange),
          const SizedBox(width: 8),
          Expanded(child: CardTitle(title, subtitle)),
        ],
      ),
    ),
  );
}

/// A card of a section, with a gap under it before the next.
class _Spaced extends StatelessWidget {
  const _Spaced(this.child);
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 16), child: child);
}

/// The top of a source's card: its icon, name and where it points, and the
/// button that has the API read it into the catalogue ([readHelp] says
/// what that reads).
class _SourceHeader extends StatelessWidget {
  const _SourceHeader({
    required this.source,
    required this.busy,
    required this.label,
    required this.readHelp,
    required this.onRead,
  });
  final DataSource source;
  final bool busy;
  final String label;
  final String readHelp;
  final VoidCallback onRead;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Tooltip(
        message: '${source.type.label} source',
        child: Icon(iconForType(source.type), size: 20, color: Aityx.orangeLight),
      ),
      const SizedBox(width: 10),
      Tooltip(
        message: source.description == null || source.description!.isEmpty
            ? 'The data source\'s name, as added on the Data sources tab'
            : source.description!,
        child: Text(source.name, style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Tooltip(
          message: 'Where datyx connects: ${source.summary}',
          child: Text(
            source.summary,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Aityx.muted, fontFamily: 'monospace', fontSize: 12),
          ),
        ),
      ),
      const SizedBox(width: 8),
      Tooltip(
        message: readHelp,
        child: FilledButton.tonalIcon(
          onPressed: busy ? null : onRead,
          icon: busy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.sync, size: 18),
          label: Text(label),
        ),
      ),
    ],
  );
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

  /// The groups being enabled or disabled, as `table/group`.
  final Set<String> _switching = {};

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

  /// Enables or disables [spec]'s group: the API removes or adds its
  /// Disabled tag in OpenMetadata, and enabling queues a training run for
  /// each of its algorithms. The group becomes the API's answer, and the
  /// table's tags are read again.
  Future<void> _setEnabled(TimeSeriesSpec spec, bool enabled) async {
    final key = '${spec.table}/${spec.group}';
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _switching.add(key);
      _error = null;
      _note = null;
    });
    try {
      final answer = await widget.api.setGroupEnabled(widget.source.id, spec.table, spec.group, enabled);
      if (!mounted) return;
      setState(() {
        _series = {
          for (final e in _series.entries)
            e.key: [for (final s in e.value) s.table == spec.table && s.group == spec.group ? answer : s],
        };
      });
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            answer.enabled
                ? '${spec.group} enabled: ${queuedRuns(answer.algorithms)}; see the Training tab.'
                : '${spec.group} disabled: tagged ${answer.disabledTagFqn} in OpenMetadata, datyx doesn\'t train it.',
          ),
        ),
      );
      final tables = await widget.api.catalog(widget.source.id);
      if (mounted) setState(() => _tables = tables);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _switching.remove(key));
    }
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
            _SourceHeader(
              source: widget.source,
              busy: _busy,
              label: tables == null || tables.isEmpty ? 'Read schema' : 'Read again',
              readHelp:
                  'Reads every table and view, with its columns, types and keys, into '
                  'OpenMetadata. No rows are read; tags added there stay',
              onRead: _sync,
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
                  switching: {
                    for (final s in _series[t.fqn] ?? const <TimeSeriesSpec>[])
                      if (_switching.contains('${s.table}/${s.group}')) s.group,
                  },
                  onEdit: (spec) => _tag(t, spec: spec),
                  onAdd: (from) => _tag(t, startFrom: from),
                  onEnabled: _setEnabled,
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
  const _TableTile({
    required this.table,
    required this.series,
    required this.switching,
    required this.onEdit,
    required this.onAdd,
    required this.onEnabled,
  });

  final CatalogTable table;

  /// Its groups as the API reads them, the default first; none: not tagged.
  final List<TimeSeriesSpec> series;

  /// The groups being enabled or disabled now.
  final Set<String> switching;
  final void Function(TimeSeriesSpec spec) onEdit;
  final void Function(TimeSeriesSpec? from) onAdd;
  final void Function(TimeSeriesSpec spec, bool enabled) onEnabled;

  @override
  Widget build(BuildContext context) {
    final colors = groupColors([
      for (final s in series) s.group,
      for (final c in table.columns)
        for (final t in c.tags) ?TimeSeriesTag.parse(t)?.group,
      for (final t in table.tags) ?AlgorithmTag.parse(t)?.group,
      for (final t in table.tags) ?disabledGroup(t),
    ]);
    final description = table.description == null || table.description!.isEmpty ? null : table.description!;
    final algorithmOf = {for (final s in series) s.group: s.algorithms};
    return ExpansionTile(
      key: PageStorageKey(table.fqn),
      tilePadding: EdgeInsets.zero,
      leading: Tooltip(
        message: tableKind(table.type),
        child: Icon(
          table.type == 'View' ? Icons.visibility_outlined : Icons.table_chart_outlined,
          size: 20,
          color: Aityx.muted,
        ),
      ),
      title: Row(
        children: [
          Flexible(
            child: Tooltip(
              message:
                  '${tableKind(table.type)} ${table.qualifiedName}'
                  '${description == null ? ', with no description in the source' : ': $description'}\n'
                  'In OpenMetadata: ${table.fqn}',
              child: Text(
                table.qualifiedName,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: 'Its columns, in the source\'s order; open the row to see them',
            child: Text('${table.columns.length} columns', style: const TextStyle(color: Aityx.muted, fontSize: 12)),
          ),
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
        if (description != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(description, style: const TextStyle(color: Aityx.muted)),
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
        for (final s in series)
          _SeriesSummary(
            spec: s,
            color: colors[s.group]!,
            switching: switching.contains(s.group),
            onEdit: () => onEdit(s),
            onEnabled: (enabled) => onEnabled(s, enabled),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: Tooltip(
            message: series.isEmpty
                ? 'Tag the columns with their roles in a forecast: the time index, the '
                      'value to forecast, what tells series apart, the features'
                : 'Another dataset in this table: a group with its own value to '
                      'forecast, sharing the columns, frequency and missing rows',
            child: OutlinedButton.icon(
              key: ValueKey('add-group-${table.fqn}'),
              onPressed: () => onAdd(series.isEmpty ? null : series.first),
              icon: Icon(series.isEmpty ? Icons.sell_outlined : Icons.add, size: 18),
              label: Text(series.isEmpty ? 'Tag for training' : 'Add a group'),
            ),
          ),
        ),
      ],
    );
  }
}

/// What a table of the catalogue is, by its OpenMetadata table type.
String tableKind(String? type) => switch (type) {
  'View' => 'View',
  'MaterializedView' => 'Materialized view',
  'Partitioned' => 'Partitioned table',
  _ => 'Table',
};

class _ColumnRow extends StatelessWidget {
  const _ColumnRow({required this.column, required this.inKey, required this.colors, required this.algorithms});

  final CatalogColumn column;
  final bool inKey;

  /// The table's groups' colors, for its TimeSeries tags.
  final Map<String, Color> colors;

  /// What trains each of the table's groups, to say what a role is to them.
  final Map<String, List<String>> algorithms;

  @override
  Widget build(BuildContext context) {
    final key = inKey || column.constraint == 'PRIMARY_KEY';
    final rules = [
      if (key) 'part of the primary key',
      if (!key && column.constraint == 'NOT_NULL') 'never empty (NOT NULL)',
      if (column.tags.isEmpty) 'not tagged',
    ];
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
                if (key)
                  const Tooltip(
                    message: 'Primary key: with the table\'s other key columns, it names one row',
                    child: Icon(Icons.key, size: 14, color: Aityx.amber),
                  ),
                if (key) const SizedBox(width: 4),
                Flexible(
                  child: Tooltip(
                    message: 'Column ${column.name}${rules.isEmpty ? '' : ': ${rules.join(', ')}'}',
                    child: Text(
                      column.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 100,
            child: Tooltip(
              message: column.dataType == null
                  ? 'Its data type isn\'t known'
                  : 'Its data type, as OpenMetadata names it: ${column.dataType}',
              child: Text(
                column.dataType ?? '?',
                style: const TextStyle(color: Aityx.muted, fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ),
          for (final tag in column.tags) _TagChip(tag, colors: colors, algorithms: algorithms),
        ],
      ),
    );
  }
}

/// A tag: a column's TimeSeries role, or one of the table's algorithms for
/// a group or its Disabled tag, in its group's color, named with its group
/// but the default's, a role with what it is to each of the group's
/// algorithms; any other tag in gray.
class _TagChip extends StatelessWidget {
  const _TagChip(this.tag, {required this.colors, required this.algorithms});
  final String tag;
  final Map<String, Color> colors;
  final Map<String, List<String>> algorithms;

  @override
  Widget build(BuildContext context) {
    final role = TimeSeriesTag.parse(tag);
    final trained = role == null ? AlgorithmTag.parse(tag) : null;
    final disabled = role == null && trained == null ? disabledGroup(tag) : null;
    final group = role?.group ?? trained?.group ?? disabled;
    final color = group == null ? null : colors[group] ?? otherGroupColor;
    final prefix = group == null || group == defaultGroup ? '' : '$group: ';
    final groupAlgorithms = role == null ? null : algorithms[role.group] ?? const [deepArAlgorithm];
    return Tooltip(
      message: role != null
          ? '${role.role.help}, in the ${role.group} group.\n'
                '${groupAlgorithms!.map((a) => '$a takes it as ${role.role.to(a)}').join('; ')}. Tag $tag in OpenMetadata'
          : (trained != null
                ? 'datyx trains the ${trained.group} group with ${trained.algorithm}. Tag $tag in OpenMetadata'
                : (disabled != null
                      ? 'The $disabled group is disabled: datyx doesn\'t train it while the table has this tag'
                      : tagHelp(tag))),
      child: Container(
        key: role != null
            ? ValueKey('tag-${role.group}-${role.role.tag}')
            : (trained != null
                  ? ValueKey('algorithm-tag-${trained.group}-${trained.algorithm}')
                  : (disabled != null ? ValueKey('disabled-tag-$disabled') : null)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color == null ? Aityx.bg2 : color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color ?? Aityx.border),
        ),
        child: Text(
          role != null
              ? '$prefix${role.role.tag} · ${role.role.toEach(groupAlgorithms!)}'
              : (trained != null
                    ? '${prefix}trained by ${trained.algorithm}'
                    : (disabled != null ? '${prefix}disabled, not trained' : tag)),
          style: TextStyle(fontSize: 11, color: group == null ? Aityx.muted : Aityx.fg),
        ),
      ),
    );
  }
}

/// What a tag that isn't a TimeSeries role says: its classification, the
/// part before the first dot, and the tag.
String tagHelp(String tag) {
  final dot = tag.indexOf('.');
  if (dot <= 0) return 'Tag $tag in OpenMetadata';
  return 'Tag ${tag.substring(dot + 1)} of the ${tag.substring(0, dot)} classification, '
      'added in OpenMetadata';
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
    final off = series.where((s) => !s.enabled).length;
    final text =
        (series.length == 1
            ? (all ? 'time series: ready' : 'time series: needs work')
            : '${series.length} time series: ${all ? 'all' : '$ready'} ready') +
        (off == 0 ? '' : (series.length == 1 ? ', disabled' : ', $off disabled'));
    return Tooltip(
      message:
          (all
              ? 'Its columns are tagged for a forecast, and datyx can train '
                    '${series.length == 1 ? 'it' : 'each group'} as tagged'
              : 'Tagged for a forecast, but ${series.length - ready} of ${series.length} '
                    '${series.length == 1 ? 'group needs' : 'groups need'} work: open the row to see what to fix') +
          (off == 0 ? '' : '. ${off == 1 && series.length == 1 ? 'It is' : '$off of them are'} disabled, not trained'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: all ? Aityx.green : Aityx.amber),
        ),
        child: Text(text, style: TextStyle(fontSize: 11, color: all ? Aityx.green : Aityx.amber)),
      ),
    );
  }
}

/// What trains one group of the table, in the group's color: the API's
/// algorithms for it and, when the table has one, its horizon; a disabled
/// group's muted, saying so.
class _TrainedBy extends StatelessWidget {
  const _TrainedBy({required this.spec, required this.color});
  final TimeSeriesSpec spec;
  final Color color;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: spec.enabled ? 1 : 0.55,
    child: Container(
      key: ValueKey('trained-by-${spec.group}'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: spec.enabled ? color.withValues(alpha: 0.18) : null,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            !spec.enabled
                ? Icons.pause_circle_outline
                : (spec.xgBoost ? Icons.account_tree_outlined : Icons.show_chart),
            size: 12,
            color: Aityx.fg,
          ),
          const SizedBox(width: 4),
          Text(
            '${spec.group}: ${spec.algorithms.join(' + ')}${spec.horizon == null ? '' : ', ${spec.horizon} ahead'}'
            '${spec.enabled ? '' : ', disabled'}',
            style: const TextStyle(fontSize: 11, color: Aityx.fg),
          ),
        ],
      ),
    ),
  );
}

/// One group of the table as a time series, as the API reads it: what its
/// algorithms make of each role (DeepAR's inputs, XGBoost's dataset), the
/// horizon, and its problems; Edit opens it in the dialog. Its switch
/// enables or disables it: a disabled group, muted and showing its
/// Disabled tag, isn't trained, and can still be edited; enabling it
/// queues a run for each of its algorithms.
/// An algorithm as a group's card names it: what it does with the group.
String algorithmTitle(String algorithm) => switch (algorithm) {
  'DeepAR' => 'DeepAR Forecasting',
  'XGBoost' => 'XGBoost Classification',
  _ => algorithm,
};

class _SeriesSummary extends StatelessWidget {
  const _SeriesSummary({
    required this.spec,
    required this.color,
    required this.switching,
    required this.onEdit,
    required this.onEnabled,
  });
  final TimeSeriesSpec spec;

  /// Its group's color, as on the group's tags.
  final Color color;

  /// Whether the API is enabling or disabling it now.
  final bool switching;
  final VoidCallback onEdit;
  final ValueChanged<bool> onEnabled;

  @override
  Widget build(BuildContext context) {
    final xgb = spec.xgBoost;
    final lines = <String>[
      if (xgb)
        'scores ${spec.target ?? '?'} summed over the next ${spec.horizon ?? '?'}, '
            'per ${spec.seriesKey.isEmpty ? 'table' : spec.seriesKey.join(' + ')}',
      for (final role in TimeSeriesRole.values)
        if (spec.of(role).isNotEmpty) '${role.toEach(spec.algorithms)} = ${spec.of(role).join(' + ')}',
      'freq = ${spec.frequency ?? '?'}',
      'horizon = ${spec.horizon ?? (xgb ? '?' : 'the trainer\'s choice')}',
      'a missing row = ${spec.missing == 'zero' ? '0' : 'unknown (a gap)'}',
    ];
    final on = spec.enabled;
    final tag = spec.disabledTagFqn;
    return Container(
      key: ValueKey('group-box-${spec.group}'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Aityx.bg0,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: on ? 0.6 : 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // The group, its state and its tag on the left; its switch and Edit
              // always at the top right, however long the left side is.
              Expanded(
                child: Row(
                  children: [
                  Tooltip(
                    message: 'The ${spec.group} group\'s color, on its tags in the columns above',
                    child: Opacity(
                      opacity: on ? 1 : 0.5,
                      child: Container(
                        key: ValueKey('group-color-${spec.group}'),
                        width: 10,
                        height: 10,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                      ),
                    ),
                  ),
                  Tooltip(
                    message:
                        'The ${spec.group} group: one dataset ${spec.algorithms.join(' and ')} '
                        '${spec.algorithms.length == 1 ? 'trains' : 'train'} on, forecasting '
                        '${spec.of(TimeSeriesRole.target).isEmpty ? 'no value yet' : spec.of(TimeSeriesRole.target).join(', ')}',
                    child: Text(
                      '${spec.algorithms.map(algorithmTitle).join(' + ')} · ${spec.group}',
                      style: TextStyle(fontWeight: FontWeight.bold, color: on ? null : Aityx.muted),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: spec.ready ? 'Ready to train' : 'Not ready to train: the problems below say what to fix',
                    child: Icon(
                      spec.ready ? Icons.check_circle_outline : Icons.error_outline,
                      size: 16,
                      color: spec.ready ? Aityx.green : Aityx.amber,
                    ),
                  ),
                  if (!on) ...[
                    const SizedBox(width: 8),
                    Flexible(
                      child: Tooltip(
                        message: 'The table\'s tag in OpenMetadata that disables the group',
                        child: Container(
                          key: ValueKey('disabled-chip-${spec.group}'),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Aityx.bg2,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Aityx.border),
                          ),
                          child: Text(
                            tag,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11, color: Aityx.muted, fontFamily: 'monospace'),
                          ),
                        ),
                      ),
                    ),
                  ],
                  ],
                ),
              ),
              Tooltip(
                message: on
                    ? 'Enabled: datyx trains this group with ${_its(spec.algorithms)}. '
                          'Disabling adds the tag $tag to the table in OpenMetadata, and datyx stops training it.'
                    : 'Disabled: datyx doesn\'t train this group. Enabling removes its $tag tag in '
                          'OpenMetadata, and ${queuedRuns(spec.algorithms)}; removing the tag in '
                          'OpenMetadata itself does the same.',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (switching)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 14),
                        child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    else
                      Switch(
                        key: ValueKey('enabled-${spec.table}-${spec.group}'),
                        value: on,
                        onChanged: onEnabled,
                      ),
                    SizedBox(
                      width: 64,
                      child: Text(
                        on ? 'Enabled' : 'Disabled',
                        style: TextStyle(fontSize: 12, color: on ? Aityx.fg : Aityx.muted),
                      ),
                    ),
                  ],
                ),
              ),
              Tooltip(
                message: 'Change this group\'s roles, its frequency and what a missing row means',
                child: TextButton.icon(
                  key: ValueKey('edit-group-${spec.table}-${spec.group}'),
                  onPressed: onEdit,
                  icon: const Icon(Icons.sell_outlined, size: 16),
                  label: const Text('Edit'),
                ),
              ),
            ],
          ),
          Opacity(
            opacity: on ? 1 : 0.55,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!on)
                  const Text(
                    'Not trained while the table has this tag in OpenMetadata; enabling removes it.',
                    style: TextStyle(color: Aityx.muted, fontSize: 12),
                  ),
                for (final l in lines)
                  Tooltip(
                    message: 'What the group\'s algorithms are given: their input = the column or setting it comes from',
                    child: Text(l, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                  ),
                for (final p in spec.problems)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('• $p', style: const TextStyle(color: Aityx.amber, fontSize: 12)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The runs datyx queues when a group trained by [algorithms] is enabled: one per algorithm.
String queuedRuns(List<String> algorithms) => algorithms.length == 1
    ? 'datyx queues a training run of it (${algorithms.single})'
    : 'datyx queues a run for each of its algorithms: ${algorithms.join(', ')}';

String _its(List<String> algorithms) => algorithms.length == 1
    ? 'its algorithm (${algorithms.single})'
    : 'each of its algorithms (${algorithms.join(', ')})';

/// One Kafka source: its topics in the catalogue, each with its records' fields.
class StreamCatalog extends StatefulWidget {
  const StreamCatalog({super.key, required this.api, required this.source});

  final DatyxApi api;
  final DataSource source;

  @override
  State<StreamCatalog> createState() => _StreamCatalogState();
}

class _StreamCatalogState extends State<StreamCatalog> {
  List<CatalogTopic>? _topics;
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
      final topics = await widget.api.topics(widget.source.id);
      if (!mounted) return;
      setState(() {
        _topics = topics;
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
          'Read ${synced.topics} topics, ${synced.fields} fields from the ${synced.sampled} with records'
          '${synced.removed.isEmpty ? '' : '; ${synced.removed.length} gone from the cluster'}.';
      await _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final topics = _topics;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SourceHeader(
              source: widget.source,
              busy: _busy,
              label: topics == null || topics.isEmpty ? 'Read topics' : 'Read again',
              readHelp:
                  'Reads every topic, its settings and the fields of its latest records '
                  'into OpenMetadata. Only names and types are kept, never a value',
              onRead: _sync,
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
            if (topics == null && _error == null)
              const Text('Loading the catalogue…', style: TextStyle(color: Aityx.muted))
            else if (topics != null && topics.isEmpty)
              const Text(
                'Not catalogued yet: Read topics reads its topics into OpenMetadata.',
                style: TextStyle(color: Aityx.amber),
              )
            else if (topics != null)
              for (final t in topics) _TopicTile(topic: t),
          ],
        ),
      ),
    );
  }
}

class _TopicTile extends StatelessWidget {
  const _TopicTile({required this.topic});
  final CatalogTopic topic;

  @override
  Widget build(BuildContext context) {
    final settings = [
      '${topic.partitions} ${topic.partitions == 1 ? 'partition' : 'partitions'}',
      if (topic.replicationFactor != null) 'replication ${topic.replicationFactor}',
      'kept ${topic.retentionTime == null ? 'for ever' : duration(topic.retentionTime!)}',
      if (topic.retentionSize != null) 'up to ${bytes(topic.retentionSize!)} a partition',
    ];
    return ExpansionTile(
      key: PageStorageKey(topic.fqn),
      tilePadding: EdgeInsets.zero,
      leading: const Tooltip(
        message: 'Kafka topic',
        child: Icon(Icons.topic_outlined, size: 20, color: Aityx.muted),
      ),
      expandedAlignment: Alignment.centerLeft,
      title: Row(
        children: [
          Flexible(
            child: Tooltip(
              message:
                  'Kafka topic ${topic.name}'
                  '${topic.description == null || topic.description!.isEmpty ? '' : ': ${topic.description}'}\n'
                  'In OpenMetadata: ${topic.fqn}',
              child: Text(topic.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'monospace')),
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: topic.fields.isEmpty
                ? 'No fields: the topic had no record to learn them from, or none was a JSON object'
                : 'The top-level fields of its records, learnt from the latest ones; open the row to see them',
            child: Text(
              topic.fields.isEmpty ? 'no fields read' : '${topic.fields.length} fields',
              style: const TextStyle(color: Aityx.muted, fontSize: 12),
            ),
          ),
          for (final p in topic.cleanupPolicies) ...[
            const SizedBox(width: 8),
            _PlainChip(p, help: cleanupHelp(p)),
          ],
        ],
      ),
      childrenPadding: const EdgeInsets.only(left: 40, bottom: 12),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Tooltip(
            message:
                'Its Kafka settings: partitions (records spread over them), replication '
                '(copies of each kept on brokers), and how long or how much it keeps',
            child: Text(settings.join(' · '), style: const TextStyle(color: Aityx.muted, fontSize: 12)),
          ),
        ),
        if (topic.description != null && topic.description!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(topic.description!, style: const TextStyle(color: Aityx.muted)),
          ),
        if (topic.tags.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [for (final t in topic.tags) _PlainChip(t, help: tagHelp(t))],
            ),
          ),
        if (topic.fields.isEmpty)
          const Text(
            'No record to learn the fields from yet, or none is a JSON object.',
            style: TextStyle(color: Aityx.muted, fontSize: 12),
          )
        else ...[
          if (topic.schemaType != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                'Records: ${topic.schemaType}, fields as their latest records have them',
                style: const TextStyle(color: Aityx.muted, fontSize: 12),
              ),
            ),
          for (final f in topic.fields) _FieldRow(field: f, depth: 0),
        ],
      ],
    );
  }
}

/// A field of a topic's records, its own fields under it, indented.
class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.field, required this.depth});
  final CatalogField field;
  final int depth;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: EdgeInsets.only(left: 16.0 * depth, top: 2, bottom: 2),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            SizedBox(
              width: 180 - 16.0 * depth.clamp(0, 5),
              child: Tooltip(
                message: field.children.isEmpty
                    ? 'Field ${field.name} of the records'
                    : 'Field ${field.name} of the records, holding the fields under it',
                child: Text(
                  field.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                ),
              ),
            ),
            SizedBox(
              width: 100,
              child: Tooltip(
                message: field.dataType == null
                    ? 'Its type isn\'t known'
                    : 'Its type, as the sampled records\' values fit it: ${field.dataType}',
                child: Text(
                  field.dataType ?? '?',
                  style: const TextStyle(color: Aityx.muted, fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ),
            for (final t in field.tags) _PlainChip(t, help: tagHelp(t)),
          ],
        ),
      ),
      for (final c in field.children) _FieldRow(field: c, depth: depth + 1),
    ],
  );
}

/// A tag or setting in gray, [help] saying what it is on hover.
class _PlainChip extends StatelessWidget {
  const _PlainChip(this.text, {required this.help});
  final String text;
  final String help;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: help,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Aityx.bg2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Aityx.border),
      ),
      child: Text(text, style: const TextStyle(fontSize: 11, color: Aityx.muted)),
    ),
  );
}

/// What a topic's cleanup policy does with its old records.
String cleanupHelp(String policy) => switch (policy.toLowerCase()) {
  'delete' => 'Cleanup policy delete: records older than the retention, or past its size, are removed',
  'compact' => 'Cleanup policy compact: only the latest record of each key is kept',
  _ => 'Cleanup policy $policy: what Kafka does with the topic\'s old records',
};

/// A retention in ms, as people say it: `1 day`, `12 hours`, `90 minutes`.
String duration(int ms) {
  String unit(int n, String name) => '$n $name${n == 1 ? '' : 's'}';
  const minute = 60 * 1000, hour = 60 * minute, day = 24 * hour;
  if (ms >= day && ms % day == 0) return unit(ms ~/ day, 'day');
  if (ms >= hour && ms % hour == 0) return unit(ms ~/ hour, 'hour');
  if (ms >= minute && ms % minute == 0) return unit(ms ~/ minute, 'minute');
  return '$ms ms';
}

/// A size in bytes, in the largest binary unit it reaches: `1 GiB`, `512 MiB`.
String bytes(int n) {
  const units = ['B', 'KiB', 'MiB', 'GiB', 'TiB'];
  var value = n.toDouble();
  var i = 0;
  while (value >= 1024 && i < units.length - 1) {
    value /= 1024;
    i++;
  }
  return '${value == value.roundToDouble() ? value.toInt() : value.toStringAsFixed(1)} ${units[i]}';
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
          Tooltip(
            message: '${source.type.label} source',
            child: Icon(iconForType(source.type), size: 20, color: Aityx.orangeLight),
          ),
          const SizedBox(width: 10),
          Text(source.name, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Expanded(
            child: Tooltip(
              message: 'Where it points: ${source.summary}',
              child: Text(
                source.summary,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Aityx.muted, fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ),
          Tooltip(
            message: 'datyx reads only database and Kafka sources into the catalogue so far',
            child: const Text(
              'not read yet: only databases and Kafka so far',
              style: TextStyle(color: Aityx.amber, fontSize: 12),
            ),
          ),
        ],
      ),
    ),
  );
}
