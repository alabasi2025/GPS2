import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../engine/models.dart';
import '../services/session_controller.dart';
import 'format.dart';
import 'theme.dart';
import 'widgets.dart';

/// ورقة التحليل: خريطة السماء، الأقمار، النقاط المحفوظة والتكرارية، الجهاز.
class SkySheet extends StatelessWidget {
  const SkySheet({required this.controller, super.key});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        final sky = c.sky;
        final caps = c.capabilities;
        final est = c.estimate;
        final raw = c.raw;
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          builder: (context, scroll) => ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceHi,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              _Section(
                title: 'خريطة السماء',
                trailing: '${sky.usedInFix} مستخدم / ${sky.visible} مرئي',
                child: SizedBox(
                  height: 230,
                  child: RepaintBoundary(
                    child: CustomPaint(painter: _SkyPainter(sky), size: Size.infinite),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _Section(
                title: 'جودة الحل',
                child: Column(
                  children: [
                    _kv(
                      'التردد المزدوج (L5)',
                      sky.dualFrequency ? 'نعم — ${sky.l5Used} قمر' : 'لا',
                      color: sky.dualFrequency ? AppTheme.good : AppTheme.warn,
                    ),
                    _kv(
                      'متوسط C/N0 للمستخدم',
                      sky.meanCn0Used > 0 ? '${sky.meanCn0Used.toStringAsFixed(1)} dB-Hz' : '—',
                      color: sky.meanCn0Used > 0 ? AppTheme.cn0Color(sky.meanCn0Used) : null,
                    ),
                    _kv(
                      'زمن أول حل (TTFF)',
                      c.ttffMs != null ? '${(c.ttffMs! / 1000).toStringAsFixed(1)} ث' : '—',
                    ),
                    if (raw != null) ...[
                      _kv('قياسات خام / بطور حامل', '${raw.measurements} / ${raw.adrValid}'),
                      if (raw.agcMeanDb != null)
                        _kv('AGC (تشويش إن انخفض فجأة)', '${raw.agcMeanDb!.toStringAsFixed(1)} dB'),
                    ],
                    _kv('عينات GNSS / مرفوضة', '${c.fixCount} / ${est?.rejectedOutliers ?? 0}'),
                    _kv('عينات المدمج (Fused)', '${c.assistCount}'),
                    if (c.solution != null)
                      _kv(
                        'المصدر المعروض',
                        c.solution!.source == FixSource.gnss ? 'GNSS (أقمار مباشرة)' : 'مدمج (Wi-Fi/خلوي/GPS)',
                        color: c.solution!.source == FixSource.gnss ? AppTheme.good : AppTheme.accent,
                      ),
                    if (c.solution?.gnssDisagreementM != null)
                      _kv('فرق GNSS عن المدمج', Fmt.meters(c.solution!.gnssDisagreementM!)),
                    if (c.lastAssist?.accuracyM != null)
                      _kv('دقة المدمج (68%)', '±${Fmt.metersShort(c.lastAssist!.accuracyM!)} م'),
                    _kv('الجلسة', '#${c.session}'),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _Section(
                title: 'الأقمار',
                child: Column(
                  children: [
                    for (final s in [...sky.satellites]..sort(_satSort)) _SatRow(s),
                    if (sky.satellites.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('لا أقمار بعد', style: TextStyle(color: AppTheme.textLo)),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _SavedPointsSection(controller: c),
              const SizedBox(height: 14),
              if (est != null)
                _Section(
                  title: 'صيغ أخرى',
                  child: Column(
                    children: [
                      _kv(
                        'DMS',
                        '${Fmt.dms(est.lat, isLat: true)}\n${Fmt.dms(est.lon, isLat: false)}',
                        ltr: true,
                      ),
                      if (est.alt != null)
                        _kv('الارتفاع (إهليلجي WGS-84)', '${est.alt!.toStringAsFixed(1)} م'),
                    ],
                  ),
                ),
              const SizedBox(height: 14),
              if (caps != null)
                _Section(
                  title: 'الجهاز',
                  child: Column(
                    children: [
                      _kv('الطراز', caps.model, ltr: true),
                      _kv('Android SDK', '${caps.sdk}'),
                      if (caps.hardwareModelName != null) _kv('شريحة GNSS', caps.hardwareModelName!, ltr: true),
                      if (caps.yearOfHardware != null) _kv('جيل العتاد', '${caps.yearOfHardware}'),
                      if (caps.hasMeasurements != null)
                        _kv('قياسات خام', caps.hasMeasurements! ? 'مدعومة' : 'غير مدعومة'),
                      if (caps.assistProvider != null) _kv('مزوّد المدمج', caps.assistProvider!, ltr: true),
                    ],
                  ),
                ),
              const SizedBox(height: 14),
              const _Section(
                title: 'كيف تختبر الدقة علمياً',
                child: Text(
                  '1) التكرارية: قف على علامة ثابتة 60 ث حتى يظهر «ثابت»، احفظ نقطة، ابتعد 50 م وارجع، كرّر 5 مرات. '
                  'التشتت أدناه هو دقتك الحقيقية.\n'
                  '2) المسافة: احفظ نقطتين على طرفي شريط قياس 50 م؛ قارن المسافة المحسوبة.\n'
                  '3) المطلق: قارن مع علامة مساحية معروفة الإحداثيات.\n'
                  'سجّل CSV أثناء كل ذلك لتحليل الخام مقابل المُرشَّح.',
                  style: TextStyle(color: AppTheme.textLo, height: 1.6, fontSize: 13),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static int _satSort(SatelliteInfo a, SatelliteInfo b) {
    if (a.usedInFix != b.usedInFix) return a.usedInFix ? -1 : 1;
    return b.cn0DbHz.compareTo(a.cn0DbHz);
  }

  static Widget _kv(String k, String v, {Color? color, bool ltr = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(k, style: const TextStyle(color: AppTheme.textLo, fontSize: 13))),
            const SizedBox(width: 12),
            Flexible(
              child: Directionality(
                textDirection: ltr ? TextDirection.ltr : TextDirection.rtl,
                child: Text(
                  v,
                  textAlign: TextAlign.left,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: color ?? AppTheme.textHi,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                if (trailing != null) Text(trailing!, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _SatRow extends StatelessWidget {
  const _SatRow(this.s);

  final SatelliteInfo s;

  @override
  Widget build(BuildContext context) {
    final color = s.usedInFix ? AppTheme.cn0Color(s.cn0DbHz) : AppTheme.textLo;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(
              '${_abbr(s.constellation)} ${s.svid}',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: s.usedInFix ? AppTheme.textHi : AppTheme.textLo,
              ),
            ),
          ),
          SizedBox(
            width: 28,
            child: s.band != null
                ? Text(
                    s.band!,
                    style: TextStyle(fontSize: 11, color: s.band == 'L5' ? AppTheme.good : AppTheme.textLo),
                  )
                : const SizedBox.shrink(),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: Fmt.clamp01(s.cn0DbHz / 50),
                minHeight: 8,
                backgroundColor: AppTheme.bg,
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 30,
            child: Text(
              s.cn0DbHz.toStringAsFixed(0),
              textAlign: TextAlign.end,
              style: TextStyle(color: color, fontSize: 12),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 30,
            child: Text(
              '${s.elevationDeg.round()}°',
              textAlign: TextAlign.end,
              style: const TextStyle(color: AppTheme.textLo, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  static String _abbr(String c) => switch (c) {
        'GPS' => 'GPS',
        'GLONASS' => 'GLO',
        'Galileo' => 'GAL',
        'BeiDou' => 'BDS',
        'QZSS' => 'QZS',
        'NavIC' => 'IRN',
        'SBAS' => 'SBS',
        _ => '?',
      };
}

class _SavedPointsSection extends StatelessWidget {
  const _SavedPointsSection({required this.controller});

  final SessionController controller;

  Future<void> _share(List<SavedPoint> pts) async {
    final sb = StringBuffer('index,lat,lon,alt,sigma_m,samples,time\n');
    for (final p in pts) {
      sb.writeln(
        '${p.index},${Fmt.coord(p.lat)},${Fmt.coord(p.lon)},'
        '${p.alt?.toStringAsFixed(1) ?? ''},${p.sigmaM.toStringAsFixed(2)},'
        '${p.samples},${p.time.toIso8601String()}',
      );
    }
    await Clipboard.setData(ClipboardData(text: sb.toString()));
    await Share.share(sb.toString(), subject: 'Point GPS points');
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final pts = c.savedPoints;
    final rep = c.repeatability;
    final lastTwo = c.lastTwoDistanceM;
    return _Section(
      title: 'النقاط المحفوظة',
      trailing: pts.isEmpty ? null : '${pts.length}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (pts.isEmpty)
            const Text(
              'احفظ نقاطاً من الشاشة الرئيسية لحساب التكرارية والمسافات.',
              style: TextStyle(color: AppTheme.textLo, fontSize: 13),
            ),
          if (rep != null) ...[
            Row(
              children: [
                StatTile(
                  label: 'أقصى تشتت',
                  value: Fmt.metersShort(rep.maxSpreadM),
                  sub: 'م',
                  color: AppTheme.accuracyColor(rep.maxSpreadM / 2),
                ),
                StatTile(label: 'RMS', value: Fmt.metersShort(rep.rmsM), sub: 'م'),
                if (lastTwo != null) StatTile(label: 'آخر نقطتين', value: Fmt.metersShort(lastTwo), sub: 'م'),
              ],
            ),
            const SizedBox(height: 8),
          ],
          for (final p in pts)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(width: 26, height: 26, child: SavedPin(index: p.index)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(
                        '${Fmt.coord(p.lat)}, ${Fmt.coord(p.lon)}',
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                      ),
                    ),
                  ),
                  Text(
                    '±${Fmt.metersShort(p.sigmaM * 2)} م · ${p.samples}',
                    style: const TextStyle(color: AppTheme.textLo, fontSize: 11),
                  ),
                ],
              ),
            ),
          if (pts.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _share(pts),
                    icon: const Icon(Icons.ios_share_rounded, size: 18),
                    label: const Text('مشاركة النقاط'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(onPressed: c.clearSavedPoints, child: const Text('مسح')),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// رسم قبة السماء: الشمال أعلى، الارتفاع 90° في المركز، 0° على المحيط.
class _SkyPainter extends CustomPainter {
  _SkyPainter(this.sky);

  final SkySnapshot sky;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2, cy = size.height / 2;
    final r = math.min(cx, cy) - 8;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = AppTheme.surfaceHi;
    for (final f in const [1.0, 2 / 3, 1 / 3]) {
      canvas.drawCircle(Offset(cx, cy), r * f, ring);
    }
    canvas
      ..drawLine(Offset(cx - r, cy), Offset(cx + r, cy), ring)
      ..drawLine(Offset(cx, cy - r), Offset(cx, cy + r), ring);

    final tp = TextPainter(textDirection: TextDirection.ltr);
    void label(String t, Offset o) {
      tp
        ..text = TextSpan(text: t, style: const TextStyle(fontSize: 10, color: AppTheme.textLo))
        ..layout()
        ..paint(canvas, o - Offset(tp.width / 2, tp.height / 2));
    }

    label('N', Offset(cx, cy - r - 2));
    label('S', Offset(cx, cy + r + 2));
    label('E', Offset(cx + r + 4, cy));
    label('W', Offset(cx - r - 4, cy));

    final dot = Paint()..style = PaintingStyle.fill;
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.white;
    for (final s in sky.satellites) {
      final rho = r * (1 - s.elevationDeg / 90).clamp(0.0, 1.0);
      final az = s.azimuthDeg * math.pi / 180;
      final x = cx + rho * math.sin(az), y = cy - rho * math.cos(az);
      dot.color = s.usedInFix ? AppTheme.cn0Color(s.cn0DbHz) : AppTheme.textLo.withValues(alpha: 0.5);
      final rad = s.usedInFix ? 6.0 : 4.0;
      canvas.drawCircle(Offset(x, y), rad, dot);
      if (s.band == 'L5') canvas.drawCircle(Offset(x, y), rad + 2, border);
    }
  }

  @override
  bool shouldRepaint(covariant _SkyPainter old) => !identical(old.sky, sky);
}
