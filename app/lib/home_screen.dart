import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';
import 'config.dart';
import 'gps_tracker.dart';
import 'models.dart';
import 'pin_screen.dart';
import 'steps_service.dart';
import 'widgets/quest_card.dart';
import 'widgets/status_tabs.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _api = Api();
  final _tracker = GpsTracker();
  final _stepsService = StepsService();
  Timer? _snapshotTimer;

  String _filter = 'available'; // which chip is selected
  List<Quest> _quests = [];
  int _xp = 0;
  bool _loading = true;
  String? _error;
  final Set<String> _busy = {}; // quest ids with a request in flight (prevents double taps)

  // Latest Health Connect reading per quest (null = no reading), and why it failed.
  final Map<String, int> _liveSteps = {};
  final Map<String, StepsResult> _stepsProblem = {};

  @override
  void initState() {
    super.initState();
    _tracker.addListener(_onTrackerChanged);
    _load();
  }

  @override
  void dispose() {
    _snapshotTimer?.cancel();
    _tracker.removeListener(_onTrackerChanged);
    _tracker.stop();
    super.dispose();
  }

  void _onTrackerChanged() => setState(() {});

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await _api.getQuests();
      setState(() {
        _quests = r.quests;
        _xp = r.xp;
      });
      // Refresh steps for ongoing step quests, without popping a permission dialog.
      for (final q in _quests.where((q) => q.status == 'ongoing' && q.targetSteps != null)) {
        unawaited(_refreshSteps(q, askPermission: false));
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Quest? _questById(String id) => _quests.where((x) => x.id == id).firstOrNull;

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 5)));

  Future<void> _withBusy(String id, Future<void> Function() action) async {
    if (_busy.contains(id)) return;
    setState(() => _busy.add(id));
    try {
      await action();
    } on ApiException catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  // ---------- steps ----------
  /// Reads Health Connect steps for [startedAt, now]. Never substitutes a value on failure.
  Future<StepsResult?> _refreshSteps(Quest q, {bool askPermission = true}) async {
    final start = q.startedAt;
    if (q.targetSteps == null || start == null) return null;
    final r = await _stepsService.stepsBetween(start, DateTime.now(), askPermission: askPermission);
    if (!mounted) return r;
    setState(() {
      if (r.steps != null) {
        _liveSteps[q.id] = r.steps!;
        _stepsProblem.remove(q.id);
      } else {
        _liveSteps.remove(q.id);
        _stepsProblem[q.id] = r;
      }
    });
    return r;
  }

  // ---------- actions ----------
  Future<void> _accept(Quest q) => _withBusy(q.id, () async {
        await _api.accept(q.id);
        await _load();
        setState(() => _filter = 'ongoing');
        final fresh = _questById(q.id)!;
        if (fresh.targetSteps != null) await _refreshSteps(fresh); // asks for step permission once
        if (fresh.needsTracking) await _startTracking(fresh);
      });

  Future<void> _startTracking(Quest q) async {
    if (_tracker.isTracking && _tracker.questId != q.id) await _stopTracking();
    final problem = await _tracker.start(q.id,
        startDistanceM: q.distanceM,
        startFixes: q.fixCount,
        startRejected: q.rejectedCount,
        startMocked: q.mockedCount);
    if (problem != null) {
      _toast(problem);
      return;
    }
    _snapshotTimer?.cancel();
    _snapshotTimer = Timer.periodic(AppConfig.snapshotEvery, (_) => _saveSnapshot(silent: true));
  }

  Future<void> _stopTracking() async {
    _snapshotTimer?.cancel();
    await _tracker.stop();
    await _saveSnapshot();
    await _load();
  }

  /// Saves distance + steps + route counts so progress survives an app restart.
  /// Informational only: never completes a quest or awards XP.
  Future<void> _saveSnapshot({bool silent = false}) async {
    final id = _tracker.questId;
    if (id == null) return;
    final q = _questById(id);
    if (q != null) await _refreshSteps(q, askPermission: false);
    try {
      await _api.saveProgress(id, distanceM: _tracker.distanceM, steps: _liveSteps[id], route: _tracker.routeSummary);
    } on ApiException catch (e) {
      if (!silent) _toast('Progress not saved: ${e.message}');
    }
  }

  Future<void> _openPin(Quest q) async {
    final saved = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => PinScreen(quest: q, api: _api)));
    if (saved == true) {
      _toast('Pin saved. Now tap Validate while you are still at the café.');
      await _load();
    }
  }

  /// Collects evidence and asks the server to validate. The server decides; we only display.
  Future<void> _validate(Quest q) => _withBusy(q.id, () async {
        final tracking = _tracker.isTracking && _tracker.questId == q.id;

        // 1. Fresh GPS fix (required for every quest).
        _toast('Getting a fresh GPS fix…');
        final Map<String, dynamic> fix;
        try {
          fix = fixToJson(await getFreshFix());
        } catch (e) {
          _toast(e.toString());
          return;
        }

        // 2. Steps for the quest window, straight from Health Connect (null if unavailable).
        Map<String, dynamic>? steps;
        if (q.targetSteps != null) {
          final end = DateTime.now();
          final r = await _stepsService.stepsBetween(q.startedAt!, end);
          if (r.steps != null) {
            steps = {'count': r.steps, 'windowStart': q.startedAtMs, 'windowEnd': end.millisecondsSinceEpoch};
          }
        }

        // 3. Distance + route summary: live tracker if running, else the saved snapshot.
        if (tracking) await _saveSnapshot(silent: true);
        final evidence = {
          'distanceM': tracking ? _tracker.distanceM : q.distanceM,
          'route': tracking
              ? _tracker.routeSummary
              : {'fixCount': q.fixCount, 'rejectedCount': q.rejectedCount, 'mockedCount': q.mockedCount},
          'steps': steps,
          'freshFix': fix,
        };

        final res = await _api.validate(q.id, evidence);
        if (res['passed'] == true && tracking) {
          _snapshotTimer?.cancel();
          await _tracker.stop();
        }
        await _load();
        if (res['passed'] == true) setState(() => _filter = 'completed');
        if (mounted) await _showResult(q, res);
      });

  Future<void> _showResult(Quest q, Map<String, dynamic> res) {
    final passed = res['passed'] == true;
    final reasons = (res['reasons'] as List? ?? []).cast<String>();
    final remaining = (res['remaining'] as List? ?? []).cast<Map<String, dynamic>>();
    return showDialog(
      context: context,
      builder: (_) => AlertDialog(
        icon: Icon(passed ? Icons.check_circle : Icons.cancel, color: passed ? Colors.green : Colors.red, size: 48),
        title: Text(passed
            ? 'Quest completed! +${res['xpAwarded']} XP'
            : res['alreadyCompleted'] == true
                ? 'Already completed'
                : 'Not validated yet'),
        content: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            if (passed) Text('${q.title} was verified by the server.\nTotal XP: ${res['totalXp']}'),
            if (!passed) ...[
              for (final r in reasons) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('• $r')),
              if (remaining.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('Remaining:', style: TextStyle(fontWeight: FontWeight.bold)),
                for (final m in remaining) Text('${m['requirement']}: ${m['actual']} / ${m['target']} ${m['unit']}'),
              ],
              const SizedBox(height: 8),
              const Text('The quest stays Ongoing. Fix the above and validate again.'),
            ],
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
      ),
    );
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    final shown = _quests.where((q) => q.status == _filter).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('PoGetIt'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(child: Text('$_xp XP', style: Theme.of(context).textTheme.titleMedium)),
          ),
          IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: StatusTabs(
            selected: _filter,
            counts: {for (final s in StatusTabs.statuses) s: _quests.where((q) => q.status == s).length},
            onChanged: (s) => setState(() => _filter = s),
          ),
        ),
        if (_error != null)
          MaterialBanner(
            content: Text(_error!),
            actions: [TextButton(onPressed: _load, child: const Text('Retry'))],
          ),
        Expanded(
          child: _loading && _quests.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(8),
                    children: [
                      if (shown.isEmpty)
                        const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No quests here.'))),
                      for (final q in shown) _cardFor(q),
                    ],
                  ),
                ),
        ),
      ]),
    );
  }

  /// Connects one QuestCard to this screen's state and actions.
  Widget _cardFor(Quest q) {
    final tracking = _tracker.isTracking && _tracker.questId == q.id;
    final problem = _stepsProblem[q.id];
    return QuestCard(
      quest: q,
      tracker: tracking ? _tracker : null,
      liveSteps: _liveSteps[q.id],
      stepsProblem: problem?.problem,
      canInstallHealthConnect: problem?.canInstall == true,
      busy: _busy.contains(q.id),
      onAccept: () => _accept(q),
      onStartTracking: () => _startTracking(q),
      onStopTracking: _stopTracking,
      onRefreshSteps: () => _refreshSteps(q),
      onInstallHealthConnect: _stepsService.installHealthConnect,
      onOpenPin: () => _openPin(q),
      onValidate: () => _validate(q),
    );
  }
}
