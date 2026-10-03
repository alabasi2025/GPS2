import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:point_gps/engine/geo_math.dart';
import 'package:point_gps/engine/models.dart';
import 'package:point_gps/engine/position_estimator.dart';

/// محاكي GNSS: نقطة حقيقية + ضوضاء غاوسية مرتبطة زمنياً (AR(1)) تحاكي
/// أخطاء المسار المتعدد/الغلاف الجوي كما تظهر فعلاً على الهواتف.
///
/// ρ = 0.7 عند 1 Hz يعني أن 60 عينة تساوي ~10 عينات مستقلة فقط — وهذا
/// أقسى من السماء المفتوحة الحقيقية عمداً، حتى تكون الأرقام المعلنة محافظة.
final class _Sim {
  _Sim({
    required this.trueLat,
    required this.trueLon,
    this.sigmaM = 3.0,
    this.reportedAccM = 3.0,
    this.correlation = 0.7, // ignore: unused_element_parameter
    this.speedNoise = 0.15,
    int seed = 42,
  }) : _rng = math.Random(seed);

  final double trueLat;
  final double trueLon;
  final double sigmaM;
  final double reportedAccM;
  final double correlation;
  final double speedNoise;
  final math.Random _rng;

  double _errE = 0, _errN = 0;
  int _t = 0;

  double _gauss() {
    final u1 = 1 - _rng.nextDouble();
    final u2 = _rng.nextDouble();
    return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
  }

  GnssFix next({
    double offsetE = 0,
    double offsetN = 0,
    double speed = 0,
    double bearingDeg = 0,
    double? jumpE,
    double? jumpN,
  }) {
    _t++;
    final drive = sigmaM * math.sqrt(1 - correlation * correlation);
    _errE = correlation * _errE + drive * _gauss();
    _errN = correlation * _errN + drive * _gauss();
    final e = offsetE + _errE + (jumpE ?? 0);
    final n = offsetN + _errN + (jumpN ?? 0);
    final ll = GeoMath.fromEnu(e: e, n: n, refLat: trueLat, refLon: trueLon);
    final measSpeed = math.max(0.0, speed + speedNoise * _gauss());
    return GnssFix(
      lat: ll.lat,
      lon: ll.lon,
      alt: 2200 + _gauss() * 5,
      accuracyM: reportedAccM,
      verticalAccuracyM: 5,
      speedMps: measSpeed,
      speedAccuracyMps: speedNoise * 2,
      bearingDeg: speed > 0.5 ? bearingDeg + 5 * _gauss() : null,
      timeMs: 1700000000000 + _t * 1000,
      elapsedNs: _t * 1000000000,
    );
  }
}

double _errM(PositionEstimate est, double lat, double lon) =>
    GeoMath.haversineM(est.lat, est.lon, lat, lon);

void main() {
  const lat = 15.3694; // صنعاء
  const lon = 44.1910;

  group('GeoMath', () {
    test('ENU round-trip is exact to sub-millimetre', () {
      final enu = GeoMath.toEnu(
        lat: lat + 0.001,
        lon: lon + 0.001,
        refLat: lat,
        refLon: lon,
      );
      final back =
          GeoMath.fromEnu(e: enu.e, n: enu.n, refLat: lat, refLon: lon);
      expect(
        GeoMath.haversineM(back.lat, back.lon, lat + 0.001, lon + 0.001),
        lessThan(0.001),
      );
    });

    test('1 degree latitude ≈ 110.6–111.1 km (WGS-84)', () {
      expect(GeoMath.metersPerDegLat(0), closeTo(110574, 50));
      expect(GeoMath.metersPerDegLat(45), closeTo(111132, 50));
    });
  });

  group('PositionEstimator — stationary averaging', () {
    test('60 s of correlated 3 m noise: filtered error well below raw', () {
      final est = PositionEstimator();
      final sim = _Sim(trueLat: lat, trueLon: lon);
      PositionEstimate? last;
      var rawErrSum = 0.0;
      for (var i = 0; i < 60; i++) {
        final fix = sim.next();
        rawErrSum += GeoMath.haversineM(fix.lat, fix.lon, lat, lon);
        last = est.update(fix);
      }
      final rawMean = rawErrSum / 60;
      final filtered = _errM(last!, lat, lon);
      expect(
        filtered,
        lessThan(rawMean * 0.6),
        reason: 'filtered=$filtered raw-mean=$rawMean',
      );
      expect(filtered, lessThan(2.0));
      expect(last.motion, MotionState.stationary);
      expect(last.samplesAveraged, greaterThan(40));
      // الصدق: دائرة 95% تغطي الخطأ الحقيقي.
      expect(last.radius95M, greaterThanOrEqualTo(filtered));
    });

    test('5 min stationary converges below 1 m (the advertised target)', () {
      final est = PositionEstimator();
      final sim = _Sim(trueLat: lat, trueLon: lon);
      PositionEstimate? last;
      for (var i = 0; i < 300; i++) {
        last = est.update(sim.next());
      }
      final filtered = _errM(last!, lat, lon);
      expect(filtered, lessThan(1.0), reason: 'filtered=$filtered');
      expect(last.sigmaM, lessThan(1.0));
    });

    test('reported sigma never goes below 0.5 m floor', () {
      final est = PositionEstimator();
      final sim =
          _Sim(trueLat: lat, trueLon: lon, sigmaM: 0.5, reportedAccM: 1);
      PositionEstimate? last;
      for (var i = 0; i < 300; i++) {
        last = est.update(sim.next());
      }
      expect(last!.sigmaM, greaterThanOrEqualTo(0.5));
    });

    test('repeatability: 20 independent 120 s sessions', () {
      final errors = <double>[];
      var covered = 0;
      for (var s = 0; s < 20; s++) {
        final est = PositionEstimator();
        final sim = _Sim(trueLat: lat, trueLon: lon, seed: 100 + s);
        PositionEstimate? last;
        for (var i = 0; i < 120; i++) {
          last = est.update(sim.next());
        }
        final err = _errM(last!, lat, lon);
        errors.add(err);
        if (last.radius95M >= err) covered++;
      }
      final sorted = [...errors]..sort();
      final median = sorted[sorted.length ~/ 2];
      final worst = sorted.last;
      expect(median, lessThan(1.0), reason: 'errors=$errors');
      expect(worst, lessThan(2.5), reason: 'errors=$errors');
      // دائرة الثقة 95% يجب أن تغطي ≥ 90% من الجلسات (صدق التقدير).
      expect(covered, greaterThanOrEqualTo(18), reason: 'covered=$covered');
    });
  });

  group('PositionEstimator — outlier gating', () {
    test('a single 40 m jump during stationarity is rejected', () {
      final est = PositionEstimator();
      final sim = _Sim(trueLat: lat, trueLon: lon);
      PositionEstimate? last;
      for (var i = 0; i < 30; i++) {
        last = est.update(sim.next());
      }
      final before = _errM(last!, lat, lon);
      last = est.update(sim.next(jumpE: 40));
      final after = _errM(last, lat, lon);
      expect(after, lessThan(before + 1.0));
      expect(last.rejectedOutliers, 1);
    });

    test('5 consecutive jumps re-initialise at the new place', () {
      final est = PositionEstimator();
      final sim = _Sim(trueLat: lat, trueLon: lon);
      for (var i = 0; i < 30; i++) {
        est.update(sim.next());
      }
      PositionEstimate? last;
      for (var i = 0; i < 5; i++) {
        last = est.update(sim.next(jumpE: 200));
      }
      final target = GeoMath.fromEnu(e: 200, n: 0, refLat: lat, refLon: lon);
      expect(_errM(last!, target.lat, target.lon), lessThan(8));
    });

    test('mock locations are never trusted', () {
      final est = PositionEstimator();
      const mock = GnssFix(
        lat: lat,
        lon: lon,
        accuracyM: 1,
        timeMs: 1,
        elapsedNs: 1,
        isMock: true,
      );
      final out = est.update(mock);
      expect(est.isInitialized, isFalse);
      expect(out.rejectedOutliers, 1);
    });
  });

  group('PositionEstimator — motion', () {
    test('walking 1.4 m/s north is tracked and flagged moving', () {
      final est = PositionEstimator();
      final sim = _Sim(trueLat: lat, trueLon: lon, sigmaM: 2.5);
      PositionEstimate? last;
      var errSum = 0.0, maxErr = 0.0, rawSum = 0.0;
      var count = 0;
      for (var i = 0; i < 120; i++) {
        final n = 1.4 * i;
        final fix = sim.next(offsetN: n, speed: 1.4);
        last = est.update(fix);
        if (i > 15) {
          final ll = GeoMath.fromEnu(e: 0, n: n, refLat: lat, refLon: lon);
          final err = _errM(last, ll.lat, ll.lon);
          errSum += err;
          rawSum += GeoMath.haversineM(fix.lat, fix.lon, ll.lat, ll.lon);
          maxErr = math.max(maxErr, err);
          count++;
        }
      }
      final mean = errSum / count;
      final rawMean = rawSum / count;
      expect(last!.motion, MotionState.moving);
      // أثناء المشي الهدف: أفضل من الخام وبدون تأخّر يتجاوز 2× الضوضاء.
      expect(mean, lessThan(rawMean), reason: 'mean=$mean raw=$rawMean');
      expect(maxErr, lessThan(3 * 2.5), reason: 'maxErr=$maxErr');
      expect(last.samplesAveraged, 0);
    });

    test('stop → walk → stop restarts averaging at the new spot', () {
      final est = PositionEstimator();
      final sim = _Sim(trueLat: lat, trueLon: lon);
      for (var i = 0; i < 40; i++) {
        est.update(sim.next());
      }
      expect(est.motion, MotionState.stationary);
      for (var i = 1; i <= 30; i++) {
        est.update(sim.next(offsetE: 1.4 * i, speed: 1.4, bearingDeg: 90));
      }
      expect(est.motion, MotionState.moving);
      PositionEstimate? last;
      for (var i = 0; i < 60; i++) {
        last = est.update(sim.next(offsetE: 42));
      }
      final target = GeoMath.fromEnu(e: 42, n: 0, refLat: lat, refLon: lon);
      expect(last!.motion, MotionState.stationary);
      expect(last.samplesAveraged, greaterThan(40));
      expect(_errM(last, target.lat, target.lon), lessThan(2.0));
    });

    test('stationary user with noisy speed is not flagged moving', () {
      final est = PositionEstimator();
      final sim = _Sim(trueLat: lat, trueLon: lon, speedNoise: 0.25);
      var movingSamples = 0;
      for (var i = 0; i < 200; i++) {
        final out = est.update(sim.next());
        if (i > 10 && out.motion == MotionState.moving) movingSamples++;
      }
      expect(movingSamples, lessThan(10));
    });
  });

  group('PositionEstimator — numerical safety', () {
    test('never yields NaN with zero/duplicate timestamps', () {
      final est = PositionEstimator();
      for (var i = 0; i < 50; i++) {
        final out = est.update(
          const GnssFix(
            lat: lat,
            lon: lon,
            accuracyM: 3,
            timeMs: 1,
            elapsedNs: 5, // ثابت عمداً
          ),
        );
        expect(out.lat.isNaN, isFalse);
        expect(out.sigmaM.isNaN, isFalse);
        expect(out.sigmaM.isFinite, isTrue);
      }
    });

    test('reset clears everything', () {
      final est = PositionEstimator();
      final sim = _Sim(trueLat: lat, trueLon: lon);
      for (var i = 0; i < 20; i++) {
        est.update(sim.next());
      }
      est.reset();
      expect(est.isInitialized, isFalse);
      expect(est.motion, MotionState.unknown);
      expect(est.rejectedCount, 0);
    });
  });
}
