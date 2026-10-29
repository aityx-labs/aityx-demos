import 'package:flutter/material.dart' hide Step;

import '../app_version.dart';
import '../game/controller.dart';
import '../players/players_panel.dart';
import '../sidebar/calls_panel.dart';
import '../sidebar/log_panel.dart';
import '../engine/game.dart';
import 'controls_bar.dart';
import 'table_view.dart';
import 'winner_dialog.dart';

/// The app's one screen: the table with its controls, and beside it the
/// sidebar with the aityx calls and the hand log. On a narrow window the
/// sidebar opens from the app bar.
class TableScreen extends StatefulWidget {
  const TableScreen({super.key, required this.controller});

  final GameController controller;

  @override
  State<TableScreen> createState() => _TableScreenState();
}

class _TableScreenState extends State<TableScreen> {
  static const _sidebarWidth = 420.0;
  static const _wide = 1100.0;

  GameController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.addListener(_changed);
    if (!c.loaded) c.load();
  }

  @override
  void dispose() {
    c.removeListener(_changed);
    super.dispose();
  }

  Step? _announced;

  void _changed() {
    if (!mounted) return;
    setState(() {});
    // The tournament's end, once per tournament.
    if (c.lastStep case final TournamentOver over when over != _announced) {
      _announced = over;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showWinner(context, c, over);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final wide = MediaQuery.sizeOf(context).width >= _wide;
    final sidebar = _Sidebar(controller: c);
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.style, color: scheme.primary),
            const SizedBox(width: 10),
            const Text(AppVersion.title),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                'every player is a set of rules, run on aityx',
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        actions: [
          if (AppVersion.version.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Text(
                  AppVersion.version,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.outline,
                  ),
                ),
              ),
            ),
          if (!wide)
            IconButton(
              tooltip: 'aityx calls and hand log',
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (context) => DraggableScrollableSheet(
                  expand: false,
                  initialChildSize: 0.8,
                  builder: (context, _) => _Sidebar(controller: c),
                ),
              ),
              icon: const Icon(Icons.receipt_long),
            ),
        ],
      ),
      body: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                if (!c.loaded)
                  const LinearProgressIndicator()
                else if (c.loadError != null)
                  _Banner(
                    text: 'Could not load the strategies: ${c.loadError}',
                    error: true,
                    action: TextButton(
                      onPressed: c.load,
                      child: const Text('Retry'),
                    ),
                  )
                else if (c.error != null)
                  _Banner(text: c.error!, error: true),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: TableView(controller: c),
                  ),
                ),
                ControlsBar(
                  controller: c,
                  onPlayers: () => showPlayers(context, c),
                ),
              ],
            ),
          ),
          if (wide)
            Container(
              width: _sidebarWidth,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                border: Border(left: BorderSide(color: scheme.outline)),
              ),
              child: sidebar,
            ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          TabBar(
            tabs: [
              Tab(text: 'aityx calls (${controller.calls.length})'),
              const Tab(text: 'Hand log'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                CallsPanel(controller: controller),
                LogPanel(controller: controller),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, required this.error, this.action});

  final String text;
  final bool error;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = error ? scheme.error : scheme.primary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      color: color.withValues(alpha: 0.12),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
          ?action,
        ],
      ),
    );
  }
}
