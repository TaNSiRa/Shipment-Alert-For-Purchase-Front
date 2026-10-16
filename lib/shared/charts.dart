part of '../main.dart';

// Small hand-drawn charts (no chart package: the build stays offline-safe and
// the charts use the design tokens directly). The two 3D ones are ported from
// RAP (TargetActualChart and the dashboard's raised donut) so both apps read
// the same.

// ---------------------------------------------------------------------------
// Extruded bar chart
// ---------------------------------------------------------------------------

/// One coloured part of a bar. A bar with several segments is stacked
/// bottom-up in the order given.
class BarSegment {
  const BarSegment(this.label, this.color, this.values);
  final String label;
  final Color color;

  /// One value per group (same length as the chart's labels).
  final List<int> values;
}

/// One bar in every group, e.g. "POs issued". Its height is the sum of its
/// segments.
class BarSeries {
  const BarSeries(this.name, this.segments, {this.notes = const []});
  final String name;
  final List<BarSegment> segments;

  /// Extra tooltip lines (label, one value per group) that are not drawn,
  /// e.g. "Still waiting" under a target bar.
  final List<(String, List<int>)> notes;

  int total(int i) => segments.fold<int>(0, (a, s) => a + s.values[i]);
}

/// Grouped bars with THICKNESS (a top face and a side face), as in RAP's KPI
/// chart: one bar per [BarSeries] in every group, a legend on top, the value
/// above each bar and a tooltip with the breakdown on hover.
///
/// The projection never changes — every bar is extruded along the same fixed
/// vector (right by `depth`, up by 62 % of it), so the front faces stay square
/// to the axis and the values are always read off the same edge.
class ExtrudedBarChart extends StatefulWidget {
  const ExtrudedBarChart({
    super.key,
    required this.labels,
    required this.series,
    this.tooltipTitles,
    this.currentIndex,
    this.height = 210,
  });
  final List<String> labels;
  final List<BarSeries> series;

  /// Full name of each group for the tooltip (defaults to [labels]).
  final List<String>? tooltipTitles;

  /// Group drawn as "now" (soft band behind it, navy pill on its label).
  final int? currentIndex;
  final double height;

  static ({
    double hPad,
    double slot,
    double barW,
    double gap,
    double chartH,
    double baseY,
    double depth,
    double rise,
    double labelH,
  }) geom(Size size, int count, int perGroup) {
    const labelH = 26.0;
    const valueH = 18.0;
    const hPad = 8.0;
    final slot = (size.width - hPad * 2) / max(1, count);
    final barW = (slot * .62 / max(1, perGroup)).clamp(7.0, 26.0);
    final thickness = (barW * .34).clamp(3.0, 8.0);
    final chartH = size.height - labelH - valueH;
    return (
      hPad: hPad,
      slot: slot,
      barW: barW,
      gap: 3.0 + thickness,
      chartH: chartH,
      baseY: valueH + chartH,
      depth: thickness,
      rise: thickness * .62,
      labelH: labelH,
    );
  }

  /// Left edge of bar [k] in group [i]. The group is nudged left by half a
  /// depth so a bar plus its thickness is what ends up centred in the slot,
  /// and the gap between bars carries the depth so a side face lands in the
  /// gap instead of on the next bar.
  static double barLeft(Size size, int count, int perGroup, int i, int k) {
    final g = geom(size, count, perGroup);
    final groupW = perGroup * g.barW + (perGroup - 1) * g.gap;
    return g.hPad + g.slot * i + g.slot / 2 - g.depth / 2 - groupW / 2 + k * (g.barW + g.gap);
  }

  @override
  State<ExtrudedBarChart> createState() => _ExtrudedBarChartState();
}

class _ExtrudedBarChartState extends State<ExtrudedBarChart> {
  ({int group, int bar})? _hover;

  int get _maxValue {
    var m = 1;
    for (final s in widget.series) {
      for (var i = 0; i < widget.labels.length; i++) {
        m = max(m, s.total(i));
      }
    }
    return m;
  }

  ({int group, int bar})? _barAt(Offset p, Size size) {
    final n = widget.labels.length, per = widget.series.length;
    if (n == 0 || per == 0) return null;
    final g = ExtrudedBarChart.geom(size, n, per);
    final i = ((p.dx - g.hPad) / g.slot).floor();
    if (i < 0 || i >= n || p.dy < 0 || p.dy > g.baseY) return null;
    for (var k = 0; k < per; k++) {
      final left = ExtrudedBarChart.barLeft(size, n, per, i, k);
      if (p.dx >= left - 3 && p.dx < left + g.barW + g.depth + 1.5) {
        return widget.series[k].total(i) > 0 ? (group: i, bar: k) : null;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 16, runSpacing: 4, children: [
        for (final s in widget.series)
          for (final seg in s.segments)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: seg.color, borderRadius: BorderRadius.circular(3))),
              const SizedBox(width: 6),
              Text(seg.label, style: DsType.meta),
            ]),
      ]),
      const SizedBox(height: 12),
      SizedBox(
        height: widget.height,
        child: LayoutBuilder(builder: (context, c) {
          final size = Size(c.maxWidth, c.maxHeight);
          return MouseRegion(
            onHover: (e) {
              final hit = _barAt(e.localPosition, size);
              if (hit != _hover) setState(() => _hover = hit);
            },
            onExit: (_) {
              if (_hover != null) setState(() => _hover = null);
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              // Touch never hovers: a tap shows (or hides) the tooltip.
              onTapUp: (e) => setState(() => _hover = _barAt(e.localPosition, size)),
              child: Stack(clipBehavior: Clip.none, children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: DsMotion.of(context, const Duration(milliseconds: 720)),
                  curve: Curves.easeOutCubic,
                  builder: (context, grow, _) => CustomPaint(
                    painter: _ExtrudedBarPainter(
                      labels: widget.labels,
                      series: widget.series,
                      maxValue: _maxValue,
                      currentIndex: widget.currentIndex,
                      hover: _hover,
                      grow: grow,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
                if (_hover != null) _tooltip(size),
              ]),
            ),
          );
        }),
      ),
    ]);
  }

  Widget _tooltip(Size size) {
    final h = _hover!;
    final s = widget.series[h.bar];
    final n = widget.labels.length, per = widget.series.length;
    final g = ExtrudedBarChart.geom(size, n, per);
    final total = s.total(h.group);
    final title = (widget.tooltipTitles ?? widget.labels)[h.group];

    Widget row(String label, String value, {Color? dot, bool bold = false}) => Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (dot != null) ...[
              Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
              const SizedBox(width: 6),
            ],
            Text('$label  ', style: const TextStyle(color: Color(0xffb9c0d4), fontSize: 11.5, height: 1.3)),
            Text(value,
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    height: 1.3,
                    fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
                    fontFamily: dsFontMono,
                    fontFamilyFallback: dsFontFallback)),
          ]),
        );

    final rows = [
      for (final seg in s.segments) row(seg.label, '${seg.values[h.group]}', dot: seg.color),
      if (s.segments.length > 1) row('Total', '$total', bold: true),
      for (final n in s.notes) row(n.$1, '${n.$2[h.group]}'),
    ];
    // Just above the bar's TOP FACE (which stands `rise` above its front),
    // clamped inside the chart.
    final left0 = ExtrudedBarChart.barLeft(size, n, per, h.group, h.bar);
    final barCx = left0 + g.barW / 2 + g.depth / 2;
    final barTop = g.baseY - g.chartH * total / _maxValue - g.rise;
    const tipW = 170.0;
    final tipH = 34.0 + rows.length * 18.0;
    return Positioned(
      left: (barCx - tipW / 2).clamp(0.0, max(0.0, size.width - tipW)).toDouble(),
      top: max(0.0, barTop - tipH - 10),
      width: tipW,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(color: const Color(0xee12183a), borderRadius: BorderRadius.circular(8)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('$title · ${s.name}',
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700, height: 1.3)),
            ...rows,
          ]),
        ),
      ),
    );
  }
}

class _ExtrudedBarPainter extends CustomPainter {
  _ExtrudedBarPainter({
    required this.labels,
    required this.series,
    required this.maxValue,
    required this.currentIndex,
    required this.hover,
    required this.grow,
  });
  final List<String> labels;
  final List<BarSeries> series;
  final int maxValue;
  final int? currentIndex;
  final ({int group, int bar})? hover;
  final double grow; // 0..1 entry animation

  @override
  void paint(Canvas canvas, Size size) {
    final n = labels.length, per = series.length;
    if (n == 0 || per == 0 || size.isEmpty) return;
    final g = ExtrudedBarChart.geom(size, n, per);
    final dx = g.depth, dy = -g.rise;
    final tp = TextPainter(textDirection: ui.TextDirection.ltr);

    // The top face is the colour lifted towards white (catching the light),
    // the side face pushed towards black (in shadow).
    Color shade(Color c, double t) =>
        (t >= 0 ? Color.lerp(c, Colors.white, t) : Color.lerp(c, Colors.black, -t))!.withValues(alpha: c.a);

    // Square corners on purpose (as in RAP): a rounded top on an extruded bar
    // makes the top face thin out and read as a bite out of the corner.
    void bar(Rect r, Color c, {bool cap = true}) {
      if (r.height <= 0) return;
      canvas.drawPath(
          Path()
            ..moveTo(r.right, r.top)
            ..lineTo(r.right + dx, r.top + dy)
            ..lineTo(r.right + dx, r.bottom + dy)
            ..lineTo(r.right, r.bottom)
            ..close(),
          Paint()..color = shade(c, -.22));
      if (cap) {
        canvas.drawPath(
            Path()
              ..moveTo(r.left, r.top)
              ..lineTo(r.left + dx, r.top + dy)
              ..lineTo(r.right + dx, r.top + dy)
              ..lineTo(r.right, r.top)
              ..close(),
            Paint()..color = shade(c, .2));
      }
      canvas.drawRect(r, Paint()..color = c);
    }

    void outline(Rect r) => canvas.drawPath(
        Path()
          ..moveTo(r.left, r.bottom)
          ..lineTo(r.left, r.top)
          ..lineTo(r.left + dx, r.top + dy)
          ..lineTo(r.right + dx, r.top + dy)
          ..lineTo(r.right + dx, r.bottom + dy)
          ..lineTo(r.right, r.bottom)
          ..close(),
        Paint()
          ..color = const Color(0xff12183a)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..strokeJoin = StrokeJoin.round);

    // Figures land once the bars have arrived instead of riding up with them.
    final labelAlpha = ((grow - .6) / .4).clamp(0.0, 1.0);

    // Faint floor line, so empty months still show where zero is.
    canvas.drawLine(Offset(g.hPad, g.baseY + .5), Offset(size.width - g.hPad, g.baseY + .5),
        Paint()..color = DsColors.track);

    for (var i = 0; i < n; i++) {
      final slotLeft = g.hPad + g.slot * i;
      final slotCx = slotLeft + g.slot / 2;
      final isCurrent = i == currentIndex;
      if (isCurrent) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(slotLeft + 2, 2, g.slot - 4, g.baseY - 2), const Radius.circular(8)),
          Paint()..color = const Color(0x141f2a63),
        );
      }

      for (var k = 0; k < per; k++) {
        final s = series[k];
        final left = ExtrudedBarChart.barLeft(size, n, per, i, k);
        final hot = hover?.group == i && hover?.bar == k;
        canvas.save();
        // The hovered bar steps toward the viewer along the depth vector.
        if (hot) canvas.translate(-dx * .45, -dy * .45);
        var top = g.baseY;
        final segs = [
          for (final seg in s.segments)
            if (seg.values[i] > 0) seg
        ];
        for (var j = 0; j < segs.length; j++) {
          final h = g.chartH * segs[j].values[i] / maxValue * grow;
          // Only the highest segment gets a top face.
          bar(Rect.fromLTWH(left, top - h, g.barW, h), segs[j].color, cap: j == segs.length - 1);
          top -= h;
        }
        final total = s.total(i);
        if (hot && total > 0) outline(Rect.fromLTWH(left, top, g.barW, g.baseY - top));
        if (total > 0 && labelAlpha > 0) {
          tp.text = TextSpan(
              text: '$total',
              style: TextStyle(
                  color: shade(s.segments.first.color, -.15).withValues(alpha: labelAlpha),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  fontFamily: dsFontMono,
                  fontFamilyFallback: dsFontFallback));
          tp.layout();
          tp.paint(canvas, Offset(left + g.barW / 2 + dx / 2 - tp.width / 2, top + dy - tp.height - 1));
        }
        canvas.restore();
      }

      tp.text = TextSpan(
          text: labels[i],
          style: TextStyle(
              color: isCurrent ? Colors.white : const Color(0xff838aa3),
              fontFamily: dsFontSans,
              fontFamilyFallback: dsFontFallback,
              fontSize: 10.5,
              fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w400));
      tp.layout();
      final labelTop = size.height - g.labelH + 6;
      if (isCurrent) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(slotCx - tp.width / 2 - 6, labelTop - 3, tp.width + 12, tp.height + 6),
              const Radius.circular(9)),
          Paint()..color = DsColors.navy,
        );
      }
      tp.paint(canvas, Offset(slotCx - tp.width / 2, labelTop));
    }
  }

  @override
  bool shouldRepaint(_ExtrudedBarPainter old) =>
      old.labels != labels ||
      old.series != series ||
      old.maxValue != maxValue ||
      old.currentIndex != currentIndex ||
      old.hover != hover ||
      old.grow != grow;
}

// ---------------------------------------------------------------------------
// Raised donut
// ---------------------------------------------------------------------------

class DonutSlice {
  const DonutSlice(this.label, this.value, this.color);
  final String label;
  final int value;
  final Color color;
}

/// A raised (tilted, extruded) donut with a callout for every wedge — name,
/// count, share — on a leader line outside the ring. The tilt makes near
/// wedges look bigger than they are, so the numbers are always shown.
/// Hovering a wedge (or its callout) lifts it.
///
/// Give it a bounded size (e.g. a SizedBox): the painter lays itself out from
/// its own size and leaves that layout in [_DonutBox] for hover hit-testing.
class RaisedDonut extends StatefulWidget {
  const RaisedDonut({super.key, required this.slices, this.caption});

  /// Slices with a value of 0 are skipped; at least one must be above 0.
  final List<DonutSlice> slices;

  /// Small line under the total in the hole (e.g. 'open').
  final String? caption;

  @override
  State<RaisedDonut> createState() => _RaisedDonutState();
}

class _RaisedDonutState extends State<RaisedDonut> {
  final _box = _DonutBox();
  int? _hovered;

  @override
  Widget build(BuildContext context) {
    final slices = [
      for (final s in widget.slices)
        if (s.value > 0) s
    ];
    return MouseRegion(
      onHover: (e) {
        final hit = _box.hitTest(e.localPosition);
        if (hit != _hovered) setState(() => _hovered = hit);
      },
      onExit: (_) {
        if (_hovered != null) setState(() => _hovered = null);
      },
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: DsMotion.of(context, const Duration(milliseconds: 900)),
        curve: Curves.easeOutCubic,
        builder: (context, t, _) => CustomPaint(
          painter: _DonutPainter3d(slices: slices, progress: t, hovered: _hovered, box: _box, caption: widget.caption),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

/// What the last paint used, so hover can hit-test the same geometry.
class _DonutBox {
  String? key;
  _DonutLayout? layout;
  int? hovered;
  double progress = 1;

  int? hitTest(Offset p) {
    final l = layout;
    if (l == null) return null;
    for (final c in l.callouts) {
      if (c.rect.inflate(4).contains(p)) return c.index;
    }
    if (hovered != null && l.topPath(hovered!, progress, hovered).contains(p)) return hovered;
    for (var i = 0; i < l.slices.length; i++) {
      if (l.topPath(i, progress, hovered).contains(p)) return i;
    }
    return null;
  }
}

class _DonutCallout {
  _DonutCallout(this.index, this.text, this.mid);
  final int index;
  final TextPainter text;
  final double mid; // the wedge's own mid angle
  double angle = 0; // where the label actually sits (nudged off [mid] on collision)
  Offset point = Offset.zero; // leader elbow
  Offset attach = Offset.zero; // where the leader meets the label
  Rect rect = Rect.zero;
}

/// Ring size, centre and callout placement for one card size and data set.
/// Independent of the opening sweep and of hover, so it is computed once and
/// cached; the wedge geometry methods take those two as arguments.
class _DonutLayout {
  _DonutLayout(Size size, this.slices) : total = slices.fold<int>(0, (s, e) => s + e.value) {
    var a = -pi / 2;
    for (final s in slices) {
      final sweep = 2 * pi * s.value / total;
      starts.add(a);
      sweeps.add(sweep);
      a += sweep;
    }
    List<TextPainter> texts(double scale) {
      final base = DsType.meta.copyWith(fontSize: (DsType.meta.fontSize ?? 12) * scale);
      return [
        for (final s in slices)
          TextPainter(
            textDirection: TextDirection.ltr,
            maxLines: 1,
            text: TextSpan(children: [
              // Each callout is written in its own wedge's colour, so the eye
              // matches name to slice without following the leader line.
              TextSpan(text: s.label, style: base.copyWith(fontWeight: FontWeight.w700, color: s.color)),
              TextSpan(
                  text: '  ${s.value}',
                  style: base.copyWith(fontFamily: dsFontMono, fontWeight: FontWeight.w700, color: s.color)),
              TextSpan(
                  text: ' · ${(s.value / total * 100).round()}%',
                  style: base.copyWith(fontFamily: dsFontMono, color: s.color.withValues(alpha: .78))),
            ]),
          )..layout(),
      ];
    }

    // The biggest ring whose callouts all fit round it without touching each
    // other, the ring or the card edge. Before letting the ring get small the
    // callout text shrinks a step; only if nothing fits at all does it fall
    // back to side columns.
    final maxR = min(size.width / 2 - 8, (size.height - 8) / (2 * cos(tilt) + thickRatio * sin(tilt)));
    const scales = [1.0, .9, .8];
    for (final minR in const [46.0, 28.0]) {
      for (final scale in scales) {
        final t = texts(scale);
        for (var r = min(maxR, 130.0); r >= minR; r -= 3) {
          if (_tryRadial(size, r, t)) return;
        }
      }
    }
    _columns(size, texts(scales.last));
  }

  static const double tilt = 58 * pi / 180;
  static const double thickRatio = .17;
  static const double innerRatio = .56;
  static const double lift = 9; // hovered wedge rises this much (px)
  static const double gap = .03;
  static const double leaderX = 16; // ring edge → elbow, sideways
  static const double leaderY = 14; // ring edge → elbow, up/down

  final List<DonutSlice> slices;
  final int total;
  final starts = <double>[];
  final sweeps = <double>[];
  double radius = 0, thick = 0;
  Offset center = Offset.zero;
  List<_DonutCallout> callouts = [];

  double mid(int i) => starts[i] + sweeps[i] / 2;

  void _setRing(Size size, double r) {
    radius = r;
    thick = r * thickRatio;
    center = Offset(size.width / 2, size.height / 2 - thick * sin(tilt) / 2);
  }

  void _place(_DonutCallout c, double a) {
    c.angle = a;
    final ca = cos(a), sa = sin(a);
    final p = Offset(
      center.dx + ca * (radius + leaderX),
      center.dy + sa * (radius * cos(tilt) + leaderY) + (sa > 0 ? thick * sin(tilt) : 0),
    );
    c.point = p;
    final w = c.text.width, h = c.text.height;
    if (ca > .4) {
      c.rect = Rect.fromLTWH(p.dx + 10, p.dy - h / 2, w, h);
      c.attach = Offset(p.dx + 8, p.dy);
    } else if (ca < -.4) {
      c.rect = Rect.fromLTWH(p.dx - 10 - w, p.dy - h / 2, w, h);
      c.attach = Offset(p.dx - 8, p.dy);
    } else if (sa < 0) {
      c.rect = Rect.fromLTWH(p.dx - w / 2, p.dy - 2 - h, w, h);
      c.attach = p;
    } else {
      c.rect = Rect.fromLTWH(p.dx - w / 2, p.dy + 2, w, h);
      c.attach = p;
    }
  }

  bool _hitsRing(Rect r) {
    final cy = center.dy + thick * sin(tilt) / 2;
    final rx = radius + 3, ry = radius * cos(tilt) + thick * sin(tilt) / 2 + 3;
    for (final p in [
      r.topLeft, r.topCenter, r.topRight, r.centerLeft, r.centerRight, r.bottomLeft, r.bottomCenter, r.bottomRight
    ]) {
      final dx = (p.dx - center.dx) / rx, dy = (p.dy - cy) / ry;
      if (dx * dx + dy * dy < 1) return true;
    }
    return false;
  }

  bool _tryRadial(Size size, double r, List<TextPainter> texts) {
    _setRing(size, r);
    final cs = [for (var i = 0; i < slices.length; i++) _DonutCallout(i, texts[i], mid(i))];
    for (final c in cs) {
      _place(c, c.mid);
    }
    // Neighbours round the ring that collide are nudged apart along the ring
    // until nothing moves.
    if (cs.length > 1) {
      for (var it = 0; it < 160; it++) {
        var moved = false;
        for (var k = 0; k < cs.length; k++) {
          final a = cs[k], b = cs[(k + 1) % cs.length];
          if (cs.length == 2 && k == 1) break;
          if (a.rect.inflate(3).overlaps(b.rect)) {
            _place(a, a.angle - .02);
            _place(b, b.angle + .02);
            moved = true;
          }
        }
        if (!moved) break;
      }
    }
    final bounds = Offset.zero & size;
    for (final c in cs) {
      if (!bounds.contains(c.rect.topLeft) || !bounds.contains(c.rect.bottomRight)) return false;
      if ((c.angle - c.mid).abs() > 1.1) return false;
      if (_hitsRing(c.rect)) return false;
    }
    for (var i = 0; i < cs.length; i++) {
      for (var j = i + 1; j < cs.length; j++) {
        if (cs[i].rect.inflate(2).overlaps(cs[j].rect)) return false;
      }
    }
    callouts = cs;
    return true;
  }

  /// Fallback for a card too small for labels all round: a column each side,
  /// pushed apart so they still never share a row.
  void _columns(Size size, List<TextPainter> texts) {
    final labelW = texts.map((t) => t.width).fold<double>(0, max);
    final pitch = texts.map((t) => t.height).fold<double>(0, max) + 6;
    final fromH = (size.height - 10 - lift) / (2 * cos(tilt) + thickRatio * sin(tilt));
    final fromW = (size.width - 2 * (labelW + 40)) / 2;
    _setRing(size, min(min(fromH, fromW), 118.0).clamp(28.0, 118.0));
    final cs = [for (var i = 0; i < slices.length; i++) _DonutCallout(i, texts[i], mid(i))];
    final rightCount = cs.where((c) => cos(c.mid) >= 0).length;
    final split = max(rightCount, cs.length - rightCount) * pitch > size.height - 4;
    final half = (cs.length / 2).ceil();
    for (final right in [true, false]) {
      final side = cs.where((c) => split ? (c.index < half) == right : (cos(c.mid) >= 0) == right).toList()
        ..sort((p, q) => sin(p.mid).compareTo(sin(q.mid)));
      var prev = -double.infinity;
      final ys = <double>[];
      for (final c in side) {
        final want = center.dy + sin(c.mid) * radius * cos(tilt);
        prev = max(max(want, 2 + pitch / 2), prev + pitch);
        ys.add(prev);
      }
      var next = double.infinity;
      for (var k = side.length - 1; k >= 0; k--) {
        ys[k] = min(ys[k], min(size.height - 2 - pitch / 2, next - pitch));
        next = ys[k];
      }
      final textX = right ? center.dx + radius + 40 : center.dx - radius - 40;
      for (var k = 0; k < side.length; k++) {
        final c = side[k], w = c.text.width, h = c.text.height;
        c.angle = c.mid;
        c.rect = Rect.fromLTWH(right ? textX : textX - w, ys[k] - h / 2, w, h);
        c.point = Offset(right ? textX - 10 : textX + 10, ys[k]);
        c.attach = Offset(right ? textX - 4 : textX + 4, ys[k]);
      }
    }
    callouts = cs;
  }

  // --- wedge geometry (depends on the opening sweep and hover) --------------

  (double, double) span(int i, double progress) {
    // A single slice is a full ring: no gap to leave between it and itself.
    final g = slices.length == 1 ? 0.0 : gap;
    final a0 = -pi / 2 + (starts[i] + pi / 2) * progress + g / 2;
    return (a0, a0 + max(0.0, sweeps[i] * progress - g));
  }

  double _base(int i, int? hovered) => hovered == i ? lift : 0;

  Offset project(double x, double y, double z) => Offset(center.dx + x, center.dy + y * cos(tilt) - z * sin(tilt));

  Offset _at(int i, int? hovered, double rad, double ang, double z) {
    final s = hovered == i && slices.length > 1 ? Offset(cos(mid(i)), sin(mid(i))) * 6 : Offset.zero;
    return project(cos(ang) * rad + s.dx, sin(ang) * rad + s.dy, z);
  }

  Offset anchor(int i, int? hovered) => _at(i, hovered, radius, mid(i), _base(i, hovered) + thick);

  List<double> _steps(double a0, double a1) {
    final n = max(2, ((a1 - a0) / .05).ceil());
    return [for (var k = 0; k <= n; k++) a0 + (a1 - a0) * k / n];
  }

  Path topPath(int i, double progress, int? hovered) {
    final (a0, a1) = span(i, progress);
    final z = _base(i, hovered) + thick;
    final angs = _steps(a0, a1);
    return Path()
      ..addPolygon([
        for (final a in angs) _at(i, hovered, radius, a, z),
        for (final a in angs.reversed) _at(i, hovered, radius * innerRatio, a, z),
      ], true);
  }

  /// One polygon per wall (not a strip of quads, whose seams showed as
  /// vertical stripes): the arc at the bottom edge, back along the top edge.
  Path wall(int i, double progress, int? hovered, double rad) {
    final (a0, a1) = span(i, progress);
    final z0 = _base(i, hovered), z1 = z0 + thick;
    final angs = _steps(a0, a1);
    return Path()
      ..addPolygon([
        for (final a in angs) _at(i, hovered, rad, a, z0),
        for (final a in angs.reversed) _at(i, hovered, rad, a, z1),
      ], true);
  }

  Path caps(int i, double progress, int? hovered) {
    final (a0, a1) = span(i, progress);
    final z0 = _base(i, hovered), z1 = z0 + thick;
    final path = Path();
    for (final a in [a0, a1]) {
      path.addPolygon([
        _at(i, hovered, radius * innerRatio, a, z0),
        _at(i, hovered, radius, a, z0),
        _at(i, hovered, radius, a, z1),
        _at(i, hovered, radius * innerRatio, a, z1),
      ], true);
    }
    return path;
  }
}

class _DonutPainter3d extends CustomPainter {
  _DonutPainter3d(
      {required this.slices, required this.progress, required this.hovered, required this.box, this.caption});
  final List<DonutSlice> slices;
  final double progress;
  final int? hovered;
  final _DonutBox box;
  final String? caption;

  static const _ink = Color(0xff0b1030);

  @override
  void paint(Canvas canvas, Size size) {
    if (slices.isEmpty || size.isEmpty) {
      box.layout = null;
      return;
    }
    final key = '${size.width.toStringAsFixed(1)}x${size.height.toStringAsFixed(1)}|'
        '${slices.map((s) => '${s.label}:${s.value}:${s.color.toARGB32()}').join(',')}';
    if (box.key != key || box.layout == null) {
      box.layout = _DonutLayout(size, slices);
      box.key = key;
    }
    final l = box.layout!;
    box
      ..hovered = hovered
      ..progress = progress;
    const tilt = _DonutLayout.tilt;

    // Soft shadow under the ring.
    canvas.drawOval(
      Rect.fromCenter(
          center: l.center + Offset(0, l.thick * sin(tilt) + 4),
          width: l.radius * 2.05,
          height: l.radius * 2 * cos(tilt) * .95),
      Paint()
        ..color = const Color(0x24131c4a)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
    );

    Paint fill(int i, double darken) => Paint()..color = Color.lerp(slices[i].color, _ink, darken)!;
    final rest = [
      for (var i = 0; i < slices.length; i++)
        if (i != hovered && l.span(i, progress).$2 > l.span(i, progress).$1) i,
    ];
    // Inner walls (seen through the hole), outer walls, end caps, then the
    // tops over all of them; the lifted wedge goes on last as a whole.
    for (final i in rest) {
      canvas.drawPath(l.wall(i, progress, hovered, l.radius * _DonutLayout.innerRatio), fill(i, .4));
    }
    for (final i in rest) {
      canvas.drawPath(l.wall(i, progress, hovered, l.radius), fill(i, .22));
    }
    for (final i in rest) {
      canvas.drawPath(l.caps(i, progress, hovered), fill(i, .32));
    }
    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: .45);
    for (final i in rest) {
      final top = l.topPath(i, progress, hovered);
      canvas.drawPath(top, Paint()..color = slices[i].color);
      canvas.drawPath(top, rim);
    }
    if (hovered != null && hovered! < slices.length) {
      final h = hovered!;
      canvas.drawPath(l.wall(h, progress, hovered, l.radius * _DonutLayout.innerRatio), fill(h, .4));
      canvas.drawPath(l.wall(h, progress, hovered, l.radius), fill(h, .22));
      canvas.drawPath(l.caps(h, progress, hovered), fill(h, .32));
      final top = l.topPath(h, progress, hovered);
      canvas.drawPath(top, Paint()..color = slices[h].color);
      canvas.drawPath(top, rim..color = Colors.white.withValues(alpha: .8));
    }

    // Total (and caption) in the hole.
    final hole = l.project(0, 0, l.thick);
    final holeH = 2 * l.radius * _DonutLayout.innerRatio * cos(tilt);
    final totalText = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
          text: '${l.total}',
          style: DsType.meta.copyWith(
              fontFamily: dsFontMono,
              fontWeight: FontWeight.w700,
              fontSize: holeH > 40 ? 16 : 12,
              color: DsColors.heading)),
    )..layout();
    final captionText = caption != null && holeH > 40
        ? (TextPainter(
            textDirection: TextDirection.ltr,
            text: TextSpan(text: caption, style: DsType.metaSm.copyWith(fontSize: 9)),
          )..layout())
        : null;
    final blockH = totalText.height + (captionText?.height ?? 0);
    totalText.paint(canvas, hole - Offset(totalText.width / 2, blockH / 2));
    captionText?.paint(canvas, hole + Offset(-captionText.width / 2, totalText.height - blockH / 2));

    // Callouts fade in once the ring is mostly drawn.
    final fade = ((progress - .55) / .45).clamp(0.0, 1.0);
    if (fade <= 0) return;
    for (final c in l.callouts) {
      final color = slices[c.index].color;
      final hot = c.index == hovered;
      final alpha = fade * (hovered != null && !hot ? .45 : 1);
      final anchor = l.anchor(c.index, hovered);
      canvas.drawPath(
        Path()
          ..moveTo(anchor.dx, anchor.dy)
          ..lineTo(c.point.dx, c.point.dy)
          ..lineTo(c.attach.dx, c.attach.dy),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = hot ? 1.8 : 1.1
          ..color = color.withValues(alpha: alpha * .85),
      );
      canvas.drawCircle(
          anchor, hot ? 3.2 : 2.4, Paint()..color = Color.lerp(color, _ink, .15)!.withValues(alpha: alpha));
      if (hot) {
        canvas.drawRRect(RRect.fromRectAndRadius(c.rect.inflate(4), const Radius.circular(6)),
            Paint()..color = color.withValues(alpha: .13));
      }
      canvas.saveLayer(c.rect.inflate(2), Paint()..color = Colors.white.withValues(alpha: alpha));
      c.text.paint(canvas, c.rect.topLeft);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_DonutPainter3d old) =>
      old.progress != progress || old.hovered != hovered || old.slices != slices || old.caption != caption;
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
