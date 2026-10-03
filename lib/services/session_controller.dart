import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../engine/geo_math.dart';
import '../engine/models.dart';
import '../engine/position_estimator.dart';
import 'csv_logger.dart';
import 'gnss_service.dart';

/// حالة الواجهة العامة.
enum SessionPhase { idle, needPermission, permissionDeniedForever, gpsOff, acquiring, tracking }

/// نقطة مثبّتة يدوياً من المستخدم (لاختبار التكرارية / القياس بالشريط).
final class SavedPoint {
  const SavedPoint({
    required this.index,
    required this.lat,
    required this.lon,
    required this.sigmaM,
    required this.samples,
    required this.time,
    this.alt,
  });

  final int index;
  final double lat;
  final double lon;
  final double? alt;
  final double sigmaM;
  final int samples;
  final DateTime time;
}

/// العقل المدبّر: يستهلك البث الأصلي، يغذّي المحرك، يحدّث الواجهة ويسجّل CSV.
///
/// `notifyListeners` يُستدعى مرة واحدة لكل حل (1 Hz) — لا إعادة بناء عند
/// كل تحديث أقمار (قد تصل 10 Hz) إلا إذا تغيّر العدد المستخدم.
final class SessionController extends ChangeNotifier {
  SessionController({GnssService? service, PositionEstimator? estimator})
      : _service = service ?? GnssService(),
        _estimator = estimator ?? PositionEstimator();

  final GnssService _service;
  final PositionEstimator _estimator;
  final CsvLogger _logger = CsvLogger();

  StreamSubscription<GnssFix>? _fixSub;
  StreamSubscription<SkySnapshot>? _skySub;
  StreamSubscription<int>? _ttffSub;
  StreamSubscription<RawSummary>? _rawSub;
  StreamSubscription<void>? _disabledSub;
  Timer? _staleTimer;

  SessionPhase _phase = SessionPhase.idle;
  GnssCapabilities? _caps;
  GnssFix? _lastFix;
  PositionEstimate? _estimate;
  SkySnapshot _sky = SkySnapshot.empty;
  RawSummary? _raw;
  int? _ttffMs;
  bool _stale = false;
  int _fixCount = 0;
  int _session = 1;
  final List<SavedPoint> _saved = [];
  DateTime? _startedAt;

  SessionPhase get phase => _phase;
  GnssCapabilities? get capabilities => _caps;
  GnssFix? get lastFix => _lastFix;
  PositionEstimate? get estimate => _estimate;
  SkySnapshot get sky => _sky;
  RawSummary? get raw => _raw;
  int? get ttffMs => _ttffMs;

  /// لم يصل حل منذ > 3 ثوانٍ (سقف/نفق).
  bool get isStale => _stale;
  int get fixCount => _fixCount;
  int get session => _session;
  List<SavedPoint> get savedPoints => List.unmodifiable(_saved);
  bool get isLogging => _logger.isActive;
  int get logLines => _logger.lines;
  DateTime? get startedAt => _startedAt;

  /// الزمن منذ آخر إعادة ضبط للتجميع (لعرض "ثبّت لمدة…").
  Duration get elapsed => _startedAt == null ? Duration.zero : DateTime.now().difference(_startedAt!);

  // ------------------------------------------------------------ دورة الحياة

  Future<void> init() async {
    _caps = await _service.capabilities();
    if (!_caps!.hasFinePermission) {
      _phase = SessionPhase.needPermission;
    } else if (!_caps!.gpsEnabled) {
      _phase = SessionPhase.gpsOff;
    } else {
      await _begin();
      return;
    }
    notifyListeners();
  }

  Future<void> requestPermission() async {
    final s = await _service.requestPermission();
    switch (s) {
      case PermissionStatus.granted:
        await init();
      case PermissionStatus.deniedForever:
        _phase = SessionPhase.permissionDeniedForever;
        notifyListeners();
      case PermissionStatus.denied:
      case PermissionStatus.unavailable:
        _phase = SessionPhase.needPermission;
        notifyListeners();
    }
  }

  Future<void> openLocationSettings() => _service.openLocationSettings();
  Future<void> openAppSettings() => _service.openAppSettings();

  /// يُستدعى عند عودة التطبيق للمقدمة (قد يكون المستخدم فعّل GPS).
  Future<void> onResumed() async {
    if (_phase == SessionPhase.gpsOff ||
        _phase == SessionPhase.needPermission ||
        _phase == SessionPhase.permissionDeniedForever) {
      await init();
    }
  }

  Future<void> _begin() async {
    final ok = await _service.start();
    if (!ok) {
      _caps = await _service.capabilities();
      _phase = !_caps!.hasFinePermission ? SessionPhase.needPermission : SessionPhase.gpsOff;
      notifyListeners();
      return;
    }
    _phase = SessionPhase.acquiring;
    _startedAt = DateTime.now();
    _fixSub ??= _service.fixes.listen(_onFix);
    _skySub ??= _service.sky.listen(_onSky);
    _ttffSub ??= _service.firstFixMs.listen((ms) {
      _ttffMs = ms;
      notifyListeners();
    });
    _rawSub ??= _service.raw.listen((r) => _raw = r);
    _disabledSub ??= _service.providerDisabled.listen((_) {
      _phase = SessionPhase.gpsOff;
      notifyListeners();
    });
    _armStaleTimer();
    notifyListeners();
  }

  void _armStaleTimer() {
    _staleTimer?.cancel();
    _staleTimer = Timer(const Duration(seconds: 3), () {
      _stale = true;
      notifyListeners();
    });
  }

  // ----------------------------------------------------------------- أحداث

  void _onFix(GnssFix fix) {
    _lastFix = fix;
    _fixCount++;
    _stale = false;
    _armStaleTimer();
    _estimate = _estimator.update(fix);
    if (_phase == SessionPhase.acquiring) _phase = SessionPhase.tracking;
    if (_logger.isActive) {
      _logger.write(fix: fix, est: _estimate!, sky: _sky, session: _session);
    }
    notifyListeners();
  }

  void _onSky(SkySnapshot sky) {
    final changed = sky.usedInFix != _sky.usedInFix ||
        sky.visible != _sky.visible ||
        sky.l5Used != _sky.l5Used ||
        _phase == SessionPhase.acquiring;
    _sky = sky;
    if (changed) notifyListeners();
  }

  // ----------------------------------------------------------- أوامر المستخدم

  /// يعيد ضبط المحرك ويبدأ جلسة تجميع جديدة (للتكرارية).
  void resetEstimator() {
    _estimator.reset();
    _estimate = null;
    _session++;
    _startedAt = DateTime.now();
    notifyListeners();
  }

  /// يحفظ التقدير الحالي كنقطة مرقّمة؛ يعيد null إن لا تقدير.
  SavedPoint? savePoint() {
    final e = _estimate;
    if (e == null) return null;
    final p = SavedPoint(
      index: _saved.length + 1,
      lat: e.lat,
      lon: e.lon,
      alt: e.alt,
      sigmaM: e.sigmaM,
      samples: e.samplesAveraged,
      time: DateTime.now(),
    );
    _saved.add(p);
    notifyListeners();
    return p;
  }

  void clearSavedPoints() {
    _saved.clear();
    notifyListeners();
  }

  /// المسافة بين آخر نقطتين محفوظتين (لاختبار الشريط 50 م).
  double? get lastTwoDistanceM {
    if (_saved.length < 2) return null;
    final a = _saved[_saved.length - 2], b = _saved.last;
    return GeoMath.haversineM(a.lat, a.lon, b.lat, b.lon);
  }

  /// إحصاء تكرارية النقاط المحفوظة: المسافة القصوى عن متوسطها.
  ({double meanLat, double meanLon, double maxSpreadM, double rmsM})? get repeatability {
    if (_saved.length < 2) return null;
    var la = 0.0, lo = 0.0;
    for (final p in _saved) {
      la += p.lat;
      lo += p.lon;
    }
    la /= _saved.length;
    lo /= _saved.length;
    var maxD = 0.0, sq = 0.0;
    for (final p in _saved) {
      final d = GeoMath.haversineM(p.lat, p.lon, la, lo);
      if (d > maxD) maxD = d;
      sq += d * d;
    }
    return (meanLat: la, meanLon: lo, maxSpreadM: maxD, rmsM: math.sqrt(sq / _saved.length));
  }

  Future<File> startLogging() async {
    final f = await _logger.start();
    notifyListeners();
    return f;
  }

  Future<File?> stopLogging() async {
    final f = await _logger.stop();
    notifyListeners();
    return f;
  }

  @override
  Future<void> dispose() async {
    _staleTimer?.cancel();
    await _fixSub?.cancel();
    await _skySub?.cancel();
    await _ttffSub?.cancel();
    await _rawSub?.cancel();
    await _disabledSub?.cancel();
    await _logger.stop();
    await _service.stop();
    super.dispose();
  }
}
