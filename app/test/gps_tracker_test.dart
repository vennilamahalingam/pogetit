// Feeds fake GPS fixes into GpsTracker to check the distance filters.
// Run from app/:  flutter test
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:pogetit/gps_tracker.dart';

const baseLat = 51.5136, baseLng = -0.0985;
const mPerDegLat = 111320.0; // 1 degree of latitude ≈ 111.32 km
final t0 = DateTime.utc(2026, 1, 1, 10);

/// A fix [northM] metres north and [eastM] metres east of the base point, [sec] seconds after t0.
Position fix(double sec, {double northM = 0, double eastM = 0, double acc = 4, bool mocked = false}) => Position(
      latitude: baseLat + northM / mPerDegLat,
      longitude: baseLng + eastM / (mPerDegLat * 0.6225), // cos(51.5°) ≈ 0.6225
      timestamp: t0.add(Duration(milliseconds: (sec * 1000).round())),
      accuracy: acc,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
      isMocked: mocked,
    );

void main() {
  test('standing still: GPS wobble within accuracy adds no distance', () {
    final t = GpsTracker();
    // 2 minutes, a fix every 2 s, wobbling up to ~3.5 m around one spot (like your RUN-01 data).
    const wobble = [[0.0, 0.0], [3.0, 1.0], [-2.0, 2.5], [1.0, -3.0], [-3.0, -1.0], [2.0, 2.0]];
    for (var i = 0; i < 60; i++) {
      final w = wobble[i % wobble.length];
      t.handleFixForTest(fix(i * 2.0, northM: w[0], eastM: w[1], acc: 4));
    }
    expect(t.distanceM, 0);
  });

  test('walking straight at 1.4 m/s for 100 s counts ~140 m', () {
    final t = GpsTracker();
    for (var i = 0; i <= 50; i++) {
      t.handleFixForTest(fix(i * 2.0, northM: i * 2.8, acc: 4)); // 2.8 m per fix: below 5 m each,
    } //                                                            but adds up once clearly away
    expect(t.distanceM, greaterThan(130));
    expect(t.distanceM, lessThanOrEqualTo(141));
  });

  test('a GPS jump faster than 8 m/s is rejected', () {
    final t = GpsTracker();
    t.handleFixForTest(fix(0));
    t.handleFixForTest(fix(2, northM: 200)); // 200 m in 2 s = 100 m/s
    expect(t.distanceM, 0);
    expect(t.rejectedCount, 1);
  });

  test('mocked fixes are ignored and counted', () {
    final t = GpsTracker();
    t.handleFixForTest(fix(0));
    t.handleFixForTest(fix(10, northM: 30, mocked: true));
    expect(t.distanceM, 0);
    expect(t.mockedCount, 1);
  });

  test('fixes worse than 30 m accuracy are rejected', () {
    final t = GpsTracker();
    t.handleFixForTest(fix(0));
    t.handleFixForTest(fix(10, northM: 40, acc: 45));
    expect(t.distanceM, 0);
    expect(t.rejectedCount, 1);
  });

  test('with poor (but allowed) accuracy, small moves are treated as noise', () {
    final t = GpsTracker();
    t.handleFixForTest(fix(0, acc: 20));
    t.handleFixForTest(fix(5, northM: 12, acc: 20)); // 12 m < 20 m uncertainty -> ignored
    expect(t.distanceM, 0);
    t.handleFixForTest(fix(20, northM: 35, acc: 20)); // 35 m from anchor -> counted
    expect(t.distanceM, closeTo(35, 0.5));
  });
}
