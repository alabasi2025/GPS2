import 'dart:math' as math;

/// تنسيقات عرض خفيفة (بلا intl في المسار الساخن).
abstract final class Fmt {
  /// إحداثيات بـ 7 منازل (≈ 1 سم) — مناسبة للنسخ والمشاركة.
  static String coord(double v) => v.toStringAsFixed(7);

  /// أمتار بذكاء: < 10 م منزلة واحدة؛ غير ذلك عدد صحيح.
  static String meters(double m) {
    if (!m.isFinite) return '—';
    if (m < 10) return '${m.toStringAsFixed(1)} م';
    if (m < 1000) return '${m.round()} م';
    return '${(m / 1000).toStringAsFixed(2)} كم';
  }

  static String metersShort(double m) =>
      !m.isFinite ? '—' : (m < 10 ? m.toStringAsFixed(1) : m.round().toString());

  static String duration(Duration d) {
    final s = d.inSeconds;
    if (s < 60) return '$s ث';
    final m = s ~/ 60, r = s % 60;
    if (m < 60) return '$m:${r.toString().padLeft(2, '0')} د';
    return '${d.inHours}:${(m % 60).toString().padLeft(2, '0')} س';
  }

  /// درجات/دقائق/ثوانٍ (لمن يقارن بعلامة مساحية).
  static String dms(double deg, {required bool isLat}) {
    final hemi = isLat ? (deg >= 0 ? 'N' : 'S') : (deg >= 0 ? 'E' : 'W');
    final a = deg.abs();
    final d = a.floor();
    final mFull = (a - d) * 60;
    final m = mFull.floor();
    final s = (mFull - m) * 60;
    return '$d° ${m.toString().padLeft(2, '0')}′ ${s.toStringAsFixed(2).padLeft(5, '0')}″ $hemi';
  }

  static String googleMapsUrl(double lat, double lon) =>
      'https://maps.google.com/?q=${coord(lat)},${coord(lon)}';

  static String geoUri(double lat, double lon, {String? label}) {
    final q = '${coord(lat)},${coord(lon)}';
    final l = label == null ? '' : '(${Uri.encodeComponent(label)})';
    return 'geo:$q?q=$q$l';
  }

  static String sigmaLabel(double sigmaM) {
    if (sigmaM <= 1.0) return 'ممتاز';
    if (sigmaM <= 3.0) return 'جيد';
    if (sigmaM <= 8.0) return 'متوسط';
    return 'ضعيف';
  }

  static double clamp01(double v) => math.min(1, math.max(0, v));
}
