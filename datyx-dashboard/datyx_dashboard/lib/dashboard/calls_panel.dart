import 'dart:convert';

import 'package:flutter/material.dart';

import '../api/datyx_api.dart';
import '../theme.dart';

/// The Audit tab: every call to the API, newest first, with method, path,
/// status and time, and, expanded, the request and the response bodies.
class CallsPanel extends StatelessWidget {
  const CallsPanel({super.key, required this.log});

  final CallLog log;

  @override
  Widget build(BuildContext context) => Material(
    color: Aityx.bg0,
    child: ListenableBuilder(
      listenable: log,
      builder: (context, _) {
        final calls = log.calls;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Row(
                children: [
                  Text('API calls', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(width: 10),
                  // Shrinks first, so the Clear button stays in the panel.
                  Expanded(
                    child: Text(
                      calls.isEmpty
                          ? 'the latest ${CallLog.keep} are kept'
                          : '${calls.length} of the latest ${CallLog.keep} kept',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Aityx.muted, fontSize: 12),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Clear',
                    onPressed: calls.isEmpty ? null : log.clear,
                    icon: const Icon(Icons.delete_outline, size: 18),
                  ),
                ],
              ),
            ),
            Expanded(
              child: calls.isEmpty
                  ? const Center(
                      child: Text('No calls yet.', style: TextStyle(color: Aityx.muted)),
                    )
                  : ListView.builder(
                      itemCount: calls.length,
                      itemBuilder: (context, i) => _CallTile(call: calls[i]),
                    ),
            ),
          ],
        );
      },
    ),
  );
}

class _CallTile extends StatelessWidget {
  const _CallTile({required this.call});
  final ApiCall call;

  @override
  Widget build(BuildContext context) {
    final color = call.pending
        ? Aityx.amber
        : call.ok
            ? Aityx.green
            : Aityx.red;
    final status = call.pending
        ? '…'
        : call.error != null
            ? 'error'
            : '${call.status}';
    final time = call.startedAt.toLocal().toString().substring(11, 19);
    final elapsed = call.elapsed == null ? '' : '${call.elapsed!.inMilliseconds} ms';
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        dense: true,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        title: Row(
          children: [
            Text(
              call.method,
              style: TextStyle(
                color: color,
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                call.path,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
            Text(status, style: TextStyle(color: color, fontSize: 12)),
          ],
        ),
        subtitle: Text(
          [time, if (elapsed.isNotEmpty) elapsed].join(' · '),
          style: const TextStyle(color: Aityx.muted, fontSize: 11),
        ),
        children: [
          if (call.requestBody != null) _Body('Request', call.requestBody!),
          if (call.error != null)
            _Body('Error', call.error!)
          else if (call.responseBody != null)
            _Body('Response', call.responseBody!),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body(this.label, this.text);
  final String label;
  final String text;

  static String pretty(String text) {
    try {
      return const JsonEncoder.withIndent('  ').convert(jsonDecode(text));
    } catch (_) {
      return text;
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: Aityx.muted, fontSize: 11)),
      const SizedBox(height: 4),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Aityx.bg1,
          border: Border.all(color: Aityx.border),
          borderRadius: BorderRadius.circular(6),
        ),
        child: SelectableText(
          pretty(text),
          style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
        ),
      ),
      const SizedBox(height: 8),
    ],
  );
}
