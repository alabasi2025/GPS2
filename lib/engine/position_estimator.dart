import 'dart:math' as math;

import 'geo_math.dart';
import 'models.dart';

/// محرك تقدير الموقع.
///
/// الحالة x = [e, n, ve, vn] في إطار ENU حول أول عينة مقبولة.
///
/// الأفكار الأساسية (كلها من أدبيات GNSS للهواتف):
/// 1. **Kalman خطّي سرعة-ثابتة** مع ضوضاء عملية تتكيّف مع حالة الحركة.
/// 2. **قياس سرعة Doppler** كقياس مستقل للحالة [ve, vn]: سرعة الهاتف من
///    Doppler دقتها ~0.1–0.3 م/ث، أفضل بعشر مرات من اشتقاق المواضع، وهي
///    ما يسمح بتنعيم الموضع أثناء المشي بلا تأخّر عند التوقف.
/// 3. **بوابة Mahalanobis** على كل قياس (χ² بدرجتي حرية) لرفض القفزات.
/// 4. **كشف سكون إحصائي**: السرعة أولاً، ثم اختبار إزاحة متوسط آخر K عينات
///    عن المتوسط التراكمي بعتبة تتناسب مع الضوضاء الفعلية (لا عتبة ثابتة).
/// 5. **متوسط موزون بعكس التباين أثناء السكون** مع σ صادقة تراعي الارتباط
///    الزمني للأخطاء (عامل 1.6).
///
/// المرجعيات: Google I/O 2018 "one-meter accuracy"; Barbeau 2019 (دقة
/// الـchipset متفائلة ~32%); Groves "Principles of GNSS" (CV model + Doppler).
///
/// بلا تخصيص ذاكرة في المسار الساخن: كل المصفوفات مُسبقة التخصيص.
final class PositionEstimator {
  PositionEstimator({
    this.accuracyInflation = 1.5,
    this.minMeasurementSigmaM = 1.5,
    this.processNoiseMovingMps2 = 0.4,
    this.processNoiseStationaryMps2 = 0.02,
    this.gateChiSquare95 = 5.991, // χ² بدرجتي حرية عند 95%
    this.stationarySpeedMps = 0.35,
    this.lowSpeedBearingMps = 0.5,
    this.stationaryConfirmSamples = 3,
    this.movingConfirmSamples = 2,
    this.minDisplacementGateM = 2.5,
    this.maxAveragingSamples = 600,
    this.temporalCorrelationFactor = 1.6,
    this.sigmaFloorM = 0.5,
  });

  // ---------------------------------------------------------------- معاملات
  /// مضاعف لدقة الـchipset قبل استخدامها كـσ قياس (Barbeau: متفائلة).
  final double accuracyInflation;

  /// أرضية σ القياس؛ لا نثق بأقل منها من هاتف.
  final double minMeasurementSigmaM;
  final double processNoiseMovingMps2;
  final double processNoiseStationaryMps2;
  final double gateChiSquare95;

  /// تحت هذه السرعة نعتبر العينة "ساكنة".
  final double stationarySpeedMps;

  /// تحت هذه السرعة الاتجاه (bearing) غير موثوق؛ نقيس السرعة كصفر.
  final double lowSpeedBearingMps;
  final int stationaryConfirmSamples;
  final int movingConfirmSamples;

  /// الحد الأدنى لعتبة الإزاحة في اختبار السكون (تكبر تلقائياً مع الضوضاء).
  final double minDisplacementGateM;
  final int maxAveragingSamples;

  /// عامل تضخيم σ المتوسط لتعويض الارتباط الزمني للأخطاء.
  final double temporalCorrelationFactor;

  /// لا نعرض أبداً σ أقل من هذا (حد واقعي لهاتف بلا تصحيحات خارجية).
  final double sigmaFloorM;

  // ---------------------------------------------------------- إطار مرجعي
  double? _refLat;
  double? _refLon;

  // ----------------------------------------------------------- حالة Kalman
  double _e = 0, _n = 0, _ve = 0, _vn = 0;
  final List<double> _p = List<double>.filled(16, 0); // 4×4 صف-رئيسي
  final List<double> _k = List<double>.filled(8, 0); // كسب 4×2 (مؤقت)
  final List<double> _tmp = List<double>.filled(16, 0); // مؤقت
  int? _lastElapsedNs;
  bool _initialized = false;

  // --------------------------------------------------------- السكون والتجميع
  MotionState _motion = MotionState.unknown;
  int _stillStreak = 0;
  int _moveStreak = 0;
  double _sumWE = 0, _sumWN = 0, _sumW = 0;
  double _sumWAlt = 0, _sumWAltW = 0;
  int _avgCount = 0;

  // حلقة آخر K عينات خام (للاختبار الإحصائي للإزاحة).
  static const int _ringK = 4;
  final List<double> _ringE = List<double>.filled(_ringK, 0);
  final List<double> _ringN = List<double>.filled(_ringK, 0);
  int _ringCount = 0;
  int _ringHead = 0;

  int _rejected = 0;
  int _consecutiveRejects = 0;
  double _lastSigmaMeas = 5.0;

  bool get isInitialized => _initialized;
  MotionState get motion => _motion;
  int get rejectedCount => _rejected;

  /// يعيد ضبط كل الحالة (مثلاً عند طلب المستخدم أو تغيّر كبير).
  void reset() {
    _refLat = _refLon = null;
    _e = _n = _ve = _vn = 0;
    _p.fillRange(0, 16, 0);
    _lastElapsedNs = null;
    _initialized = false;
    _resetAveraging();
    _ringCount = _ringHead = 0;
    _motion = MotionState.unknown;
    _stillStreak = _moveStreak = 0;
    _rejected = 0;
    _consecutiveRejects = 0;
  }

  void _resetAveraging() {
    _sumWE = _sumWN = _sumW = 0;
    _sumWAlt = _sumWAltW = 0;
    _avgCount = 0;
  }

  /// يعالج عينة ويعيد التقدير الحالي.
  PositionEstimate update(GnssFix fix) {
    if (fix.isMock) {
      _rejected++;
      return _currentEstimate(fix);
    }
    final sigma = _measurementSigma(fix.accuracyM);
    _lastSigmaMeas = sigma;
    final r = sigma * sigma;

    if (!_initialized) {
      _initialize(fix, r);
      return _currentEstimate(fix);
    }

    // ---------------------------------------------------------- تنبؤ
    final dt = _dtSeconds(fix.elapsedNs);
    _predict(dt);

    // ------------------------------------------------- قياس الموضع في ENU
    final z = GeoMath.toEnu(
      lat: fix.lat,
      lon: fix.lon,
      refLat: _refLat!,
      refLon: _refLon!,
    );
    final innovE = z.e - _e;
    final innovN = z.n - _n;

    // S = H P Hᵀ + R → 2×2
    final s00 = _p[0] + r, s01 = _p[1], s11 = _p[5] + r;
    final det = s00 * s11 - s01 * s01;
    if (!(det > 0) || !det.isFinite) {
      _initialize(fix, r);
      return _currentEstimate(fix);
    }
    final inv00 = s11 / det, inv01 = -s01 / det, inv11 = s00 / det;
    final mahal = innovE * (inv00 * innovE + inv01 * innovN) +
        innovN * (inv01 * innovE + inv11 * innovN);

    // ------------------------------------------------------ بوابة القفزات
    final gate = _motion == MotionState.stationary
        ? gateChiSquare95
        : gateChiSquare95 * 3;
    if (mahal > gate) {
      _rejected++;
      _consecutiveRejects++;
      // 5 رفضات متتالية = الفلتر ضلّ (نفق/قفزة حقيقية) → إعادة تهيئة.
      if (_consecutiveRejects >= 5) _initialize(fix, r);
      return _currentEstimate(fix);
    }
    _consecutiveRejects = 0;

    // ----------------------------------------------- تحديث Kalman (موضع)
    _correctPosition(innovE, innovN, inv00, inv01, inv11);

    // ---------------------------------------------- تحديث Kalman (سرعة)
    _correctVelocity(fix);

    // ---------------------------------------------------- حلقة العينات
    _ringE[_ringHead] = z.e;
    _ringN[_ringHead] = z.n;
    _ringHead = (_ringHead + 1) % _ringK;
    if (_ringCount < _ringK) _ringCount++;

    // ------------------------------------------------------- كشف السكون
    _updateMotion(fix, sigma);

    // -------------------------------------- التجميع الموزون أثناء السكون
    if (_motion == MotionState.stationary) {
      final w = 1.0 / r;
      _sumWE += w * z.e;
      _sumWN += w * z.n;
      _sumW += w;
      final alt = fix.alt;
      if (alt != null) {
        final va = fix.verticalAccuracyM;
        final wa = va != null && va > 0 ? 1.0 / (va * va) : w;
        _sumWAlt += wa * alt;
        _sumWAltW += wa;
      }
      _avgCount++;
      if (_avgCount > maxAveragingSamples) {
        // نافذة منزلقة تقريبية بلا تخزين: اضمحلال أسّي للأوزان القديمة.
        const decay = 0.995;
        _sumWE *= decay;
        _sumWN *= decay;
        _sumW *= decay;
        _sumWAlt *= decay;
        _sumWAltW *= decay;
      }
    }

    return _currentEstimate(fix);
  }

  // ------------------------------------------------------------------ داخلي

  double _measurementSigma(double? reported) {
    final base = (reported == null || reported <= 0) ? 10.0 : reported;
    final s = base * accuracyInflation;
    return s < minMeasurementSigmaM ? minMeasurementSigmaM : s;
  }

  double _dtSeconds(int elapsedNs) {
    final last = _lastElapsedNs;
    _lastElapsedNs = elapsedNs;
    if (last == null) return 1.0;
    final dt = (elapsedNs - last) / 1e9;
    return dt.clamp(0.05, 30.0); // حماية من ساعات شاذة أو عينات مكررة
  }

  void _initialize(GnssFix fix, double r) {
    _refLat = fix.lat;
    _refLon = fix.lon;
    _e = _n = _ve = _vn = 0;
    _p.fillRange(0, 16, 0);
    _p[0] = r;
    _p[5] = r;
    _p[10] = 4.0; // σv = 2 م/ث مبدئياً
    _p[15] = 4.0;
    _lastElapsedNs = fix.elapsedNs;
    _initialized = true;
    _motion = MotionState.unknown;
    _stillStreak = _moveStreak = 0;
    _consecutiveRejects = 0;
    _ringCount = _ringHead = 0;
    _resetAveraging();
  }

  void _predict(double dt) {
    _e += _ve * dt;
    _n += _vn * dt;

    // P = F P Fᵀ + Q ، F = [[1,0,dt,0],[0,1,0,dt],[0,0,1,0],[0,0,0,1]]
    final p = _p;
    final p00 = p[0], p01 = p[1], p02 = p[2], p03 = p[3];
    final p11 = p[5], p12 = p[6], p13 = p[7];
    final p22 = p[10], p23 = p[11], p33 = p[15];

    final n00 = p00 + 2 * dt * p02 + dt * dt * p22;
    final n01 = p01 + dt * (p03 + p12) + dt * dt * p23;
    final n02 = p02 + dt * p22;
    final n03 = p03 + dt * p23;
    final n11 = p11 + 2 * dt * p13 + dt * dt * p33;
    final n12 = p12 + dt * p23;
    final n13 = p13 + dt * p33;

    // ضوضاء عملية: نموذج تسارع أبيض متقطع (Bar-Shalom).
    final q = _motion == MotionState.stationary
        ? processNoiseStationaryMps2
        : processNoiseMovingMps2;
    final qq = q * q;
    final dt2 = dt * dt, dt3 = dt2 * dt, dt4 = dt3 * dt;
    final q00 = qq * dt4 / 4, q02 = qq * dt3 / 2, q22 = qq * dt2;

    p[0] = n00 + q00;
    p[1] = n01;
    p[2] = n02 + q02;
    p[3] = n03;
    p[4] = n01;
    p[5] = n11 + q00;
    p[6] = n12;
    p[7] = n13 + q02;
    p[8] = n02 + q02;
    p[9] = n12;
    p[10] = p22 + q22;
    p[11] = p23;
    p[12] = n03;
    p[13] = n13 + q02;
    p[14] = p23;
    p[15] = p33 + q22;
  }

  /// تحديث عام لقياس ثنائي على زوج الحالات (i0, i0+1) بعكس S المعطى.
  void _correct2(
    int i0,
    double innov0,
    double innov1,
    double inv00,
    double inv01,
    double inv11,
  ) {
    final p = _p;
    final k = _k;
    final c0 = i0, c1 = i0 + 1;
    // K = P Hᵀ S⁻¹ ; P Hᵀ = العمودان c0,c1 من P
    for (var i = 0; i < 4; i++) {
      final pi0 = p[i * 4 + c0], pi1 = p[i * 4 + c1];
      k[i * 2] = pi0 * inv00 + pi1 * inv01;
      k[i * 2 + 1] = pi0 * inv01 + pi1 * inv11;
    }
    _e += k[0] * innov0 + k[1] * innov1;
    _n += k[2] * innov0 + k[3] * innov1;
    _ve += k[4] * innov0 + k[5] * innov1;
    _vn += k[6] * innov0 + k[7] * innov1;

    // P = (I − K H) P ثم إجبار التناظر.
    final np = _tmp;
    for (var i = 0; i < 4; i++) {
      final ki0 = k[i * 2], ki1 = k[i * 2 + 1];
      for (var j = 0; j < 4; j++) {
        np[i * 4 + j] = p[i * 4 + j] - (ki0 * p[c0 * 4 + j] + ki1 * p[c1 * 4 + j]);
      }
    }
    for (var i = 0; i < 4; i++) {
      p[i * 4 + i] = math.max(np[i * 4 + i], 1e-6);
      for (var j = i + 1; j < 4; j++) {
        final v = 0.5 * (np[i * 4 + j] + np[j * 4 + i]);
        p[i * 4 + j] = v;
        p[j * 4 + i] = v;
      }
    }
  }

  void _correctPosition(
    double innovE,
    double innovN,
    double inv00,
    double inv01,
    double inv11,
  ) =>
      _correct2(0, innovE, innovN, inv00, inv01, inv11);

  /// قياس السرعة من Doppler. تحت [lowSpeedBearingMps] الاتجاه غير موثوق
  /// فنقيس (0,0) — وهذا بحد ذاته معلومة قوية: الهاتف ساكن.
  void _correctVelocity(GnssFix fix) {
    final speed = fix.speedMps;
    if (speed == null || speed < 0) return;
    double zve, zvn;
    final bearing = fix.bearingDeg;
    if (speed < lowSpeedBearingMps || bearing == null) {
      if (speed >= lowSpeedBearingMps) return; // سرعة بلا اتجاه: لا نعرف
      zve = 0;
      zvn = 0;
    } else {
      final b = GeoMath.toRad(bearing);
      zve = speed * math.sin(b);
      zvn = speed * math.cos(b);
    }
    var sv = fix.speedAccuracyMps ?? 0.5;
    if (sv < 0.3) sv = 0.3;
    final rv = sv * sv;

    final innovE = zve - _ve, innovN = zvn - _vn;
    final s00 = _p[10] + rv, s01 = _p[11], s11 = _p[15] + rv;
    final det = s00 * s11 - s01 * s01;
    if (!(det > 0) || !det.isFinite) return;
    final inv00 = s11 / det, inv01 = -s01 / det, inv11 = s00 / det;
    final mahal = innovE * (inv00 * innovE + inv01 * innovN) +
        innovN * (inv01 * innovE + inv11 * innovN);
    // بوابة متساهلة: التسارع الحقيقي عند بدء المشي مفاجئ.
    if (mahal > gateChiSquare95 * 4) return;
    _correct2(2, innovE, innovN, inv00, inv01, inv11);
  }

  void _updateMotion(GnssFix fix, double sigmaMeas) {
    final reportedSpeed = fix.speedMps;
    final filteredSpeed = math.sqrt(_ve * _ve + _vn * _vn);

    bool looksStill;
    if (reportedSpeed != null && reportedSpeed >= 0) {
      // Doppler أدق مصدر؛ نضيف هامش دقة السرعة إن وُجد.
      final acc = fix.speedAccuracyMps ?? 0;
      final thr = math.max(stationarySpeedMps, acc);
      looksStill = reportedSpeed < thr && filteredSpeed < 3 * thr;
    } else {
      looksStill = filteredSpeed < 2 * stationarySpeedMps;
    }

    // اختبار إزاحة إحصائي: متوسط آخر K عينات مقابل المتوسط التراكمي.
    // العتبة تتبع الضوضاء الفعلية حتى لا نتذبذب عند ضوضاء كبيرة.
    if (looksStill && _motion == MotionState.stationary && _sumW > 0 &&
        _ringCount == _ringK) {
      var me = 0.0, mn = 0.0;
      for (var i = 0; i < _ringK; i++) {
        me += _ringE[i];
        mn += _ringN[i];
      }
      me /= _ringK;
      mn /= _ringK;
      final ae = _sumWE / _sumW, an = _sumWN / _sumW;
      final d = math.sqrt((me - ae) * (me - ae) + (mn - an) * (mn - an));
      // σ لمتوسط K عينات مرتبطة ≈ σ·1.6/√K ؛ عتبة 3σ.
      final thr = math.max(
        minDisplacementGateM,
        3 * temporalCorrelationFactor * sigmaMeas / math.sqrt(_ringK),
      );
      if (d > thr) looksStill = false;
    }

    if (looksStill) {
      _stillStreak++;
      _moveStreak = 0;
      if (_motion != MotionState.stationary &&
          _stillStreak >= stationaryConfirmSamples) {
        _motion = MotionState.stationary;
        _resetAveraging();
        // سكون مؤكد: نصفّر السرعة ونقلّص تغايرها حتى لا تتضخم P الموضع.
        _ve = 0;
        _vn = 0;
        _p[10] = 0.01;
        _p[15] = 0.01;
        _p[2] = _p[3] = _p[6] = _p[7] = 0;
        _p[8] = _p[12] = _p[9] = _p[13] = 0;
        _p[11] = _p[14] = 0;
      }
    } else {
      _moveStreak++;
      _stillStreak = 0;
      if (_motion != MotionState.moving && _moveStreak >= movingConfirmSamples) {
        _motion = MotionState.moving;
        _resetAveraging();
        // نسمح للفلتر بالتقاط السرعة بسرعة.
        _p[10] = math.max(_p[10], 1.0);
        _p[15] = math.max(_p[15], 1.0);
      }
    }
  }

  PositionEstimate _currentEstimate(GnssFix last) {
    if (!_initialized) {
      return PositionEstimate(
        lat: last.lat,
        lon: last.lon,
        alt: last.alt,
        sigmaM: _measurementSigma(last.accuracyM),
        motion: MotionState.unknown,
        samplesAveraged: 0,
        rawAccuracyM: last.accuracyM,
        rejectedOutliers: _rejected,
        timeMs: last.timeMs,
      );
    }

    double outE = _e, outN = _n;
    // σ الفلتر؛ أثناء الحركة لا نعرض أقل من 0.35×σ القياس: Kalman متفائل
    // عند عدم مطابقة النموذج (منعطفات، مسار متعدد).
    double sigma = math.sqrt(math.max(_p[0], _p[5]));
    if (_motion != MotionState.stationary) {
      sigma = math.max(sigma, 0.35 * _lastSigmaMeas);
    }
    double? alt = last.alt;
    var averaged = 0;

    if (_motion == MotionState.stationary && _sumW > 0 && _avgCount >= 2) {
      outE = _sumWE / _sumW;
      outN = _sumWN / _sumW;
      averaged = _avgCount;
      // σ المتوسط الموزون = 1/√Σw مضروبة بعامل الارتباط الزمني.
      final sigmaAvg = temporalCorrelationFactor / math.sqrt(_sumW);
      sigma = math.min(sigma, sigmaAvg);
      if (_sumWAltW > 0) alt = _sumWAlt / _sumWAltW;
    }
    if (sigma < sigmaFloorM || !sigma.isFinite) sigma = sigmaFloorM;

    final ll = GeoMath.fromEnu(
      e: outE,
      n: outN,
      refLat: _refLat!,
      refLon: _refLon!,
    );
    return PositionEstimate(
      lat: ll.lat,
      lon: ll.lon,
      alt: alt,
      sigmaM: sigma,
      motion: _motion,
      samplesAveraged: averaged,
      rawAccuracyM: last.accuracyM,
      rejectedOutliers: _rejected,
      timeMs: last.timeMs,
    );
  }
}
