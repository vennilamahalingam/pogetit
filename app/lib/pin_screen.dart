import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'api.dart';
import 'config.dart';
import 'gps_tracker.dart';
import 'models.dart';

/// Café check-in: get a fresh GPS fix, preview it, user confirms -> POST /pin.
/// The pin only records where the user says they are. The server later compares it
/// with a *new* fresh fix and the café geofence before giving any XP.
class PinScreen extends StatefulWidget {
  final Quest quest;
  final Api api;
  const PinScreen({super.key, required this.quest, required this.api});

  @override
  State<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<PinScreen> {
  Position? _fix;
  String? _error;
  bool _locating = false, _saving = false;

  @override
  void initState() {
    super.initState();
    _getFix();
  }

  Future<void> _getFix() async {
    setState(() {
      _locating = true;
      _error = null;
    });
    try {
      final f = await getFreshFix();
      setState(() => _fix = f);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _confirm() async {
    setState(() => _saving = true);
    try {
      await widget.api.savePin(widget.quest.id, fixToJson(_fix!));
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cafe = widget.quest.cafe!;
    final f = _fix;
    final distToCafe = f == null ? null : haversineM(f.latitude, f.longitude, cafe.lat, cafe.lng);
    final inside = distToCafe != null && distToCafe <= cafe.radiusM;
    final accurate = f != null && f.accuracy <= AppConfig.maxAccuracyM;
    final err = Theme.of(context).colorScheme.error;
    final ok = Colors.green.shade700;

    return Scaffold(
      appBar: AppBar(title: Text('Check in · ${widget.quest.title}')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Café: ${cafe.lat.toStringAsFixed(6)}, ${cafe.lng.toStringAsFixed(6)}  (radius ${cafe.radiusM.toStringAsFixed(0)} m)'),
        const Divider(height: 32),
        if (_locating) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
        if (!_locating && f != null) ...[
          Text('Your position', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text('${f.latitude.toStringAsFixed(6)}, ${f.longitude.toStringAsFixed(6)}',
              style: Theme.of(context).textTheme.headlineSmall),
          Text('Accuracy: ±${f.accuracy.toStringAsFixed(0)} m', style: TextStyle(color: accurate ? ok : err)),
          Text('Fix time: ${f.timestamp.toLocal().toIso8601String().substring(11, 19)}'),
          const SizedBox(height: 8),
          Text('Distance to café: ${distToCafe!.toStringAsFixed(0)} m',
              style: TextStyle(fontWeight: FontWeight.bold, color: inside ? ok : err)),
          if (!inside) Text('You are outside the ${cafe.radiusM.toStringAsFixed(0)} m café area.', style: TextStyle(color: err)),
          if (!accurate) Text('Accuracy is too low; move outdoors and refresh.', style: TextStyle(color: err)),
          if (f.isMocked) Text('Mock location detected. This pin will be rejected.', style: TextStyle(color: err)),
        ],
        if (_error != null) Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(_error!, style: TextStyle(color: err)),
        ),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: _locating || _saving ? null : _getFix,
          icon: const Icon(Icons.my_location),
          label: const Text('Get a new fix'),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: f == null || _locating || _saving ? null : _confirm,
          icon: const Icon(Icons.push_pin),
          label: Text(_saving ? 'Saving…' : 'Confirm pin here'),
        ),
        const SizedBox(height: 12),
        const Text('Confirming saves this position. It is checked again with a fresh fix when you validate.',
            style: TextStyle(fontSize: 12)),
      ]),
    );
  }
}
