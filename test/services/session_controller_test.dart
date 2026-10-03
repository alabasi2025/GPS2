import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:point_gps/engine/models.dart';
import 'package:point_gps/services/gnss_service.dart';
import 'package:point_gps/services/session_controller.dart';

/// اختبار تكاملي للجسر Dart ↔ Android بقنوات وهمية.
/// يكشف أخطاء من نوع «الأقمار تظهر والموقع لا» (الاشتراك المزدوج) و«المدمج
/// يصل قبل GNSS» بدون جهاز.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  const fixCh = EventChannel('point_gps/fix');
  const statusCh = EventChannel('point_gps/status');
  const rawCh = EventChannel('point_gps/raw');
  const control = MethodChannel('point_gps/control');

  final startCalls = <String>[];
  late StreamController<Map<String, Object?>> fixCtl;
  late StreamController<Map<String, Object?>> statusCtl;
  late StreamController<Map<String, Object?>> rawCtl;

  setUp(() {
    startCalls.clear();
    fixCtl = StreamController<Map<String, Object?>>.broadcast();
    statusCtl = StreamController<Map<String, Object?>>.broadcast();
    rawCtl = StreamController<Map<String, Object?>>.broadcast();
    messenger.setMockStreamHandler(fixCh, MockStreamHandler.inline(onListen: (_, sink) {
      fixCtl.stream.listen(sink.success);
    }));
    messenger.setMockStreamHandler(statusCh, MockStreamHandler.inline(onListen: (_, sink) {
      statusCtl.stream.listen(sink.success);
    }));
    messenger.setMockStreamHandler(rawCh, MockStreamHandler.inline(onListen: (_, sink) {
      rawCtl.stream.listen(sink.success);
    }));
    messenger.setMockMethodCallHandler(control, (call) async {
      startCalls.add(call.method);
      return switch (call.method) {
        'start' => true,
        'capabilities' => <String, Object?>{'sdk': 34, 'model': 'test', 'gpsEnabled': true, 'hasFinePermission': true},
        _ => null,
      };
    });
  });

  tearDown(() async {
    await fixCtl.close();
    await statusCtl.close();
    await rawCtl.close();
    messenger.setMockStreamHandler(fixCh, null);
    messenger.setMockStreamHandler(statusCh, null);
    messenger.setMockStreamHandler(rawCh, null);
    messenger.setMockMethodCallHandler(control, null);
  });

  Map<String, Object?> gnss(double lat, double lon, {int t = 1700000000000, double acc = 3}) => {
        'lat': lat, 'lon': lon, 'alt': 2200.0, 'acc': acc, 'speed': 0.0, 'speedAcc': 0.3,
        'timeMs': t, 'elapsedNs': t * 1000, 'provider': 'gps', 'mock': false, 'source': 'gnss',
      };
  Map<String, Object?> assist(double lat, double lon, {int t = 1700000000000, double acc = 20}) => {
        'lat': lat, 'lon': lon, 'acc': acc, 'timeMs': t, 'elapsedNs': t * 1000, 'provider': 'fused', 'mock': false,
        'source': 'assist',
      };
  Map<String, Object?> sky(int used) => {
        'count': used + 5, 'usedInFix': used, 'l5Used': 2,
        'satellites': List.generate(used, (i) => {
          'svid': i + 1, 'constellation': 'GPS', 'cn0': 40.0, 'elevation': 45.0, 'azimuth': 10.0 * i,
          'usedInFix': true, 'band': 'L1', 'hasEphemeris': true,
        }),
      };

  Future<void> pump() => Future<void>.delayed(const Duration(milliseconds: 20));

  test('init → start called → fused shown immediately, GNSS fixes reach the engine', () async {
    final c = SessionController(service: GnssService());
    var notifications = 0;
    c.addListener(() => notifications++);
    await c.init();
    await pump();
    expect(startCalls, containsAll(['capabilities', 'start']));
    expect(c.phase, SessionPhase.acquiring);

    // المدمج يصل أولاً (كما يحدث داخل البيت) → يُعرض فوراً.
    fixCtl.add(assist(15.0, 44.0));
    await pump();
    expect(c.solution, isNotNull);
    expect(c.solution!.source, FixSource.assist);
    expect(c.phase, SessionPhase.tracking);

    // الأقمار ثم GNSS متسق → بعد التأكيد يُعرض GNSS (الأدق).
    statusCtl.add(sky(12));
    for (var i = 0; i < 5; i++) {
      fixCtl.add(gnss(15.00001, 44.00001, t: 1700000000000 + i * 1000));
      fixCtl.add(assist(15.0, 44.0, t: 1700000000000 + i * 1000));
      await pump();
    }
    expect(c.fixCount, 5);
    expect(c.estimate, isNotNull);
    expect(c.solution!.source, FixSource.gnss, reason: 'consistent GNSS must be shown');
    expect(c.sky.usedInFix, 12);
    expect(notifications, greaterThan(5));
    await c.dispose();
  });

  test('indoors: GNSS 200 m away from fused → fused is what the user sees', () async {
    final c = SessionController(service: GnssService());
    await c.init();
    await pump();
    statusCtl.add(sky(7));
    for (var i = 0; i < 5; i++) {
      fixCtl.add(assist(15.0, 44.0, t: 1700000000000 + i * 1000));
      fixCtl.add(gnss(15.0018, 44.0, t: 1700000000000 + i * 1000, acc: 8)); // ~200 m north
      await pump();
    }
    expect(c.solution!.source, FixSource.assist);
    expect((c.solution!.lat - 15.0).abs(), lessThan(1e-6));
    expect(c.solution!.gnssDisagreementM, greaterThan(150));
    await c.dispose();
  });

  test('providerDisabled on the same channel does not swallow fixes', () async {
    final c = SessionController(service: GnssService());
    await c.init();
    await pump();
    fixCtl.add(gnss(15.0, 44.0));
    await pump();
    expect(c.fixCount, 1, reason: 'fix channel must have exactly one native sink');
    fixCtl.add({'event': 'providerDisabled'});
    await pump();
    expect(c.phase, SessionPhase.gpsOff);
    await c.dispose();
  });

  test('missing permission → needPermission phase, start not called', () async {
    messenger.setMockMethodCallHandler(control, (call) async {
      startCalls.add(call.method);
      if (call.method == 'capabilities') {
        return <String, Object?>{'sdk': 34, 'model': 'x', 'gpsEnabled': true, 'hasFinePermission': false};
      }
      return null;
    });
    final c = SessionController(service: GnssService());
    await c.init();
    expect(c.phase, SessionPhase.needPermission);
    expect(startCalls, isNot(contains('start')));
    await c.dispose();
  });
}
