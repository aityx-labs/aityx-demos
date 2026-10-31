import 'package:flutter/material.dart';

import '../api/datyx_api.dart';
import '../theme.dart';

/// The pandas offsets offered for a table's frequency; any other can be typed.
const frequencies = ['15min', '1h', '1D', '1W', '1MS'];

/// Tags one table's columns with their roles in a forecast (the TimeSeries
/// tags DeepAR reads), its frequency and what a missing row means, starting
/// from the tags it has. Save sends them (`PUT .../timeseries`) and shows
/// what the API makes of them; it closes, answering the API's spec, once
/// the table is ready.
class TimeSeriesDialog extends StatefulWidget {
  const TimeSeriesDialog({
    super.key,
    required this.api,
    required this.sourceId,
    required this.table,
  });

  final DatyxApi api;
  final int sourceId;
  final CatalogTable table;

  @override
  State<TimeSeriesDialog> createState() => _TimeSeriesDialogState();
}

class _TimeSeriesDialogState extends State<TimeSeriesDialog> {
  late final Map<TimeSeriesRole, List<String>> _roles;
  late final TextEditingController _frequency;
  late String _missing;
  TimeSeriesSpec? _answer;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _roles = {for (final role in TimeSeriesRole.values) role: <String>[]};
    for (final c in widget.table.columns) {
      for (final tag in c.tags) {
        final role = TimeSeriesRole.ofTag(tag);
        if (role != null) _roles[role]!.add(c.name);
      }
    }
    _frequency = TextEditingController(
      text: '${widget.table.properties['timeSeriesFrequency'] ?? ''}',
    );
    _missing = '${widget.table.properties['timeSeriesMissing'] ?? 'unknown'}';
  }

  @override
  void dispose() {
    _frequency.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final spec = await widget.api.setTimeSeries(
        widget.sourceId,
        TimeSeriesRoles(
          table: widget.table.fqn,
          columns: _roles,
          frequency: _frequency.text.trim().isEmpty ? null : _frequency.text.trim(),
          missing: _missing,
        ),
      );
      if (!mounted) return;
      if (spec.ready) {
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
      title: Text('Tag ${widget.table.qualifiedName} for DeepAR'),
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
                'themselves, so they can be edited there too.',
                style: TextStyle(color: Aityx.muted),
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
                  role.deepAr + (role.single ? ', one' : ''),
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
