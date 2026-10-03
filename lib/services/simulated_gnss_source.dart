import 'dart:async';
import 'dart:math' as math;

import '../engine/geo_math.dart';
import '../engine/models.dart';
import 'gnss_service.dart';

/// مصدر محاكٍ للمعاينة على الويب (المتصفح لا يملك GNSS خاماً).
///
/// السيناريو (واقعي، مبني على أرقام Google I/O 2018 وBarbeau 2019):
///  0–8 ث    داخل مبنى: Fused ±18 م صحيح، GNSS منعكس (~170 م شرقاً، ±9 م مدّعاة)
///  8–20 ث   نمشي للخارج 1.4 م/ث: GNSS يعود للاتساق تدريجياً
///  20 ث+    سماء مفتوحة ثابتون: GNSS ±3 م خام → التجميع ينزل تحت المتر
/// Fused في العراء يبقى ±8 م (لا يتحسن) — وهنا يظهر الفرق.
final class SimulatedGnssSource implements GnssSource {
  SimulatedGnssSource({this.lat0 = 15.3547, this.lon0 = 44.2066, int seed = 7}) : _rng = math.Random(seed);

  final double lat0;
  final double lon0;
  final math.Random _rng;

  final _fix = StreamController<GnssFix>.broadcast();
  final _sky = StreamController<SkySnapshot>.broadcast();
  final _ttff = StreamController<int>.broadcast();
  final _raw = StreamController<RawSummary>.broadcast();
  Timer? _timer;
  int _t = 0;
  double _errE = 0, _errN = 0;

  double _gauss() {
    final u1 = 1 - _rng.nextDouble(), u2 = _rng.nextDouble();
    return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
  }

  @override
  Stream<GnssFix> get fixes => _fix.stream;
  @override
  Stream<void> get providerDisabled => const Stream.empty();
  @override
  Stream<SkySnapshot> get sky => _sky.stream;
  @override
  Stream<int> get firstFixMs => _ttff.stream;
  @override
  Stream<RawSummary> get raw => _raw.stream;

  @override
  Future<bool> start() async {
    _timer?.cancel();
    _t = 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    return true;
  }

  @override
  Future<void> stop() async => _timer?.cancel();

  @override
  Future<void> refresh() async => _tick();

  @override
  Future<GnssCapabilities> capabilities() async => const GnssCapabilities(
        sdk: 34,
        model: 'محاكاة (معاينة ويب)',
        gpsEnabled: true,
        hasFinePermission: true,
        hardwareModelName: 'SIM L1+L5',
        yearOfHardware: 2023,
        hasMeasurements: true,
        assistProvider: 'fused(sim)',
      );

  @override
  Future<PermissionStatus> requestPermission() async => PermissionStatus.granted;
  @override
  Future<void> openLocationSettings() async {}
  @override
  Future<void> openAppSettings() async {}

  void _tick() {
    _t++;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final elapsedNs = _t * 1000000000;

    // الموقع الحقيقي: نخرج من المبنى 12 ث مشياً شمالاً ثم نقف.
    final walkT = (_t - 8).clamp(0, 12);
    final trueN = 1.4 * walkT;
    final speed = _t > 8 && _t <= 20 ? 1.4 : 0.0;
    final indoors = _t <= 8;
    final transitioning = _t > 8 && _t <= 20;

    // Fused: ±18 م داخل، ±8 م خارج؛ ضوضاء بسيطة.
    final fAcc = indoors ? 18.0 : 8.0;
    final fll = GeoMath.fromEnu(e: _gauss() * fAcc * 0.4, n: trueN + _gauss() * fAcc * 0.4, refLat: lat0, refLon: lon0);
    _fix.add(GnssFix(lat: fll.lat, lon: fll.lon, accuracyM: fAcc, timeMs: nowMs, elapsedNs: elapsedNs, source: FixSource.assist));

    if (_t == 1) _ttff.add(2300);

    // GNSS: منعكس داخل المبنى، ثم يتسق.
    const sigma = 3.0;
    const rho = 0.7;
    _errE = rho * _errE + sigma * math.sqrt(1 - rho * rho) * _gauss();
    _errN = rho * _errN + sigma * math.sqrt(1 - rho * rho) * _gauss();
    final biasE = indoors ? 170.0 : (transitioning ? 170.0 * (1 - (_t - 8) / 12) * 0.3 : 0.0);
    final gll = GeoMath.fromEnu(e: biasE + _errE, n: trueN + _errN, refLat: lat0, refLon: lon0);
    final used = indoors ? 6 : (transitioning ? 9 : 14);
    _fix.add(GnssFix(
      lat: gll.lat,
      lon: gll.lon,
      alt: 2250 + _gauss() * 4,
      accuracyM: indoors ? 9.0 : sigma,
      verticalAccuracyM: 6,
      speedMps: math.max(0, speed + 0.12 * _gauss()),
      speedAccuracyMps: 0.25,
      bearingDeg: speed > 0.5 ? 0 + 4 * _gauss() : null,
      timeMs: nowMs,
      elapsedNs: elapsedNs,
    ));

    final sats = <SatelliteInfo>[];
    const consts = ['GPS', 'Galileo', 'BeiDou', 'GLONASS'];
    for (var i = 0; i < used + 8; i++) {
      final inFix = i < used;
      sats.add(SatelliteInfo(
        svid: 1 + i * 3 % 32,
        constellation: consts[i % 4],
        cn0DbHz: (inFix ? 38 : 24) + 6 * math.sin(i + _t / 9),
        elevationDeg: 15 + (i * 37 % 70).toDouble(),
        azimuthDeg: (i * 53 % 360).toDouble(),
        usedInFix: inFix,
        hasEphemeris: true,
        band: i % 3 == 0 ? 'L5' : 'L1',
      ));
    }
    _sky.add(SkySnapshot(satellites: sats, visible: sats.length, usedInFix: used, l5Used: (used + 2) ~/ 3));
    _raw.add(RawSummary(measurements: used + 8, adrValid: indoors ? 0 : used - 2, agcMeanDb: 3.1 + 0.2 * _gauss()));
  }
}
