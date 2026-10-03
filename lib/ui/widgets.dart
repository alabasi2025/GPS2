import 'package:flutter/material.dart';

import '../engine/models.dart';
import 'format.dart';
import 'theme.dart';

/// رأس لوحة الدقة: الرقم الكبير + مقارنة مع الخام.
class AccuracyHeader extends StatelessWidget {
  const AccuracyHeader({
    required this.estimate,
    required this.rawAccuracyM,
    required this.stale,
    super.key,
  });

  final PositionEstimate estimate;
  final double? rawAccuracyM;
  final bool stale;

  @override
  Widget build(BuildContext context) {
    final e = estimate;
    final color = stale ? AppTheme.textLo : AppTheme.accuracyColor(e.sigmaM);
    final raw = rawAccuracyM;
    final gain = raw != null && raw > 0 ? raw / e.sigmaM : null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              stale ? 'انقطعت الإشارة' : 'دقة الموقع (95%)',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '±${Fmt.metersShort(e.radius95M)}',
                  style: TextStyle(fontSize: 40, fontWeight: FontWeight.w700, color: color, height: 1),
                ),
                const SizedBox(width: 4),
                Text('م', style: TextStyle(fontSize: 20, color: color, fontWeight: FontWeight.w700)),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    Fmt.sigmaLabel(e.sigmaM),
                    style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
        const Spacer(),
        if (raw != null)
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
          ),
      ],
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
