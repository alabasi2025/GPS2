import 'package:flutter_test/flutter_test.dart';
import 'package:point_gps/engine/geo_math.dart';
import 'package:point_gps/engine/models.dart';
import 'package:point_gps/engine/solution_arbiter.dart';

void main() {
  const lat = 15.3694, lon = 44.1910;
  const t0 = 1700000000000;

  GnssFix assistAt({double e = 0, double n = 0, double acc = 20, int t = t0}) {
    final ll = GeoMath.fromEnu(e: e, n: n, refLat: lat, refLon: lon);
    return GnssFix(lat: ll.lat, lon: ll.lon, accuracyM: acc, timeMs: t, elapsedNs: t * 1000, source: FixSource.assist);
  }

  PositionEstimate gnssAt({double e = 0, double n = 0, double sigma = 2, int t = t0}) {
    final ll = GeoMath.fromEnu(e: e, n: n, refLat: lat, refLon: lon);
    return PositionEstimate(
      lat: ll.lat,
      lon: ll.lon,
      sigmaM: sigma,
      motion: MotionState.stationary,
      samplesAveraged: 30,
      rawAccuracyM: 3,
      rejectedOutliers: 0,
      timeMs: t,
    );
  }

  group('SolutionArbiter', () {
    test('no GNSS yet → shows assist immediately (never a blank screen)', () {
      final arb = SolutionArbiter()..updateAssist(assistAt(acc: 25));
      final s = arb.decide(estimate: null, usedSatellites: 0, nowMs: t0)!;
      expect(s.source, FixSource.assist);
      expect(s.reason, ArbiterReason.gnssMissing);
      expect(s.sigmaM, 25);
    });

    test('indoors: GNSS 200 m off while assist is 20 m → assist wins (the user bug)', () {
      final arb = SolutionArbiter()..updateAssist(assistAt(acc: 20));
      final s = arb.decide(estimate: gnssAt(e: 200, sigma: 8), usedSatellites: 6, nowMs: t0)!;
      expect(s.source, FixSource.assist);
      expect(s.reason, ArbiterReason.gnssInconsistent);
      expect(GeoMath.haversineM(s.lat, s.lon, lat, lon), lessThan(0.01));
      expect(s.gnssDisagreementM, closeTo(200, 1));
    });

    test('open sky: GNSS 1 m consistent with assist 15 m → GNSS wins after confirmation', () {
      final arb = SolutionArbiter()..updateAssist(assistAt(e: 5, acc: 15));
      DisplaySolution? s;
      for (var i = 0; i < 3; i++) {
        s = arb.decide(estimate: gnssAt(sigma: 1), usedSatellites: 12, nowMs: t0 + i * 1000);
      }
      expect(s!.source, FixSource.gnss);
      expect(s.reason, ArbiterReason.gnssTrusted);
      expect(s.sigmaM, 1);
    });

    test('consistent GNSS is shown even before confirmation when it is the more precise one', () {
      final arb = SolutionArbiter()..updateAssist(assistAt(e: 5, acc: 15));
      final s = arb.decide(estimate: gnssAt(sigma: 1), usedSatellites: 12, nowMs: t0)!;
      expect(s.source, FixSource.gnss);
    });

    test('few satellites → GNSS weak → assist', () {
      final arb = SolutionArbiter()..updateAssist(assistAt(acc: 20));
      final s = arb.decide(estimate: gnssAt(e: 10, sigma: 12), usedSatellites: 3, nowMs: t0)!;
      expect(s.source, FixSource.assist);
      expect(s.reason, ArbiterReason.gnssWeak);
    });

    test('weak GNSS but assist even worse and consistent → GNSS (lesser evil)', () {
      final arb = SolutionArbiter()..updateAssist(assistAt(acc: 800));
      final s = arb.decide(estimate: gnssAt(sigma: 30), usedSatellites: 4, nowMs: t0)!;
      expect(s.source, FixSource.gnss);
    });

    test('stale assist (> 15 s) is ignored → GNSS', () {
      final arb = SolutionArbiter()..updateAssist(assistAt(e: 300, acc: 20, t: t0 - 60000));
      final s = arb.decide(estimate: gnssAt(sigma: 3), usedSatellites: 10, nowMs: t0)!;
      expect(s.source, FixSource.gnss);
    });

    test('hysteresis: walking out of a building flips to GNSS only after 3 consistent fixes', () {
      final arb = SolutionArbiter();
      // داخل المبنى
      arb.updateAssist(assistAt(acc: 20));
      arb.decide(estimate: gnssAt(e: 150, sigma: 10), usedSatellites: 6, nowMs: t0);
      // خرجنا: GNSS صار متسقاً
      final sources = <FixSource>[];
      for (var i = 1; i <= 4; i++) {
        arb.updateAssist(assistAt(acc: 20, t: t0 + i * 1000));
        sources.add(
          arb.decide(estimate: gnssAt(e: 2, sigma: 3, t: t0 + i * 1000), usedSatellites: 9, nowMs: t0 + i * 1000)!.source,
        );
      }
      // GNSS أدق من المدمج فيُعرض فور الاتساق، ويبقى بعد التأكيد.
      expect(sources.last, FixSource.gnss);
      expect(arb.lastReason, ArbiterReason.gnssTrusted);
    });

    test('mock assist is ignored', () {
      final arb = SolutionArbiter()
        ..updateAssist(
          const GnssFix(lat: 0, lon: 0, accuracyM: 5, timeMs: t0, elapsedNs: 1, isMock: true, source: FixSource.assist),
        );
      expect(arb.decide(estimate: null, usedSatellites: 0, nowMs: t0), isNull);
    });
  });
}
