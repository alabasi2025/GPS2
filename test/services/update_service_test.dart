import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:point_gps/services/update_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const ch = MethodChannel('point_gps/update');

  late Directory tmp;
  final apkBytes = List<int>.generate(1_200_000, (i) => (i * 31 + 7) & 0xff);
  final apkSha = sha256.convert(apkBytes).toString();
  final installCalls = <String>[];
  var canInstall = true;

  Map<String, Object?> latest({int code = 200}) => {
        'versionName': '1.3.0',
        'versionCode': code,
        'tag': 'v1.3.0+$code',
        'apk': 'https://github.com/x/y/releases/download/v1.3.0+$code/app.apk',
        'sha256': apkSha,
        'sizeBytes': apkBytes.length,
        'notes': 'test',
        'publishedAt': '2026-10-03T00:00:00Z',
      };

  http.Client clientWith({Map<String, Object?>? json, List<int>? apk, int jsonStatus = 200}) =>
      MockClient.streaming((req, body) async {
        if (req.url.path.endsWith('latest.json')) {
          return http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(json ?? latest()))), jsonStatus);
        }
        final data = apk ?? apkBytes;
        // بثّ على دفعات لاختبار التقدم
        Stream<List<int>> chunks() async* {
          for (var i = 0; i < data.length; i += 100_000) {
            yield data.sublist(i, (i + 100_000).clamp(0, data.length));
          }
        }
        return http.StreamedResponse(chunks(), 200, contentLength: data.length);
      });

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('pg_upd');
    installCalls.clear();
    canInstall = true;
    messenger.setMockMethodCallHandler(ch, (call) async {
      switch (call.method) {
        case 'versionCode':
          return 104;
        case 'cacheDir':
          return tmp.path;
        case 'canInstall':
          return canInstall;
        case 'openInstallPermission':
          return null;
        case 'install':
          installCalls.add((call.arguments as Map)['path'] as String);
          return true;
      }
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(ch, null);
    tmp.deleteSync(recursive: true);
  });

  test('newer release → available; download verifies SHA-256 and installs', () async {
    final s = UpdateService(client: clientWith());
    expect(await s.check(), isTrue);
    expect(s.phase, UpdatePhase.available);
    expect(s.latest!.versionCode, 200);

    var progressSeen = 0;
    s.addListener(() {
      if (s.phase == UpdatePhase.downloading && s.progress > 0) progressSeen++;
    });
    final f = await s.download();
    expect(f, isNotNull);
    expect(s.phase, UpdatePhase.readyToInstall);
    expect(progressSeen, greaterThan(2), reason: 'progress must be reported during streaming');
    expect(f!.lengthSync(), apkBytes.length);

    expect(await s.install(), isTrue);
    expect(installCalls.single, f.path);
  });

  test('same or older versionCode → upToDate, no download', () async {
    final s = UpdateService(client: clientWith(json: latest(code: 104)));
    expect(await s.check(), isFalse);
    expect(s.phase, UpdatePhase.upToDate);
    expect(await s.download(), isNull);
  });

  test('tampered APK (hash mismatch) is deleted and never installed', () async {
    final bad = List<int>.from(apkBytes)..[500] ^= 0xff;
    final s = UpdateService(client: clientWith(apk: bad));
    await s.check();
    final f = await s.download();
    expect(f, isNull);
    expect(s.phase, UpdatePhase.error);
    expect(s.error, contains('SHA-256'));
    expect(tmp.listSync().whereType<File>().where((x) => x.path.endsWith('.apk')), isEmpty);
    expect(await s.install(), isFalse);
    expect(installCalls, isEmpty);
  });

  test('missing install permission → opens settings, does not install', () async {
    canInstall = false;
    final s = UpdateService(client: clientWith());
    await s.check();
    await s.download();
    expect(await s.install(), isFalse);
    expect(s.phase, UpdatePhase.needInstallPermission);
    expect(installCalls, isEmpty);
    canInstall = true;
    await s.retryInstallAfterPermission();
    expect(installCalls, hasLength(1));
  });

  test('no release yet (404) → friendly error', () async {
    final s = UpdateService(client: clientWith(jsonStatus: 404));
    expect(await s.check(), isFalse);
    expect(s.phase, UpdatePhase.error);
    expect(s.error, contains('لا يوجد إصدار'));
  });

  test('already-downloaded matching file is reused without re-download', () async {
    File('${tmp.path}/point_gps_200.apk').writeAsBytesSync(apkBytes);
    var apkRequests = 0;
    final client = MockClient.streaming((req, body) async {
      if (req.url.path.endsWith('latest.json')) {
        return http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(latest()))), 200);
      }
      apkRequests++;
      return http.StreamedResponse(Stream.value(apkBytes), 200);
    });
    final s = UpdateService(client: client);
    await s.check();
    expect(await s.download(), isNotNull);
    expect(apkRequests, 0);
  });
}
