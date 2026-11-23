import 'package:health/health.dart';

/// Result of a step read. Either [steps] is set, or [problem] explains why not.
/// We never invent or substitute a number: no data means steps == null.
class StepsResult {
  final int? steps;
  final String? problem;
  final bool canInstall; // Health Connect missing / needs update -> offer the Play Store
  StepsResult.ok(int this.steps)
      : problem = null,
        canInstall = false;
  StepsResult.fail(String this.problem, {this.canInstall = false}) : steps = null;
}

/// Reads steps from Android Health Connect for a quest's time window.
class StepsService {
  final _health = Health();
  bool _configured = false;

  Future<void> _configure() async {
    if (!_configured) {
      await _health.configure();
      _configured = true;
    }
  }

  /// Checks Health Connect is available and asks for READ_STEPS if needed.
  /// Returns null when ready, otherwise a StepsResult describing the problem.
  Future<StepsResult?> ensureReady({bool askPermission = true}) async {
    await _configure();
    final status = await _health.getHealthConnectSdkStatus();
    if (status == HealthConnectSdkStatus.sdkUnavailable) {
      return StepsResult.fail('Health Connect is not available on this phone. Install it from the Play Store.',
          canInstall: true);
    }
    if (status == HealthConnectSdkStatus.sdkUnavailableProviderUpdateRequired) {
      return StepsResult.fail('Health Connect needs an update. Update it from the Play Store.', canInstall: true);
    }
    final types = [HealthDataType.STEPS];
    final access = [HealthDataAccess.READ];
    var granted = await _health.hasPermissions(types, permissions: access) ?? false;
    if (!granted && askPermission) {
      granted = await _health.requestAuthorization(types, permissions: access);
    }
    if (!granted) {
      return StepsResult.fail('Step permission denied. Open Health Connect → App permissions → PoGetIt '
          'and allow "Steps".');
    }
    return null;
  }

  /// Total steps between [start] and [end].
  ///
  /// Uses Health Connect's *aggregate* total, which de-duplicates overlapping
  /// sources (e.g. phone + watch), instead of summing raw records.
  /// Manually entered steps are excluded.
  Future<StepsResult> stepsBetween(DateTime start, DateTime end, {bool askPermission = true}) async {
    try {
      final problem = await ensureReady(askPermission: askPermission);
      if (problem != null) return problem;
      final total = await _health.getTotalStepsInInterval(start, end, includeManualEntry: false);
      return StepsResult.ok(total);
    } catch (e) {
      return StepsResult.fail('Could not read steps from Health Connect: $e');
    }
  }

  Future<void> installHealthConnect() => _health.installHealthConnect();
}
