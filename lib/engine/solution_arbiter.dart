import 'dart:math' as math;

import 'geo_math.dart';
import 'models.dart';

/// سبب اختيار الحل المعروض.
enum ArbiterReason {
  /// لا شيء بعد.
  none,

  /// GNSS متسق مع المدمج (أو لا مدمج) → نعرض تقديرنا الأدق.
  gnssTrusted,

  /// GNSS يخالف المدمج بأكثر من حدود الثقة (داخل مبنى/انعكاسات) → المدمج.
  gnssInconsistent,

  /// GNSS ضعيف جداً (σ كبيرة أو أقمار قليلة) → المدمج مؤقتاً.
  gnssWeak,

  /// لا GNSS بعد؛ المدمج فقط حتى يصل.
  gnssMissing,
}

/// الحل النهائي المعروض للمستخدم.
final class DisplaySolution {
  const DisplaySolution({
    required this.lat,
    required this.lon,
    required this.sigmaM,
    required this.source,
    required this.reason,
    required this.alt,
    required this.timeMs,
    this.gnssDisagreementM,
  });

  final double lat;
  final double lon;
  final double sigmaM;
  final double? alt;
  final FixSource source;
  final ArbiterReason reason;
  final int timeMs;

  /// المسافة بين حل GNSS والمدمج وقت القرار (للتشخيص).
  final double? gnssDisagreementM;

  double get radius95M => sigmaM * 2;
}

/// حكم بين تقدير GNSS المُرشَّح وحل النظام المدمج.
///
/// القاعدة الذهبية: **لا نكون أبداً أسوأ من مدمج النظام (WhatsApp)**.
/// - إن اتفق الاثنان ضمن حدود الثقة → نعرض GNSS (الأدق في العراء).
/// - إن اختلفا بأكثر من k·√(σ²_gnss + σ²_assist) → GNSS مضلَّل بالانعكاسات
///   (داخل مبنى/شارع ضيق) → نعرض المدمج بدقته هو.
/// - GNSS بلا أقمار كافية أو σ ضخمة → المدمج.
/// - بعد الاتفاق نحتاج [consistentConfirm] عينات متتالية قبل الرجوع لـGNSS
///   (هستيرية تمنع التذبذب بين المصدرين).
final class SolutionArbiter {
  SolutionArbiter({
    this.disagreementK = 2.5,
    this.minUsedSatellites = 5,
    this.maxGnssSigmaM = 25,
    this.assistMaxAgeMs = 15000,
    this.consistentConfirm = 3,
  });

  /// مضاعف الانحراف المشترك لاعتبار الحلين متناقضين.
  final double disagreementK;
  final int minUsedSatellites;
  final double maxGnssSigmaM;
  final int assistMaxAgeMs;
  final int consistentConfirm;

  GnssFix? _assist;
  int _consistentStreak = 0;
  bool _trustingGnss = false;

  ArbiterReason _lastReason = ArbiterReason.none;
  ArbiterReason get lastReason => _lastReason;

  void reset() {
    _assist = null;
    _consistentStreak = 0;
    _trustingGnss = false;
    _lastReason = ArbiterReason.none;
  }

  /// يُغذَّى بكل حل مدمج.
  void updateAssist(GnssFix fix) {
    if (fix.isMock) return;
    _assist = fix;
  }

  /// يقرر الحل المعروض. [estimate] قد يكون null قبل أول حل GNSS.
  DisplaySolution? decide({
    required PositionEstimate? estimate,
    required int usedSatellites,
    required int nowMs,
  }) {
    final a = _assist;
    final assistFresh = a != null && (nowMs - a.timeMs) <= assistMaxAgeMs;
    final assistSigma = a == null ? double.infinity : math.max(a.accuracyM ?? 50.0, 5.0);

    if (estimate == null) {
      if (a == null) return null;
      return _fromAssist(a, assistSigma, ArbiterReason.gnssMissing, null);
    }

    final gnssWeak = usedSatellites < minUsedSatellites || estimate.sigmaM > maxGnssSigmaM;

    if (!assistFresh) {
      // لا مدمج حديث: GNSS هو كل ما لدينا.
      _lastReason = gnssWeak ? ArbiterReason.gnssWeak : ArbiterReason.gnssTrusted;
      return _fromGnss(estimate, null);
    }

    final d = GeoMath.haversineM(estimate.lat, estimate.lon, a.lat, a.lon);
    final joint = math.sqrt(estimate.sigmaM * estimate.sigmaM + assistSigma * assistSigma);
    final consistent = d <= disagreementK * joint;

    if (gnssWeak) {
      _consistentStreak = 0;
      _trustingGnss = false;
      // GNSS ضعيف ⇒ σ الخاصة به غير موثوقة أصلاً. نعرضه فقط إن كان المدمج
      // أسوأ منه بوضوح (≥3×، مثل خلوي 800 م) ومتسقاً معه.
      if (assistSigma >= 3 * estimate.sigmaM && consistent) {
        _lastReason = ArbiterReason.gnssWeak;
        return _fromGnss(estimate, d);
      }
      return _fromAssist(a, assistSigma, ArbiterReason.gnssWeak, d);
    }

    if (consistent) {
      _consistentStreak++;
      if (_consistentStreak >= consistentConfirm || _trustingGnss) {
        _trustingGnss = true;
        _lastReason = ArbiterReason.gnssTrusted;
        return _fromGnss(estimate, d);
      }
      // في فترة التأكيد: نعرض الأدق من الاثنين بحذر.
      if (estimate.sigmaM <= assistSigma) {
        _lastReason = ArbiterReason.gnssTrusted;
        return _fromGnss(estimate, d);
      }
      return _fromAssist(a, assistSigma, ArbiterReason.gnssInconsistent, d);
    }

    // متناقضان: GNSS مضلَّل. المدمج بدقته.
    _consistentStreak = 0;
    _trustingGnss = false;
    return _fromAssist(a, assistSigma, ArbiterReason.gnssInconsistent, d);
  }

  DisplaySolution _fromGnss(PositionEstimate e, double? d) => DisplaySolution(
        lat: e.lat,
        lon: e.lon,
        sigmaM: e.sigmaM,
        alt: e.alt,
        source: FixSource.gnss,
        reason: _lastReason,
        timeMs: e.timeMs,
        gnssDisagreementM: d,
      );

  DisplaySolution _fromAssist(GnssFix a, double sigma, ArbiterReason r, double? d) {
    _lastReason = r;
    return DisplaySolution(
      lat: a.lat,
      lon: a.lon,
      sigmaM: sigma,
      alt: a.alt,
      source: FixSource.assist,
      reason: r,
      timeMs: a.timeMs,
      gnssDisagreementM: d,
    );
  }
}
