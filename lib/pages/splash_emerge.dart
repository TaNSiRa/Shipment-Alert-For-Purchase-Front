part of '../main.dart';

// ===========================================================================
// Splash — the lockup rises out of the Halcyon water.
//
// Ported from RAP, so PSA opens the same way. The shell (app_shell.dart) shows
// it while a refresh restores the session and again between sign-in and the
// app. [kSplashWaterEmerge] below turns it off: the shell then shows its plain
// spinner on boot and goes straight on after sign-in.
//
// ── What it does ──────────────────────────────────────────────────────────
//
// The scene's water (login_water.dart) is a real surface: a height field that
// anything can push. So the two marks are not animated ON the water, they are
// animated THROUGH it, and every disturbance in the sequence is handed to the
// solver, which answers with its own rings:
//
//  1. A swell runs ahead of each mark — the surface domes up before anything
//     breaks it (`disturb` with settled:false, i.e. a velocity, so it keeps
//     building rather than collapsing at once).
//  2. It breaches: one settled displacement, which collapses immediately and
//     radiates the ring you see running outward.
//  3. While the mark is still crossing the line, the surface is held open
//     around it — the same trick [_HalcyonWater._hold] uses for the cursor.
//  4. Water comes with it. A veil hangs from the bottom edge back to the
//     surface and thins until it breaks, a film drains down the face, and
//     beads gather along the bottom edge.
//  5. Each bead hangs, necks, and falls under gravity. Where it lands is a
//     real `disturb` at the point of impact, so the ripple it makes is the
//     solver's, not a drawn circle.
//
// The wordmark and the loader are held back until the marks are out and still
// (the user asked for this explicitly): nothing textual is on screen before
// ~940 ms, so the whole first act reads as one physical event.
//
// ── Why so much of it is arithmetic and so little is state ────────────────
//
// Every drip's whole life — when it forms, when it lets go, when it lands — is
// decided once, in [_seedDrips]. The painter is then a pure function of the
// clock, and the only thing the ticker does per frame is hand the solver the
// pushes whose time has come. That is also what makes the impact ripples land
// on the frame they should: the landing time is solved from the fall, not
// discovered by watching a y coordinate cross a line.
// ===========================================================================

/// Whether the splash runs at all.
///
/// `true` — the marks rise out of the water (this file).
/// `false` — no splash: a plain spinner while booting, nothing after sign-in.
const bool kSplashWaterEmerge = true;

// --- Tuning ---------------------------------------------------------------

/// The storyboard, in milliseconds. The splash is held for 1.5 s (see
/// `_holdSplash` in app_shell.dart), so everything lands
/// inside that; if loading runs longer the scene simply holds its last frame
/// with the loader still bouncing.
const double _kEmergeBreachL = 120; // the left mark breaks the surface
const double _kEmergeBreachR = 195; // the right one follows, never together
const double _kEmergeRise = 700; // how long the lift out of the water takes
const double _kEmergeTitle = 940; // nothing textual exists before this
const double _kEmergeSub = 1060;
const double _kEmergeLoader = 1190;

/// How long the clock runs. Longer than the splash is held: see [_run].
const int _kEmergeRun = 2600;

/// Gravity for the drips, in logical pixels per second squared. Real gravity
/// (~9800 px/s² at 100 px per metre) makes a 200 px fall take 0.2 s, which at
/// this scale reads as a twitch; this is the value at which a drop falls the
/// height of the lockup in about the time the eye wants it to.
const double _kEmergeGravity = 1500;

/// How hard the marks push the water. Same units as [_kWaterHold] — the
/// surface only ever hears about them through [_HalcyonWater.disturb].
const double _kEmergeSwell = 5.0; // the dome that runs ahead of the breach
const double _kEmergeBreak = 2.4; // the one-shot displacement at the breach
const double _kEmergeHold = 4.2; // per second, while the mark still crosses
const double _kEmergeDrip = 1.35; // one drip landing

/// How dark a drop is.
///
/// The part of the scene a drip refracts is the brightest part of it — the
/// drips fall straight through the horizon bloom — so honest refraction alone
/// comes out as pale pink beads, which is what the user saw. This multiplies
/// the whole body down toward the night colour, hue kept: 0 lets the scene
/// through as it comes, 1 is near-black glass with only its rim and specular
/// left to read.
const double _kEmergeDropDark = .62;

/// Whether water stays ON a mark after it is out: the film that drains down
/// the face, its rivulets, and the beads that never let go.
///
/// The user asked for a dry mark on 2026-08-24 — the marks come out clean and
/// only the falling drips are left. Set true to put the wet face back; nothing
/// else has to change.
const bool _kEmergeWetFace = false;

/// Alpha of that film, when it is on. Past ~.35 it stops looking like water on
/// a white card and starts looking like a coloured card.
const double _kEmergeFilm = .17;

// ---------------------------------------------------------------------------
// Geometry
// ---------------------------------------------------------------------------

/// Everything the sequence measures, derived once per layout.
///
/// The lockup is placed against the WATERLINE rather than centred in the
/// screen: it has to stand clear of the surface it just came out of, and the
/// wordmark underneath it has to stay above the line, where the backdrop is
/// still sky. Centring it would put the loader in the middle of the water.
class _EmergeGeom {
  _EmergeGeom(this.size)
      : waterY = size.height * _kHalcyonHorizon,
        tile = (size.height * .115).clamp(58.0, 88.0);

  final Size size;

  /// Where the water starts — the scene's own horizon, not a guess.
  final double waterY;

  /// Side of one square logo tile.
  final double tile;

  double get cx => size.width / 2;

  /// The gap between the two tiles carries the `×`; 2.66 tiles wide overall is
  /// the original lockup's proportion at its original 84 px tile.
  double get lockW => tile * 2.66;

  /// Where the tiles come to rest: high enough that the wordmark below them
  /// still sits over sky.
  double get restTop => waterY - size.height * .18 - tile;

  /// Fully under: the tile starts far enough below the line that its top edge
  /// is submerged too, so the breach is the first thing you see of it.
  double get riseFrom => waterY + tile * .85;

  double xOf(bool left) => left ? cx - lockW / 2 : cx + lockW / 2 - tile;

  double centreOf(bool left) => xOf(left) + tile / 2;

  /// Where a drip from this lockup meets the water. Not the horizon itself:
  /// the lockup is standing a little in FRONT of the far edge of the pond, and
  /// a ripple exactly on the horizon is foreshortened into nothing.
  double get dripLandY => waterY + (size.height - waterY) * .12;

  /// The rise. Ease-out for the lift, then a short damped bob — water lets go
  /// of something with a small overshoot, and a lift that simply stops looks
  /// like it was moved by a script.
  double topAt(double t, bool left) {
    final start = left ? _kEmergeBreachL : _kEmergeBreachR;
    if (t <= start) return riseFrom;
    final u = ((t - start) / _kEmergeRise).clamp(0.0, 1.0);
    // Ease IN as well as out. An ease-out alone is fastest at the instant it
    // breaks the surface, which is the one moment worth watching — the water
    // has to let go of it before it can come up.
    final e = Curves.easeInOutCubic.transform(u);
    var y = riseFrom + (restTop - riseFrom) * e;
    if (u >= 1) {
      final s = (t - start - _kEmergeRise) / 1000;
      y += sin(s * 26) * 3.2 * exp(-s * 6);
    }
    return y;
  }
}

/// One bead of water: it gathers on the bottom edge, hangs, necks, lets go,
/// falls, and rings the surface where it lands. Every time in it is decided
/// before the sequence starts — see the note at the top of the file.
class _EmergeDrip {
  _EmergeDrip({
    required this.x,
    required this.fromY,
    required this.r,
    required this.formAt,
    required this.detachAt,
    required this.landY,
    required this.cling,
  });

  /// Where it hangs, and the edge it hangs from.
  final double x;
  final double fromY;
  final double r;

  final double formAt;
  final double detachAt;

  /// Where the fall ends — the water, and the ripple.
  final double landY;

  /// A bead that never lets go: the two or three that are still sitting on the
  /// bottom edge when the sequence ends are what keeps the mark looking wet
  /// rather than dried.
  final bool cling;

  /// Solved from the fall, not watched for. `null` for a clinging bead.
  double get landAt =>
      detachAt + sqrt(max(0.0, 2 * (landY - fromY - r * .6) / _kEmergeGravity)) * 1000;

  bool fired = false;
}

// ---------------------------------------------------------------------------
// The splash
// ---------------------------------------------------------------------------

/// Branded splash whose lockup comes up out of the scene's water.
///
/// It owns the scene itself, because the sequence has to reach the water's solver and
/// only a child of [HalcyonScene] can (see [_HalcyonSceneScope]).
class WaterEmergeSplash extends StatelessWidget {
  const WaterEmergeSplash({super.key, this.freezeAt});

  /// Stops the sequence on the given millisecond of the storyboard and holds
  /// it there. For headless captures (RAP's lib/dev/splash_emerge_preview.dart):
  /// a capture cannot ask a running widget what frame it is on, so it asks
  /// for the frame instead. The water still receives every push up to that point,
  /// so a frozen frame shows the rings it should.
  final double? freezeAt;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Same bloom as the original splash: the wordmark lands where the
      // horizon glow is brightest, and at full strength white text there
      // scores about 1:1 against the backdrop.
      body: HalcyonScene(bloom: .62, child: _EmergeStage(freezeAt: freezeAt)),
    );
  }
}

class _EmergeStage extends StatefulWidget {
  const _EmergeStage({this.freezeAt});

  final double? freezeAt;

  @override
  State<_EmergeStage> createState() => _EmergeStageState();
}

class _EmergeStageState extends State<_EmergeStage> with TickerProviderStateMixin {
  /// Runs past the 1.5 s the splash is held for. The storyboard is over well
  /// before that, but the last drips are still in the air at 1500 ms — and if
  /// the clock stopped there they would hang in mid-fall for as long as the
  /// loading took, and never ring the water.
  late final AnimationController _run =
      AnimationController(vsync: this, duration: const Duration(milliseconds: _kEmergeRun));

  /// The loader keeps its own clock: the sequence finishes, the wait may not.
  late final AnimationController _dots =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1150))..repeat();

  static const _dotColors = [Colors.white, Color(0xff5b8cff), Color(0xff34d17b)];

  _HalcyonModel? _scene;
  _EmergeGeom? _geom;
  final List<_EmergeDrip> _drips = [];
  final Set<bool> _broke = {};
  double _lastT = 0;
  bool _frozen = false;

  /// The lens every drop looks through: the scene's sky snapshot as a shader,
  /// kept across frames because the snapshot itself only changes about a dozen
  /// times a second and building one per frame is pure waste.
  ///
  /// It is handed a CLONE, and that is not defensive style — on CanvasKit an
  /// `ImageShader` TAKES OWNERSHIP of the image and disposes it with itself.
  /// Give it the scene's own snapshot and the next refresh disposes an image
  /// that is already gone, inside the ticker, and the whole page freezes
  /// mid-frame. That shipped once; see login_water.dart.
  ui.ImageShader? _lens;
  ui.Image? _lensFor;

  ui.ImageShader? _lensShader(ui.Image? sky) {
    if (sky == null) {
      _retire(_lens);
      _lens = null;
      _lensFor = null;
      return null;
    }
    if (identical(sky, _lensFor)) return _lens;
    _retire(_lens);
    _lensFor = sky;
    _lens = ui.ImageShader(
      sky.clone(),
      TileMode.clamp,
      TileMode.clamp,
      // Texture coordinates are handed in SCREEN space; this is what turns
      // them into pixels of a snapshot taken at [_kWaterSkyScale].
      Matrix4.diagonal3Values(1 / _kWaterSkyScale, 1 / _kWaterSkyScale, 1).storage,
      filterQuality: FilterQuality.medium,
    );
    return _lens;
  }

  /// Frees a replaced shader a couple of frames late. The frame that used it
  /// may not have been rasterised yet, and freeing a shader out from under a
  /// display list still in flight is exactly the class of bug that froze the
  /// login page once — the scene gives its own outgoing snapshot the same
  /// grace, see `_HalcyonSceneState._refreshSky`.
  void _retire(ui.ImageShader? shader) {
    if (shader == null) return;
    Future<void>.delayed(const Duration(milliseconds: 200), shader.dispose);
  }

  @override
  void initState() {
    super.initState();
    _run
      ..addListener(_pushWater)
      ..forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Published by HalcyonScene to everything inside it.
    _scene = _HalcyonSceneScope.maybeOf(context);
  }

  @override
  void dispose() {
    _run.dispose();
    _dots.dispose();
    // Takes the clone it was given with it; the scene's own snapshot is
    // untouched. Deferred for the same reason [_retire] defers: the splash's
    // last frame may still be on its way to the raster thread.
    _retire(_lens);
    _lens = null;
    super.dispose();
  }

  /// Lays out the drips for a given lockup. Deterministic — same screen, same
  /// drips — so nothing here can flicker on a rebuild.
  void _seedDrips(_EmergeGeom g) {
    _drips.clear();
    final bottom = g.restTop + g.tile;
    for (final left in const [true, false]) {
      final x0 = g.xOf(left);
      final breach = left ? _kEmergeBreachL : _kEmergeBreachR;
      // Along the bottom edge, away from the rounded corners.
      // Uneven on purpose: beads at even spacing read as a row of pearls stuck
      // to the card rather than as water finding its own way down. A dry mark
      // gets fewer of them, because every one of them has to leave.
      const spots = _kEmergeWetFace ? [.15, .31, .52, .71, .87] : [.26, .55, .81];
      for (var i = 0; i < spots.length; i++) {
        final s = _halcyonRnd(i, left ? 41 : 57);
        // On a wet mark only the two heaviest let go and the light ones stay
        // behind; on a dry one nothing may stay behind, so all of them fall.
        final heavy = !_kEmergeWetFace || i == 1 || i == 3;
        // And they gather later, as the last of the water leaving it, rather
        // than while it is still coming up with a filmful of water on it.
        final form = breach + _kEmergeRise * (_kEmergeWetFace ? .42 : .62) + i * 46 + s * 40;
        _drips.add(_EmergeDrip(
          x: x0 + g.tile * (spots[i] + (s - .5) * .09),
          fromY: bottom,
          // Bigger than a real drop off a card this size. At 4 px a drip is
          // a speck nobody notices in a second and a half.
          r: (g.tile / 84) * (heavy ? 6.4 + s * 1.8 : 2.4 + s * 2.4),
          formAt: form,
          detachAt: form + (heavy ? (_kEmergeWetFace ? 165 + s * 70 : 130 + s * 60) : 1e6),
          landY: g.dripLandY,
          cling: !heavy,
        ));
      }
    }
  }

  /// Everything the sequence says to the water, once per frame.
  void _pushWater() {
    // Preview only. Pinned rather than "stopped when it gets there": under a
    // headless capture's virtual clock the very first tick can arrive seconds
    // in, so waiting for the storyboard to reach the mark never catches it.
    final freeze = widget.freezeAt;
    if (freeze != null && !_frozen) {
      _frozen = true;
      _run.stop();
      _run.value = (freeze / _kEmergeRun).clamp(0.0, 1.0);
    }
    final t = _run.value * _kEmergeRun;
    final g = _geom;
    final water = _scene?.water;
    if (g == null || water == null || !water.ready) return;
    final dt = (t - _lastT) / 1000;
    _lastT = t;
    if (dt <= 0) return;

    for (final left in const [true, false]) {
      final breach = left ? _kEmergeBreachL : _kEmergeBreachR;
      final cx = g.centreOf(left);

      // 1. The dome that runs ahead of it. A velocity, not a displacement:
      //    it has to keep building for the whole approach.
      if (t > breach - 110 && t < breach) {
        water.disturb(Offset(cx, g.waterY + g.tile * .3), _kEmergeSwell * dt, g.tile * .75,
            settled: false);
      }

      // 2. The breach itself — one settled displacement, which collapses at
      //    once and sends the ring out. Plus a shallow dent behind it, which
      //    is the water falling back into the hole the mark left.
      if (t >= breach && !_broke.contains(left)) {
        _broke.add(left);
        water.disturb(Offset(cx, g.waterY + g.tile * .18), _kEmergeBreak, g.tile * .62);
        water.disturb(Offset(cx, g.waterY + g.tile * .18), -_kEmergeBreak * .5, g.tile * .3);
      }

      // 3. While it is still crossing the line, hold the surface open around
      //    it — the same velocity dent the cursor leaves.
      final top = g.topAt(t, left);
      if (t >= breach && top + g.tile > g.waterY) {
        water.disturb(Offset(cx, g.waterY + g.tile * .12), -_kEmergeHold * dt, g.tile * .5,
            settled: false);
      }
    }

    // 4. Impacts. The ripple is the solver's answer, not a drawn ring.
    for (final d in _drips) {
      if (d.cling || d.fired || t < d.landAt) continue;
      d.fired = true;
      water.disturb(Offset(d.x, d.landY), -_kEmergeDrip, g.tile * .2);
      water.disturb(Offset(d.x, d.landY), -_kEmergeDrip * .45, g.tile * .09);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight);
      final g = _geom;
      if (g == null || g.size != size) {
        _geom = _EmergeGeom(size);
        _seedDrips(_geom!);
      }
      final geom = _geom!;
      return AnimatedBuilder(
        animation: _run,
        builder: (context, _) {
          final t = _run.value * _kEmergeRun;
          final leftTop = geom.topAt(t, true);
          final rightTop = geom.topAt(t, false);
          return Stack(children: [
            // The spotlight scrim the original splash carries, for the same
            // reason: white text over the horizon glow is otherwise unreadable.
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    radius: .62,
                    colors: [Color(0x8c03060f), Color(0x4d03060f), Color(0x0003060f)],
                    stops: [0, .5, 1],
                  ),
                ),
              ),
            ),

            // What is still under the surface: dimmed, blurred and pulled
            // toward the water's own colour. Without it the mark appears out of
            // nothing at the line instead of rising to it. Dropped the moment
            // there is nothing left below the line — it is three saveLayers.
            if (rightTop + geom.tile > geom.waterY)
              Positioned.fill(
                child: ClipRect(
                  clipper: _EmergeClip(top: geom.waterY, bottom: geom.size.height),
                  child: Opacity(
                    opacity: .34,
                    child: ImageFiltered(
                      imageFilter: ui.ImageFilter.blur(sigmaX: 4.0, sigmaY: 5.2),
                      child: ColorFiltered(
                        colorFilter: ColorFilter.mode(
                            _HcPalette.water2.withValues(alpha: .8), BlendMode.srcATop),
                        child: _lockLayer(geom, leftTop, rightTop),
                      ),
                    ),
                  ),
                ),
              ),

            // The reflection the simulated surface cannot give us: it mirrors
            // the SKY snapshot, which is painted before this widget exists. Kept
            // faint — it only has to say the marks are standing over water.
            if (t > _kEmergeBreachL + _kEmergeRise * .5)
              Positioned.fill(
                child: IgnorePointer(
                  child: Opacity(
                    opacity:
                        (((t - _kEmergeBreachL - _kEmergeRise * .5) / 420).clamp(0.0, 1.0)) * .17,
                    child: ClipRect(
                      clipper: _EmergeClip(top: geom.waterY, bottom: geom.size.height),
                      // Falls away with depth. Flat, it reads as two grey
                      // blocks parked in the pond rather than as a reflection.
                      child: ShaderMask(
                        blendMode: BlendMode.dstIn,
                        shaderCallback: (rect) => ui.Gradient.linear(
                          Offset(0, geom.waterY),
                          Offset(0, geom.waterY + (geom.size.height - geom.waterY) * .55),
                          [const Color(0xffffffff), const Color(0x00ffffff)],
                        ),
                        child: ImageFiltered(
                          imageFilter: ui.ImageFilter.blur(sigmaX: 3.0, sigmaY: 4.4),
                          child: Transform(
                            alignment: Alignment.topLeft,
                            // Mirror about the waterline, squashed the way the
                            // scene's own reflections are.
                            // y -> waterY + (waterY - y) * .62, i.e. mirrored
                            // about the line and squashed by the same amount the
                            // scene's own reflections are.
                            transform: Matrix4.identity()
                              ..translateByDouble(0.0, geom.waterY * 1.62, 0.0, 1.0)
                              ..scaleByDouble(1.0, -.62, 1.0, 1.0),
                            child: _lockLayer(geom, leftTop, rightTop),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // The marks themselves, cut off at the waterline.
            Positioned.fill(
              child: ClipRect(
                clipper: _EmergeClip(top: 0, bottom: geom.waterY),
                child: _lockLayer(geom, leftTop, rightTop),
              ),
            ),

            // Everything wet: the veil, the film draining down the face, the
            // meniscus at the line, the beads and the falling drips.
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _EmergeWaterPainter(
                    t: t,
                    geom: geom,
                    leftTop: leftTop,
                    rightTop: rightTop,
                    drips: _drips,
                    lens: _lensShader(_scene?.skyImage),
                  ),
                ),
              ),
            ),

            // The words, once the marks are out and still.
            Positioned(
              left: 0,
              right: 0,
              top: geom.restTop + geom.tile + geom.tile * .34,
              child: Column(children: [
                _fadeUp(t, _kEmergeTitle,
                    child: Text('Purchase Shipment Alert',
                        style: TextStyle(
                            fontSize: geom.tile * .262,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: -.2,
                            shadows: const [Shadow(color: Color(0x80000000), blurRadius: 12)]))),
                SizedBox(height: geom.tile * .07),
                _fadeUp(t, _kEmergeSub,
                    child: Text('TPK  ×  AUTOMATION DEPARTMENT',
                        style: TextStyle(
                            fontSize: geom.tile * .137,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 2.4,
                            color: const Color(0xe6ffffff),
                            shadows: const [Shadow(color: Color(0x99000000), blurRadius: 10)]))),
                SizedBox(height: geom.tile * .4),
                _fadeUp(t, _kEmergeLoader,
                    child: Column(children: [
                      SizedBox(
                        height: 20,
                        child: AnimatedBuilder(
                          animation: _dots,
                          builder: (context, _) => Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (var i = 0; i < 3; i++) ...[
                                _dot(i),
                                if (i < 2) const SizedBox(width: 10),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text('Preparing your workspace…',
                          style: TextStyle(
                              fontSize: 12,
                              color: Color(0xbfffffff),
                              shadows: [Shadow(color: Color(0x99000000), blurRadius: 10)])),
                    ])),
              ]),
            ),

            const Positioned(
              right: 20,
              bottom: 16,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.precision_manufacturing_outlined, size: 15, color: Color(0x99ffffff)),
                  SizedBox(width: 7),
                  Text('Developed by Automation Department',
                      style: TextStyle(
                          color: Color(0xccffffff),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          letterSpacing: .2)),
                ],
              ),
            ),
          ]);
        },
      );
    });
  }

  /// The two marks and the `×`, positioned in stage coordinates so the clips,
  /// the reflection and the painter all measure the same thing.
  Widget _lockLayer(_EmergeGeom g, double leftTop, double rightTop) {
    return Stack(children: [
      Positioned(left: g.xOf(true), top: leftTop, child: _tile(g, 'logo_tpk.png')),
      Positioned(left: g.xOf(false), top: rightTop, child: _tile(g, 'Automation_Logo.png')),
      Positioned(
        left: g.cx - g.tile * .25,
        top: (leftTop + rightTop) / 2 + g.tile * .5 - g.tile * .22,
        width: g.tile * .5,
        child: Opacity(
          // The × has nothing to rise out of on its own, so it simply catches
          // up with the marks over the last part of their lift.
          opacity: (1 - (leftTop - g.restTop).abs() / (g.tile * 1.1)).clamp(0.0, 1.0),
          child: Text('×',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: g.tile * .357,
                  height: 1,
                  fontWeight: FontWeight.w300,
                  color: const Color(0xb3ffffff),
                  shadows: const [Shadow(color: Color(0x66000000), blurRadius: 8)])),
        ),
      ),
    ]);
  }

  Widget _tile(_EmergeGeom g, String asset) {
    return Container(
      width: g.tile,
      height: g.tile,
      alignment: Alignment.center,
      padding: EdgeInsets.all(g.tile * .143),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(g.tile * .262),
        boxShadow: const [
          BoxShadow(color: Color(0x59060b28), blurRadius: 26, offset: Offset(0, 12))
        ],
      ),
      // Mipmapped sampling — both marks are minified ~7x into these tiles and
      // the default bilinear filter makes them look blurry.
      child: Image.asset(asset, fit: BoxFit.contain, filterQuality: FilterQuality.medium),
    );
  }

  /// Text arriving after the water has finished with it.
  Widget _fadeUp(double t, double at, {required Widget child}) {
    final u = ((t - at) / 420).clamp(0.0, 1.0);
    final e = Curves.easeOutCubic.transform(u);
    return Opacity(
      opacity: e,
      child: Transform.translate(offset: Offset(0, (1 - e) * 14), child: child),
    );
  }

  Widget _dot(int i) {
    final phase = (_dots.value - i * 0.18) % 1.0;
    final wave = (sin(phase * 2 * pi) + 1) / 2;
    return Transform.translate(
      offset: Offset(0, -wave * 6),
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: _dotColors[i].withValues(alpha: 0.45 + wave * 0.55),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
                color: _dotColors[i].withValues(alpha: wave * 0.4),
                blurRadius: 8,
                offset: const Offset(0, 3)),
          ],
        ),
      ),
    );
  }
}

/// Straight horizontal band clip — above the waterline for the marks, below it
/// for what is still submerged and for the reflection.
class _EmergeClip extends CustomClipper<Rect> {
  const _EmergeClip({required this.top, required this.bottom});

  final double top;
  final double bottom;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(0, top, size.width, bottom);

  @override
  bool shouldReclip(_EmergeClip old) => old.top != top || old.bottom != bottom;
}

// ---------------------------------------------------------------------------
// The water that comes out with them
// ---------------------------------------------------------------------------

class _EmergeWaterPainter extends CustomPainter {
  _EmergeWaterPainter({
    required this.t,
    required this.geom,
    required this.leftTop,
    required this.rightTop,
    required this.drips,
    required this.lens,
  });

  final double t;
  final _EmergeGeom geom;
  final double leftTop;
  final double rightTop;
  final List<_EmergeDrip> drips;

  /// The scene's own sky snapshot as a shader — the same texture the water
  /// mirrors, taken at [_kWaterSkyScale] and covering everything above the
  /// waterline. It is what the drops refract; see [_glassDrop]. Null until the
  /// first snapshot lands, and whenever the classic water is running.
  final ui.ImageShader? lens;

  @override
  void paint(Canvas canvas, Size size) {
    for (final left in const [true, false]) {
      _mark(canvas, left, left ? leftTop : rightTop);
    }
    for (final d in drips) {
      _drip(canvas, d);
    }
  }

  /// Everything wet about one mark.
  void _mark(Canvas canvas, bool left, double top) {
    final g = geom;
    final breach = left ? _kEmergeBreachL : _kEmergeBreachR;
    if (t < breach) return;
    final x = g.xOf(left);
    final bottom = top + g.tile;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(x, top, g.tile, g.tile),
      Radius.circular(g.tile * .262),
    );

    // -- the surface it is coming through ---------------------------------
    // A lens of lifted water around the crossing, plus the cusp the surface
    // pulls up against the sides. Only while it is actually crossing.
    if (bottom > g.waterY && top < g.waterY + g.tile) {
      final cross = ((g.waterY - top) / g.tile).clamp(0.0, 1.0);
      final lens = Paint()
        ..shader = ui.Gradient.radial(
          Offset(x + g.tile / 2, g.waterY),
          g.tile * 1.05,
          [
            _HcPalette.glint.withValues(alpha: .30 * (1 - cross * .5)),
            _HcPalette.glint.withValues(alpha: 0),
          ],
        );
      canvas.save();
      canvas.scale(1, .3);
      canvas.translate(0, g.waterY / .3 - g.waterY);
      canvas.drawCircle(Offset(x + g.tile / 2, g.waterY), g.tile * 1.05, lens);
      canvas.restore();
    }

    // -- the veil ----------------------------------------------------------
    // Water lifted with the mark, still joined to the surface, thinning until
    // it breaks. Lives only over the ~180 ms after the bottom edge clears.
    if (bottom < g.waterY) {
      final gap = g.waterY - bottom;
      final reach = g.tile * 1.5;
      if (gap < reach) {
        final f = 1 - gap / reach; // 1 the instant it clears, 0 when it breaks
        final halfTop = g.tile * .46 * f;
        final halfFoot = g.tile * .16 * f;
        final path = Path()
          ..moveTo(x + g.tile / 2 - halfTop, bottom - 1)
          ..quadraticBezierTo(x + g.tile / 2 - halfFoot * 1.6, bottom + gap * .55,
              x + g.tile / 2 - halfFoot, g.waterY)
          ..lineTo(x + g.tile / 2 + halfFoot, g.waterY)
          ..quadraticBezierTo(x + g.tile / 2 + halfFoot * 1.6, bottom + gap * .55,
              x + g.tile / 2 + halfTop, bottom - 1)
          ..close();
        canvas.drawPath(
          path,
          Paint()
            ..shader = ui.Gradient.linear(
              Offset(0, bottom),
              Offset(0, g.waterY),
              [
                _HcPalette.glint.withValues(alpha: .22 * f),
                _HcPalette.rippleCrest.withValues(alpha: .10 * f),
              ],
            ),
        );
      }
    }

    // -- the film draining down the face -----------------------------------
    // Everything that has cleared the surface is wet; it dries from the top
    // down. `filmTop` is where the receding edge has got to.
    final outAt = breach + _kEmergeRise * .72; // roughly when it is clear
    final drain = ((t - outAt) / 520).clamp(0.0, 1.0);
    final filmTop = top + g.tile * Curves.easeInOut.transform(drain);
    if (_kEmergeWetFace && filmTop < bottom - 1) {
      canvas.save();
      canvas.clipRRect(rrect);
      final film = Rect.fromLTRB(x, filmTop, x + g.tile, bottom);
      canvas.drawRect(
        film,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(0, filmTop),
            Offset(0, bottom),
            [
              _HcPalette.water0.withValues(alpha: _kEmergeFilm * .55),
              _HcPalette.water1.withValues(alpha: _kEmergeFilm),
            ],
          ),
      );
      // The receding edge itself, with the wobble a real one has.
      final edge = Path()..moveTo(x, filmTop);
      for (var i = 0; i <= 12; i++) {
        final u = i / 12;
        edge.lineTo(x + g.tile * u, filmTop + sin(u * 7 + t * .012) * g.tile * .02);
      }
      canvas.drawPath(
        edge,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = g.tile * .022
          ..color = _HcPalette.glint.withValues(alpha: .5 * (1 - drain)),
      );
      // Two rivulets running ahead of the edge, down to the bottom corner.
      for (var i = 0; i < 2; i++) {
        final rx = x + g.tile * (i == 0 ? .32 : .69);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(rx, filmTop - g.tile * .1, g.tile * .035, bottom - filmTop + g.tile * .1),
            Radius.circular(g.tile * .02),
          ),
          Paint()..color = _HcPalette.glint.withValues(alpha: .18 * (1 - drain)),
        );
      }
      canvas.restore();
    }

    // -- the beads on the bottom edge --------------------------------------
    for (final d in drips) {
      if ((d.x < g.cx) != left) continue;
      if (t < d.formAt || t >= d.detachAt) continue;
      // Gathering has to fit inside the hang: a bead that only exists for
      // 130 ms before it falls would otherwise let go at half its size.
      final gather = d.cling ? 220.0 : min(220.0, (d.detachAt - d.formAt) * .55);
      final grow = ((t - d.formAt) / gather).clamp(0.0, 1.0);
      // Sag, then neck: the last stretch before it lets go it is being pulled
      // into a teardrop rather than growing.
      final neck = d.cling ? 90.0 : min(90.0, (d.detachAt - d.formAt) * .45);
      final pull = d.cling ? 0.0 : ((t - (d.detachAt - neck)) / neck).clamp(0.0, 1.0);
      _bead(canvas, Offset(d.x, bottom + d.r * .55 + pull * d.r * 1.5), d.r * grow, pull, bottom);
    }
  }

  /// One drop of water, drawn as the lens it is.
  ///
  /// A drop is not a coloured blob with a highlight painted on it — that is
  /// what it was until 2026-08-24, and the user was right that it did not read
  /// as water. What makes a real drop unmistakable is that you can SEE THROUGH
  /// it, magnified and turned upside down, because a sphere of water is a
  /// short-focus lens.
  ///
  /// The same idea as [LiquidDrop] in the glass theme, and available for the
  /// same reason: there is already a texture of what is behind — the scene's
  /// sky snapshot, taken for the water to mirror. So the body of the drop is
  /// that snapshot, sampled from where the drop is, scaled UP, and rotated
  /// half a turn. The gate's arch bends through a falling drip because the
  /// arch really is in the picture the drop is showing you.
  ///
  /// Everything else is edges: light grazing the rim, one specular where the
  /// horizon glow catches it, and the bright foot where the lens throws that
  /// light back out.
  void _glassDrop(Canvas canvas, Offset at, double rx, double ry) {
    if (rx <= .3) return;
    final oval = Rect.fromCenter(center: at, width: rx * 2, height: ry * 2);

    if (lens != null) {
      // A mesh across the drop, every vertex carrying the point of the scene
      // that the water bends into it — the same displacement-map refraction
      // [RenderLiquidDrop] uses for the glass theme and [_HalcyonWater] uses
      // for its mirror, and available on CanvasKit for the same reason
      // (`ui.ImageFilter.shader` is Impeller-only).
      final mesh = _lensMesh(at, rx, ry);
      canvas.drawVertices(
        mesh,
        BlendMode.srcOver,
        Paint()
          ..filterQuality = FilterQuality.medium
          ..shader = lens,
      );
      // Rebuilt every frame; handing it straight back keeps the drops off the
      // garbage collector's list. The display list has its own reference.
      mesh.dispose();
    } else {
      // No snapshot yet, or the classic water is running and nothing is
      // snapshotting the sky at all. The drop still has to be there.
      canvas.drawOval(oval, Paint()..color = _HcPalette.water0.withValues(alpha: .5));
    }

    canvas.save();
    canvas.clipPath(Path()..addOval(oval));
    // Down toward the night colour. Multiply can only take brightness OUT and
    // it keeps the hue, so the scene inside the drop is still the scene — just
    // deep enough that the horizon's bloom stops turning it into a pink bead.
    canvas.drawRect(
      oval,
      Paint()
        ..blendMode = BlendMode.multiply
        ..color = Color.lerp(const Color(0xffffffff), _HcPalette.water2, _kEmergeDropDark)!,
    );
    // And darkest of all at the rim, where the ray path through the water is
    // longest and the angle steepest — the shading that stops a drop reading
    // as a flat disc of scene.
    canvas.drawRect(
      oval,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(at.dx, at.dy - ry * .15),
          max(rx, ry) * 1.15,
          [
            _HcPalette.water3.withValues(alpha: 0),
            _HcPalette.water3.withValues(alpha: .62),
          ],
          [.35, 1],
        ),
    );
    canvas.restore();

    // The rim. Grazing light rides the whole edge, brightest where the scene's
    // light is — the horizon bloom, dead centre at the waterline.
    final toLight = (Offset(geom.cx, geom.waterY) - at);
    final lightDir = toLight.distance < 1 ? const Offset(0, 1) : toLight / toLight.distance;
    canvas.drawOval(
      oval.deflate(rx * .07),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(.8, rx * .15)
        ..shader = ui.Gradient.linear(
          at - lightDir * ry,
          at + lightDir * ry,
          [
            _HcPalette.glint.withValues(alpha: .10),
            _HcPalette.glint.withValues(alpha: .42),
          ],
        ),
    );
    // The specular: small, hard, and on the side the light is on. On a dark
    // drop this and the rim are the whole silhouette, so they stay — a drop
    // with neither is a hole in the sky.
    canvas.drawCircle(
      at - lightDir * (rx * .46),
      max(.6, rx * .17),
      Paint()..color = Colors.white.withValues(alpha: .5),
    );
    // And the foot, where the little the lens gathered leaves it again.
    canvas.drawCircle(
      at + lightDir * (ry * .52),
      rx * .26,
      Paint()..color = _HcPalette.rippleCrest.withValues(alpha: .12),
    );
  }

  /// The drop's refraction, as a triangle fan of texture coordinates.
  ///
  /// Where each vertex SAMPLES is the whole physics. For a point at fractional
  /// radius `r` across the drop, the scene it shows is at
  ///
  ///   `-dir * spread * (r + bend*r^5) / (1 + bend)`
  ///
  /// three things at once, and each one is a thing a real drop does:
  ///
  /// * the minus sign — the image inside a drop is UPSIDE DOWN, and no painted
  ///   highlight can stand in for that;
  /// * `spread` — a drop this size has a focal length of a fraction of a
  ///   millimetre, so it is a fisheye, not a magnifier. It shows a view eight
  ///   times its own width. (Magnifying instead was the first attempt: it
  ///   samples three pixels of sky and every drop comes out a flat pill.)
  /// * `r^5` — nearly linear across the clear middle, then running away near
  ///   the rim, so the last tenth of the drop crushes half the view into it.
  ///   That crush IS the rim of a drop; it is what the eye reads as thickness.
  ///
  /// Positions are screen points and texture coordinates are screen points
  /// too — [_lensShader] carries the scale from screen space into the
  /// snapshot's own pixels.
  ui.Vertices _lensMesh(Offset at, double rx, double ry) {
    const rings = 6;
    const seg = 18;
    const spread = 8.0;
    const bend = 3.4;

    const count = 1 + rings * seg;
    final positions = Float32List(count * 2);
    final texture = Float32List(count * 2);

    positions[0] = at.dx;
    positions[1] = at.dy;
    texture[0] = at.dx;
    texture[1] = at.dy;

    var v = 1;
    for (var i = 1; i <= rings; i++) {
      final r = i / rings;
      final map = spread * (r + bend * pow(r, 5)) / (1 + bend);
      for (var s = 0; s < seg; s++) {
        final a = s * 2 * pi / seg;
        final dx = cos(a), dy = sin(a);
        positions[v * 2] = at.dx + dx * rx * r;
        positions[v * 2 + 1] = at.dy + dy * ry * r;
        texture[v * 2] = at.dx - dx * rx * map;
        texture[v * 2 + 1] = at.dy - dy * ry * map;
        v++;
      }
    }

    // Fan around the centre, then a quad strip between each pair of rings.
    final indices = Uint16List((seg + (rings - 1) * seg * 2) * 3);
    var k = 0;
    int ring(int i, int s) => 1 + (i - 1) * seg + (s % seg);
    for (var s = 0; s < seg; s++) {
      indices[k++] = 0;
      indices[k++] = ring(1, s);
      indices[k++] = ring(1, s + 1);
    }
    for (var i = 2; i <= rings; i++) {
      for (var s = 0; s < seg; s++) {
        final a = ring(i - 1, s), b = ring(i - 1, s + 1);
        final c = ring(i, s), d = ring(i, s + 1);
        indices[k++] = a;
        indices[k++] = c;
        indices[k++] = d;
        indices[k++] = a;
        indices[k++] = d;
        indices[k++] = b;
      }
    }

    return ui.Vertices.raw(
      VertexMode.triangles,
      positions,
      textureCoordinates: texture,
      indices: indices,
    );
  }

  /// A bead hanging from an edge: the drop itself, plus the neck that still
  /// holds it to the edge.
  void _bead(Canvas canvas, Offset at, double r, double pull, double edgeY) {
    if (r <= .2) return;
    // The neck thins as the pull comes on — that IS the "about to fall".
    final neck = Path()
      ..moveTo(at.dx - r * (.85 - pull * .62), edgeY)
      ..quadraticBezierTo(at.dx - r * .5, at.dy - r * .2, at.dx, at.dy)
      ..quadraticBezierTo(at.dx + r * .5, at.dy - r * .2, at.dx + r * (.85 - pull * .62), edgeY)
      ..close();
    canvas.drawPath(
      neck,
      Paint()
        // Kept in step with the drop it feeds — see [_kEmergeDropDark]. A pale
        // neck under a dark bead reads as a scratch on the card.
        ..shader = ui.Gradient.radial(
          Offset(at.dx - r * .3, at.dy - r * .4),
          r * 1.7,
          [
            _HcPalette.glint.withValues(alpha: .34 * (1 - _kEmergeDropDark * .6)),
            _HcPalette.water2.withValues(alpha: .42),
          ],
        ),
    );
    _glassDrop(canvas, at, r, r * (1 + pull * .35));
  }

  /// A drip in the air: stretched by its own speed, and gone the moment it
  /// reaches the water (where the solver takes over — see [_pushWater]).
  void _drip(Canvas canvas, _EmergeDrip d) {
    if (d.cling || t < d.detachAt) return;
    final s = (t - d.detachAt) / 1000;
    final y = d.fromY + d.r * .55 + .5 * _kEmergeGravity * s * s;
    if (y >= d.landY) return;
    final v = _kEmergeGravity * s;
    final stretch = (1 + v / 900).clamp(1.0, 1.8);
    final rx = d.r / sqrt(stretch);
    final ry = d.r * stretch;
    final at = Offset(d.x, y);
    // The tail a fast drop leaves behind it — under the drop, so the lens
    // stays the brightest thing about it.
    if (stretch > 1.4) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(at.dx - rx * .3, at.dy - ry * 1.9, rx * .6, ry * 1.0),
          Radius.circular(rx),
        ),
        Paint()..color = _HcPalette.glint.withValues(alpha: .11 * (1 - _kEmergeDropDark * .6)),
      );
    }
    _glassDrop(canvas, at, rx, ry);
  }

  @override
  bool shouldRepaint(_EmergeWaterPainter old) => true;
}
