import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../engine/models.dart';
import '../engine/solution_arbiter.dart';

/// سجل CSV لكل عينة — أساس المنهجية العلمية للاختبار:
/// يمكن مقارنة الخام مقابل المُرشَّح، وحساب تكرارية الجلسات، والتحقق من
/// صدق دائرة الثقة بعد الرجوع للنقطة نفسها.
///
/// الكتابة مُجمَّعة (buffer) وتُدفَع كل [flushEvery] سطراً لتقليل I/O.
final class CsvLogger {
  CsvLogger({this.flushEvery = 20});

  static const header =
      'time_ms,lat_raw,lon_raw,alt_raw,acc_raw_m,speed_mps,bearing_deg,'
      'lat_est,lon_est,alt_est,sigma_m,radius95_m,motion,samples_avg,'
      'rejected,sats_visible,sats_used,l5_used,mean_cn0,session,'
      'shown_lat,shown_lon,shown_sigma_m,shown_source,shown_reason';

  final int flushEvery;
  final StringBuffer _buf = StringBuffer();
  int _pending = 0;
  int _lines = 0;
  File? _file;
  IOSink? _sink; // ignore: close_sinks

  bool get isActive => _sink != null;
  int get lines => _lines;
  File? get file => _file;

  Future<File> start() async {
    await stop();
    final dir = await getApplicationDocumentsDirectory();
    final logs = Directory('${dir.path}/logs');
    if (!logs.existsSync()) logs.createSync(recursive: true);
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
    final f = File('${logs.path}/pointgps_$stamp.csv');
    _sink = f.openWrite();
    _sink!.writeln(header);
    _file = f;
    _lines = 0;
    return f;
  }

  void write({
    required GnssFix fix,
    required PositionEstimate est,
    required SkySnapshot sky,
    required int session,
    DisplaySolution? solution,
  }) {
    final s = _sink;
    if (s == null) return;
    _buf
      ..write(fix.timeMs)
      ..write(',')
      ..write(fix.lat.toStringAsFixed(8))
      ..write(',')
      ..write(fix.lon.toStringAsFixed(8))
      ..write(',')
      ..write(_f(fix.alt, 2))
      ..write(',')
      ..write(_f(fix.accuracyM, 2))
      ..write(',')
      ..write(_f(fix.speedMps, 2))
      ..write(',')
      ..write(_f(fix.bearingDeg, 1))
      ..write(',')
      ..write(est.lat.toStringAsFixed(8))
      ..write(',')
      ..write(est.lon.toStringAsFixed(8))
      ..write(',')
      ..write(_f(est.alt, 2))
      ..write(',')
      ..write(est.sigmaM.toStringAsFixed(2))
      ..write(',')
      ..write(est.radius95M.toStringAsFixed(2))
      ..write(',')
      ..write(est.motion.name)
      ..write(',')
      ..write(est.samplesAveraged)
      ..write(',')
      ..write(est.rejectedOutliers)
      ..write(',')
      ..write(sky.visible)
      ..write(',')
      ..write(sky.usedInFix)
      ..write(',')
      ..write(sky.l5Used)
      ..write(',')
      ..write(sky.meanCn0Used.toStringAsFixed(1))
      ..write(',')
      ..write(session)
      ..write(',')
      ..write(solution == null ? '' : solution.lat.toStringAsFixed(8))
      ..write(',')
      ..write(solution == null ? '' : solution.lon.toStringAsFixed(8))
      ..write(',')
      ..write(solution == null ? '' : solution.sigmaM.toStringAsFixed(2))
      ..write(',')
      ..write(solution?.source.name ?? '')
      ..write(',')
      ..write(solution?.reason.name ?? '')
      ..write('\n');
    _pending++;
    _lines++;
    if (_pending >= flushEvery) _flush();
  }

  void _flush() {
    final s = _sink;
    if (s == null || _pending == 0) return;
    s.write(_buf.toString());
    _buf.clear();
    _pending = 0;
  }

  Future<File?> stop() async {
    final s = _sink;
    if (s == null) return null;
    _flush();
    await s.flush();
    await s.close();
    _sink = null;
    return _file;
  }

  static String _f(double? v, int digits) => v == null ? '' : v.toStringAsFixed(digits);
}
