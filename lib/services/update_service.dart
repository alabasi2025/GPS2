import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:convert/convert.dart' show AccumulatorSink;
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

/// وصف إصدار منشور في GitHub Releases (ملف latest.json الذي يولّده CI).
final class ReleaseInfo {
  const ReleaseInfo({
    required this.versionName,
    required this.versionCode,
    required this.tag,
    required this.apkUrl,
    required this.sha256,
    required this.sizeBytes,
    required this.notes,
    required this.publishedAt,
  });

  factory ReleaseInfo.fromJson(Map<String, Object?> j) => ReleaseInfo(
        versionName: j['versionName'] as String? ?? '?',
        versionCode: (j['versionCode'] as num?)?.toInt() ?? 0,
        tag: j['tag'] as String? ?? '',
        apkUrl: j['apk'] as String? ?? '',
        sha256: (j['sha256'] as String? ?? '').toLowerCase(),
        sizeBytes: (j['sizeBytes'] as num?)?.toInt() ?? 0,
        notes: j['notes'] as String? ?? '',
        publishedAt: j['publishedAt'] as String? ?? '',
      );

  final String versionName;
  final int versionCode;
  final String tag;
  final String apkUrl;
  final String sha256;
  final int sizeBytes;
  final String notes;
  final String publishedAt;
}

enum UpdatePhase { idle, checking, upToDate, available, downloading, verifying, readyToInstall, needInstallPermission, error }

/// خدمة التحديث الذاتي من GitHub Releases.
///
/// المسار: latest.json → مقارنة versionCode → تنزيل متدفق مع تقدم → SHA-256
/// → مثبّت النظام. لا يُثبَّت أي ملف لا يطابق البصمة المنشورة.
final class UpdateService extends ChangeNotifier {
  UpdateService({
    this.repo = 'alabasi2025/GPS2',
    http.Client? client,
    MethodChannel? channel,
    this.currentVersionCodeOverride,
  })  : _client = client ?? http.Client(),
        _ch = channel ?? const MethodChannel('point_gps/update');

  /// owner/repo في GitHub.
  final String repo;
  final http.Client _client;
  final MethodChannel _ch;

  /// للاختبار/الويب: تجاوز قراءة versionCode من النظام.
  final int? currentVersionCodeOverride;

  UpdatePhase _phase = UpdatePhase.idle;
  ReleaseInfo? _latest;
  int _current = 0;
  double _progress = 0; // 0..1
  int _received = 0;
  String? _error;
  File? _downloaded;
  DateTime? _lastCheck;

  UpdatePhase get phase => _phase;
  ReleaseInfo? get latest => _latest;
  int get currentVersionCode => _current;
  double get progress => _progress;
  int get receivedBytes => _received;
  String? get error => _error;
  DateTime? get lastCheck => _lastCheck;
  bool get hasUpdate => _latest != null && _latest!.versionCode > _current;

  Uri get _latestJsonUri => Uri.parse('https://github.com/$repo/releases/latest/download/latest.json');

  Future<int> _readCurrentVersion() async {
    if (currentVersionCodeOverride != null) return currentVersionCodeOverride!;
    if (kIsWeb) return 0;
    try {
      final v = await _ch.invokeMethod<Object>('versionCode');
      return (v as num?)?.toInt() ?? 0;
    } on PlatformException {
      return 0;
    }
  }

  /// يفحص آخر إصدار. يعيد true إن وُجد تحديث.
  Future<bool> check() async {
    _set(UpdatePhase.checking, error: null);
    try {
      _current = await _readCurrentVersion();
      final r = await _client.get(_latestJsonUri, headers: {'Accept': 'application/json'}).timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) {
        throw HttpException('latest.json → HTTP ${r.statusCode}');
      }
      final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, Object?>;
      _latest = ReleaseInfo.fromJson(j);
      _lastCheck = DateTime.now();
      if (_latest!.sha256.length != 64 || _latest!.apkUrl.isEmpty) {
        throw const FormatException('latest.json ناقص (sha256/apk)');
      }
      _set(hasUpdate ? UpdatePhase.available : UpdatePhase.upToDate);
      return hasUpdate;
    } on Object catch (e) {
      _set(UpdatePhase.error, error: _friendly(e));
      return false;
    }
  }

  /// ينزّل الـAPK ويتحقق من البصمة. يعيد الملف الجاهز أو null.
  Future<File?> download() async {
    final rel = _latest;
    if (rel == null || !hasUpdate) return null;
    _progress = 0;
    _received = 0;
    _set(UpdatePhase.downloading, error: null);
    try {
      final dirPath = kIsWeb ? null : await _ch.invokeMethod<String>('cacheDir');
      if (dirPath == null) throw const FileSystemException('cacheDir غير متاح');
      final dir = Directory(dirPath);
      if (!dir.existsSync()) dir.createSync(recursive: true);
      // تنظيف ملفات قديمة
      for (final f in dir.listSync().whereType<File>()) {
        if (!f.path.endsWith('${rel.versionCode}.apk')) {
          try {
            f.deleteSync();
          } on FileSystemException {
            // تجاهل
          }
        }
      }
      final out = File('${dir.path}/point_gps_${rel.versionCode}.apk');

      // إن كان موجوداً ومطابقاً لا نعيد التنزيل
      if (out.existsSync() && await _sha256(out) == rel.sha256) {
        _downloaded = out;
        _progress = 1;
        _set(UpdatePhase.readyToInstall);
        return out;
      }

      final req = http.Request('GET', Uri.parse(rel.apkUrl))..followRedirects = true..maxRedirects = 8;
      final resp = await _client.send(req).timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200) throw HttpException('APK → HTTP ${resp.statusCode}');
      final total = resp.contentLength ?? rel.sizeBytes;
      final sink = out.openWrite();
      final digest = AccumulatorSink<Digest>();
      final hasher = sha256.startChunkedConversion(digest);
      var lastNotify = DateTime.now();
      var lastProgress = 0.0;
      try {
        await for (final chunk in resp.stream) {
          sink.add(chunk);
          hasher.add(chunk);
          _received += chunk.length;
          if (total > 0) _progress = (_received / total).clamp(0, 1);
          final now = DateTime.now();
          // إشعار كل 120 مللي ثانية أو كل 2% تقدم — أيهما أولاً (لا نُغرق الواجهة ولا نجمّدها).
          if (now.difference(lastNotify).inMilliseconds > 120 || _progress - lastProgress >= 0.02) {
            lastNotify = now;
            lastProgress = _progress;
            notifyListeners();
          }
        }
      } finally {
        await sink.flush();
        await sink.close();
      }
      hasher.close();
      _set(UpdatePhase.verifying);
      final got = digest.events.single.toString();
      if (got != rel.sha256) {
        try {
          out.deleteSync();
        } on FileSystemException {
          // تجاهل
        }
        throw const FormatException('البصمة SHA-256 لا تطابق — أُلغي الملف');
      }
      if (rel.sizeBytes > 0 && out.lengthSync() != rel.sizeBytes) {
        throw FormatException('الحجم ${out.lengthSync()} ≠ ${rel.sizeBytes}');
      }
      _downloaded = out;
      _progress = 1;
      _set(UpdatePhase.readyToInstall);
      return out;
    } on Object catch (e) {
      _set(UpdatePhase.error, error: _friendly(e));
      return null;
    }
  }

  /// يفتح مثبّت النظام. إن غاب إذن التثبيت يفتح الإعدادات ويعيد false.
  Future<bool> install() async {
    final f = _downloaded;
    if (f == null) return false;
    if (kIsWeb) return false;
    final can = await _ch.invokeMethod<bool>('canInstall') ?? false;
    if (!can) {
      _set(UpdatePhase.needInstallPermission);
      await _ch.invokeMethod<void>('openInstallPermission');
      return false;
    }
    // تحقق أخير قبل التسليم للنظام (حماية من استبدال الملف)
    if (await _sha256(f) != _latest!.sha256) {
      _set(UpdatePhase.error, error: 'الملف تغيّر بعد التنزيل');
      return false;
    }
    final ok = await _ch.invokeMethod<bool>('install', {'path': f.path}) ?? false;
    if (!ok) _set(UpdatePhase.error, error: 'تعذّر فتح المثبّت');
    return ok;
  }

  /// فحص → تنزيل → تثبيت بخطوة واحدة (زر «تحديث تلقائي»).
  Future<void> autoUpdate() async {
    if (!await check()) return;
    if (await download() == null) return;
    await install();
  }

  /// بعد عودة المستخدم من شاشة الإذن.
  Future<void> retryInstallAfterPermission() async {
    if (_phase == UpdatePhase.needInstallPermission && _downloaded != null) {
      _set(UpdatePhase.readyToInstall);
      await install();
    }
  }

  static Future<String> _sha256(File f) async => (await sha256.bind(f.openRead()).first).toString();

  void _set(UpdatePhase p, {String? error = ''}) {
    _phase = p;
    if (error != '') _error = error;
    notifyListeners();
  }

  static String _friendly(Object e) {
    final s = e.toString();
    if (e is SocketException || s.contains('Failed host lookup')) return 'لا يوجد اتصال بالإنترنت';
    if (e is TimeoutException) return 'انتهت مهلة الاتصال';
    if (s.contains('HTTP 404')) return 'لا يوجد إصدار منشور بعد';
    return s.replaceFirst('Exception: ', '').replaceFirst('FormatException: ', '');
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }
}
