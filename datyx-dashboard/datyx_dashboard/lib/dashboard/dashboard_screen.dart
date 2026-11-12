import 'dart:async';

import 'package:flutter/material.dart';

import '../api/datyx_api.dart';
import '../app_version.dart';
import '../auth/auth_controller.dart';
import '../persist/address.dart';
import '../theme.dart';
import 'aityx_tab.dart';
import 'calls_panel.dart';
import 'catalog_tab.dart';
import 'data_sources_card.dart';
import 'health_tab.dart';
import 'profile_tab.dart';
import 'inference_tab.dart';
import 'training_tab.dart';
import 'user_menu.dart';

/// The dashboard's tabs, in their order. The page's address keeps the open
/// one by its [name] (`?tab=catalog`), and its key is `tab-<name>`.
enum DashboardTab {
  sources('Data sources'),
  catalog('Catalog'),
  training('Training'),
  inference('Inference'),
  aityx('aityx'),
  audit('Audit'),
  health('Health'),
  profile('Profile');

  const DashboardTab(this.label);

  final String label;

  /// The tab [name] names; Data sources when none does.
  static DashboardTab named(String? name) =>
      values.firstWhere((t) => t.name == name, orElse: () => sources);
}

/// The dashboard, in eight tabs ([DashboardTab]): Data sources, the ones on
/// record; Catalog, what datyx makes of their data; Training, the models
/// datyx trains on it, their runs and results; Inference, the account of
/// the calls to those models, and a place to try one; aityx, the account of
/// the calls datyx routes to aityx; Audit, every call made
/// to the API; Health, the system's status as the API reports it and this
/// build's version; Profile, the caller's profile and its identities. The
/// open tab is kept in the page's address, so a reload opens it again.
/// Refreshes the status, the data sources and the profile every
/// [refreshEvery]. With authentication on, the data sources and the
/// profile wait for a signed-in user ([auth]); the rest is open.
///
/// Nothing the API secures is asked before the sign-in is settled
/// ([AuthController.settled]: the API said whether it wants one, and a
/// session kept from before a reload is restored): until then only the
/// Audit and Health tabs are built, the others wait, so a tab's first call
/// goes out as whoever is signed in.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.api,
    required this.auth,
    this.refreshEvery = const Duration(seconds: 15),
    this.initialTab,
  });

  final DatyxApi api;
  final AuthController auth;
  final Duration refreshEvery;

  /// The tab open at start; the one the page's address names when null.
  final DashboardTab? initialTab;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: DashboardTab.values.length,
    initialIndex: (widget.initialTab ?? DashboardTab.named(Address.tab)).index,
    vsync: this,
  )..addListener(_tabChanged);

  SystemStatus? _status;
  String? _statusError;
  List<DataSource> _sources = const [];
  Profile? _profile;
  Me? _me;
  bool _busy = false;
  bool _settled = false;
  bool _signedIn = false;

  /// Whether who calls changed during a refresh: another follows it.
  bool _stale = false;

  /// Counts the changes of who calls ([_authChanged]): an answer asked for
  /// before the latest is the caller before's, and is dropped.
  int _callers = 0;
  Timer? _timer;

  /// Whether it is still unknown who calls: the API's sign-in settings
  /// haven't come, so no secured call can be made yet.
  bool get _waiting => !widget.auth.settled;

  /// Whether the API would refuse the secured calls right now.
  bool get _locked => widget.auth.enabled && !widget.auth.signedIn;

  @override
  void initState() {
    super.initState();
    _settled = widget.auth.settled;
    _signedIn = widget.auth.signedIn;
    widget.auth.addListener(_authChanged);
    _refresh();
    if (widget.refreshEvery > Duration.zero) {
      _timer = Timer.periodic(widget.refreshEvery, (_) => _refresh());
    }
  }

  @override
  void dispose() {
    widget.auth.removeListener(_authChanged);
    _timer?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  /// Keeps the open tab in the address, for the next reload.
  void _tabChanged() {
    if (!_tabs.indexIsChanging) {
      Address.showTab(DashboardTab.values[_tabs.index].name);
    }
  }

  void _authChanged() {
    final settled = widget.auth.settled;
    final signedIn = widget.auth.signedIn;
    if (settled == _settled && signedIn == _signedIn) return;
    // The API answered its sign-in settings: when its status had failed
    // (the API down at start), it is asked again, so its error doesn't
    // stay above what loads now.
    final askStatus = settled && !_settled && _statusError != null;
    // The sign-in settling, signing in or out: the tabs are built again as
    // whoever calls now (a tab of each caller, [_caller]: nothing of the
    // one before stays, nor any of its timers), and the API is asked again
    // for what it secures, since it shows them something else.
    _callers++;
    setState(() {
      _settled = settled;
      _signedIn = signedIn;
      if (!signedIn) {
        _me = null;
        _profile = null;
        _sources = const [];
      }
    });
    if (_busy) {
      // The refresh under way may be past its secured calls already.
      _stale = true;
    } else {
      _refresh(status: askStatus);
    }
  }

  /// Who calls the API now, as a key: each secured tab is made anew when
  /// it changes, so a tab never shows the previous caller's data, nor goes
  /// on asking for them with a timer of its own.
  Key get _caller => ValueKey(
    widget.auth.enabled
        ? (widget.auth.signedIn ? 'user:${widget.auth.user?.email ?? widget.auth.user?.name ?? '?'}' : 'nobody')
        : 'local',
  );

  /// Asks the API again: the [status], open to all, then what it secures,
  /// and that once more when who calls changed meanwhile.
  Future<void> _refresh({bool status = true}) async {
    if (_busy) return;
    setState(() => _busy = true);
    if (status) await _askStatus();
    do {
      if (!mounted) return;
      _stale = false;
      await _askSecured();
    } while (_stale);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _askStatus() async {
    try {
      final status = await widget.api.status();
      if (!mounted) return;
      setState(() {
        _status = status;
        _statusError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _statusError = e.toString());
    }
  }

  /// What the API secures: asked once it is known who calls, and unless
  /// the API would refuse them.
  ///
  /// Each call is made only while the caller is the one this round began
  /// with, and its answer is kept only then: one that comes back after a
  /// sign-out or another sign-in is the caller before's, and goes (the
  /// round that follows asks as whoever calls now).
  Future<void> _askSecured() async {
    final callers = _callers;
    bool same() => mounted && callers == _callers;
    if (!_waiting && !_locked) {
      try {
        final sources = await widget.api.dataSources();
        if (same()) setState(() => _sources = sources);
      } catch (_) {
        // The call is in the audit; the list keeps what it had.
      }
      if (!same() || _locked) return;
      try {
        final profile = await widget.api.profile();
        if (same()) setState(() => _profile = profile);
      } catch (_) {
        // Likewise.
      }
    }
    if (!same()) return;
    if (widget.auth.enabled && widget.auth.signedIn && _me == null) {
      try {
        final me = await widget.api.me();
        if (same()) setState(() => _me = me);
      } catch (_) {
        // In the audit.
      }
    }
  }

  /// A tab whose data the API secures: built once the sign-in is settled,
  /// so that it starts, and asks, as whoever is signed in.
  Widget _secured(Widget Function() tab) => _waiting
      ? _WaitingForSignIn(statusError: _statusError)
      : KeyedSubtree(key: _caller, child: tab());

  Future<void> _addSource(NewDataSource source) async {
    try {
      await widget.api.addDataSource(source);
      await _refresh();
    } catch (e) {
      _tell('$e');
    }
  }

  Future<void> _removeSource(DataSource source) async {
    try {
      await widget.api.removeDataSource(source.id);
      await _refresh();
    } catch (e) {
      _tell('$e');
    }
  }

  void _tell(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final log = widget.api.log;
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppVersion.title),
        actions: [
          UserMenu(auth: widget.auth),
          const SizedBox(width: 12),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _busy ? null : _refresh,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(kTextTabBarHeight),
          child: TabBar(
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            padding: const EdgeInsets.only(left: 4),
            tabs: [
              for (final tab in DashboardTab.values) Tab(key: Key('tab-${tab.name}'), text: tab.label),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        // In the order of [DashboardTab].
        children: [
          _secured(
            () => ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_statusError != null) ApiDownLine(_statusError!),
                DataSourcesCard(
                  sources: _sources,
                  locked: _locked,
                  onAdd: _addSource,
                  onRemove: _removeSource,
                ),
              ],
            ),
          ),
          _secured(
            () => CatalogTab(
              api: widget.api,
              sources: _sources,
              locked: _locked,
              statusError: _statusError,
            ),
          ),
          _secured(
            () => TrainingTab(
              api: widget.api,
              locked: _locked,
              statusError: _statusError,
            ),
          ),
          _secured(
            () => InferenceTab(
              api: widget.api,
              locked: _locked,
              statusError: _statusError,
            ),
          ),
          _secured(
            () => AityxTab(
              api: widget.api,
              locked: _locked,
              statusError: _statusError,
            ),
          ),
          CallsPanel(log: log),
          HealthTab(
            status: _status,
            statusError: _statusError,
            auth: widget.auth,
            me: _me,
            refreshEvery: widget.refreshEvery,
          ),
          _secured(
            () => ProfileTab(
              profile: _profile,
              locked: _locked,
              statusError: _statusError,
            ),
          ),
        ],
      ),
    );
  }
}

/// What a secured tab shows until the sign-in is settled: nothing is asked
/// yet, so there is nothing to show but that, and the API being down.
class _WaitingForSignIn extends StatelessWidget {
  const _WaitingForSignIn({required this.statusError});

  final String? statusError;

  @override
  Widget build(BuildContext context) => ListView(
    key: const Key('waiting-for-sign-in'),
    padding: const EdgeInsets.all(16),
    children: [
      if (statusError != null) ApiDownLine(statusError!),
      const Text(
        'Waiting for the API\'s sign-in settings (GET /api/auth/config).',
        style: TextStyle(color: Aityx.muted),
      ),
    ],
  );
}
