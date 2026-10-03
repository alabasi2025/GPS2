import 'dart:math' as math;

/// رياضيات جيوديسية خفيفة على WGS-84.
///
/// نعمل في إطار محلي مستوٍ (ENU: شرق/شمال بالأمتار) حول نقطة مرجعية؛
/// لمسافات أقل من بضعة كيلومترات الخطأ أقل من ملّيمتر، وهذا يجعل فلتر
/// Kalman خطياً بالكامل ويتجنّب حساب مثلثات كروية في كل عينة.
abstract final class GeoMath {
  static const double earthRadiusM = 6378137.0; // WGS-84 semi-major
  static const double _flattening = 1 / 298.257223563;
  static const double _e2 = _flattening * (2 - _flattening);

  static double toRad(double deg) => deg * math.pi / 180.0;
  static double toDeg(double rad) => rad * 180.0 / math.pi;

  /// نصف قطر الانحناء في اتجاه الزوال (شمال-جنوب) عند خط عرض.
  static double meridionalRadius(double latRad) {
    final s = math.sin(latRad);
    final d = 1 - _e2 * s * s;
    return earthRadiusM * (1 - _e2) / (d * math.sqrt(d));
  }

  /// نصف قطر الانحناء في الاتجاه العمودي الأول (شرق-غرب).
  static double primeVerticalRadius(double latRad) {
    final s = math.sin(latRad);
    return earthRadiusM / math.sqrt(1 - _e2 * s * s);
  }

  /// أمتار لكل درجة خط عرض عند خط عرض معين.
  static double metersPerDegLat(double latDeg) =>
      meridionalRadius(toRad(latDeg)) * math.pi / 180.0;

  /// أمتار لكل درجة خط طول عند خط عرض معين.
  static double metersPerDegLon(double latDeg) {
    final latRad = toRad(latDeg);
    return primeVerticalRadius(latRad) * math.cos(latRad) * math.pi / 180.0;
  }

  /// (lat, lon) → (east, north) بالأمتار حول مرجع.
  static ({double e, double n}) toEnu({
    required double lat,
    required double lon,
    required double refLat,
    required double refLon,
  }) {
    return (
      e: (lon - refLon) * metersPerDegLon(refLat),
      n: (lat - refLat) * metersPerDegLat(refLat),
    );
  }

  /// (east, north) → (lat, lon).
  static ({double lat, double lon}) fromEnu({
    required double e,
    required double n,
    required double refLat,
    required double refLon,
  }) {
    return (
      lat: refLat + n / metersPerDegLat(refLat),
      lon: refLon + e / metersPerDegLon(refLat),
    );
  }

  /// مسافة Haversine بالأمتار (كافية للعرض والاختبار؛ خطأ < 0.5%).
  static double haversineM(double lat1, double lon1, double lat2, double lon2) {
    final dLat = toRad(lat2 - lat1);
    final dLon = toRad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(toRad(lat1)) *
            math.cos(toRad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return 2 * earthRadiusM * math.asin(math.min(1, math.sqrt(a)));
  }
}
