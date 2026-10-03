/// حل GNSS خام كما يصل من `LocationManager.GPS_PROVIDER`.
final class GnssFix {
  const GnssFix({
    required this.lat,
    required this.lon,
    required this.timeMs,
    required this.elapsedNs,
    this.alt,
    this.accuracyM,
    this.verticalAccuracyM,
    this.speedMps,
    this.speedAccuracyMps,
    this.bearingDeg,
    this.isMock = false,
    this.source = FixSource.gnss,
  });

  factory GnssFix.fromMap(Map<Object?, Object?> m) {
    double? d(Object? v) => v == null ? null : (v as num).toDouble();
    return GnssFix(
      lat: d(m['lat'])!,
      lon: d(m['lon'])!,
      alt: d(m['alt']),
      accuracyM: d(m['acc']),
      verticalAccuracyM: d(m['vacc']),
      speedMps: d(m['speed']),
      speedAccuracyMps: d(m['speedAcc']),
      bearingDeg: d(m['bearing']),
      timeMs: (m['timeMs'] as num).toInt(),
      elapsedNs: (m['elapsedNs'] as num).toInt(),
      isMock: m['mock'] == true,
      source: m['source'] == 'assist' ? FixSource.assist : FixSource.gnss,
    );
  }

  final double lat;
  final double lon;
  final double? alt;

  /// نصف قطر ثقة 68% بالأمتار كما يقدّره الـchipset (قد يكون متفائلاً).
  final double? accuracyM;
  final double? verticalAccuracyM;
  final double? speedMps;
  final double? speedAccuracyMps;
  final double? bearingDeg;

  /// وقت UTC بالملّي ثانية.
  final int timeMs;

  /// ساعة monotonic بالنانو ثانية — المرجع الصحيح لفروق الزمن.
  final int elapsedNs;
  final bool isMock;

  /// مصدر الحل: GNSS صافٍ أو مدمج (Wi-Fi/خلوي/GPS كما يراه النظام).
  final FixSource source;
}

/// مصدر حل الموقع.
enum FixSource { gnss, assist }

/// قمر واحد من `GnssStatus`.
final class SatelliteInfo {
  const SatelliteInfo({
    required this.svid,
    required this.constellation,
    required this.cn0DbHz,
    required this.elevationDeg,
    required this.azimuthDeg,
    required this.usedInFix,
    required this.hasEphemeris,
    this.band,
  });

  factory SatelliteInfo.fromMap(Map<Object?, Object?> m) => SatelliteInfo(
        svid: (m['svid'] as num).toInt(),
        constellation: m['constellation'] as String,
        cn0DbHz: (m['cn0'] as num).toDouble(),
        elevationDeg: (m['elevation'] as num).toDouble(),
        azimuthDeg: (m['azimuth'] as num).toDouble(),
        usedInFix: m['usedInFix'] == true,
        hasEphemeris: m['hasEphemeris'] == true,
        band: m['band'] as String?,
      );

  final int svid;
  final String constellation;
  final double cn0DbHz;
  final double elevationDeg;
  final double azimuthDeg;
  final bool usedInFix;
  final bool hasEphemeris;

  /// "L1" / "L5" / "L2" / null إن لم يُبلّغ الجهاز عن التردد.
  final String? band;
}

/// لقطة حالة السماء.
final class SkySnapshot {
  const SkySnapshot({
    required this.satellites,
    required this.visible,
    required this.usedInFix,
    required this.l5Used,
  });

  factory SkySnapshot.fromMap(Map<Object?, Object?> m) => SkySnapshot(
        satellites: (m['satellites'] as List<Object?>)
            .map((e) => SatelliteInfo.fromMap(e! as Map<Object?, Object?>))
            .toList(growable: false),
        visible: (m['count'] as num).toInt(),
        usedInFix: (m['usedInFix'] as num).toInt(),
        l5Used: (m['l5Used'] as num).toInt(),
      );

  static const empty =
      SkySnapshot(satellites: [], visible: 0, usedInFix: 0, l5Used: 0);

  final List<SatelliteInfo> satellites;
  final int visible;
  final int usedInFix;
  final int l5Used;

  /// متوسط C/N0 للأقمار المستخدمة في الحل — مؤشر جودة الإشارة.
  double get meanCn0Used {
    final used = satellites.where((s) => s.usedInFix);
    if (used.isEmpty) return 0;
    return used.fold<double>(0, (a, s) => a + s.cn0DbHz) / used.length;
  }

  bool get dualFrequency => l5Used > 0;
}

/// حالة الحركة كما يستنتجها المحرك.
enum MotionState { unknown, stationary, moving }

/// الناتج النهائي للمحرك في كل خطوة.
final class PositionEstimate {
  const PositionEstimate({
    required this.lat,
    required this.lon,
    required this.sigmaM,
    required this.motion,
    required this.samplesAveraged,
    required this.rawAccuracyM,
    required this.rejectedOutliers,
    required this.timeMs,
    this.alt,
  });

  final double lat;
  final double lon;
  final double? alt;

  /// الانحراف المعياري الأفقي المقدَّر (1σ ≈ 68%) بعد الفلترة/التجميع.
  final double sigmaM;
  final MotionState motion;

  /// عدد العينات الداخلة في المتوسط الثابت (0 إذا متحرك).
  final int samplesAveraged;

  /// دقة الـchipset الخام لآخر عينة — للمقارنة أمام المستخدم.
  final double? rawAccuracyM;
  final int rejectedOutliers;
  final int timeMs;

  /// نصف قطر 95% (2σ تقريباً للتوزيع ثنائي البُعد ≈ 2.45σ، نستخدم 2σ
  /// كمحافظة مقبولة شائعة في الخرائط).
  double get radius95M => sigmaM * 2.0;
}
