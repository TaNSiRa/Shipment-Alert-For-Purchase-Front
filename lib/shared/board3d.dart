part of '../main.dart';

// ---------------------------------------------------------------------------
// 3D stage board — the RAP request-timeline look (RAP
// request_timeline_dialog.dart: _Board3d / _TlCamera / _TlBoardPainter /
// _TlArrowPainter), shared by the dashboard's shipment pipeline and the
// Workflow page.
//
// The stages run left→right, U-turn, right→left on a board tilted away from
// the viewer ("tilted desk"). Flutter has no preserve-3d, so everything is
// projected by hand in [_B3Camera.project]:
//  - the rail is painted as stacked ribbons, the darker lower layers showing
//    as its side wall;
//  - the stage discs, top bands and labels stay ordinary upright widgets placed
//    at their projected points, so they float above the rail facing the viewer;
//  - white chevrons flow along the rail in the direction of travel.
// The row gap is solved per width so a lower row's top band can never cover
// the labels of the row above it (the board is foreshortened, so a fixed gap
// would squeeze them together).
// ---------------------------------------------------------------------------

/// One stop on a [Board3dRail].
class Board3dStage {
  const Board3dStage({
    required this.title,
    required this.icon,
    required this.accent,
    this.number,
    this.top,
    this.pills = const [],
    this.lines = const [],
    this.muted = false,
    this.glow = false,
    this.onTap,
  });

  final String title;
  final IconData icon;
  final Color accent;

  /// Small navy badge on the disc (the step number).
  final String? number;

  /// Band floating above the disc (a count, a milestone).
  final String? top;

  /// Pills above the title, as (text, colour).
  final List<(String, Color)> pills;

  /// Detail lines under the title.
  final List<String> lines;

  /// Nothing here yet: grey disc and grey rail into it.
  final bool muted;

  /// Highlighted stage: a soft halo in its accent.
  final bool glow;
  final VoidCallback? onTap;

  String get _signature =>
      '$title|${icon.codePoint}|${accent.toARGB32()}|$number|$top|$pills|$lines|$muted|$glow|${onTap != null}';
}

/// Bright infographic palette, cycled across stages.
const List<Color> board3dPalette = [
  DsColors.blueFg, // blue
  Color(0xff0ea5a5), // teal
  Color(0xfff59e0b), // amber
  DsColors.greenDot, // green
  Color(0xffe0447c), // pink
  Color(0xff6d5ef0), // purple
  Color(0xff0891b2), // cyan
  Color(0xffd97706), // orange
];
const Color _b3Upcoming = Color(0xffdfe4ee);
const Color _b3UpcomingIcon = Color(0xffa4abc2);

// Opening sequence: node i pops at progress i, the rail to node i+1 draws
// itself over the next unit.
double _b3NodeReveal(double p, num at) => ((p - at) / .35).clamp(0.0, 1.0);
double _b3SegReveal(double p, num at) => ((p - at - .15) / .85).clamp(0.0, 1.0);

const _b3TitleStyle = TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: DsColors.heading, height: 1.3);
const _b3LineStyle = TextStyle(fontSize: 11.5, color: DsColors.muted, height: 1.4);
const _b3PillStyle = TextStyle(fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: .4);

class _B3Camera {
  _B3Camera._({
    required this.perRow,
    required this.rows,
    required this.stages,
    required this.labelHeights,
    required this.centers,
    required this.plate,
    required this.cx,
    required this.cy,
    required this.k,
    required this.ox,
    required this.oy,
    required this.height,
  });

  static const double tilt = 52 * pi / 180;
  static const double perspective = 1500; // board units
  static const double cellW = 240; // board units per column
  static const double trackW = 26;
  static const double trackH = 14; // rail height above the board
  static const double plateDepth = 12;
  static const double lift = 38; // disc centre above the rail
  static const double liftHover = 58;
  static const double discSize = 60; // px, nearest row
  static const double turnR = 100; // how far a U-turn swings past its column

  final int perRow;
  final int rows;
  final List<Board3dStage> stages;
  final double Function(int i, double w) labelHeights;
  final List<Offset> centers; // board space
  final Rect plate; // board space
  final double cx, cy; // board point projected to the screen origin
  final double k, ox, oy; // screen fit
  final double height;

  double get boardW => perRow * cellW;
  int get segmentCount => centers.length - 1;
  bool segmentMuted(int i) => stages[i + 1].muted;

  static Offset _raw(double x, double y, double z, double cx, double cy) {
    final depth = -(y - cy) * sin(tilt) - z * cos(tilt);
    final f = perspective / (perspective + depth);
    return Offset((x - cx) * f, ((y - cy) * cos(tilt) - z * sin(tilt)) * f);
  }

  double depthScale(double y, double z) {
    final depth = -(y - cy) * sin(tilt) - z * cos(tilt);
    return perspective / (perspective + depth);
  }

  Offset project(double x, double y, double z) {
    final p = _raw(x, y, z, cx, cy);
    return Offset(p.dx * k + ox, p.dy * k + oy);
  }

  Path polygon(List<Offset> boardPts, double z) =>
      Path()..addPolygon([for (final p in boardPts) project(p.dx, p.dy, z)], true);

  double discDiameter(int i) {
    final nearest = depthScale(centers.map((c) => c.dy).reduce(max), trackH + lift);
    final f = depthScale(centers[i].dy, trackH + lift);
    return (discSize * f / max(f, nearest)).clamp(46.0, discSize);
  }

  double labelWidth(int i) => max(96.0, cellW * k * depthScale(centers[i].dy, 0) - 4);

  /// Screen top (top band, at hover lift) and bottom (labels) of node [i].
  (double, double) nodeExtent(int i) {
    final c = centers[i];
    final r = discDiameter(i) / 2;
    final hover = project(c.dx, c.dy, trackH + liftHover);
    final rest = project(c.dx, c.dy, trackH + lift);
    final top = hover.dy - r - (stages[i].top != null ? 26 : 8);
    final bottom = rest.dy + r + 8 + labelHeights(i, labelWidth(i));
    return (top, bottom);
  }

  bool get _rowsClear {
    for (var row = 0; row < rows - 1; row++) {
      var bottom = -double.infinity, top = double.infinity;
      for (var i = 0; i < centers.length; i++) {
        final (t, b) = nodeExtent(i);
        if (i ~/ perRow == row) bottom = max(bottom, b);
        if (i ~/ perRow == row + 1) top = min(top, t);
      }
      if (top - bottom < 10) return false;
    }
    return true;
  }

  static _B3Camera? solve(List<Board3dStage> stages, double width,
      {required double minCellPx, required int maxPerRow, required TextScaler scaler}) {
    // Label heights depend only on the label width; measure each once per width.
    final cache = <(int, int), double>{};
    double labelHeight(int i, double w) => cache.putIfAbsent((i, w.round()), () => _measureLabel(stages[i], w, scaler));

    // As many stages a row as fit — judged on the projected columns, since the
    // far row is foreshortened and the U-turns eat into the width. Past three
    // rows the board runs so deep the perspective falls apart, so then nothing
    // fits and the caller shows its flat fallback.
    for (var want = max(2, min(maxPerRow, stages.length)); want >= 2; want--) {
      final rows = (stages.length / want).ceil();
      if (rows > maxRows) break;
      // Even rows: 9 stages at 7 a row become 5 + 4, not 7 + 2.
      final perRow = (stages.length / rows).ceil();
      for (var gap = 180.0; gap <= 900; gap += 10) {
        final cam = _build(stages, labelHeight, width, perRow, rows, gap);
        if (!cam._rowsClear) continue;
        if (cam.narrowestColumn >= minCellPx) return cam;
        break;
      }
    }
    return null;
  }

  static const int maxRows = 3;

  /// On-screen width of the most foreshortened column.
  double get narrowestColumn => centers.map((c) => cellW * k * depthScale(c.dy, 0)).reduce(min);

  static double _textHeight(String text, TextStyle style, double w, int maxLines, TextScaler scaler) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: maxLines,
      ellipsis: '…',
      textScaler: scaler,
    )..layout(maxWidth: max(1.0, w));
    final h = tp.height;
    tp.dispose();
    return h;
  }

  /// Height of [_Board3dRailState._label] at width [w].
  static double _measureLabel(Board3dStage s, double w, TextScaler scaler) {
    final inner = w - 12;
    var h = 12.0; // vertical padding
    for (final (text, _) in s.pills) {
      h += _textHeight(text, _b3PillStyle, inner - 16, 1, scaler) + 6 + 3;
    }
    h += _textHeight(s.title, _b3TitleStyle, inner, 3, scaler);
    for (final line in s.lines) {
      h += 2 + _textHeight(line, _b3LineStyle, inner, 3, scaler);
    }
    return h + 2;
  }

  static _B3Camera _build(List<Board3dStage> stages, double Function(int, double) labelHeight, double width, int perRow,
      int rows, double gap) {
    final boardW = perRow * cellW;
    final centers = <Offset>[];
    for (var i = 0; i < stages.length; i++) {
      final row = i ~/ perRow;
      final col = i % perRow;
      final x = row.isEven ? cellW * (col + .5) : boardW - cellW * (col + .5);
      centers.add(Offset(x, row * gap));
    }
    // U-turns bulge past the outer column by [turnR] — a fixed amount, so a
    // wider row gap makes the board deeper but never narrower on screen.
    final bulge = rows > 1 ? max(0.0, turnR - cellW / 2 + trackW / 2 + 26) : 0.0;
    final plate = Rect.fromLTRB(-bulge - 6, -64, boardW + bulge + 6, (rows - 1) * gap + 72);
    final cx = plate.center.dx, cy = plate.center.dy;

    final corners = [plate.topLeft, plate.topRight, plate.bottomLeft, plate.bottomRight];
    var minX = double.infinity, maxX = -double.infinity;
    for (final c in corners) {
      for (final z in const [0.0, -plateDepth]) {
        final p = _raw(c.dx, c.dy, z, cx, cy);
        minX = min(minX, p.dx);
        maxX = max(maxX, p.dx);
      }
    }
    final k = (width - 2) / (maxX - minX);
    final ox = 1 - minX * k;

    final probe = _B3Camera._(
        perRow: perRow,
        rows: rows,
        stages: stages,
        labelHeights: labelHeight,
        centers: centers,
        plate: plate,
        cx: cx,
        cy: cy,
        k: k,
        ox: ox,
        oy: 0,
        height: 0);
    var top = double.infinity, bottom = -double.infinity;
    for (final c in corners) {
      top = min(top, probe.project(c.dx, c.dy, 0).dy);
      bottom = max(bottom, probe.project(c.dx, c.dy, -plateDepth).dy + 16);
    }
    for (var i = 0; i < stages.length; i++) {
      final (t, b) = probe.nodeExtent(i);
      top = min(top, t);
      bottom = max(bottom, b);
    }
    return _B3Camera._(
        perRow: perRow,
        rows: rows,
        stages: stages,
        labelHeights: labelHeight,
        centers: centers,
        plate: plate,
        cx: cx,
        cy: cy,
        k: k,
        ox: ox,
        oy: 6 - top,
        height: bottom - top + 12);
  }

  Path segmentPath(int i) {
    final a = centers[i];
    final b = centers[i + 1];
    final path = Path()..moveTo(a.dx, a.dy);
    if ((a.dy - b.dy).abs() < 1) {
      path.lineTo(b.dx, b.dy);
    } else {
      // U-turn: out past the column, down the side, back in — two quarter
      // turns of radius [turnR] joined by a straight run (a stadium end).
      final right = a.dx > boardW / 2;
      final side = right ? 1.0 : -1.0;
      const r = turnR / 2;
      final xo = a.dx + side * turnR;
      path
        ..lineTo(xo - side * r, a.dy)
        ..arcToPoint(Offset(xo, a.dy + r), radius: const Radius.circular(r), clockwise: right)
        ..lineTo(xo, b.dy - r)
        ..arcToPoint(Offset(xo - side * r, b.dy), radius: const Radius.circular(r), clockwise: right)
        ..lineTo(b.dx, b.dy);
    }
    return path;
  }
}

/// The stages on a tilted 3D board with a raised rail between them. Below
/// [minWidth] the board would be too cramped, so [fallback] is shown instead.
class Board3dRail extends StatefulWidget {
  const Board3dRail({
    super.key,
    required this.stages,
    required this.fallback,
    this.minCellPx = 200,
    this.maxPerRow = 4,
    this.minWidth = 480,
  });

  final List<Board3dStage> stages;
  final WidgetBuilder fallback;

  /// Narrowest a column may get on screen; sets how many stages share a row.
  final double minCellPx;
  final int maxPerRow;
  final double minWidth;

  @override
  State<Board3dRail> createState() => _Board3dRailState();
}

class _Board3dRailState extends State<Board3dRail> with TickerProviderStateMixin {
  late final AnimationController _intro =
      AnimationController(vsync: this, duration: Duration(milliseconds: 300 + 150 * widget.stages.length));
  late final AnimationController _flow = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));
  bool _started = false;
  int? _hovered;
  _B3Camera? _cam;
  String _camKey = '';

  List<Board3dStage> get stages => widget.stages;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.of(context).disableAnimations) {
      _intro.value = 1;
    } else {
      _intro.forward();
      _flow.repeat();
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    _flow.dispose();
    super.dispose();
  }

  Color _accent(int i) => stages[i].muted ? _b3Upcoming : stages[i].accent;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      if (width < widget.minWidth || stages.length < 2) return widget.fallback(context);
      final scaler = MediaQuery.textScalerOf(context);
      final key = '$width|${widget.minCellPx}|${widget.maxPerRow}|${scaler.scale(10)}|'
          '${stages.map((s) => s._signature).join('·')}';
      if (_camKey != key) {
        _cam = _B3Camera.solve(stages, width, minCellPx: widget.minCellPx, maxPerRow: widget.maxPerRow, scaler: scaler);
        _camKey = key;
      }
      final cam = _cam;
      if (cam == null) return widget.fallback(context);
      final segmentColors = [for (var i = 1; i < stages.length; i++) _accent(i)];

      return SizedBox(
        width: width,
        height: cam.height,
        child: AnimatedBuilder(
          animation: _intro,
          builder: (context, _) {
            final p = Curves.easeInOutCubic.transform(_intro.value) * (stages.length - .5);
            return Stack(clipBehavior: Clip.none, children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _B3BoardPainter(cam: cam, colors: segmentColors, progress: p),
                  foregroundPainter: _B3ArrowPainter(cam: cam, flow: _flow, progress: p),
                ),
              ),
              for (var i = 0; i < stages.length; i++) ..._buildNode(i, cam, p),
            ]);
          },
        ),
      );
    });
  }

  Widget _label(Board3dStage stage) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        // A soft tag, so the text stays clean over the dot grid and the
        // board's edge line.
        color: Colors.white.withValues(alpha: .86),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        for (final (text, color) in stage.pills)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: _B3Pill(text: text, color: color),
          ),
        Text(stage.title,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: stage.muted ? _b3TitleStyle.copyWith(color: DsColors.faint2) : _b3TitleStyle),
        for (final line in stage.lines) ...[
          const SizedBox(height: 2),
          Text(line,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: stage.muted ? _b3LineStyle.copyWith(color: DsColors.faint2) : _b3LineStyle),
        ],
      ]),
    );
  }

  List<Widget> _buildNode(int index, _B3Camera cam, double progress) {
    final stage = stages[index];
    final accent = _accent(index);
    final reveal = _b3NodeReveal(progress, index);
    final c = cam.centers[index];
    final d = cam.discDiameter(index);
    final labelW = cam.labelWidth(index);
    final rest = cam.project(c.dx, c.dy, _B3Camera.trackH + _B3Camera.lift);
    final lifted = _hovered == index ? cam.project(c.dx, c.dy, _B3Camera.trackH + _B3Camera.liftHover) : rest;
    const liftDuration = Duration(milliseconds: 220);

    return [
      // Top band above the floating disc.
      if (stage.top != null)
        AnimatedPositioned(
          duration: liftDuration,
          curve: Curves.easeOutCubic,
          left: lifted.dx - (labelW + 64) / 2,
          top: lifted.dy - d / 2 - 24,
          width: labelW + 64,
          child: Opacity(
            opacity: reveal,
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .9),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(stage.top!,
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w800, color: stage.muted ? _b3UpcomingIcon : accent)),
                ),
              ),
            ),
          ),
        ),
      // Node disc, floating above the rail.
      AnimatedPositioned(
        duration: liftDuration,
        curve: Curves.easeOutCubic,
        left: lifted.dx - d / 2,
        top: lifted.dy - d / 2,
        child: MouseRegion(
          cursor: stage.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
          onEnter: (_) => setState(() => _hovered = index),
          onExit: (_) {
            if (_hovered == index) setState(() => _hovered = null);
          },
          child: GestureDetector(
            onTap: stage.onTap,
            child: Opacity(
              opacity: reveal,
              child: Transform.scale(
                scale: Curves.easeOutBack.transform(reveal),
                child: Stack(clipBehavior: Clip.none, children: [
                  Container(
                    width: d,
                    height: d,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: accent, width: stage.glow ? 4 : 3.5),
                      boxShadow: [
                        const BoxShadow(color: Color(0x33131c4a), blurRadius: 14, offset: Offset(0, 8)),
                        if (stage.glow)
                          BoxShadow(color: accent.withValues(alpha: .45), blurRadius: 16, spreadRadius: 3),
                      ],
                    ),
                    child: Icon(stage.icon, size: d * .42, color: stage.muted ? _b3UpcomingIcon : accent),
                  ),
                  if (stage.number != null)
                    Positioned(
                      left: -4,
                      top: -4,
                      child: Container(
                        width: 22,
                        height: 22,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: stage.muted ? _b3UpcomingIcon : DsColors.navy,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: Text(stage.number!,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 10.5)),
                      ),
                    ),
                ]),
              ),
            ),
          ),
        ),
      ),
      // Labels below the disc (they stay put while the disc lifts on hover).
      Positioned(
        left: rest.dx - labelW / 2,
        top: rest.dy + d / 2 + 8,
        width: labelW,
        child: Opacity(opacity: reveal, child: _label(stage)),
      ),
    ];
  }
}

class _B3Pill extends StatelessWidget {
  const _B3Pill({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: .45)),
      ),
      child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: _b3PillStyle.copyWith(color: color)),
    );
  }
}

/// The tilted board, the rail (stacked ribbons) and the disc shadows.
class _B3BoardPainter extends CustomPainter {
  _B3BoardPainter({required this.cam, required this.colors, required this.progress});
  final _B3Camera cam;
  final List<Color> colors; // one per segment
  final double progress;

  static List<Offset> _sample(Path path, double step) {
    final pts = <Offset>[];
    for (final m in path.computeMetrics()) {
      for (var s = 0.0; s < m.length; s += step) {
        pts.add(m.getTangentForOffset(s)!.position);
      }
    }
    return pts;
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Board plate: shadow, thickness, top.
    final plateRRect = RRect.fromRectAndRadius(cam.plate, const Radius.circular(30));
    final outline = _sample(Path()..addRRect(plateRRect), 8);
    canvas.drawPath(
      cam.polygon(outline, -_B3Camera.plateDepth).shift(const Offset(0, 12)),
      Paint()
        ..color = const Color(0x26131c4a)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
    );
    canvas.drawPath(cam.polygon(outline, -_B3Camera.plateDepth), Paint()..color = const Color(0xffd9d7ea));
    final top = cam.polygon(outline, 0);
    canvas.drawPath(top, Paint()..color = const Color(0xfff8f8fd));
    canvas.drawPath(
        top,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0xffdedcec));

    // Dot grid printed on the board.
    final dots = <Offset>[];
    for (var y = cam.plate.top + 20; y < cam.plate.bottom - 10; y += 26) {
      for (var x = cam.plate.left + 20; x < cam.plate.right - 10; x += 26) {
        if (plateRRect.contains(Offset(x, y))) dots.add(cam.project(x, y, 0));
      }
    }
    canvas.drawPoints(
        ui.PointMode.points,
        dots,
        Paint()
          ..color = const Color(0xffd3d1e6)
          ..strokeWidth = 2.2 * cam.k
          ..strokeCap = StrokeCap.round);

    // Rail: each segment is a ribbon stacked from the board up to trackH.
    for (var i = 0; i < cam.segmentCount; i++) {
      final reveal = _b3SegReveal(progress, i);
      if (reveal <= 0) continue;
      final metric = cam.segmentPath(i).computeMetrics().first;
      final end = metric.length * reveal;
      final left = <Offset>[], right = <Offset>[];
      for (var s = 0.0;; s = min(end, s + 6)) {
        final t = metric.getTangentForOffset(s)!;
        final n = Offset(-t.vector.dy, t.vector.dx) * (_B3Camera.trackW / 2);
        left.add(t.position + n);
        right.add(t.position - n);
        if (s >= end) break;
      }
      final ribbon = [...left, ...right.reversed];
      final side = Paint()..color = Color.lerp(colors[i], const Color(0xff0b1030), .34)!;
      for (var z = 0.0; z < _B3Camera.trackH; z += 1.75) {
        canvas.drawPath(cam.polygon(ribbon, z), side);
      }
      canvas.drawPath(cam.polygon(ribbon, _B3Camera.trackH), Paint()..color = colors[i]);
    }

    // Soft shadows on the rail under the floating discs.
    final shadow = Paint()
      ..color = const Color(0x38131c4a)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    for (var i = 0; i < cam.centers.length; i++) {
      final reveal = _b3NodeReveal(progress, i);
      if (reveal <= 0) continue;
      final c = cam.centers[i];
      final floor = cam.project(c.dx, c.dy + 8, _B3Camera.trackH);
      final w = 48 * cam.k * cam.depthScale(c.dy, _B3Camera.trackH) * reveal;
      canvas.drawOval(Rect.fromCenter(center: floor, width: w, height: w * cos(_B3Camera.tilt) * .8), shadow);
    }
  }

  @override
  bool shouldRepaint(_B3BoardPainter oldDelegate) =>
      oldDelegate.cam != cam || oldDelegate.progress != progress || oldDelegate.colors != colors;
}

/// Chevrons flowing along the top of the rail in the direction of travel.
class _B3ArrowPainter extends CustomPainter {
  _B3ArrowPainter({required this.cam, required this.flow, required this.progress}) : super(repaint: flow);
  final _B3Camera cam;
  final Animation<double> flow;
  final double progress;

  static const double _spacing = 58;

  @override
  void paint(Canvas canvas, Size size) {
    final shift = flow.value * _spacing;
    const z = _B3Camera.trackH + .3;
    var start = 0.0;
    for (var i = 0; i < cam.segmentCount; i++) {
      final metric = cam.segmentPath(i).computeMetrics().first;
      final len = metric.length;
      final visible = len * _b3SegReveal(progress, i);
      final upcoming = cam.segmentMuted(i);
      for (var s = (shift - start) % _spacing; s < visible; s += _spacing) {
        // Fade out towards the discs so chevrons don't pop at segment joins.
        final fade = (min(s, len - s) / 34).clamp(0.0, 1.0);
        if (fade <= 0) continue;
        final t = metric.getTangentForOffset(s)!;
        final p = t.position, v = t.vector;
        final n = Offset(-v.dy, v.dx);
        final back = p - v * 5;
        final wingL = back + n * 7, tip = p + v * 6, wingR = back - n * 7;
        final a = cam.project(wingL.dx, wingL.dy, z);
        final b = cam.project(tip.dx, tip.dy, z);
        final c = cam.project(wingR.dx, wingR.dy, z);
        canvas.drawPath(
          Path()
            ..moveTo(a.dx, a.dy)
            ..lineTo(b.dx, b.dy)
            ..lineTo(c.dx, c.dy),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.4 * cam.k * cam.depthScale(p.dy, z)
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..color = (upcoming ? _b3UpcomingIcon : Colors.white).withValues(alpha: .9 * fade),
        );
      }
      start += len;
    }
  }

  @override
  bool shouldRepaint(_B3ArrowPainter oldDelegate) => oldDelegate.cam != cam || oldDelegate.progress != progress;
}
