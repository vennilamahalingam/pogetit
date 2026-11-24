import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'config.dart';

/// Haversine distance in metres (same formula as the backend).
double haversineM(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371000.0;
  double rad(double d) => d * pi / 180;
  final dLat = rad(lat2 - lat1), dLng = rad(lng2 - lng1);
  final a = pow(sin(dLat / 2), 2) + cos(rad(lat1)) * cos(rad(lat2)) * pow(sin(dLng / 2), 2);
  return 2 * r * asin(sqrt(a));
}

/// Checks GPS is on and permission is granted. Returns null if OK, else a message for the user.
Future<String?> checkLocationReady() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    return 'Location (GPS) is turned off. Turn it on in quick settings and try again.';
  }
  var perm = await Geolocator.checkPermission();
  if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
  if (perm == LocationPermission.denied) {
    return 'Location permission denied. PoGetIt needs it to measure your distance.';
  }
  if (perm == LocationPermission.deniedForever) {
    return 'Location permission is blocked. Open Settings → Apps → PoGetIt → Permissions → Location '
        'and choose "Allow only while using the app".';
  }
  return null;
}

/// Gets one fresh, high-accuracy fix (used for pin confirmation and validation).
/// Throws a readable String on failure.
Future<Position> getFreshFix() async {
  final problem = await checkLocationReady();
  if (problem != null) throw problem;
  try {
    return await Geolocator.getCurrentPosition(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.best,
        forceLocationManager: false,
        timeLimit: const Duration(seconds: 25),
      ),
    );
  } on TimeoutException {
    throw 'No GPS fix within 25 s (indoors / weak signal?). Move outside and try again.';
  }
}

/// Foreground GPS tracker for one quest.
///
/// Distance = sum of haversine distances between successive *accepted* fixes.
/// A fix is rejected if: accuracy > 30 m, it is mocked, or the implied speed
/// from the last accepted fix is > 8 m/s (a GPS jump).
class GpsTracker extends ChangeNotifier {
  String? questId;
  double distanceM = 0;
  int fixCount = 0; // accepted fixes
  int rejectedCount = 0; // dropped for accuracy / jump
  int mockedCount = 0; // fixes flagged isMocked (also dropped)
  Position? lastFix; // latest fix of any kind, for display
  String? message; // warning shown under the tracker (weak signal, mock, error)

  Position? _anchor; // last accepted fix
  DateTime? _lastAcceptedAt;
  StreamSubscription<Position>? _sub;
  Timer? _watchdog;

  bool get isTracking => _sub != null;

  Map<String, int> get routeSummary =>
      {'fixCount': fixCount, 'rejectedCount': rejectedCount, 'mockedCount': mockedCount};

  /// Start (or resume) tracking. [startDistanceM] restores the saved snapshot after a restart.
  /// Returns an error message, or null if tracking started.
  Future<String?> start(String id,
      {double startDistanceM = 0, int startFixes = 0, int startRejected = 0, int startMocked = 0}) async {
    await stop();
    final problem = await checkLocationReady();
    if (problem != null) return problem;

    questId = id;
    distanceM = startDistanceM;
    fixCount = startFixes;
    rejectedCount = startRejected;
    mockedCount = startMocked; // restored, so a restart can't wipe earlier mock detections
    _anchor = null;
    lastFix = null;
    _lastAcceptedAt = DateTime.now();
    message = 'Waiting for GPS fix…';
    notifyListeners();

    _sub = Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: AppConfig.distanceFilterM,
        intervalDuration: const Duration(seconds: 2),
        forceLocationManager: false, // use the fused location provider
      ),
    ).listen(_onFix, onError: _onError);

    _watchdog = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_lastAcceptedAt != null && DateTime.now().difference(_lastAcceptedAt!) > AppConfig.weakSignalAfter) {
        message = 'Weak GPS signal (indoors?). Move outside with a clear view of the sky.';
        notifyListeners();
      }
    });
    return null;
  }

  /// Lets unit tests feed fixes directly (no real GPS needed).
  @visibleForTesting
  void handleFixForTest(Position p) => _onFix(p);

  void _onFix(Position p) {
    lastFix = p;
    if (p.isMocked) {
      mockedCount++;
      message = 'Mock location detected — these fixes are ignored and the quest will fail validation.';
      notifyListeners();
      return;
    }
    if (p.accuracy > AppConfig.maxAccuracyM) {
      rejectedCount++;
      message = 'GPS accuracy is poor (${p.accuracy.toStringAsFixed(0)} m). Waiting for a better fix…';
      notifyListeners();
      return;
    }
    final a = _anchor;
    if (a != null) {
      final d = haversineM(a.latitude, a.longitude, p.latitude, p.longitude);
      final dtS = p.timestamp.difference(a.timestamp).inMilliseconds / 1000;
      if (dtS <= 0) return; // duplicate / out-of-order fix
      if (d / dtS > AppConfig.maxSpeedMps) {
        // Implausible jump. Keep the old anchor: as time passes the implied speed drops,
        // so real movement is accepted again on a later fix.
        rejectedCount++;
        notifyListeners();
        return;
      }
      // Drift filter: standing still, GPS still "wobbles" a few metres each fix.
      // Only count a move that is bigger than the GPS uncertainty of the two fixes
      // (or minMoveM, whichever is larger). Smaller changes are treated as noise:
      // nothing is added and the anchor is NOT moved, so slow real walking still
      // adds up once you are clearly away from the anchor.
      final minMove = max(AppConfig.minMoveM, max(a.accuracy, p.accuracy));
      if (d < minMove) {
        _lastAcceptedAt = DateTime.now(); // good signal, just not moving
        message = null;
        notifyListeners();
        return;
      }
      distanceM += d;
    }
    _anchor = p;
    fixCount++;
    _lastAcceptedAt = DateTime.now();
    message = null;
    notifyListeners();
  }

  void _onError(Object e) {
    message = e is LocationServiceDisabledException
        ? 'GPS was turned off. Turn it back on and tap Resume tracking.'
        : 'Location error: $e';
    stop(keepMessage: true);
  }

  Future<void> stop({bool keepMessage = false}) async {
    await _sub?.cancel();
    _sub = null;
    _watchdog?.cancel();
    _watchdog = null;
    if (!keepMessage) message = null;
    notifyListeners();
  }
}
