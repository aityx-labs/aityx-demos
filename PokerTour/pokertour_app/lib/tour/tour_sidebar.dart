import 'package:flutter/material.dart';

import '../game/controller.dart';
import '../sidebar/calls_panel.dart';
import '../sidebar/log_panel.dart';
import 'leaderboard_panel.dart';
import 'profile_panel.dart';
import 'tour_session.dart';

/// The sidebar beside the table, in three tabs: the leaderboard, the
/// aityx calls (with the hand log a switch away), and the player's
/// profile. It opens on Profile, and turns to it, whenever the table has
/// no aityx key that works, or the aityx light is tapped.
class TourSidebar extends StatefulWidget {
  const TourSidebar({super.key, required this.session, required this.controller});

  final TourSession session;
  final GameController controller;

  static const leaderboardTab = 0;
  static const callsTab = 1;
  static const profileTab = 2;

  @override
  State<TourSidebar> createState() => _TourSidebarState();
}

class _TourSidebarState extends State<TourSidebar> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: 3,
    vsync: this,
    initialIndex: widget.session.needsKey ? TourSidebar.profileTab : TourSidebar.leaderboardTab,
  );
  late bool _neededKey = widget.session.needsKey;
  late int _profileRequests = widget.session.profileRequests;

  TourSession get s => widget.session;

  @override
  void initState() {
    super.initState();
    s.addListener(_sessionChanged);
    widget.controller.addListener(_rebuild);
  }

  @override
  void dispose() {
    s.removeListener(_sessionChanged);
    widget.controller.removeListener(_rebuild);
    _tabs.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  /// To Profile when a key becomes needed, or when asked to.
  void _sessionChanged() {
    if (!mounted) return;
    final needs = s.needsKey;
    final asked = s.profileRequests != _profileRequests;
    if ((needs && !_neededKey) || asked) _tabs.animateTo(TourSidebar.profileTab);
    _neededKey = needs;
    _profileRequests = s.profileRequests;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          key: const Key('sidebar-tabs'),
          controller: _tabs,
          labelPadding: const EdgeInsets.symmetric(horizontal: 8),
          tabs: [
            const Tab(key: Key('tab-leaderboard'), icon: Icon(Icons.emoji_events_outlined, size: 20), text: 'Leaderboard'),
            Tab(
              key: const Key('tab-calls'),
              icon: const Icon(Icons.bolt, size: 20),
              text: 'aityx calls (${widget.controller.calls.length})',
            ),
            Tab(
              key: const Key('tab-profile'),
              icon: ListenableBuilder(
                listenable: s,
                builder: (context, _) => s.needsKey
                    ? Icon(Icons.key_off, size: 20, color: Theme.of(context).colorScheme.error)
                    : const Icon(Icons.person_outline, size: 20),
              ),
              text: 'Profile',
            ),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              ListView(
                padding: const EdgeInsets.all(16),
                children: [LeaderboardView(session: s, controller: widget.controller, compact: true)],
              ),
              _CallsAndLog(controller: widget.controller),
              ProfilePanel(session: s),
            ],
          ),
        ),
      ],
    );
  }
}

/// The aityx calls, and the hand log a switch away.
class _CallsAndLog extends StatefulWidget {
  const _CallsAndLog({required this.controller});

  final GameController controller;

  @override
  State<_CallsAndLog> createState() => _CallsAndLogState();
}

class _CallsAndLogState extends State<_CallsAndLog> {
  bool _log = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: SegmentedButton<bool>(
            key: const Key('calls-or-log'),
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: false, label: Text('Calls'), icon: Icon(Icons.bolt, size: 16)),
              ButtonSegment(value: true, label: Text('Hand log'), icon: Icon(Icons.receipt_long, size: 16)),
            ],
            selected: {_log},
            onSelectionChanged: (v) => setState(() => _log = v.first),
          ),
        ),
        Expanded(
          child: _log ? LogPanel(controller: widget.controller) : CallsPanel(controller: widget.controller),
        ),
      ],
    );
  }
}
