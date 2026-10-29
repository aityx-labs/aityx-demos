import 'package:flutter/material.dart';

import '../api/datyx_api.dart';
import '../theme.dart';

/// The form for a new data source: its name and type, then the access
/// details of that type, as `POST /api/datasources` takes them. Answers a
/// [NewDataSource], or null when dismissed. The API validates; this only
/// asks for what the type requires.
class AddDataSourceDialog extends StatefulWidget {
  const AddDataSourceDialog({super.key});

  static Future<NewDataSource?> show(BuildContext context) =>
      showDialog<NewDataSource>(context: context, builder: (_) => const AddDataSourceDialog());

  @override
  State<AddDataSourceDialog> createState() => _AddDataSourceDialogState();
}

class _AddDataSourceDialogState extends State<AddDataSourceDialog> {
  DataSourceType _type = DataSourceType.database;
  final _name = TextEditingController();
  final _description = TextEditingController();
  // One controller per field, keyed as the API names the field.
  final _fields = <String, TextEditingController>{
    for (final key in const [
      'engine', 'host', 'port', 'database', 'username', 'password',
      'bucket', 'region', 'endpoint', 'prefix', 'accessKeyId', 'secretAccessKey',
      'path',
    ])
      key: TextEditingController(),
  };
  String? _problem;

  @override
  void initState() {
    super.initState();
    _fields['engine']!.text = 'postgresql';
    _fields['port']!.text = '5432';
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  String? _text(String key) {
    final value = _fields[key]!.text.trim();
    return value.isEmpty ? null : value;
  }

  /// A secret as typed, spaces and all; null when empty.
  String? _secret(String key) {
    final value = _fields[key]!.text;
    return value.isEmpty ? null : value;
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _problem = 'A name is needed.');
      return;
    }
    final Map<String, Object?> details;
    switch (_type) {
      case DataSourceType.database:
        final port = int.tryParse(_fields['port']!.text.trim());
        if (_text('engine') == null || _text('host') == null || port == null || _text('database') == null) {
          setState(() => _problem = 'Engine, host, a numeric port and the database are needed.');
          return;
        }
        details = {
          'engine': _text('engine'),
          'host': _text('host'),
          'port': port,
          'database': _text('database'),
          'username': _text('username'),
          'password': _secret('password'),
        };
      case DataSourceType.s3:
        if (_text('bucket') == null) {
          setState(() => _problem = 'The bucket is needed.');
          return;
        }
        details = {
          'bucket': _text('bucket'),
          'region': _text('region'),
          'endpoint': _text('endpoint'),
          'prefix': _text('prefix'),
          'accessKeyId': _text('accessKeyId'),
          'secretAccessKey': _secret('secretAccessKey'),
        };
      case DataSourceType.filesystem:
        if (_text('path') == null) {
          setState(() => _problem = 'The path is needed.');
          return;
        }
        details = {'path': _text('path')};
    }
    details.removeWhere((_, v) => v == null);
    Navigator.of(context).pop(NewDataSource(
      name: name,
      type: _type,
      description: _description.text.trim(),
      details: details,
    ));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add a data source'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<DataSourceType>(
              segments: [
                for (final t in DataSourceType.values)
                  ButtonSegment(value: t, label: Text(t.label), icon: Icon(iconForType(t), size: 16)),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() {
                _type = s.first;
                _problem = null;
              }),
            ),
            const SizedBox(height: 12),
            _field(_name, 'Name', key: 'ds-name', autofocus: true),
            _field(_description, 'Description (optional)', key: 'ds-description'),
            const SizedBox(height: 8),
            ..._detailFields(),
            if (_problem != null) ...[
              const SizedBox(height: 8),
              Text(_problem!, style: const TextStyle(color: Aityx.red)),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
      FilledButton(key: const Key('ds-submit'), onPressed: _submit, child: const Text('Add')),
    ],
  );

  List<Widget> _detailFields() => switch (_type) {
    DataSourceType.database => [
      Row(children: [
        Expanded(child: _field(_fields['engine']!, 'Engine (postgresql, mysql, ...)')),
        const SizedBox(width: 8),
        Expanded(child: _field(_fields['port']!, 'Port', number: true)),
      ]),
      _field(_fields['host']!, 'Host'),
      _field(_fields['database']!, 'Database'),
      Row(children: [
        Expanded(child: _field(_fields['username']!, 'Username')),
        const SizedBox(width: 8),
        Expanded(child: _field(_fields['password']!, 'Password', secret: true)),
      ]),
    ],
    DataSourceType.s3 => [
      _field(_fields['bucket']!, 'Bucket'),
      Row(children: [
        Expanded(child: _field(_fields['region']!, 'Region')),
        const SizedBox(width: 8),
        Expanded(child: _field(_fields['prefix']!, 'Prefix (a folder in the bucket)')),
      ]),
      _field(_fields['endpoint']!, 'Endpoint (S3-compatible stores only)'),
      Row(children: [
        Expanded(child: _field(_fields['accessKeyId']!, 'Access key id')),
        const SizedBox(width: 8),
        Expanded(child: _field(_fields['secretAccessKey']!, 'Secret access key', secret: true)),
      ]),
    ],
    DataSourceType.filesystem => [
      _field(_fields['path']!, 'Path', key: 'ds-path'),
    ],
  };

  Widget _field(
    TextEditingController controller,
    String label, {
    String? key,
    bool secret = false,
    bool number = false,
    bool autofocus = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: TextField(
      key: key == null ? null : Key(key),
      controller: controller,
      autofocus: autofocus,
      obscureText: secret,
      keyboardType: number ? TextInputType.number : null,
      decoration: InputDecoration(labelText: label),
      onSubmitted: (_) => _submit(),
    ),
  );

}

/// The icon of a kind of data source.
IconData iconForType(DataSourceType type) => switch (type) {
  DataSourceType.database => Icons.storage,
  DataSourceType.s3 => Icons.cloud_outlined,
  DataSourceType.filesystem => Icons.folder_outlined,
};
