part of '../main.dart';

// ===========================================================================
// Halcyon water — the surface that behaves like water.
//
// The scene's ORIGINAL water is untouched and still complete: the gradient, the
// two wobbling reflection legs, the crest families, the glints and the drawn
// ripple rings all still live in login_halcyon.dart. [HcWater] picks which of
// the two the scene paints, and the pill at the top right of the login page
// flips it. Nothing here deletes anything there.
//
// ── Why the old ripples read as "circles" ─────────────────────────────────
//
// Because they ARE circles: `_ripples()` strokes three concentric ovals per
// splash on top of the water. Real water has no such lines. You see a ripple
// because the surface tilts, and a tilted mirror sends you a DIFFERENT part of
// the sky — the reflection bends, stretches, and tears. That is the whole
// effect, and it is the only thing this file draws.
//
// ── How it works ──────────────────────────────────────────────────────────
//
//  1. A height field on a grid, stepped with the wave equation. Waves spread,
//     interfere, and die on their own; nothing tracks "a ripple" as an object.
//  2. The sky above the waterline is snapshotted into a texture ~11 times a
//     second — the reflection is bent far too hard for anyone to see it step.
//  3. The water is covered with a triangle mesh whose texture coordinates are
//     the mirrored sky, PUSHED SIDEWAYS by the local slope of the height field.
//     A texture coordinate per vertex is a displacement map, so this is real
//     refraction — the same trick [LiquidDrop] uses for the glass theme, and
//     the reason it is available here at all (`ui.ImageFilter.shader` is
//     Impeller-only; this app is CanvasKit).
//  4. The water's own body is painted back OVER that mirror, and its alpha is
//     the Fresnel term: nothing at the waterline, where a grazing angle
//     mirrors almost perfectly, most of the way up close, where you are
//     looking down into the water instead. (It has to be a second pass.
//     Vertices carrying colours and texture coordinates at once draw nothing
//     at all on CanvasKit — see the note in [_HalcyonWater.paint].)
//  5. That same colour carries the light: a facet whose reflection landed on
//     the gate's bloom is looking straight at the light and burns white.
//
// So the light column that breaks into shards across a disturbed surface is
// never drawn as a thing. It is what step 5 does when step 3 scatters the
// direction each facet is looking in.
//
// ── The grid is warped, and that is the perspective ───────────────────────
//
// Rows are not evenly spaced down the screen: row j sits at (j/rows)^1.7 of the
// way from the waterline to the bottom edge, so they crowd toward the horizon
// exactly as a receding plane does. The wave step is isotropic in GRID space,
// which means a splash that is a circle in the grid lands on screen as the
// flattened ellipse perspective demands — with no per-ripple `squash` value
// anywhere. It also means a disturbance of a given screen radius is a circle of
// the same radius in grid units, which is why [_HalcyonWater.disturb] is so
// short.
// ===========================================================================

/// Which water the Halcyon scene paints — the new simulated surface, or the
/// original drawn one. Persisted, like [Lg], because it is a preference about
/// how the machine in front of you copes, not a per-session mood.
class HcWater {
  HcWater._();

  static final ValueNotifier<bool> enabled = ValueNotifier<bool>(true)..addListener(_remember);

  static bool get on => enabled.value;

  static const String _key = 'psa.halcyonWater';

  /// Reads the remembered choice. Call once, before `runApp`.
  static void restore() {
    final saved = html.window.localStorage[_key];
    if (saved == null) return;
    enabled.removeListener(_remember);
    enabled.value = saved == '1';
    enabled.addListener(_remember);
  }

  static void _remember() {
    try {
      html.window.localStorage[_key] = enabled.value ? '1' : '0';
    } catch (_) {
      // Private-mode browsers refuse to write. The choice still works; it just
      // forgets, which is not worth taking the page down for.
    }
  }
}

// --- Tuning ----------------------------------------------------------------
// Everything the surface's look hangs on, in one place. These were set by eye
// against the scene; the comments say which way each one moves.

/// How the rows crowd toward the waterline — this IS the perspective. 1 is a
/// flat plan view (ripples stay circular), 2.2 is a very low camera almost on
/// the surface. Below ~1.3 the far water stops looking like distance.
const double _kWaterRowBias = 1.7;

/// How much of a wave survives each step, at 120 steps a second. .9995 is a
/// mirror-calm pool that rings for half a minute; .995 is gone in a blink.
const double _kWaterDamping = .9986;

/// Wave speed, as the square of cells-per-step. The stencil below is stable up
/// to .5, which is also one cell per step — and one cell per step is far too
/// fast: at 120 steps a second the ring would cross the whole pond in a second
/// and vanish. This is the knob that makes it a pond rather than a puddle.
///
/// .015 works out at about 130 px a second on a 1440-wide window, which is the
/// speed a ring actually travels on water you could stand next to. Anything
/// past ~.05 and the ring is gone before the eye has followed it out.
const double _kWaterSpeed = .015;

/// How far down the sky the reflection reaches at the bottom edge of the
/// screen, as a multiple of the water's own height. 1.0 is the physically
/// honest mirror, which cuts the top off the gate's arch; a little over 1 tilts
/// the imaginary camera down and fits the whole arch into the water.
const double _kWaterMirror = 1.34;

/// Sideways pull, in logical pixels, that a unit of surface slope gives the
/// sampled reflection at the near edge. This is the strength of the whole
/// effect: 0 is a flat mirror, past ~200 the surface tears into ribbons.
///
/// It has to be this large because slope is measured per GRID CELL, and a cell
/// is ~11 px wide: the tallest wave the pond ever carries is a fraction of a
/// unit high, so a small number here reads as a perfect mirror.
const double _kWaterRefract = 68;

/// The standing sea — the surface is never glass, even on a page that has just
/// opened. Height units, where a mouse wake is about .3 and a thrown stone
/// about 3. Past ~.5 the reflection starts to tear on the swell alone.
const double _kWaterSwell = .30;

/// Seconds between sky snapshots. The reflection is distorted enough that this
/// can be far slower than the frame rate; lower it only if the reflected gate
/// visibly steps when the pointer moves. Raise it if the page hitches.
const double _kWaterSkyRefresh = .09;

/// Resolution of that snapshot, relative to the viewport. The reflection is
/// bent, tinted and re-sampled, so half is already generous.
const double _kWaterSkyScale = .45;

/// How hard a facet burns when it is looking straight at the gate's light.
/// Kept low: the gate's glow is already IN the reflected sky, so this only has
/// to add the sharpness the snapshot's own softness loses.
const double _kWaterSpecular = .38;

/// The whole surface's colour, scaled. Below 1 for a deeper, heavier sea.
const double _kWaterDarken = .80;

/// How much brighter than the water around it a lit crest gets. It stays the
/// same HUE — see the note where it is used.
const double _kWaterCrestLift = 2.8;

/// How far that light reaches across the pond, as a fraction of the viewport
/// width. Wide and soft; the shattering comes from the waves, not from this.
const double _kWaterLightSpread = .42;

/// The light is a broad glow sitting ON the waterline, so a facet that samples
/// well to the side is still looking at it while one that samples far above is
/// not. Below 1 the reach is wider across than up.
const double _kWaterLightAspect = .55;

/// Brightness for steepness alone, standing in for the rest of the sky — this
/// is what a ripple crossing the dark corners is seen BY.
const double _kWaterSheen = 2.6;

/// How much slope a facet has to have before it counts as a crest at all.
///
/// This has to sit clear ABOVE the standing sea, not just at it. Set level with
/// it, the sea's own peaks cross the line only where two trains happen to add,
/// and the surface comes out covered in soft white patches — a threshold
/// artefact, not foam. Above it, the ambient sea is carried entirely by the
/// mirror it bends, and the light is kept for things that really are steep: a
/// wake, a splash, the odd steepest crest.
const double _kWaterCrestFloor = .62;

/// The brightest a crest can get from steepness alone. Above the floor the
/// ramp is LINEAR: squaring it looked right in the numbers and wrong on screen,
/// because a steep curve sends neighbouring vertices from nothing to full and
/// the triangles between them show up as flat blocks.
const double _kWaterCrestMax = .45;

/// How deeply the pointer drags through the surface, per pixel it travels.
/// See [_HalcyonWater.wake].
const double _kWaterWake = .022;

/// How hard the pointer holds that trough open, per second, while it is moving.
/// This is the one that reads as the water being CUT rather than tapped, so if
/// the cursor is not parting the surface enough, raise this before [_kWaterWake]
/// — the wake only sheds rings behind, this is what makes the furrow.
const double _kWaterHold = 3.2;

/// Gravity for thrown droplets, logical px/s².
const double _kWaterGravity = 1150;

/// One airborne drop of spray thrown up by a splash.
///
/// It is never DRAWN. It was, as a small white bead, and that is exactly what
/// it looked like: white dots popping out of the water. What it is kept for is
/// where it lands — each one rings the surface again a moment after the impact
/// and a little way off from it, and those second-hand rings are most of what
/// makes a splash read as water rather than as one expanding circle. The whole
/// effect is now carried by the height field alone, with nothing drawn on top.
class _WaterDroplet {
  _WaterDroplet({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.r,
    required this.landY,
  });

  double x;
  double y;
  double vx;
  double vy;
  final double r;

  /// The height of the surface it left, and so the height it comes back to.
  final double landY;
}

/// The height field, its mesh, and everything thrown off it.
///
/// One of these belongs to each [_HalcyonModel]; the scene state pushes pointer
/// events into it and the painter asks it to draw.
class _HalcyonWater {
  // ── grid ────────────────────────────────────────────────────────────────
  // 144 x 80 cells is ~10 px per cell across a 1440-wide window: fine enough
  // that a ripple crest is a curve rather than a staircase, coarse enough that
  // the per-frame vertex work stays around a millisecond. Raising it further
  // sharpens the rings; the ceiling is the 65535 vertices a Uint16 index can
  // reach, which is about 255 x 255.
  static const int _cols = 144;
  static const int _rows = 80;
  static const int _vx = _cols + 1;
  static const int _vy = _rows + 1;
  static const int _n = _vx * _vy;

  // Three height buffers, rotated rather than copied — hence not final.
  Float32List _h = Float32List(_n);
  Float32List _hPrev = Float32List(_n);
  Float32List _hNext = Float32List(_n);

  /// What is actually drawn: the simulation plus the standing swell.
  final Float32List _draw = Float32List(_n);

  /// [_draw], softened by one blur pass. The slopes are read off THIS, not off
  /// [_draw]: a single cell that disagrees with its neighbours throws its two
  /// triangles at a completely different part of the sky, which shows up as a
  /// scatter of hard dashes across the ripple. One blur costs a pass over the
  /// grid and removes them.
  final Float32List _soft = Float32List(_n);

  // Row tables, all indexed by vertex row.
  final Float32List _rowS = Float32List(_vy); // 0 at the waterline, 1 at the bottom
  final Float32List _rowY = Float32List(_vy); // screen y
  final Float32List _rowZ = Float32List(_vy); // a stand-in for distance
  final Float32List _rowW = Float32List(_vy); // z^.6, the wave coordinate

  // Mesh buffers, filled in place every frame so the frame allocates nothing
  // but the Vertices handle itself.
  final Float32List _pos = Float32List(_n * 2);
  final Float32List _uv = Float32List(_n * 2);
  final Int32List _col = Int32List(_n);
  final Uint16List _idx = _buildIndices();

  final List<_WaterDroplet> droplets = [];

  /// The mirror, kept between frames along with the snapshot it was built for.
  ui.ImageShader? _mirror;
  ui.Image? _shaderFor;

  Size _size = Size.zero;
  double _horizon = 0;
  double _waterH = 1;
  double _lastStep = -1;
  double _accum = 0;

  static Uint16List _buildIndices() {
    final idx = Uint16List(_cols * _rows * 6);
    var k = 0;
    for (var j = 0; j < _rows; j++) {
      for (var i = 0; i < _cols; i++) {
        final a = j * _vx + i;
        final b = a + 1;
        final c = a + _vx;
        final d = c + 1;
        idx[k++] = a;
        idx[k++] = b;
        idx[k++] = c;
        idx[k++] = b;
        idx[k++] = d;
        idx[k++] = c;
      }
    }
    return idx;
  }

  bool get ready => !_size.isEmpty;

  /// Rebuilds the row tables and the static half of the mesh. Cheap enough to
  /// call every frame; it returns immediately unless the viewport moved.
  void layout(Size size, double horizon) {
    if (size == _size && horizon == _horizon) return;
    _size = size;
    _horizon = horizon;
    _waterH = max(1.0, size.height - horizon);
    for (var j = 0; j < _vy; j++) {
      final s = pow(j / _rows, _kWaterRowBias).toDouble();
      _rowS[j] = s;
      _rowY[j] = horizon + s * _waterH;
      // Distance falls off hyperbolically with screen depth, so the standing
      // swell computed against it gets finer toward the horizon by itself.
      final z = 1 / (s + .075);
      _rowZ[j] = z;
      // See the note on the sea in [_fill] for why the waves run on z^.6.
      _rowW[j] = pow(z, .6).toDouble();
    }
    for (var j = 0; j < _vy; j++) {
      for (var i = 0; i < _vx; i++) {
        final k = j * _vx + i;
        _pos[k * 2] = i / _cols * size.width;
        _pos[k * 2 + 1] = _rowY[j];
      }
    }
  }

  /// Runs the simulation forward to [time] on a fixed 120 Hz step, so the water
  /// moves at the same speed on a 60 Hz panel and a 144 Hz one.
  void advance(double time) {
    if (_lastStep < 0) {
      _lastStep = time;
      return;
    }
    final dt = (time - _lastStep).clamp(0.0, .05);
    _lastStep = time;
    if (dt <= 0) return;
    _moveDroplets(dt);
    _hold(dt);
    _accum += dt;
    const fixed = 1 / 120;
    var steps = 0;
    while (_accum >= fixed && steps < 4) {
      _accum -= fixed;
      steps++;
      _step();
    }
    // A tab that was in the background comes back with a huge backlog; drop it
    // rather than spending a second of frames catching up.
    if (_accum > .25) _accum = 0;
  }

  void _step() {
    final h = _h;
    final p = _hPrev;
    final n = _hNext;
    for (var j = 1; j < _vy - 1; j++) {
      final row = j * _vx;
      for (var i = 1; i < _vx - 1; i++) {
        final k = row + i;
        final hk = h[k];
        final lap = h[k - 1] + h[k + 1] + h[k - _vx] + h[k + _vx] - 4 * hk;
        n[k] = (2 * hk - p[k] + _kWaterSpeed * lap) * _kWaterDamping;
      }
    }
    _openEdges(h, n);
    final spare = _hPrev;
    _hPrev = _h;
    _h = _hNext;
    _hNext = spare;
  }

  /// Lets waves leave.
  ///
  /// The grid stops at the edge of the screen, but the sea does not, so a wave
  /// that reaches the edge has to keep going and simply stop being drawn. The
  /// first thing tried here — extra damping in a margin — does NOT do that. A
  /// damped band is an impedance step, and an impedance step reflects: the
  /// swell visibly turned around a few centimetres short of the left and right
  /// edges and came back in.
  ///
  /// This is Mur's first-order absorbing condition instead, which is the exact
  /// solution for a wave crossing the boundary head-on: it predicts the edge
  /// cell from where the wave inside it has just got to. Oblique waves leak a
  /// little, which is invisible next to a wall.
  void _openEdges(Float32List h, Float32List n) {
    final mur = _mur;
    final last = _vx - 1;
    final bottom = _vy - 1;
    for (var j = 0; j < _vy; j++) {
      final row = j * _vx;
      n[row] = h[row + 1] + mur * (n[row + 1] - h[row]);
      n[row + last] = h[row + last - 1] + mur * (n[row + last - 1] - h[row + last]);
    }
    final penult = (bottom - 1) * _vx;
    final edge = bottom * _vx;
    for (var i = 0; i < _vx; i++) {
      n[i] = h[_vx + i] + mur * (n[_vx + i] - h[i]);
      n[edge + i] = h[penult + i] + mur * (n[penult + i] - h[edge + i]);
    }
  }

  /// (c·dt − dx) / (c·dt + dx) for [_openEdges], where c·dt/dx is the Courant
  /// number the solver runs at. Derived rather than written down, so it cannot
  /// drift out of step with [_kWaterSpeed].
  static final double _mur = (sqrt(_kWaterSpeed) - 1) / (sqrt(_kWaterSpeed) + 1);

  void _moveDroplets(double dt) {
    for (var i = droplets.length - 1; i >= 0; i--) {
      final d = droplets[i];
      d.vy += _kWaterGravity * dt;
      d.x += d.vx * dt;
      d.y += d.vy * dt;
      if (d.vy > 0 && d.y >= d.landY) {
        droplets.removeAt(i);
        disturb(Offset(d.x, d.landY), -.30 * d.r, 10 + d.r * 4);
      }
    }
  }

  /// Pushes the surface at a point on screen. Positive lifts, negative dents.
  ///
  /// [radius] is in logical pixels, and needs no perspective correction: the
  /// grid is already warped, so a circle in grid space IS the right ellipse on
  /// screen, and screen radius converts to grid radius with one scale factor.
  ///
  /// [settled] is the difference between a dent and a shove, and it matters:
  /// the solver reads velocity as the gap between the two height buffers.
  ///  * `true` displaces both, leaving the water still — it collapses at once
  ///    and radiates rings, which is what a stone does.
  ///  * `false` displaces only the current one, which IS a downward velocity.
  ///    The dent persists and keeps being pressed. That is what an object held
  ///    in the water does, and it is why the cursor leaves a trough rather than
  ///    a string of rings.
  void disturb(Offset local, double amount, double radius, {bool settled = true}) {
    if (!ready) return;
    final gi = local.dx / _size.width * _cols;
    final s = ((local.dy - _horizon) / _waterH).clamp(0.0, 1.0);
    final gj = pow(s, 1 / _kWaterRowBias).toDouble() * _rows;
    final r = max(1.3, radius * _cols / _size.width);
    final i0 = max(1, (gi - r).floor());
    final i1 = min(_vx - 2, (gi + r).ceil());
    final j0 = max(1, (gj - r).floor());
    final j1 = min(_vy - 2, (gj + r).ceil());
    for (var j = j0; j <= j1; j++) {
      final dj = j - gj;
      for (var i = i0; i <= i1; i++) {
        final di = i - gi;
        final d = sqrt(di * di + dj * dj) / r;
        if (d >= 1) continue;
        // A cosine bell, so the dent has no corner for the solver to ring on.
        final push = amount * (cos(d * pi) + 1) * .5;
        final k = j * _vx + i;
        _h[k] += push;
        if (settled) _hPrev[k] += push;
      }
    }
  }

  /// The pointer dragging across the surface. [from] .. [to] is the segment it
  /// covered since the last event, seeded along its length so a flicked mouse
  /// leaves a continuous wake instead of a row of separate rings.
  ///
  /// Deliberately keyed to DISTANCE and not to speed. Speed needs a clock, and
  /// the only clock here is the frame — but pointer events arrive faster than
  /// frames, so every event after the first in a frame measures dt = 0 and, on
  /// a machine drawing 20 fps, most of the mouse's travel silently deposits
  /// nothing. Water pushed aside goes with the path, not with the hurry.
  void wake(Offset from, Offset to) {
    if (!ready) return;
    final travel = (to - from).distance;
    if (travel < .5) return;
    // Sized so that about a second of ordinary mouse movement puts in as much
    // as one thrown stone — the energy goes in per pixel travelled, and a hover
    // event arrives every frame or two. Turn [_kWaterWake] up for a heavier
    // hand through the water, down for a lighter one; it is the only knob this
    // needs.
    final push = min(.45, travel * _kWaterWake + .012);
    final steps = travel <= 14 ? 1 : min(6, (travel / 14).ceil());
    for (var i = 1; i <= steps; i++) {
      final p = Offset.lerp(from, to, i / steps)!;
      if (p.dy <= _horizon) continue;
      // Deeper toward the horizon, where the surface is so foreshortened that
      // the same wave moves the reflection a fraction as far.
      final depth = (p.dy - _horizon) / _waterH;
      disturb(p, -push / steps * (1.55 - .55 * depth), 34);
    }
    // And hand the trough its position. See [_hold].
    if (to.dy > _horizon) {
      _holdAt = to;
      _holdLife = .13;
    }
  }

  /// The dent the pointer holds open while it is moving through the water, and
  /// how long it has left to live.
  ///
  /// The rings [wake] sheds are the wake BEHIND the cursor; this is the parting
  /// underneath it. Without it the surface reads as being tapped along a line
  /// rather than cut, because a settled displacement collapses the instant it
  /// is made and never travels with anything.
  ///
  /// It expires shortly after the pointer stops. That is not only so a parked
  /// cursor does not slowly bore a crater — a cursor that has stopped moving is
  /// not pushing any water aside, so there is nothing left to hold the dent
  /// open.
  Offset? _holdAt;
  double _holdLife = 0;

  void _hold(double dt) {
    final at = _holdAt;
    if (at == null || _holdLife <= 0) return;
    _holdLife -= dt;
    if (_holdLife <= 0) {
      _holdAt = null;
      return;
    }
    final depth = ((at.dy - _horizon) / _waterH).clamp(0.0, 1.0);
    disturb(at, -_kWaterHold * dt * (1.55 - .55 * depth), 34, settled: false);
  }

  /// A stone in the pond: the dent, and the spray thrown up around the rim.
  ///
  /// Nothing is drawn. The whole thing is height — the crater, the rings it
  /// sheds, and the second-hand rings the spray makes coming back down.
  void splash(Offset local, double time) {
    if (!ready) return;
    disturb(local, -3.2, 46);
    // A narrow, deeper core inside the wide dent — the rebound off it is what
    // sends the second, faster ring out behind the first.
    disturb(local, -1.6, 20);
    final s = ((local.dy - _horizon) / _waterH).clamp(0.0, 1.0);
    // Droplets are thrown in screen pixels, so the far ones have to be smaller
    // and slower or they read as boulders landing in the distance.
    final scale = .35 + s * .65;
    final count = 7 + (_halcyonRnd(time.toInt() * 7, 71) * 6).round();
    for (var i = 0; i < count; i++) {
      final a = _halcyonRnd(i, (time * 60).toInt() % 997);
      final b = _halcyonRnd(i, 81);
      final dir = a < .5 ? -1.0 : 1.0;
      droplets.add(_WaterDroplet(
        x: local.dx + dir * b * 14 * scale,
        y: local.dy,
        vx: dir * (40 + b * 190) * scale,
        vy: -(190 + a * 260) * scale,
        r: (1.1 + b * 1.7) * scale,
        landY: local.dy + b * 6,
      ));
    }
    if (droplets.length > 90) droplets.removeRange(0, droplets.length - 90);
  }

  /// Everything below the waterline. The caller has already laid down the base
  /// gradient and clipped to the water rect.
  void paint(Canvas canvas, Size size, double horizon, double cx, double t, ui.Image? sky, double bloomScale) {
    layout(size, horizon);
    advance(t);
    if (sky == null) return;

    _fill(t, cx);

    // ── Two passes, and it has to be two ──────────────────────────────────
    // The obvious single pass — texture coordinates AND vertex colours, blended
    // with modulate — draws NOTHING on CanvasKit. Not dimmed, not mis-blended:
    // nothing at all. Vertices carrying both at once are silently dropped, and
    // this was checked by drawing the same mesh four ways side by side. So the
    // mirror goes down first at full strength, and the water's own body is
    // painted back over it with the Fresnel fade as its alpha, which is the
    // same lerp the modulate would have been.
    // The shader outlives the frame — the snapshot behind it only changes a
    // dozen times a second, and building one per frame is pure waste.
    if (!identical(sky, _shaderFor)) {
      _mirror = ui.ImageShader(
        sky,
        TileMode.clamp,
        TileMode.clamp,
        Matrix4.diagonal3Values(1 / _kWaterSkyScale, 1 / _kWaterSkyScale, 1).storage,
        filterQuality: FilterQuality.medium,
      );
      _shaderFor = sky;
    }
    final mesh = ui.Vertices.raw(VertexMode.triangles, _pos, textureCoordinates: _uv, indices: _idx);
    canvas.drawVertices(
      mesh,
      BlendMode.srcOver,
      Paint()
        ..filterQuality = FilterQuality.medium
        ..shader = _mirror,
    );
    final tint = ui.Vertices.raw(VertexMode.triangles, _pos, colors: _col, indices: _idx);
    canvas.drawVertices(tint, BlendMode.srcOver, Paint());
    // Both meshes are rebuilt from scratch next frame, and each one is a
    // quarter of a megabyte of engine-side memory. Handing them back now keeps
    // the water off the garbage collector's list entirely; the display list has
    // taken its own reference by this point.
    mesh.dispose();
    tint.dispose();

    _subsurface(canvas, size, horizon, cx, t, bloomScale);
  }

  /// The light of the gate carried INSIDE the water rather than off it — the
  /// near half of the surface is only a partial mirror, and what it does not
  /// reflect it lets through.
  void _subsurface(Canvas canvas, Size size, double horizon, double cx, double t, double bloomScale) {
    final rx = size.width * .30;
    final ry = _waterH * .82;
    canvas.save();
    canvas.translate(cx + sin(t * .4) * 6, horizon);
    canvas.scale(1, ry / rx);
    canvas.drawCircle(
      Offset.zero,
      rx,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.radial(
          Offset.zero,
          rx,
          [
            _HcPalette.bloomMid.withValues(alpha: .07 * bloomScale),
            _HcPalette.bloomMid.withValues(alpha: .035 * bloomScale),
            _HcPalette.bloomMid.withValues(alpha: 0),
          ],
          const [0, .45, 1],
        ),
    );
    canvas.restore();
  }

  /// Fills the per-frame half of the mesh: heights, then the slope-driven
  /// texture coordinates and colours read off them.
  void _fill(double t, double lightX) {
    final h = _h;
    final draw = _draw;

    // -- heights: simulation + the standing sea ----------------------------
    // Open water, not a pond: five trains at different headings and scales.
    // Nothing here is ever still, and none of it is drawn — it is height, so it
    // reaches the screen the same way a splash does, through the mirror.
    //
    // The two SWELLS depend only on distance, so their crests run straight
    // across the view and roll in toward the viewer. That is the motion the eye
    // reads as sea. The three CHOP terms cross them at an angle and break the
    // corrugation up.
    //
    // The wave coordinate is z^.6, NOT z. On a true ground plane the distance
    // to the far side of the view is fifteen times the distance to the near
    // edge, so a wave train with one wavelength runs sixty crests across the
    // horizon and less than one across the foreground — which is exactly what
    // the first attempt looked like: fine texture at the waterline and dead
    // flat glass everywhere near. Compressing the range to about five gives
    // both ends waves you can see, and costs only that a pedant with a ruler
    // could catch the wavelength growing slightly too slowly with distance.
    //
    // The chop is still faded out with distance, and not for looks: up near the
    // horizon its wavelength falls below a grid cell, where it would alias into
    // a crawling shimmer instead of water.
    for (var j = 0; j < _vy; j++) {
      final zw = _rowW[j];
      final s = _rowS[j];
      final row = j * _vx;
      // Rolling in. The slow beat between the two keeps a set from arriving on
      // an obvious count.
      final roll = sin(zw * 26.0 - t * 1.00) * .80 + sin(zw * 11.5 - t * 1.57) * .55;
      // Amplitude falls as 1/zw, which is not a fade — it is a correction. What
      // reaches the screen is SLOPE, and a train of fixed height has five times
      // the slope per grid cell out at the horizon as it does underfoot, so
      // equal amplitudes give a horizon that fizzes over a foreground of glass.
      // Dividing it out gives every distance the same texture, which is what
      // the perspective scale in the loop below then puts back into
      // perspective.
      final ampA = .90 / zw;
      final ampB = 1.55 / zw;
      // The finest train is cut off with distance as well, since its wavelength
      // there falls below a grid cell and it would alias into a crawl.
      final ampC = .85 / zw * s;

      // Each chop term is a sine of an angle that steps by a FIXED amount from
      // one vertex to the next along the row, so it can be advanced by rotating
      // a unit vector instead of calling sin() 40,000 times a frame. Over 145
      // steps a double-precision rotation drifts by about 1e-13.
      final x0 = -.5 * zw;
      final dx = zw / _cols;
      var sa = sin(12.0 * x0 - t * 1.25), ca = cos(12.0 * x0 - t * 1.25);
      final sda = sin(12.0 * dx), cda = cos(12.0 * dx);
      var sb = sin(25.0 * x0 + t * 1.05), cb = cos(25.0 * x0 + t * 1.05);
      final sdb = sin(25.0 * dx), cdb = cos(25.0 * dx);
      var sc = sin(52.0 * x0 - t * 2.40), cc = cos(52.0 * x0 - t * 2.40);
      final sdc = sin(52.0 * dx), cdc = cos(52.0 * dx);

      for (var i = 0; i < _vx; i++) {
        draw[row + i] =
            h[row + i] + (sa * ampA + sb * ampB + sc * ampC + roll) * _kWaterSwell;
        var next = sa * cda + ca * sda;
        ca = ca * cda - sa * sda;
        sa = next;
        next = sb * cdb + cb * sdb;
        cb = cb * cdb - sb * sdb;
        sb = next;
        next = sc * cdc + cc * sdc;
        cc = cc * cdc - sc * sdc;
        sc = next;
      }
    }

    // -- soften ------------------------------------------------------------
    final soft = _soft;
    for (var j = 0; j < _vy; j++) {
      final row = j * _vx;
      final up = j > 0 ? row - _vx : row;
      final down = j < _vy - 1 ? row + _vx : row;
      for (var i = 0; i < _vx; i++) {
        final k = row + i;
        final l = i > 0 ? k - 1 : k;
        final r = i < _vx - 1 ? k + 1 : k;
        soft[k] = draw[k] * .52 + (draw[l] + draw[r] + draw[up + i] + draw[down + i]) * .12;
      }
    }

    // -- slopes, texture coordinates, colour -------------------------------
    final pos = _pos;
    final lightR = _size.width * _kWaterLightSpread;
    final uv = _uv;
    final col = _col;
    for (var j = 0; j < _vy; j++) {
      final row = j * _vx;
      final s = _rowS[j];
      // How many screen pixels a unit of slope is worth here. Almost nothing at
      // the horizon, where the whole surface is edge-on.
      final scale = _kWaterRefract * (.10 + .90 * s);
      // Grazing angles mirror; steep ones let the water's own colour through.
      // This is the alpha of the BODY laid back over the mirror, so it runs the
      // other way: nothing at the waterline, most of the way up close.
      final base = .44 + .56 * pow(1 - s, 1.35).toDouble();
      final body = _bodyAt(s);
      final br = body.r * _kWaterDarken;
      final bg = body.g * _kWaterDarken;
      final bb = body.b * _kWaterDarken;
      // What a lit crest turns into: the water's own colour, lifted. NOT a
      // white one. Lighting toward white is what a foam cap does, and this
      // water does not break — a crest catching the gate's glow on a violet sea
      // is a brighter violet, and pulling it toward white put grey smears
      // across the surface and a white streak behind the cursor.
      final lr = min(1.0, br * _kWaterCrestLift);
      final lg = min(1.0, bg * _kWaterCrestLift);
      final lb = min(1.0, bb * _kWaterCrestLift);
      final mirrorY = _horizon - (_rowY[j] - _horizon) * _kWaterMirror;
      final up = j > 0 ? row - _vx : row;
      final down = j < _vy - 1 ? row + _vx : row;
      for (var i = 0; i < _vx; i++) {
        final k = row + i;
        final l = i > 0 ? k - 1 : k;
        final r = i < _vx - 1 ? k + 1 : k;
        final dx = (soft[r] - soft[l]) * .5;
        final dy = (soft[down + i] - soft[up + i]) * .5;

        uv[k * 2] = pos[k * 2] + dx * scale;
        // Vertically the surface is seen almost edge-on, so the same slope
        // moves the sampled row much further than it moves the column — this
        // is what stretches the reflection into ribbons instead of wobbling
        // it side to side.
        uv[k * 2 + 1] = mirrorY - dy * scale * 1.5;

        // The wave also lifts the vertex itself. Only worth seeing in the
        // foreground, where a crest is several pixels tall.
        pos[k * 2 + 1] = _rowY[j] - soft[k] * 9 * s * s;

        // A face tilted toward the viewer shows less sky and more water. Kept
        // gentle: pushed any harder, a dent stops reading as a dent and starts
        // reading as a hole punched in the water.
        var mirror = base * (1 - (dy * .55).clamp(-.14, .22));
        if (mirror < 0) mirror = 0;
        if (mirror > 1) mirror = 1;

        // Specular. On a night sky the mirror alone cannot show a ripple: the
        // sky it samples is the same near-black either side of the crest, so a
        // wave away from the gate would be invisible. What makes a real ripple
        // visible on dark water is the light it catches — so ask where this
        // facet is actually looking. If its sample landed near the gate's
        // bloom, it is looking straight at the light and burns; the bloom is at
        // (lightX, horizon) in the sky's own coordinates, which is exactly the
        // space the texture coordinates are already in. The light column
        // shattering into shards across a disturbed surface is this term, and
        // it needs no code of its own.
        final du = (uv[k * 2] - lightX) * _kWaterLightAspect;
        final dv = uv[k * 2 + 1] - _horizon;
        var toLight = 1 - sqrt(du * du + dv * dv) / lightR;
        if (toLight < 0) toLight = 0;
        // Cubed, then squared: a soft falloff lights the whole middle of the
        // pond evenly and the shattering is lost.
        toLight = toLight * toLight * toLight * _kWaterSpecular;
        toLight *= toLight;

        // And the crest itself. This is the term that carries a ripple crossing
        // the dark corners, where there is no light to catch — so it has to be
        // strong. What keeps it from washing the calm water out is the FLOOR,
        // not the strength: the standing swell tops out around .3 of slope, so
        // anything under that is thrown away and only a real wave clears it.
        var crest = ((dx.abs() + dy.abs()) * _kWaterSheen - _kWaterCrestFloor) * .9;
        if (crest < 0) {
          crest = 0;
        } else if (crest > _kWaterCrestMax) {
          crest = _kWaterCrestMax;
        }

        final lit = min(1.0, toLight + crest);
        final a = (1 - mirror) + lit * .70;
        col[k] = ((((a < 0 ? 0 : (a > 1 ? 1 : a)) * 255).round() & 0xff) << 24) |
            ((((br + (lr - br) * lit) * 255).round() & 0xff) << 16) |
            ((((bg + (lg - bg) * lit) * 255).round() & 0xff) << 8) |
            (((bb + (lb - bb) * lit) * 255).round() & 0xff);
      }
    }
  }

  /// The water's own colour at screen depth [s] — the same four stops the base
  /// gradient uses, so the body painted back over the mirror matches what is
  /// underneath it.
  Color _bodyAt(double s) {
    if (s < .28) return Color.lerp(_HcPalette.water0, _HcPalette.water1, s / .28)!;
    if (s < .68) return Color.lerp(_HcPalette.water1, _HcPalette.water2, (s - .28) / .40)!;
    return Color.lerp(_HcPalette.water2, _HcPalette.water3, (s - .68) / .32)!;
  }

}

// ---------------------------------------------------------------------------
// The switch
// ---------------------------------------------------------------------------

/// The pill at the top right of the login page: simulated water, or the drawn
/// one the page shipped with. Sits in the scene's palette so it reads as part
/// of the page rather than as a debug control.
class HalcyonWaterToggle extends StatefulWidget {
  const HalcyonWaterToggle({super.key});

  @override
  State<HalcyonWaterToggle> createState() => _HalcyonWaterToggleState();
}

class _HalcyonWaterToggleState extends State<HalcyonWaterToggle> {
  bool hover = false;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: HcWater.enabled,
      builder: (context, on, _) {
        return Tooltip(
          message: on
              ? 'Realistic water: the surface is simulated and mirrors the sky.\nClick to go back to the original drawn ripples.'
              : 'Classic water: the original drawn ripples.\nClick for the simulated surface.',
          waitDuration: const Duration(milliseconds: 300),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => hover = true),
            onExit: (_) => setState(() => hover = false),
            child: GestureDetector(
              // The scene is listening for taps underneath this, and a click on
              // the switch should not also throw a stone in the pond.
              behavior: HitTestBehavior.opaque,
              onTap: () => HcWater.enabled.value = !on,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: hover ? .14 : .07),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withValues(alpha: hover ? .32 : .16)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(
                    on ? Icons.waves : Icons.blur_circular_outlined,
                    size: 15,
                    color: on ? _HcPalette.inputFocus : Colors.white.withValues(alpha: .70),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    on ? 'Realistic water' : 'Classic water',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: .2,
                      color: Colors.white.withValues(alpha: .86),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }
}
