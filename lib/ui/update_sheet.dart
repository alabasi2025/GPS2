import 'package:flutter/material.dart';

import '../services/update_service.dart';
import 'theme.dart';

/// ورقة التحديث التلقائي: فحص → تنزيل (شريط تقدم) → تثبيت.
class UpdateSheet extends StatefulWidget {
  const UpdateSheet({required this.service, required this.autoStart, super.key});

  final UpdateService service;

  /// إن true: يبدأ الفحص+التنزيل+التثبيت فور الفتح (زر «تحديث تلقائي»).
  final bool autoStart;

  @override
  State<UpdateSheet> createState() => _UpdateSheetState();
}

class _UpdateSheetState extends State<UpdateSheet> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.service.autoUpdate());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // عاد المستخدم من شاشة إذن «تثبيت تطبيقات غير معروفة»
    if (state == AppLifecycleState.resumed) widget.service.retryInstallAfterPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.service,
      builder: (context, _) {
        final s = widget.service;
        final rel = s.latest;
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(color: AppTheme.surfaceHi, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Row(
                children: [
                  const Icon(Icons.system_update_rounded, color: AppTheme.accent),
                  const SizedBox(width: 10),
                  Text('التحديث التلقائي', style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  Text('الحالي: ${s.currentVersionCode == 0 ? '—' : s.currentVersionCode}',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
              const SizedBox(height: 14),
              _status(context, s, rel),
              const SizedBox(height: 16),
              _actions(context, s),
            ],
          ),
        );
      },
    );
  }

  Widget _status(BuildContext context, UpdateService s, ReleaseInfo? rel) {
    final small = Theme.of(context).textTheme.bodySmall;
    switch (s.phase) {
      case UpdatePhase.idle:
        return Text('اضغط «تحديث تلقائي» للفحص والتنزيل والتثبيت.', style: small);
      case UpdatePhase.checking:
        return const _Line(icon: Icons.sync_rounded, text: 'جارٍ فحص آخر إصدار من GitHub…', spin: true);
      case UpdatePhase.upToDate:
        return _Line(
          icon: Icons.check_circle_rounded,
          color: AppTheme.good,
          text: 'لديك أحدث إصدار (${rel?.versionName} · ${rel?.versionCode})',
        );
      case UpdatePhase.available:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Line(
              icon: Icons.new_releases_rounded,
              color: AppTheme.warn,
              text: 'إصدار جديد ${rel!.versionName} (${rel.versionCode}) — ${(rel.sizeBytes / 1048576).toStringAsFixed(1)} MB',
            ),
            if (rel.notes.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(rel.notes, style: small, maxLines: 4, overflow: TextOverflow.ellipsis),
            ],
          ],
        );
      case UpdatePhase.downloading:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Line(
              icon: Icons.download_rounded,
              text: 'جارٍ التنزيل… ${(s.progress * 100).toStringAsFixed(0)}%  '
                  '(${(s.receivedBytes / 1048576).toStringAsFixed(1)} / ${((rel?.sizeBytes ?? 0) / 1048576).toStringAsFixed(1)} MB)',
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(value: s.progress, minHeight: 10, backgroundColor: AppTheme.bg, color: AppTheme.accent),
            ),
          ],
        );
      case UpdatePhase.verifying:
        return const _Line(icon: Icons.verified_user_rounded, text: 'التحقق من البصمة SHA-256…', spin: true);
      case UpdatePhase.readyToInstall:
        return const _Line(icon: Icons.verified_rounded, color: AppTheme.good, text: 'الملف سليم ومطابق للبصمة. جاهز للتثبيت.');
      case UpdatePhase.needInstallPermission:
        return const _Line(
          icon: Icons.lock_open_rounded,
          color: AppTheme.warn,
          text: 'اسمح لـ«نقطة» بتثبيت التطبيقات في الشاشة التي فُتحت، ثم ارجع هنا — سيُكمل تلقائياً.',
        );
      case UpdatePhase.error:
        return _Line(icon: Icons.error_outline_rounded, color: AppTheme.bad, text: s.error ?? 'خطأ');
    }
  }

  Widget _actions(BuildContext context, UpdateService s) {
    final busy = s.phase == UpdatePhase.checking || s.phase == UpdatePhase.downloading || s.phase == UpdatePhase.verifying;
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: busy
                ? null
                : switch (s.phase) {
                    UpdatePhase.readyToInstall => s.install,
                    UpdatePhase.available => () async {
                        if (await s.download() != null) await s.install();
                      },
                    UpdatePhase.needInstallPermission => s.retryInstallAfterPermission,
                    _ => s.autoUpdate,
                  },
            icon: Icon(switch (s.phase) {
              UpdatePhase.readyToInstall => Icons.install_mobile_rounded,
              UpdatePhase.available => Icons.download_rounded,
              _ => Icons.autorenew_rounded,
            }),
            label: Text(switch (s.phase) {
              UpdatePhase.readyToInstall => 'تثبيت الآن',
              UpdatePhase.available => 'تنزيل وتثبيت',
              UpdatePhase.needInstallPermission => 'متابعة التثبيت',
              _ => 'تحديث تلقائي',
            }),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton(onPressed: busy ? null : s.check, child: const Text('فحص')),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text, this.color, this.spin = false});

  final IconData icon;
  final String text;
  final Color? color;
  final bool spin;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (spin)
          const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: AppTheme.accent))
        else
          Icon(icon, size: 20, color: color ?? AppTheme.textHi),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(color: color ?? AppTheme.textHi, height: 1.4))),
      ],
    );
  }
}
