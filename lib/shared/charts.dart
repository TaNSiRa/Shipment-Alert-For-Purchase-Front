part of '../main.dart';

// Small hand-drawn charts (no chart package: the build stays offline-safe and
// the charts use the design tokens directly).

/// Grouped vertical bars, one group per label, with a legend.
class GroupedBarChart extends StatelessWidget {
  const GroupedBarChart({
    super.key,
    required this.labels,
    required this.series,
    this.height = 210,
  });
  final List<String> labels;
  final List<(String, Color, List<num>)> series;
  final double height;

  @override
  Widget build(BuildContext context) {
    final maxValue = series.expand((s) => s.$3).fold<num>(0, (a, b) => b > a ? b : a);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 16, children: [
        for (final s in series)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: s.$2, borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 6),
            Text(s.$1, style: DsType.meta),
          ]),
      ]),
      const SizedBox(height: 12),
      SizedBox(
        height: height,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: DsMotion.of(context, const Duration(milliseconds: 700)),
          curve: Curves.easeOutCubic,
          builder: (context, t, _) => LayoutBuilder(builder: (context, c) {
            final groupWidth = c.maxWidth / max(1, labels.length);
            final barWidth = min(22.0, (groupWidth - 18) / max(1, series.length));
            return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (var i = 0; i < labels.length; i++)
                SizedBox(
                  width: groupWidth,
                  child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                    Expanded(
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                        for (final s in series)
                          Tooltip(
                            message: '${s.$1}: ${s.$3[i]}',
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 2),
                              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                                if (s.$3[i] > 0)
                                  Text('${s.$3[i]}', style: mono(size: 10, weight: FontWeight.w700, color: s.$2)),
                                const SizedBox(height: 3),
                                Container(
                                  width: barWidth,
                                  height: maxValue == 0 ? 2 : max(2, (c.maxHeight - 44) * (s.$3[i] / maxValue) * t).toDouble(),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [s.$2, s.$2.withValues(alpha: .7)],
                                    ),
                                    borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
                                  ),
                                ),
                              ]),
                            ),
                          ),
                      ]),
                    ),
                    const SizedBox(height: 6),
                    Text(labels[i], maxLines: 1, overflow: TextOverflow.ellipsis, style: DsType.metaSm),
                  ]),
                ),
            ]);
          }),
        ),
      ),
    ]);
  }
}

/// Donut with a centred total and a legend beside it.
class DonutChart extends StatelessWidget {
  const DonutChart({super.key, required this.slices, this.size = 130, this.centerLabel = 'total'});
  final List<(String, Color, num)> slices;
  final double size;
  final String centerLabel;

  @override
  Widget build(BuildContext context) {
    final total = slices.fold<num>(0, (a, s) => a + s.$3);
    return Row(children: [
      SizedBox(
        width: size,
        height: size,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: DsMotion.of(context, const Duration(milliseconds: 800)),
          curve: Curves.easeOutCubic,
          builder: (context, t, _) => CustomPaint(
            painter: _DonutPainter(slices: slices, total: total, progress: t),
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('$total', style: DsType.stat(22)),
                Text(centerLabel, style: DsType.metaSm),
              ]),
            ),
          ),
        ),
      ),
      const SizedBox(width: 18),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          for (final s in slices)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: s.$2, borderRadius: BorderRadius.circular(3))),
                const SizedBox(width: 8),
                Expanded(child: Text(s.$1, style: DsType.meta, overflow: TextOverflow.ellipsis)),
                Text('${s.$3}', style: mono(size: 12, weight: FontWeight.w700)),
                const SizedBox(width: 6),
                SizedBox(
                  width: 40,
                  child: Text(total == 0 ? '' : '${(s.$3 / total * 100).round()}%', textAlign: TextAlign.right, style: DsType.metaSm),
                ),
              ]),
            ),
        ]),
      ),
    ]);
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.slices, required this.total, required this.progress});
  final List<(String, Color, num)> slices;
  final num total;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * .16;
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);
    final track = Paint()
      ..color = DsColors.track
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawArc(rect, 0, pi * 2, false, track);
    if (total == 0) return;
    var start = -pi / 2;
    for (final s in slices) {
      final sweep = (s.$3 / total) * pi * 2 * progress;
      if (sweep <= 0) continue;
      final paint = Paint()
        ..color = s.$2
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(rect, start, max(0, sweep - .02), false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) => old.progress != progress || old.total != total || old.slices != slices;
}

/// One horizontal bar with a label on the left and the count on the right.
class HBar extends StatelessWidget {
  const HBar({super.key, required this.label, required this.value, required this.max, required this.color, this.extra, this.onTap});
  final String label;
  final num value;
  final num max;
  final Color color;
  final Widget? extra;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fraction = max == 0 ? 0.0 : (value / max).clamp(0, 1).toDouble();
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
        child: Row(children: [
          SizedBox(width: 120, child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: DsType.meta)),
          Expanded(
            child: Stack(children: [
              Container(height: 12, decoration: BoxDecoration(color: DsColors.track, borderRadius: BorderRadius.circular(6))),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: fraction),
                duration: DsMotion.of(context, const Duration(milliseconds: 650)),
                curve: Curves.easeOutCubic,
                builder: (context, f, _) => FractionallySizedBox(
                  widthFactor: f,
                  child: Container(height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6))),
                ),
              ),
            ]),
          ),
          const SizedBox(width: 10),
          SizedBox(width: 30, child: Text('$value', textAlign: TextAlign.right, style: mono(size: 12, weight: FontWeight.w700))),
          if (extra != null) ...[const SizedBox(width: 8), extra!],
        ]),
      ),
    );
  }
}
