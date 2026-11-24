/// App-wide settings. Override the backend at build time:
///   flutter run --dart-define=API_BASE=http://192.168.1.2:8000
class AppConfig {
  static const apiBase = String.fromEnvironment('API_BASE', defaultValue: 'http://192.168.1.2:8000');

  // --- GPS filtering (client side; the backend re-checks what matters) ---
  /// Fixes with reported accuracy worse than this are dropped.
  static const maxAccuracyM = 30.0;

  /// Implied speed between two fixes above this is an implausible jump (walking/jogging).
  static const maxSpeedMps = 8.0;

  /// A move between fixes only counts if it is at least this far AND bigger than the
  /// GPS accuracy of both fixes. Stops standing-still drift from adding fake distance.
  static const minMoveM = 5.0;

  /// Ask Android for an update only after moving at least this far (reduces standing-still jitter).
  static const distanceFilterM = 5;

  /// No accepted fix for this long while tracking -> show "weak GPS signal".
  static const weakSignalAfter = Duration(seconds: 20);

  /// How often to save a progress snapshot to the backend while tracking.
  static const snapshotEvery = Duration(seconds: 15);
}
