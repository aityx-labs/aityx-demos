import 'package:flutter/material.dart';

import '../api/datyx_api.dart';
import '../theme.dart';

/// The pandas offsets offered for a table's frequency; any other can be typed.
const frequencies = ['15min', '1h', '1D', '1W', '1MS'];

/// The pandas offsets offered for a table's horizon; any other can be typed.
const horizons = ['24h', '7D', '30D', '90D'];

/// Tags one group of a table's columns with their roles in a forecast (the
/// TimeSeries tags), the algorithm that trains the group (DeepAR or
/// XGBoost, a tag on the table), and the table's frequency, horizon and
/// what a missing row means, which its groups share. Editing a group starts from
/// the API's reading of it ([spec]); a new one is named here and starts
/// from [startFrom]'s roles but its Target, or from none. Save sends them
/// (`PUT .../timeseries`) and shows what the API makes of them; it closes,
/// answering the API's spec, once the group is ready. Remove group sends
/// the group with no roles.
class TimeSeriesDialog extends StatefulWidget {
  const TimeSeriesDialog({
    super.key,
    required this.api,
    required this.sourceId,
    required this.table,
    this.spec,
    this.startFrom,
    this.groups = const [],
  });

  final DatyxApi api;
  final int sourceId;
  final CatalogTable table;

  /// The group to edit; null for a new one.
  final TimeSeriesSpec? spec;

  /// A new group's starting roles: another group's, but its Target.
  final TimeSeriesSpec? startFrom;

  /// The groups the table has, which a new one can't be named after.
  final List<String> groups;

  @override
  State<TimeSeriesDialog> createState() => _TimeSeriesDialogState();
}

class _TimeSeriesDialogState extends State<TimeSeriesDialog> {
  late final Map<TimeSeriesRole, List<String>> _roles;
  late final TextEditingController _frequency;
  late final TextEditingController _horizon;
  late final TextEditingController _group;
  late String _missing;
  late String _algorithm;
  TimeSeriesSpec? _answer;
  String? _error;
  bool _saving = false;
  bool _confirmRemove = false;

  bool get _isNew => widget.spec == null;

  @override
  void initState() {
    super.initState();
    final from = widget.spec ?? widget.startFrom;
    _roles = {
      for (final role in TimeSeriesRole.values)
        role: [
          if (from != null && !(_isNew && role == TimeSeriesRole.target)) ...from.of(role),
        ],
    };
    _group = TextEditingController(
      text: widget.spec?.group ?? (widget.groups.isEmpty ? defaultGroup : ''),
    );
    _frequency = TextEditingController(
      text: '${widget.table.properties['timeSeriesFrequency'] ?? ''}',
    );
    _horizon = TextEditingController(
      text: '${widget.table.properties['timeSeriesHorizon'] ?? ''}',
    );
    _missing = '${widget.table.properties['timeSeriesMissing'] ?? 'unknown'}';
    _algorithm = from?.algorithm ?? deepArAlgorithm;
  }

  @override
  void dispose() {
    _frequency.dispose();
    _horizon.dispose();
    _group.dispose();
    super.dispose();
  }

  Future<void> _save({bool remove = false}) async {
    final group = _group.text.trim().isEmpty ? defaultGroup : _group.text.trim();
    if (_isNew && widget.groups.contains(group)) {
      setState(() => _error = 'The table has a group named $group already: edit it from its own box.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final spec = await widget.api.setTimeSeries(
        widget.sourceId,
        TimeSeriesRoles(
          table: widget.table.fqn,
          group: group,
          algorithm: _algorithm,
          columns: remove ? const {} : _roles,
          frequency: _frequency.text.trim().isEmpty ? null : _frequency.text.trim(),
          horizon: _horizon.text.trim().isEmpty ? null : _horizon.text.trim(),
          missing: _missing,
        ),
      );
      if (!mounted) return;
      if (spec.ready || remove) {
        Navigator.of(context).pop(spec);
        return;
      }
      setState(() => _answer = spec);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toggle(TimeSeriesRole role, String column, bool on) {
    setState(() {
      final list = _roles[role]!;
      if (role.single) list.clear();
      if (on && !list.contains(column)) list.add(column);
      if (!on) list.remove(column);
    });
  }

  @override
  Widget build(BuildContext context) {
    final answer = _answer;
    return AlertDialog(
      title: Text(
        _isNew
            ? 'Tag ${widget.table.qualifiedName} for $_algorithm'
            : 'Tag ${widget.table.qualifiedName} for $_algorithm: ${widget.spec!.group}',
      ),
      content: SizedBox(
        width: 720,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Pick each role\'s columns. They are saved as tags of the '
                'TimeSeries classification in OpenMetadata, on the columns '
                'themselves, so they can be edited there too. A table can '
                'hold several series, each a group with its own roles '
                '(TimeSeries.acute.Target) and the algorithm that trains it, '
                'a tag on the table (TimeSeries.acute.XGBoost); the frequency, '
                'horizon and missing rows are the table\'s, for all of them.',
                style: TextStyle(color: Aityx.muted),
              ),
              const SizedBox(height: 12),
              if (_isNew) ...[
                Row(
                  children: [
                    const SizedBox(width: 170, child: Text('Group', style: TextStyle(fontWeight: FontWeight.bold))),
                    SizedBox(
                      width: 220,
                      child: TextField(
                        key: const ValueKey('group'),
                        controller: _group,
                        decoration: const InputDecoration(isDense: true, hintText: 'acute'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'letters, digits, _ and -; default: tagged without a group',
                        style: TextStyle(color: Aityx.muted, fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  const SizedBox(width: 170, child: Text('Trained by', style: TextStyle(fontWeight: FontWeight.bold))),
                  SegmentedButton<String>(
                    key: const ValueKey('algorithm'),
                    segments: const [
                      ButtonSegment(value: deepArAlgorithm, label: Text('DeepAR'), icon: Icon(Icons.show_chart)),
                      ButtonSegment(
                        value: xgBoostAlgorithm,
                        label: Text('XGBoost'),
                        icon: Icon(Icons.account_tree_outlined),
                      ),
                    ],
                    selected: {_algorithm},
                    onSelectionChanged: (v) => setState(() => _algorithm = v.first),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _algorithm == xgBoostAlgorithm
                          ? 'a score per series: the Target summed over the horizon'
                          : 'a forecast of each series, step by step',
                      style: const TextStyle(color: Aityx.muted, fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              for (final role in TimeSeriesRole.values) _roleRow(role),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(width: 170, child: Text('Frequency', style: TextStyle(fontWeight: FontWeight.bold))),
                  SizedBox(
                    width: 110,
                    child: TextField(
                      key: const ValueKey('frequency'),
                      controller: _frequency,
                      decoration: const InputDecoration(isDense: true, hintText: '1h'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      children: [
                        for (final f in frequencies)
                          ActionChip(
                            key: ValueKey('frequency-$f'),
                            label: Text(f),
                            onPressed: () => setState(() => _frequency.text = f),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 170,
                    child: Text(
                      _algorithm == xgBoostAlgorithm ? 'Horizon (required)' : 'Horizon',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  SizedBox(
                    width: 110,
                    child: TextField(
                      key: const ValueKey('horizon'),
                      controller: _horizon,
                      decoration: const InputDecoration(isDense: true, hintText: '30D'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      children: [
                        for (final h in horizons)
                          ActionChip(
                            key: ValueKey('horizon-$h'),
                            label: Text(h),
                            onPressed: () => setState(() => _horizon.text = h),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const SizedBox(width: 170, child: Text('A missing row', style: TextStyle(fontWeight: FontWeight.bold))),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'zero', label: Text('counts as 0')),
                      ButtonSegment(value: 'unknown', label: Text('is unknown')),
                    ],
                    selected: {_missing},
                    onSelectionChanged: (v) => setState(() => _missing = v.first),
                  ),
                ],
              ),
              if (answer != null) ...[
                const SizedBox(height: 16),
                Text(
                  answer.ready ? 'Ready to train.' : 'Saved, but not trainable yet:',
                  style: TextStyle(color: answer.ready ? Aityx.green : Aityx.amber, fontWeight: FontWeight.bold),
                ),
                for (final p in answer.problems)
                  Text('• $p', style: const TextStyle(color: Aityx.amber)),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Aityx.red)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (!_isNew)
          TextButton(
            key: const ValueKey('remove-group'),
            onPressed: _saving
                ? null
                : () => _confirmRemove ? _save(remove: true) : setState(() => _confirmRemove = true),
            style: TextButton.styleFrom(foregroundColor: Aityx.red),
            child: Text(_confirmRemove ? 'Remove its tags: sure?' : 'Remove group'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(answer),
          child: Text(answer == null ? 'Cancel' : 'Close'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Save tags'),
        ),
      ],
    );
  }

  Widget _roleRow(TimeSeriesRole role) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 170,
          child: Tooltip(
            message: role.help,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(role.tag, style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(
                  role.to(_algorithm) + (role.single ? ', one' : ''),
                  style: const TextStyle(color: Aityx.muted, fontFamily: 'monospace', fontSize: 11),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in widget.table.columns)
                FilterChip(
                  key: ValueKey('${role.tag}-${c.name}'),
                  label: Text('${c.name} · ${c.dataType ?? '?'}', style: const TextStyle(fontSize: 12)),
                  selected: _roles[role]!.contains(c.name),
                  onSelected: (on) => _toggle(role, c.name, on),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}
