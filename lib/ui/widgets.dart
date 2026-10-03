import 'package:flutter/material.dart';

import '../engine/models.dart';
import '../engine/solution_arbiter.dart';
import 'format.dart';
import 'theme.dart';

/// رأس لوحة الدقة: الرقم الكبير + مصدر الحل + إرشاد.
class SolutionHeader extends StatelessWidget {
  const SolutionHeader({
    required this.solution,
    required this.gnssSigmaM,
    required this.rawAccuracyM,
    required this.stale,
    super.key,
  });

  final DisplaySolution solution;
  final double? gnssSigmaM;
  final double? rawAccuracyM;
  final bool stale;

  @override
  Widget build(BuildContext context) {
    final s = solution;
    final color = stale ? AppTheme.textLo : AppTheme.accuracyColor(s.sigmaM);
    final isGnss = s.source == FixSource.gnss;
    final raw = rawAccuracyM;
    final gain = isGnss && raw != null && raw > 0 ? raw / s.sigmaM : null;
    final hint = switch (s.reason) {
      ArbiterReason.gnssInconsistent => 'إشارة الأقمار منعكسة (داخل مبنى؟) — اخرج لسماء مفتوحة للدقة العالية',
      ArbiterReason.gnssWeak => 'أقمار قليلة — اخرج لمكان مكشوف',
      ArbiterReason.gnssMissing => 'بانتظار الأقمار — الموقع الحالي من الشبكة',
      ArbiterReason.gnssTrusted || ArbiterReason.none => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(stale ? 'انقطعت الإشارة' : 'دقة الموقع (95%)', style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(width: 8),
                    SourceBadge(source: s.source),
                  ],
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      '±${Fmt.metersShort(s.radius95M)}',
                      style: TextStyle(fontSize: 40, fontWeight: FontWeight.w700, color: color, height: 1),
                    ),
                    const SizedBox(width: 4),
                    Text('م', style: TextStyle(fontSize: 20, color: color, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: color.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(8)),
                      child: Text(
                        Fmt.sigmaLabel(s.sigmaM),
                        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const Spacer(),
            if (isGnss && raw != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('الخام من الجهاز', style: Theme.of(context).textTheme.bodySmall),
                  Text(
                    '±${Fmt.metersShort(raw)} م',
                    style: const TextStyle(fontSize: 16, color: AppTheme.textLo, fontWeight: FontWeight.w700),
                  ),
                  if (gain != null && gain >= 1.2)
                    Text(
                      'أفضل ×${gain.toStringAsFixed(1)}',
                      style: const TextStyle(fontSize: 11, color: AppTheme.good, fontWeight: FontWeight.w700),
                    ),
                ],
              )
            else if (!isGnss && gnssSigmaM != null && s.gnssDisagreementM != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('GNSS منحرف', style: Theme.of(context).textTheme.bodySmall),
                  Text(
                    Fmt.meters(s.gnssDisagreementM!),
                    style: const TextStyle(fontSize: 16, color: AppTheme.warn, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
          ],
        ),
        if (hint != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.info_outline_rounded, size: 14, color: AppTheme.warn),
              const SizedBox(width: 6),
              Expanded(child: Text(hint, style: const TextStyle(fontSize: 12, color: AppTheme.warn))),
            ],
          ),
        ],
      ],
    );
  }
}

/// شارة مصدر الحل: GNSS (أقمار مباشرة) أو مدمج (Wi-Fi/خلوي/GPS من النظام).
class SourceBadge extends StatelessWidget {
  const SourceBadge({required this.source, super.key});

  final FixSource source;

  @override
  Widget build(BuildContext context) {
    final gnss = source == FixSource.gnss;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: (gnss ? AppTheme.good : AppTheme.accent).withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: gnss ? AppTheme.good : AppTheme.accent, width: 1),
      ),
      child: Text(
        gnss ? 'GNSS' : 'مدمج',
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: gnss ? AppTheme.good : AppTheme.accent),
      ),
    );
  }
}

class StatTile extends StatelessWidget {
  const StatTile({required this.label, required this.value, required this.sub, this.color, super.key});

  final String label;
  final String value;
  final String sub;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.textLo)),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: color ?? AppTheme.textHi, height: 1.1),
          ),
          Text(sub, style: const TextStyle(fontSize: 10, color: AppTheme.textLo)),
        ],
      ),
    );
  }
}

class GlassPill extends StatelessWidget {
  const GlassPill({required this.child, this.onTap, super.key});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surface.withValues(alpha: 0.94),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: child,
        ),
      ),
    );
  }
}

class BandBadge extends StatelessWidget {
  const BandBadge({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(color: AppTheme.good, borderRadius: BorderRadius.circular(6)),
      child: Text(
        text,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.bg),
      ),
    );
  }
}

/// علامة الموقع: نقطة مع هالة نابضة أثناء الحركة.
class PositionDot extends StatelessWidget {
  const PositionDot({required this.motion, required this.stale, super.key});

  final MotionState motion;
  final bool stale;

  @override
  Widget build(BuildContext context) {
    final color = stale
        ? AppTheme.textLo
        : (motion == MotionState.stationary ? AppTheme.good : AppTheme.accent);
    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.25),
        ),
        child: Center(
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              border: Border.all(color: Colors.white, width: 2.5),
              boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 4)],
            ),
          ),
        ),
      ),
    );
  }
}

class SavedPin extends StatelessWidget {
  const SavedPin({required this.index, super.key});

  final int index;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppTheme.warn,
        border: Border.all(color: Colors.white, width: 2),
      ),
      alignment: Alignment.center,
      child: Text(
        '$index',
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.bg),
      ),
    );
  }
}
