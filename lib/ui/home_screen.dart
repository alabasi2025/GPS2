import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../engine/models.dart';
import '../engine/solution_arbiter.dart';
import '../services/session_controller.dart';
import 'format.dart';
import 'sky_sheet.dart';
import 'theme.dart';
import 'widgets.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({required this.controller, super.key});

  final SessionController controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final MapController _map = MapController();
  bool _follow = true;
  bool _mapReady = false;
  double _zoom = 18;
  Timer? _tick;

  SessionController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.addListener(_onUpdate);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && c.mode == SessionMode.quick && !c.isLocked) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    c.removeListener(_onUpdate);
    _map.dispose();
    super.dispose();
  }

  void _onUpdate() {
    final e = c.solution;
    if (_follow && _mapReady && e != null) {
      _map.move(LatLng(e.lat, e.lon), _zoom);
    }
    if (mounted) setState(() {});
  }

  // ----------------------------------------------------------------- أفعال

  Future<void> _share() async {
    final e = c.solution;
    if (e == null) return;
    final txt = StringBuffer()
      ..writeln('موقعي (نقطة):')
      ..writeln(Fmt.googleMapsUrl(e.lat, e.lon))
      ..writeln('${Fmt.coord(e.lat)}, ${Fmt.coord(e.lon)}')
      ..write('الدقة ±${Fmt.metersShort(e.radius95M)} م (95%)');
    final est = c.estimate;
    if (e.source == FixSource.gnss && est != null && est.samplesAveraged > 0) {
      txt.write(' — GNSS، متوسط ${est.samplesAveraged} عينة');
    }
    await Share.share(txt.toString(), subject: 'موقعي');
  }

  Future<void> _openInMaps() async {
    final e = c.solution;
    if (e == null) return;
    final geo = Uri.parse(Fmt.geoUri(e.lat, e.lon, label: 'نقطة'));
    if (!await launchUrl(geo)) {
      await launchUrl(Uri.parse(Fmt.googleMapsUrl(e.lat, e.lon)), mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _copy() async {
    final e = c.solution;
    if (e == null) return;
    await Clipboard.setData(ClipboardData(text: '${Fmt.coord(e.lat)}, ${Fmt.coord(e.lon)}'));
    _toast('نُسخت الإحداثيات');
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  Future<void> _toggleLog() async {
    if (c.isLogging) {
      final f = await c.stopLogging();
      if (f != null && mounted) {
        final share = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('حُفظ السجل'),
            content: Text('${c.logLines} سطر\n${f.path.split('/').last}'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إغلاق')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('مشاركة CSV')),
            ],
          ),
        );
        if (share ?? false) {
          await Share.shareXFiles([XFile(f.path, mimeType: 'text/csv')], subject: 'Point GPS log');
        }
      }
    } else {
      await c.startLogging();
      _toast('بدأ تسجيل CSV');
    }
  }

  void _savePoint() {
    final p = c.savePoint();
    if (p == null) return;
    final d = c.lastTwoDistanceM;
    _toast(d == null ? 'حُفظت النقطة ${p.index}' : 'النقطة ${p.index} — المسافة عن السابقة: ${Fmt.meters(d)}');
  }

  void _showSky() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SkySheet(controller: c),
    );
  }

  // ----------------------------------------------------------------- بناء

  @override
  Widget build(BuildContext context) {
    final phase = c.phase;
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: _buildMap()),
          if (phase == SessionPhase.needPermission ||
              phase == SessionPhase.permissionDeniedForever ||
              phase == SessionPhase.gpsOff)
            Positioned.fill(child: _buildBlocker(phase)),
          SafeArea(
            child: Column(
              children: [
                if (kIsWeb)
                  Container(
                    width: double.infinity,
                    color: AppTheme.warn,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: const Text(
                      'معاينة ويب — بيانات محاكاة (داخل مبنى → خروج → سماء مفتوحة)',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.bg, fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ),
                _buildTopBar(),
                const Spacer(),
                if (phase == SessionPhase.acquiring || phase == SessionPhase.tracking || phase == SessionPhase.locked)
                  _buildBottomPanel(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMap() {
    final sol = c.solution;
    final est = c.estimate;
    final center = sol != null ? LatLng(sol.lat, sol.lon) : const LatLng(15.3694, 44.1910);
    final color = sol == null ? AppTheme.textLo : AppTheme.accuracyColor(sol.sigmaM);
    return FlutterMap(
      mapController: _map,
      options: MapOptions(
        initialCenter: center,
        initialZoom: sol != null ? 18 : 5,
        maxZoom: 20,
        minZoom: 3,
        backgroundColor: AppTheme.bg,
        onMapReady: () => _mapReady = true,
        onPositionChanged: (pos, hasGesture) {
          _zoom = pos.zoom;
          if (hasGesture && _follow) setState(() => _follow = false);
        },
        interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          fallbackUrl: 'https://a.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.pointgps.location',
          maxNativeZoom: 19,
          keepBuffer: 2,
          panBuffer: 1,
          evictErrorTileStrategy: EvictErrorTileStrategy.notVisibleRespectMargin,
        ),
        if (sol != null)
          CircleLayer(
            circles: [
              // GNSS المُرشَّح (رمادي) عندما لا يكون هو المعروض — للمقارنة والتشخيص.
              if (sol.source == FixSource.assist && est != null)
                CircleMarker(
                  point: LatLng(est.lat, est.lon),
                  radius: est.radius95M,
                  useRadiusInMeter: true,
                  color: Colors.white.withValues(alpha: 0.05),
                  borderColor: Colors.white.withValues(alpha: 0.3),
                  borderStrokeWidth: 1,
                ),
              // دائرة الثقة 95% للحل المعروض
              CircleMarker(
                point: LatLng(sol.lat, sol.lon),
                radius: sol.radius95M,
                useRadiusInMeter: true,
                color: color.withValues(alpha: 0.18),
                borderColor: color,
                borderStrokeWidth: 2,
              ),
            ],
          ),
        if (c.savedPoints.isNotEmpty)
          MarkerLayer(
            markers: [
              for (final p in c.savedPoints)
                Marker(
                  point: LatLng(p.lat, p.lon),
                  width: 26,
                  height: 26,
                  child: SavedPin(index: p.index),
                ),
            ],
          ),
        if (sol != null)
          MarkerLayer(
            markers: [
              Marker(
                point: LatLng(sol.lat, sol.lon),
                width: 28,
                height: 28,
                child: PositionDot(
                  motion: sol.source == FixSource.gnss ? (est?.motion ?? MotionState.unknown) : MotionState.unknown,
                  stale: c.isStale && sol.source == FixSource.gnss,
                ),
              ),
            ],
          ),
        const RichAttributionWidget(
          alignment: AttributionAlignment.bottomLeft,
          showFlutterMapAttribution: false,
          attributions: [TextSourceAttribution('© OpenStreetMap')],
        ),
      ],
    );
  }

  Widget _buildTopBar() {
    final sky = c.sky;
    final sol = c.solution;
    final e = sol != null && sol.source == FixSource.gnss ? c.estimate : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          GlassPill(
            onTap: _showSky,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.satellite_alt_rounded, size: 18),
                const SizedBox(width: 6),
                Text('${sky.usedInFix}/${sky.visible}', style: const TextStyle(fontWeight: FontWeight.w700)),
                if (sky.dualFrequency) ...[
                  const SizedBox(width: 8),
                  const BandBadge(text: 'L5'),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          GlassPill(
            onTap: () => c.setMode(c.mode == SessionMode.quick ? SessionMode.precision : SessionMode.quick),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  c.isLocked
                      ? Icons.lock_rounded
                      : (c.mode == SessionMode.quick ? Icons.bolt_rounded : Icons.adjust_rounded),
                  size: 18,
                  color: c.isLocked ? AppTheme.good : (c.mode == SessionMode.quick ? AppTheme.warn : AppTheme.accent),
                ),
                const SizedBox(width: 6),
                Text(
                  c.isLocked
                      ? 'مثبَّت'
                      : c.mode == SessionMode.quick
                          ? 'سريع · ${c.quickRemaining.inSeconds} ث'
                          : (e == null
                              ? 'دقة قصوى'
                              : switch (e.motion) {
                                  MotionState.stationary => 'ثابت · ${Fmt.duration(c.elapsed)}',
                                  MotionState.moving => 'متحرك',
                                  MotionState.unknown => 'دقة قصوى',
                                }),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: _follow ? 'التتبع مفعّل' : 'العودة لموقعي',
            onPressed: () {
              setState(() => _follow = true);
              final est = c.estimate;
              if (est != null && _mapReady) _map.move(LatLng(est.lat, est.lon), 18);
            },
            icon: Icon(_follow ? Icons.my_location_rounded : Icons.location_searching_rounded),
            style: IconButton.styleFrom(
              backgroundColor: _follow ? AppTheme.accent : AppTheme.surfaceHi,
              foregroundColor: _follow ? AppTheme.bg : AppTheme.textHi,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomPanel() {
    final sol = c.solution;
    final est = c.estimate;
    final raw = c.lastFix;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 8))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (sol == null)
            _AcquiringRow(sky: c.sky, ttffMs: c.ttffMs)
          else ...[
            SolutionHeader(
              solution: sol,
              gnssSigmaM: est?.sigmaM,
              rawAccuracyM: raw?.accuracyM,
              stale: c.isStale && sol.source == FixSource.gnss,
            ),
            const SizedBox(height: 10),
            _CoordRow(lat: sol.lat, lon: sol.lon, onCopy: _copy),
            const SizedBox(height: 10),
            _StatsRow(sol: sol, est: est, sky: c.sky, fixCount: c.fixCount),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: FilledButton.icon(
                    onPressed: c.isLocked || c.mode == SessionMode.precision ? c.refresh : null,
                    icon: Icon(c.isLocked ? Icons.my_location_rounded : Icons.hourglass_top_rounded, size: 20),
                    label: Text(c.isLocked ? 'حدّث الموقع' : 'جارٍ التحديد…'),
                    style: FilledButton.styleFrom(
                      backgroundColor: c.isLocked ? AppTheme.accent : AppTheme.surfaceHi,
                      foregroundColor: c.isLocked ? AppTheme.bg : AppTheme.textHi,
                      disabledBackgroundColor: AppTheme.surfaceHi,
                      disabledForegroundColor: AppTheme.textHi,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: _share,
                    icon: const Icon(Icons.share_rounded, size: 20),
                    label: const Text('مشاركة'),
                    style: FilledButton.styleFrom(backgroundColor: AppTheme.good, foregroundColor: AppTheme.bg),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _MiniAction(icon: Icons.push_pin_rounded, label: 'حفظ نقطة', onTap: _savePoint),
                _MiniAction(
                  icon: c.isLogging ? Icons.stop_circle_rounded : Icons.fiber_manual_record_rounded,
                  label: c.isLogging ? 'إيقاف CSV (${c.logLines})' : 'تسجيل CSV',
                  color: c.isLogging ? AppTheme.bad : null,
                  onTap: _toggleLog,
                ),
                _MiniAction(icon: Icons.map_rounded, label: 'الخرائط', onTap: _openInMaps),
                _MiniAction(icon: Icons.science_rounded, label: 'التحليل', onTap: _showSky),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBlocker(SessionPhase phase) {
    final (icon, title, body, action, onTap) = switch (phase) {
      SessionPhase.needPermission => (
          Icons.location_on_rounded,
          'نحتاج إذن الموقع الدقيق',
          'التطبيق يقرأ إشارات الأقمار مباشرة من جهازك. لا يُرسل موقعك لأي خادم.',
          'السماح',
          c.requestPermission,
        ),
      SessionPhase.permissionDeniedForever => (
          Icons.lock_rounded,
          'الإذن مرفوض',
          'فعّل «الموقع → دقيق» للتطبيق من إعدادات النظام.',
          'فتح الإعدادات',
          c.openAppSettings,
        ),
      _ => (
          Icons.gps_off_rounded,
          'الموقع مغلق',
          'شغّل الموقع من الإعدادات واختر وضع «دقة عالية».',
          'فتح إعدادات الموقع',
          c.openLocationSettings,
        ),
    };
    return ColoredBox(
      color: AppTheme.bg.withValues(alpha: 0.92),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 72, color: AppTheme.accent),
              const SizedBox(height: 20),
              Text(title, style: Theme.of(context).textTheme.headlineMedium, textAlign: TextAlign.center),
              const SizedBox(height: 10),
              Text(body, style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton(onPressed: onTap, child: Text(action)),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------- أجزاء خاصة

class _AcquiringRow extends StatelessWidget {
  const _AcquiringRow({required this.sky, required this.ttffMs});

  final SkySnapshot sky;
  final int? ttffMs;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 3, color: AppTheme.accent),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('جارٍ تحديد الموقع…', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 2),
              Text(
                sky.visible == 0
                    ? 'اخرج لمكان مكشوف للسماء'
                    : 'مرئي ${sky.visible} · مستخدم ${sky.usedInFix}${sky.dualFrequency ? ' · L5' : ''}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CoordRow extends StatelessWidget {
  const _CoordRow({required this.lat, required this.lon, required this.onCopy});

  final double lat;
  final double lon;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onCopy,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: AppTheme.bg.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(10)),
        child: Row(
          children: [
            Expanded(
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Text(
                  '${Fmt.coord(lat)}, ${Fmt.coord(lon)}',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 15, color: AppTheme.textHi),
                  textAlign: TextAlign.left,
                ),
              ),
            ),
            const Icon(Icons.copy_rounded, size: 18, color: AppTheme.textLo),
          ],
        ),
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.sol, required this.est, required this.sky, required this.fixCount});

  final DisplaySolution sol;
  final PositionEstimate? est;
  final SkySnapshot sky;
  final int fixCount;

  @override
  Widget build(BuildContext context) {
    final cn0 = sky.meanCn0Used;
    final gnssShown = sol.source == FixSource.gnss;
    return Row(
      children: [
        StatTile(label: 'أقمار', value: '${sky.usedInFix}', sub: 'من ${sky.visible}'),
        StatTile(
          label: 'إشارة',
          value: cn0 > 0 ? cn0.toStringAsFixed(0) : '—',
          sub: 'dB-Hz',
          color: cn0 > 0 ? AppTheme.cn0Color(cn0) : null,
        ),
        StatTile(
          label: 'متوسط',
          value: gnssShown && est != null && est!.samplesAveraged > 0 ? '${est!.samplesAveraged}' : '—',
          sub: 'عينة',
        ),
        StatTile(
          label: 'ارتفاع',
          value: sol.alt != null ? sol.alt!.round().toString() : '—',
          sub: 'م',
        ),
        StatTile(label: 'مرفوض', value: '${est?.rejectedOutliers ?? 0}', sub: 'من $fixCount'),
      ],
    );
  }
}

class _MiniAction extends StatelessWidget {
  const _MiniAction({required this.icon, required this.label, required this.onTap, this.color});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: color ?? AppTheme.textHi),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(fontSize: 11, color: color ?? AppTheme.textLo),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
