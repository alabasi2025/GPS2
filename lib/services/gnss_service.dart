import 'dart:async';

import 'package:flutter/services.dart';

import '../engine/models.dart';

/// نتيجة طلب الصلاحية من الطبقة الأصلية.
enum PermissionStatus { granted, denied, deniedForever, unavailable }

/// قدرات جهاز GNSS كما يبلّغ عنها Android.
final class GnssCapabilities {
  const GnssCapabilities({
    required this.sdk,
    required this.model,
    required this.gpsEnabled,
    required this.hasFinePermission,
    this.hardwareModelName,
    this.yearOfHardware,
    this.hasMeasurements,
  });

  factory GnssCapabilities.fromMap(Map<Object?, Object?> m) => GnssCapabilities(
        sdk: (m['sdk'] as num?)?.toInt() ?? 0,
        model: m['model'] as String? ?? '',
        gpsEnabled: m['gpsEnabled'] == true,
        hasFinePermission: m['hasFinePermission'] == true,
        hardwareModelName: m['hardwareModelName'] as String?,
        yearOfHardware: (m['yearOfHardware'] as num?)?.toInt(),
        hasMeasurements: m['hasMeasurements'] as bool?,
      );

  final int sdk;
  final String model;
  final bool gpsEnabled;
  final bool hasFinePermission;
  final String? hardwareModelName;
  final int? yearOfHardware;
  final bool? hasMeasurements;
}

/// ملخص القياسات الخام (للتشخيص فقط).
final class RawSummary {
  const RawSummary({
    required this.measurements,
    required this.adrValid,
    this.agcMeanDb,
  });

  factory RawSummary.fromMap(Map<Object?, Object?> m) => RawSummary(
        measurements: (m['measurements'] as num?)?.toInt() ?? 0,
        adrValid: (m['adrValid'] as num?)?.toInt() ?? 0,
        agcMeanDb: (m['agcMeanDb'] as num?)?.toDouble(),
      );

  final int measurements;

  /// عدد القياسات ذات طور حامل صالح — مؤشر على جودة الجهاز.
  final int adrValid;
  final double? agcMeanDb;
}

/// جسر Dart ↔ Kotlin. طبقة رقيقة بلا منطق: تحويل خرائط إلى نماذج فقط.
final class GnssService {
  GnssService({
    MethodChannel? control,
    EventChannel? fix,
    EventChannel? status,
    EventChannel? raw,
  })  : _control = control ?? const MethodChannel('point_gps/control'),
        _fixChannel = fix ?? const EventChannel('point_gps/fix'),
        _statusChannel = status ?? const EventChannel('point_gps/status'),
        _rawChannel = raw ?? const EventChannel('point_gps/raw');

  final MethodChannel _control;
  final EventChannel _fixChannel;
  final EventChannel _statusChannel;
  final EventChannel _rawChannel;

  Stream<GnssFix>? _fixes;
  Stream<SkySnapshot>? _sky;
  Stream<int>? _firstFix;
  Stream<RawSummary>? _raw;
  Stream<Map<Object?, Object?>>? _statusEvents;

  /// حلول الموقع الخام من GPS_PROVIDER.
  Stream<GnssFix> get fixes => _fixes ??= _fixChannel
      .receiveBroadcastStream()
      .map((e) => e as Map<Object?, Object?>)
      .where((m) => m['lat'] != null)
      .map(GnssFix.fromMap);

  /// حدث تعطيل مزوّد GPS أثناء التشغيل.
  Stream<void> get providerDisabled => _fixChannel
      .receiveBroadcastStream()
      .map((e) => e as Map<Object?, Object?>)
      .where((m) => m['event'] == 'providerDisabled')
      .map((_) {});

  Stream<Map<Object?, Object?>> get _status => _statusEvents ??=
      _statusChannel.receiveBroadcastStream().map((e) => e as Map<Object?, Object?>).asBroadcastStream();

  /// حالة الأقمار.
  Stream<SkySnapshot> get sky =>
      _sky ??= _status.where((m) => m['satellites'] != null).map(SkySnapshot.fromMap);

  /// زمن أول حل (TTFF) بالملّي ثانية.
  Stream<int> get firstFixMs => _firstFix ??= _status
      .where((m) => m['event'] == 'firstFix')
      .map((m) => (m['ttffMillis'] as num).toInt());

  Stream<RawSummary> get raw => _raw ??= _rawChannel
      .receiveBroadcastStream()
      .map((e) => RawSummary.fromMap(e as Map<Object?, Object?>));

  /// يبدأ البث. يعيد false إن غابت الصلاحية أو GPS معطل.
  Future<bool> start() async => await _control.invokeMethod<bool>('start') ?? false;

  Future<void> stop() => _control.invokeMethod<void>('stop');

  Future<GnssCapabilities> capabilities() async {
    final m = await _control.invokeMethod<Map<Object?, Object?>>('capabilities');
    return GnssCapabilities.fromMap(m ?? const {});
  }

  Future<PermissionStatus> requestPermission() async {
    final s = await _control.invokeMethod<String>('requestPermission');
    return switch (s) {
      'granted' => PermissionStatus.granted,
      'denied' => PermissionStatus.denied,
      'deniedForever' => PermissionStatus.deniedForever,
      _ => PermissionStatus.unavailable,
    };
  }

  Future<void> openLocationSettings() => _control.invokeMethod<void>('openLocationSettings');
  Future<void> openAppSettings() => _control.invokeMethod<void>('openAppSettings');
}
