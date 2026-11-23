import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';
import 'config.dart';
import 'gps_tracker.dart';
import 'models.dart';
import 'pin_screen.dart';
import 'steps_service.dart';

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
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              segments: [
                for (final s in ['available', 'ongoing', 'completed'])
                  ButtonSegment(
                    value: s,
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('${s[0].toUpperCase()}${s.substring(1)} '
                          '${_quests.where((q) => q.status == s).length}'),
                    ),
                  ),
              ],
              selected: {_filter},
              onSelectionChanged: (sel) => setState(() => _filter = sel.first),
            ),
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
                        const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(child: Text('No quests here.')),
                        ),
                      for (final q in shown) _questCard(q),
                    ],
                  ),
                ),
        ),
      ]),
    );
  }

  Widget _questCard(Quest q) {
    final tracking = _tracker.isTracking && _tracker.questId == q.id;
    final distance = tracking ? _tracker.distanceM : q.distanceM;
    final steps = _liveSteps[q.id] ?? q.steps;
    final ongoing = q.status == 'ongoing';
    // Live % while ongoing (display only). Café part uses the server's view of the saved pin.
    final cafeOk = q.cafe != null && q.pin != null &&
        haversineM(q.pin!['lat'], q.pin!['lng'], q.cafe!.lat, q.cafe!.lng) <= q.cafe!.radiusM;
    final pct = ongoing ? progressPct(q, distanceM: distance, steps: steps, cafeOk: cafeOk) : q.progressPct;
    final busy = _busy.contains(q.id);
    final text = Theme.of(context).textTheme;
    final err = Theme.of(context).colorScheme.error;
    final stepsProblem = _stepsProblem[q.id];

    final scheme = Theme.of(context).colorScheme;
    final isRun = q.type == 'run';
    final accent = isRun ? const Color(0xFF2E7D6B) : const Color(0xFF9A5B2E); // run = teal, café = coffee
    final muted = text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant);

    Widget req(IconData icon, String label) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(children: [
            Icon(icon, size: 18, color: accent),
            const SizedBox(width: 8),
            Expanded(child: Text(label, style: text.bodyMedium)),
          ]),
        );

    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: accent.withValues(alpha: 0.12),
              child: Icon(isRun ? Icons.directions_run : Icons.local_cafe, color: accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(q.title, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                Text(q.id, style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant, letterSpacing: 0.8)),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF4D6),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('+${q.xp} XP',
                  style: text.labelLarge?.copyWith(fontWeight: FontWeight.w700, color: const Color(0xFF8A6100))),
            ),
          ]),
          if (q.description.isNotEmpty) Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(q.description, style: muted),
          ),
          const SizedBox(height: 4),
          if (q.targetDistanceM != null)
            req(Icons.straighten, '${q.targetDistanceM!.toStringAsFixed(0)} m GPS distance'),
          if (q.targetSteps != null) req(Icons.directions_walk, '${q.targetSteps} steps during the quest'),
          if (q.cafe != null)
            req(Icons.place, 'Check in within ${q.cafe!.radiusM.toStringAsFixed(0)} m of the café'),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: pct / 100,
                  minHeight: 8,
                  color: accent,
                  backgroundColor: accent.withValues(alpha: 0.12),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text('$pct%', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          ]),
          if (q.status != 'available' && q.needsTracking)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Distance: ${distance.toStringAsFixed(0)} / ${q.targetDistanceM!.toStringAsFixed(0)} m'),
            ),
          if (ongoing && q.targetSteps != null) ...[
            Text('Steps (Health Connect): ${_liveSteps[q.id] ?? '—'} / ${q.targetSteps}'),
            if (_liveSteps[q.id] == 0)
              Text('No steps recorded yet. Make sure Samsung Health syncs to Health Connect.',
                  style: TextStyle(color: err, fontSize: 12)),
            if (stepsProblem != null) Text(stepsProblem.problem!, style: TextStyle(color: err, fontSize: 12)),
          ],
          if (ongoing && q.cafe != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(q.pin == null
                  ? 'Café pin: not confirmed'
                  : 'Café pin: saved (±${(q.pin!['accuracyM'] as num).toStringAsFixed(0)} m, '
                      '${cafeOk ? 'inside' : 'outside'} café area)'),
            ),
          if (tracking) _trackingPanel(),
          if (ongoing && pct >= 100)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('Targets reached. Tap Validate: it stays Ongoing until the server confirms.'),
            ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, children: _buttons(q, tracking, busy, stepsProblem)),
        ]),
      ),
    );
  }

  Widget _trackingPanel() {
    final f = _tracker.lastFix;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('● Tracking (keep the app open)', style: TextStyle(fontWeight: FontWeight.bold)),
        Text('Fixes: ${_tracker.fixCount} accepted · ${_tracker.rejectedCount} rejected'
            '${_tracker.mockedCount > 0 ? ' · ${_tracker.mockedCount} mocked' : ''}'),
        if (f != null) Text('Last fix accuracy: ${f.accuracy.toStringAsFixed(0)} m'),
        if (_tracker.message != null)
          Text(_tracker.message!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ]),
    );
  }

  List<Widget> _buttons(Quest q, bool tracking, bool busy, StepsResult? stepsProblem) {
    switch (q.status) {
      case 'available':
        return [
          FilledButton(onPressed: busy ? null : () => _accept(q), child: const Text('Accept / Start')),
        ];
      case 'ongoing':
        return [
          if (q.needsTracking && tracking)
            OutlinedButton(onPressed: _stopTracking, child: const Text('Stop tracking')),
          if (q.needsTracking && !tracking)
            OutlinedButton(
              onPressed: busy ? null : () => _startTracking(q),
              child: Text(q.distanceM > 0 ? 'Resume tracking' : 'Start tracking'),
            ),
          if (q.targetSteps != null)
            TextButton(onPressed: busy ? null : () => _refreshSteps(q), child: const Text('Refresh steps')),
          if (stepsProblem?.canInstall == true)
            TextButton(onPressed: _stepsService.installHealthConnect, child: const Text('Get Health Connect')),
          if (q.cafe != null)
            OutlinedButton.icon(
              onPressed: busy ? null : () => _openPin(q),
              icon: const Icon(Icons.push_pin),
              label: Text(q.pin == null ? 'Confirm location' : 'Re-confirm location'),
            ),
          FilledButton(
            onPressed: busy ? null : () => _validate(q),
            child: Text(busy ? 'Validating…' : 'Validate'),
          ),
        ];
      default:
        return [const Chip(label: Text('Completed ✓'))];
    }
  }
}
