part of '../main.dart';

// ===========================================================================
// "Halcyon Gate" login — a sky / still-water scene painted on canvas, with the
// sign-in form floating on frosted glass in the middle of the gate.
//
// It has two faces of the same place, chosen by the clock (see halcyonIsDay):
// blue-and-gold morning up to 12:00, violet night from 12:01. Only the colours
// change — every layer, ripple and meteor below is shared, and the whole switch
// lives inside _HcPalette.
//
// Ported from RAP so both systems share one sign-in. Everything here is
// self-contained: the classic login card (_classic() in login_page.dart) is
// untouched, and `kUseHalcyonLogin` below picks which one the login stage
// shows. Flip it to false to go straight back to the old card.
//
// Scene layers, back to front:
//   sky gradient -> nebula -> stars (+ shooting stars) -> horizon bloom ->
//   the gate arch -> mist -> water (reflected bloom, gate reflection, ripple
//   crests, pointer ripples) -> drifting motes -> vignette.
//
// The pointer drives four things: parallax on the sky, a soft aura that
// follows the cursor, stars brightening near it, and — the main event —
// ripples on the water. Moving over the water sheds small ripples; clicking
// the water drops a big one, and clicking the sky calls down a meteor. Live
// ripples also bend the reflection lines and the crest streaks they pass
// through, so the water reacts as one surface.
// ===========================================================================

/// Set to false to restore the original login card (_classic()).
const bool kUseHalcyonLogin = true;

/// Where the waterline sits, as a fraction of the viewport height.
const double _kHalcyonHorizon = .60;

// --- How solid the sign-in card looks -------------------------------------
// The card is frosted glass: the scene behind it is blurred, then a white
// wash is laid over the blur. Raise the wash to hide more of the scene, lower
// it to let more through. Every value is 0 (invisible) .. 1 (solid white).
// These four are the whole knob set — nothing else tints the card.

/// Blur applied to the scene behind the card, in logical pixels. This is the
/// "frost"; it does not darken or lighten, it only smears. 0 = clear glass.
const double kHalcyonCardBlur = 0;

/// The white wash over the blur, at the card's top-left corner (the brighter
/// end of its diagonal gradient). This is the main opacity knob.
const double kHalcyonCardTintTop = .06;

/// The same wash at the bottom-right corner. Keep it below [kHalcyonCardTintTop]
/// so the card keeps its lit-from-above look; set both equal for a flat card.
const double kHalcyonCardTintBottom = .02;

/// The hairline border around the card.
const double kHalcyonCardBorder = .26;

/// The fill behind the email/password fields, so they can be lifted along with
/// the card — on a near-solid card the default .07 wash disappears.
const double kHalcyonFieldFill = .10;

// --- How the card leans toward the pointer --------------------------------
// Read the note above _HalcyonTilt before touching these: this effect has a
// history of making the card's thin-bordered controls shimmer, and the fix it
// now relies on only holds while the card is a cached raster layer.

/// Maximum lean, in degrees, reached when the pointer is at the edge of the
/// viewport. Past ~10 the perspective starts to distort the text. 0 disables
/// the tilt entirely.
const double kHalcyonCardTiltDegrees = 6;

/// Strength of the perspective — how much nearer edges grow and far ones
/// shrink. Larger is more dramatic; .0016 already reads as quite deep.
const double kHalcyonCardTiltPerspective = .0011;

/// How much of the current lean survives each frame, 0..1. 0 glues the card to
/// the pointer (twitchy); .90 is a slow, heavy drift. This lag is not just
/// polish — it keeps the matrix from tracking every jittery mouse sample.
const double kHalcyonCardTiltEase = .86;

/// How the leaning card is re-sampled. The card is rasterised once and moved
/// as a texture (see [_HalcyonTilt]), so every frame lands it on a slightly
/// different sub-pixel offset; the sampler decides whether hard edges hold
/// steady or flash. `low` is bilinear and lets high-contrast edges strobe,
/// which is what the Microsoft logo's four saturated squares were doing.
/// `high` (bicubic) costs a little more and softens the card by a hair.
const FilterQuality kHalcyonCardTiltFilter = FilterQuality.high;

/// Pins the login to one tone so the other can be looked at without waiting for
/// the clock: `true` forces day, `false` forces night, `null` (the shipping
/// value) follows the time of day. Only ever set this while looking at the
/// page — left set, the scene stops following the clock for everyone.
///
/// Deliberately not `const`: a const here would fold the clock away and the
/// analyzer would report the real implementation as dead code.
bool? kHalcyonForceTone;

/// The clock the login reads. Morning is the day scene; from just past noon the
/// sun is on its way down and the night sky comes back.
///
/// Stated as "before 12:01" rather than a range so there is no minute that
/// belongs to neither face — 12:00 exactly is still morning.
bool halcyonIsDay([DateTime? now]) {
  final forced = kHalcyonForceTone;
  if (forced != null) return forced;
  final t = now ?? DateTime.now();
  return t.hour < 12 || (t.hour == 12 && t.minute == 0);
}

/// Every colour the scene and its card use, in one place — the tone has been
/// swapped wholesale more than once, so nothing below should hard-code a hex.
///
/// Two faces of the SAME place: [halcyonIsDay] picks between a violet/pink
/// "Halcyon Night" and a blue/gold "Halcyon Day", token for token, so the
/// scene, the gate, the water and the card all move together. Every entry is a
/// getter rather than a const, which is what lets the page turn over at noon
/// without being rebuilt — the painter re-reads these each frame.
///
/// The day tone is a NOON SKY SEEN FROM SHADE, not a white one. Everything on
/// the card is white text over a translucent pane, so the sky it sits against
/// has to stay dark enough to carry it; a literally bright day would need the
/// whole card re-coloured. Hence a deep azure zenith falling to a pale, warm
/// horizon — bright in hue, still deep in value. (The pre-violet navy night
/// variant this file used to carry in trailing comments is in git history.)
class _HcPalette {
  static bool get day => halcyonIsDay();

  // -- sky ------------------------------------------ day             night
  static Color get skyTop => day ? const Color(0xff0b3b6b) : const Color(0xff06041a);
  static Color get skyMid => day ? const Color(0xff1b5f9e) : const Color(0xff180f3d);
  static Color get skyLow => day ? const Color(0xff3f92c9) : const Color(0xff331c5e);
  static Color get skyHorizon => day ? const Color(0xff8fc7e3) : const Color(0xff4d2a72);
  // By day these are cloud banks rather than nebulae — same shapes, lit.
  static Color get nebulaA => day ? const Color(0xff7fb8dd) : const Color(0xff7a4bc9);
  static Color get nebulaB => day ? const Color(0xff4a7fb5) : const Color(0xff42309f);
  static Color get nebulaC => day ? const Color(0xffcfe4f2) : const Color(0xffa055b4);
  // And the stars become the glitter of daylight on dust — kept close to the
  // sky's own value so they sparkle instead of reading as stars at noon.
  static Color get starWarm => day ? const Color(0xffeaf6ff) : const Color(0xffe8e2ff);
  static Color get starCool => day ? const Color(0xffffffff) : const Color(0xffffd7f2);
  static Color get starHalo => day ? const Color(0xffbcd9f0) : const Color(0xffbfa8ff);

  // -- the central light: the moon becomes the sun --------------------------
  static Color get bloom => day ? const Color(0xfffffbe8) : const Color(0xfffbe3f5);
  static Color get bloomMid => day ? const Color(0xffffd98a) : const Color(0xffde8ecd);
  static Color get accent => day ? const Color(0xffffb347) : const Color(0xff8b5cf6);
  static Color get mist => day ? const Color(0xfffff1d0) : const Color(0xffffe6f7);

  // -- the gate -------------------------------------------------------------
  static Color get gateInner => day ? const Color(0xffffe9b8) : const Color(0xffe9c9f2);
  static Color get gateFrame => day ? const Color(0xff0a2c4d) : const Color(0xff190733);
  static Color get gateBloom => day ? const Color(0xffffcf7a) : const Color(0xffb886ff);
  static Color get gateRimTop => day ? const Color(0xfffff6e0) : const Color(0xffffe4fb);
  static Color get gateRimFoot => day ? const Color(0xffffd58a) : const Color(0xffd7b0ff);
  static Color get gateShimmer => day ? const Color(0xfffff2cf) : const Color(0xffffd9f4);

  // -- water ----------------------------------------------------------------
  static Color get water0 => day ? const Color(0xff2e7fa8) : const Color(0xff42265f);
  static Color get water1 => day ? const Color(0xff1f6690) : const Color(0xff2b1548);
  static Color get water2 => day ? const Color(0xff14506f) : const Color(0xff180a2f);
  static Color get water3 => day ? const Color(0xff0c3b53) : const Color(0xff0c0520);
  static Color get reflect => day ? const Color(0xff1d6b95) : const Color(0xff2b1152);
  static Color get reflectGlow => day ? const Color(0xffffcf7a) : const Color(0xffb98cff);
  static Color get glint => day ? const Color(0xffeaf7ff) : const Color(0xffe4d4ff);
  static Color get rippleCrest => day ? const Color(0xfff2fbff) : const Color(0xffefe0ff);
  static Color get rippleTrough => day ? const Color(0xff0a3049) : const Color(0xff120826);
  static Color get shoreSoft => day ? const Color(0xffffe6b8) : const Color(0xffffd9f4);
  static Color get moteCore => day ? const Color(0xfffff4d8) : const Color(0xffffe0f6);
  static Color get moteHalo => day ? const Color(0xffffce7f) : const Color(0xffc9a3ff);
  static Color get vignette => day ? const Color(0xff04263c) : const Color(0xff05020f);

  // -- the card and its controls --------------------------------------------
  static Color get pageBg => day ? const Color(0xff0b3b6b) : const Color(0xff06041a);
  static Color get cardShadow => day ? const Color(0x8c03203a) : const Color(0x8c0a0320);
  static Color get inputIcon => day ? const Color(0xffbcdcf5) : const Color(0xffc4b5fd);
  static Color get inputFocus => day ? const Color(0xffffd58a) : const Color(0xffd8b4fe);
  static Color get cursor => day ? const Color(0xffeaf6ff) : const Color(0xffe9d5ff);
  static Color get eyeIcon => day ? const Color(0xffa8c8e0) : const Color(0xffb9a7e8);
  static Color get buttonA => day ? const Color(0xff2f8fd0) : const Color(0xff7c5cf0);
  static Color get buttonB => day ? const Color(0xfff0a04b) : const Color(0xffd14fae);
  static Color get buttonGlow => day ? const Color(0xff1f7ab8) : const Color(0xff9333ea);
  // Error tints and the status-pill greens read the same in both tones.
  static const errorText = Color(0xffffb0c8);
  static const errorLine = Color(0xffff92b4);
}

/// Deterministic 0..1 noise — the scene must look identical frame to frame
/// apart from the parts that are meant to move.
double _halcyonRnd(int i, [int salt = 0]) {
  final x = sin(i * 127.1 + salt * 311.7 + 13.37) * 43758.5453;
  return x - x.floorToDouble();
}

/// A meteor streaking across the sky — one drifts past on its own every so
/// often, and clicking the sky calls one (sometimes two) down on the spot.
class _HalcyonMeteor {
  _HalcyonMeteor({
    required this.origin,
    required this.born,
    required this.life,
    required this.dir,
    required this.travel,
    required this.len,
    required this.slope,
  });

  final Offset origin;
  final double born;
  final double life;

  /// -1 flies left, +1 flies right.
  final double dir;
  final double travel;
  final double len;

  /// How steeply it falls, as a fraction of the horizontal travel.
  final double slope;
}

/// One expanding ring on the water.
class _HalcyonRipple {
  _HalcyonRipple({
    required this.center,
    required this.born,
    required this.life,
    required this.maxRadius,
    required this.strength,
    required this.squash,
  });

  final Offset center;
  final double born;
  final double life;
  final double maxRadius;
  final double strength;

  /// Vertical flattening — ripples near the horizon are seen edge-on.
  final double squash;
}

/// Mutable scene state. The painter listens to this instead of the widget
/// rebuilding, so the animation costs a repaint per frame and nothing else.
class _HalcyonModel extends ChangeNotifier {
  double time = 0;
  Offset pointer = const Offset(.5, .42);
  bool pointerInside = false;

  /// Set by [_HalcyonSceneShield] when a pointer lands on the login card or on
  /// one of the controls floating over the scene, and consumed by the scene's
  /// own pointer handler, which then leaves that tap alone. See the shield for
  /// why a [Listener] cannot work this out for itself.
  bool pointerOnCard = false;
  final List<_HalcyonRipple> ripples = [];
  final List<_HalcyonMeteor> meteors = [];

  /// The simulated surface — see login_water.dart. Built whether or not
  /// [HcWater] is on: it costs nothing until something disturbs it, and it
  /// means the switch takes effect on the next frame rather than after a
  /// rebuild.
  final _HalcyonWater water = _HalcyonWater();

  /// The sky above the waterline, snapshotted for the water to reflect. Owned
  /// by [_HalcyonSceneState], which refreshes and disposes it.
  ui.Image? skyImage;

  @override
  void dispose() {
    skyImage?.dispose();
    skyImage = null;
    super.dispose();
  }

  void tick(double t) {
    time = t;
    if (ripples.isNotEmpty) {
      ripples.removeWhere((r) => t - r.born > r.life);
    }
    if (meteors.isNotEmpty) {
      meteors.removeWhere((m) => t - m.born > m.life);
    }
    notifyListeners();
  }

  void add(_HalcyonRipple r) {
    // Hard cap so a fast mouse can't pile up work.
    if (ripples.length > 26) ripples.removeAt(0);
    ripples.add(r);
  }

  void addMeteor(_HalcyonMeteor m) {
    if (meteors.length > 12) meteors.removeAt(0);
    meteors.add(m);
  }
}

// ---------------------------------------------------------------------------
// Scene widget
// ---------------------------------------------------------------------------

/// Full-bleed animated backdrop with [child] floating on top of it. Pass no
/// child to use it as a plain backdrop (the picker splash does this, so the
/// login and the splash share one continuous scene).
///
/// [bloom] scales the central light (horizon glow, its reflection, the mist
/// and the waterline seam). The login wants it at full strength; the splash
/// turns it down so its centred wordmark isn't sitting in a white-out.
class HalcyonScene extends StatefulWidget {
  const HalcyonScene({super.key, this.child, this.bloom = 1});

  final Widget? child;
  final double bloom;

  @override
  State<HalcyonScene> createState() => _HalcyonSceneState();
}

class _HalcyonSceneState extends State<HalcyonScene> with SingleTickerProviderStateMixin {
  final _HalcyonModel model = _HalcyonModel();

  late final ticker = createTicker(_frame);
  Size sceneSize = Size.zero;
  Offset lastRippleAt = Offset.zero;
  double lastRippleTime = -1;
  int rippleSeed = 0;
  int meteorSeed = 0;

  /// Where the pointer was on the previous hover event, and when — the wake
  /// needs the segment it covered, not just where it ended up.
  Offset? wakeAt;
  double wakeTime = 0;

  double lastSky = -99;

  void _frame(Duration elapsed) {
    model.tick(elapsed.inMicroseconds / 1000000);
    if (HcWater.on) _refreshSky();
  }

  /// Re-snapshots the sky for the water to mirror, a few times a second.
  ///
  /// Deliberately not once per frame: it is a second full render of every star,
  /// cloud and glow, and the reflection is bent far too hard for anyone to see
  /// it stepping. Until the first one lands the water has nothing to reflect
  /// and stays calm and empty; see [_HalcyonWater.paint].
  ///
  /// `toImageSync` rather than `toImage`, and the difference is not style: the
  /// async one copies the pixels back off the GPU, which Chrome reports as
  /// "GPU stall due to ReadPixels" eighteen times a second. The sync one leaves
  /// the snapshot resident on the GPU, where the very next thing to touch it is
  /// a texture lookup anyway.
  void _refreshSky() {
    if (sceneSize.isEmpty) return;
    if (model.time - lastSky < _kWaterSkyRefresh) return;
    lastSky = model.time;
    final size = sceneSize;
    final horizon = horizonY;
    final w = (size.width * _kWaterSkyScale).round();
    final h = (horizon * _kWaterSkyScale).round();
    if (w < 8 || h < 8) return;
    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.scale(_kWaterSkyScale);
      _HalcyonScenePainter(model, widget.bloom).paintSky(canvas, size, horizon);
      final picture = recorder.endRecording();
      final image = picture.toImageSync(w, h);
      picture.dispose();
      final old = model.skyImage;
      model.skyImage = image;
      // The outgoing image may still be inside a frame that has not been
      // rasterised yet, so it is given a couple of frames' grace rather than
      // being freed the instant it is replaced.
      if (old != null) Future.delayed(const Duration(milliseconds: 200), old.dispose);
    } catch (_) {
      // A failed snapshot just means the water keeps the reflection it has.
    }
  }

  @override
  void initState() {
    super.initState();
    ticker.start();
  }

  @override
  void dispose() {
    ticker.dispose();
    model.dispose();
    super.dispose();
  }

  double get horizonY => sceneSize.height * _kHalcyonHorizon;

  /// Perspective flattening for a ripple at [y]: tight near the horizon,
  /// rounder as the surface comes toward the viewer.
  double squashAt(double y) {
    final waterHeight = max(1.0, sceneSize.height - horizonY);
    final depth = ((y - horizonY) / waterHeight).clamp(0.0, 1.0);
    return .14 + depth * .34;
  }

  void handleHover(Offset local) {
    if (sceneSize.isEmpty) return;
    model.pointer = Offset(
      (local.dx / max(1.0, sceneSize.width)).clamp(0.0, 1.0),
      (local.dy / max(1.0, sceneSize.height)).clamp(0.0, 1.0),
    );
    model.pointerInside = true;

    if (HcWater.on) {
      // The simulated surface wants the whole segment the pointer covered, so
      // that a flicked mouse digs one continuous wake rather than a row of
      // separate rings. Nothing is throttled here: the events themselves are
      // the sampling, and the wake's strength is per-second, not per-event.
      final previous = wakeAt;
      // Only used to notice the pointer has been away and the stored point is
      // stale — the wake itself measures distance, not time. See [wake].
      final gap = model.time - wakeTime;
      wakeAt = local;
      wakeTime = model.time;
      if (previous != null && gap < .3 && local.dy > horizonY) {
        model.water.wake(previous, local);
      }
      return;
    }

    // Trail of small ripples, throttled by both distance and time so the
    // density is the same whether the mouse is flicked or crawled.
    if (local.dy <= horizonY) return;
    final moved = (local - lastRippleAt).distance;
    final elapsed = model.time - lastRippleTime;
    if (moved < 26 && elapsed < .55) return;
    if (elapsed < .10) return;
    lastRippleAt = local;
    lastRippleTime = model.time;
    final s = _halcyonRnd(rippleSeed++, 5);
    model.add(_HalcyonRipple(
      center: local,
      born: model.time,
      life: 2.3 + s * 1.1,
      maxRadius: 78 + s * 74,
      strength: .55 + s * .25,
      squash: squashAt(local.dy),
    ));
  }

  void handleTap(Offset local) {
    if (sceneSize.isEmpty) return;

    // The tap belongs to the card - a text field, a button, the water switch.
    // The scene stays out of it: no meteor behind the card, no stone in the
    // pond, and above all no touching focus. See [_HalcyonSceneShield].
    if (model.pointerOnCard) {
      model.pointerOnCard = false;
      return;
    }

    // A click on the scene ends whatever was being typed.
    //
    // This is what keeps the login fields alive on the web. Typing does not go
    // into the canvas: the engine parks an invisible <input> over the focused
    // field and the browser types into THAT. Clicking the scene moves the
    // browser's own focus off it - but nothing here used to tell Flutter, so
    // the field kept its caret blinking while every keystroke, backspace
    // included, went to the page instead. Clicking the same field again does
    // not help: as far as the framework is concerned it never lost focus, so
    // there is nothing to re-open, and the only way out is a page reload.
    // Dropping focus here keeps the two in step, so the next click on a field
    // is a real focus change and gets a fresh connection.
    FocusManager.instance.primaryFocus?.unfocus();

    // Clicking the sky calls down a meteor from roughly where you pointed —
    // random heading, speed and length, and now and then a second one chasing
    // it. Below the waterline the same click is a stone in the pond instead.
    if (local.dy <= horizonY) {
      final pair = _halcyonRnd(meteorSeed, 61) > .76;
      for (var i = 0; i < (pair ? 2 : 1); i++) {
        final s = meteorSeed++;
        model.addMeteor(_HalcyonMeteor(
          origin: local + Offset(_halcyonRnd(s, 62) * 70 - 35, _halcyonRnd(s, 63) * 44 - 30),
          born: model.time + i * .24,
          life: 1.0 + _halcyonRnd(s, 64) * .65,
          dir: _halcyonRnd(s, 65) > .5 ? 1 : -1,
          travel: sceneSize.width * (.34 + _halcyonRnd(s, 66) * .32),
          len: sceneSize.width * (.15 + _halcyonRnd(s, 67) * .15),
          slope: .26 + _halcyonRnd(s, 68) * .36,
        ));
      }
      return;
    }

    if (HcWater.on) {
      model.water.splash(local, model.time);
      return;
    }

    model.add(_HalcyonRipple(
      center: local,
      born: model.time,
      life: 3.4,
      maxRadius: 300,
      strength: 1,
      squash: squashAt(local.dy),
    ));
    model.add(_HalcyonRipple(
      center: local,
      born: model.time + .18,
      life: 2.2,
      maxRadius: 150,
      strength: .7,
      squash: squashAt(local.dy),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      sceneSize = Size(constraints.maxWidth, constraints.maxHeight);
      return MouseRegion(
        onHover: (e) => handleHover(e.localPosition),
        onExit: (_) => model.pointerInside = false,
        child: Listener(
          onPointerDown: (e) => handleTap(e.localPosition),
          child: Stack(children: [
            Positioned.fill(child: CustomPaint(painter: _HalcyonScenePainter(model, widget.bloom))),
            // The child is published the scene's model so anything inside it
            // can follow the same pointer the scene does — the card's tilt is
            // the only user today. See [_HalcyonTilt].
            if (widget.child != null)
              Positioned.fill(child: _HalcyonSceneScope(model: model, child: widget.child!)),
          ]),
        ),
      );
    });
  }
}

/// Publishes the live scene model to the widgets floating on top of it.
class _HalcyonSceneScope extends InheritedWidget {
  const _HalcyonSceneScope({required this.model, required super.child});

  final _HalcyonModel model;

  static _HalcyonModel? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_HalcyonSceneScope>()?.model;

  @override
  bool updateShouldNotify(_HalcyonSceneScope oldWidget) => oldWidget.model != model;
}

/// Claims a pointer-down for the card, so the scene underneath ignores it.
///
/// [Listener] takes no part in the gesture arena: an ancestor listener fires
/// for every pointer that lands anywhere inside it, whatever the widget under
/// the cursor does with the event. The scene's listener wraps the whole page -
/// it has to, or the card's own scroll view would eat every click before the
/// water saw it - so on its own it cannot tell "clicked the pond" from
/// "clicked into the password box". Both used to make a splash.
///
/// Pointer events travel from the deepest thing hit outwards, so this runs
/// first and can leave a note for the scene.
class _HalcyonSceneShield extends StatelessWidget {
  const _HalcyonSceneShield({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final model = _HalcyonSceneScope.maybeOf(context);
    return Listener(
      onPointerDown: (_) => model?.pointerOnCard = true,
      child: child,
    );
  }
}

/// Leans [child] toward the pointer in 3D.
///
/// READ THIS BEFORE EDITING. A pointer-driven tilt was put on this card twice
/// before and reverted both times: the thin-bordered translucent controls —
/// the Microsoft button most of all — visibly flickered while the mouse moved.
/// The cause was never the BackdropFilter (removing it did not help). It was
/// that the card was being *re-rasterised* every frame at a slightly different
/// sub-pixel position, so anti-aliasing along every hairline border landed
/// differently 60x a second.
///
/// What makes it safe this time is the [RepaintBoundary] below. It gives the
/// card its own compositing layer, so [Transform] pushes a transform layer and
/// hands the matrix to the GPU instead of repainting the card into a new
/// canvas — the card is rasterised once and the texture is moved. Two things
/// therefore matter more than they look:
///
///  * Keep the RepaintBoundary directly inside the Transform, and keep it in
///    AnimatedBuilder's `child` (built once) rather than in its builder.
///  * A live BackdropFilter *inside* the card defeats the cache — its backdrop
///    changes every frame, so the layer cannot be reused and the old flicker
///    can come back. The card only builds one when [kHalcyonCardBlur] > 0. If
///    you turn the blur back up and see shimmering, that is this, and the tilt
///    is the thing to give up, not the blur.
class _HalcyonTilt extends StatefulWidget {
  const _HalcyonTilt({required this.child});

  final Widget child;

  @override
  State<_HalcyonTilt> createState() => _HalcyonTiltState();
}

class _HalcyonTiltState extends State<_HalcyonTilt> {
  /// Where the card is leaning right now, as -1..1 on each axis. Driven from
  /// the scene's ticker rather than from setState, so following the pointer
  /// rebuilds nothing but the Transform.
  final ValueNotifier<Offset> lean = ValueNotifier(Offset.zero);
  _HalcyonModel? model;

  /// Whether something inside the card - in practice one of the two fields -
  /// holds the keyboard. While it does, the card levels out and stays level.
  ///
  /// Not cosmetic. The tilt is a 3D transform over the fields that changes on
  /// every frame the mouse moves, and on the web the engine has to keep the
  /// invisible <input> it types into sitting exactly on top of the field -
  /// which means re-projecting it through that matrix 60 times a second, with
  /// [Transform.transformHitTests] off, so Flutter's idea of where the field
  /// is and the browser's disagree by a few pixels the whole time. Both go
  /// away the moment the card is flat.
  bool typing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = _HalcyonSceneScope.maybeOf(context);
    if (next == model) return;
    model?.removeListener(follow);
    model = next;
    model?.addListener(follow);
  }

  @override
  void dispose() {
    model?.removeListener(follow);
    lean.dispose();
    super.dispose();
  }

  void follow() {
    final m = model;
    if (m == null) return;
    // Off the window, the card comes back to rest rather than freezing mid-lean.
    final target = (m.pointerInside && !typing)
        ? Offset((m.pointer.dx - .5) * 2, (m.pointer.dy - .5) * 2)
        : Offset.zero;
    final k = 1 - kHalcyonCardTiltEase.clamp(0.0, .99);
    final next = Offset(
      lean.value.dx + (target.dx - lean.value.dx) * k,
      lean.value.dy + (target.dy - lean.value.dy) * k,
    );
    // Parked (or as good as): stop pushing frames at the compositor.
    if ((next - lean.value).distance < .0004) return;
    lean.value = next;
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeDisableAnimationsOf(context) == true;
    if (still || kHalcyonCardTiltDegrees <= 0) return widget.child;
    // Watches only: it cannot be focused itself and is skipped by Tab, it just
    // reports when anything inside the card takes or gives up the keyboard.
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      // No setState: [follow] reads this on the scene's next tick, which is
      // the very next frame, and rebuilding the card here would rebuild the
      // field that just took focus.
      onFocusChange: (has) => typing = has,
      child: AnimatedBuilder(
        animation: lean,
        child: RepaintBoundary(child: widget.child),
        builder: (_, child) {
          final v = lean.value;
          final radians = kHalcyonCardTiltDegrees * pi / 180;
          return Transform(
            alignment: Alignment.center,
            // Hit-test against the card's UNTILTED rectangle. This is what stops
            // the "Sign in with Microsoft 365" button from strobing: with hit
            // tests transformed, every frame of lean slides the controls a
            // fraction of a pixel under a stationary cursor, so a pointer near
            // any edge falls in and out of the button dozens of times a second.
            // Each flip repaints it with a different fill AND a different border
            // (.11/.20 -> .17/.34) — by far the loudest hover state on the card,
            // which is why that one button strobed and nothing else did.
            // The cost is that the click target stays where the card would be at
            // rest: about 3-4 px off the drawn corners at the default 6 degrees,
            // far too little to feel. Raise kHalcyonCardTiltDegrees a lot and
            // that gap grows — the tilt, not this flag, is what to reconsider.
            transformHitTests: false,
            filterQuality: kHalcyonCardTiltFilter,
            // Pointer to the right leans the right edge away (rotate about Y);
            // pointer below leans the bottom away (rotate about X, negated so
            // the card tips toward the cursor rather than away from it).
            transform: Matrix4.identity()
              ..setEntry(3, 2, kHalcyonCardTiltPerspective)
              ..rotateX(-v.dy * radians)
              ..rotateY(v.dx * radians),
            child: child,
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Painter
// ---------------------------------------------------------------------------

class _HalcyonScenePainter extends CustomPainter {
  _HalcyonScenePainter(this.model, this.bloomScale) : super(repaint: model);

  final _HalcyonModel model;

  /// Multiplier on the central light — see [HalcyonScene.bloom].
  final double bloomScale;

  // Read fresh on every paint, not captured once: the tone turns over at noon
  // and the scene is repainting anyway.
  static Color get _skyTop => _HcPalette.skyTop;
  static Color get _skyMid => _HcPalette.skyMid;
  static Color get _skyLow => _HcPalette.skyLow;
  static Color get _skyHorizon => _HcPalette.skyHorizon;
  static Color get _bloom => _HcPalette.bloom;
  static Color get _bloomMid => _HcPalette.bloomMid;
  static Color get _accent => _HcPalette.accent;

  /// Where the gate stands. It drifts a hair with the pointer so the scene
  /// feels volumetric, which is why it is not simply the middle of the screen.
  double _cx(Size size) => size.width * .5 + (model.pointer.dx - .5) * 14;

  /// Everything ABOVE the waterline.
  ///
  /// Split out of [paint] because the simulated water reflects it: the scene
  /// state renders this into an offscreen image and the surface mirrors that.
  /// Nothing in here may read anything below the horizon, or the reflection
  /// would feed on itself.
  void paintSky(Canvas canvas, Size size, double horizon) {
    final t = model.time;
    final pointer = model.pointer;
    final pointerPx = Offset(pointer.dx * size.width, pointer.dy * size.height);
    final par = Offset(pointer.dx - .5, pointer.dy - .5);
    final cx = _cx(size);

    _sky(canvas, size, horizon);
    _nebula(canvas, size, horizon, t, par);
    _stars(canvas, size, horizon, t, par, pointerPx);
    _shootingStar(canvas, size, horizon, t);
    _meteors(canvas, t);
    if (model.pointerInside && pointer.dy < _kHalcyonHorizon + .04) {
      _glow(canvas, pointerPx, min(size.width, size.height) * .26, _accent.withValues(alpha: .13));
    }
    _horizonBloom(canvas, size, horizon, cx, t);
    _gate(canvas, size, horizon, cx, t);
    _mist(canvas, size, horizon, cx, t);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final w = size.width;
    final h = size.height;
    final t = model.time;
    final horizon = h * _kHalcyonHorizon;
    final waterH = h - horizon;
    final pointer = model.pointer;
    final pointerPx = Offset(pointer.dx * w, pointer.dy * h);
    final cx = _cx(size);

    paintSky(canvas, size, horizon);

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, horizon, w, waterH + 1));
    // The body of the water, under either surface.
    _waterBase(canvas, size, horizon);
    if (HcWater.on) {
      // The simulated surface. Everything the drawn one puts on the water —
      // the bloom, the gate's legs, the crest families, the glints, the rings —
      // is in the reflected sky instead, so none of it is drawn twice. Until
      // the first snapshot lands there is nothing to mirror and the water is
      // simply calm; see [_HalcyonWater.paint].
      model.water.paint(canvas, size, horizon, cx, t, model.skyImage, bloomScale);
    } else {
      _waterBloom(canvas, size, horizon, cx, t);
      _gateReflection(canvas, size, horizon, cx, t);
      _crests(canvas, size, horizon, cx, t);
      _starGlints(canvas, size, horizon, t);
      _ripples(canvas, t);
    }
    canvas.restore();

    _shoreline(canvas, size, horizon, cx, t);
    _motes(canvas, size, horizon, t, pointerPx);
    _vignette(canvas, size);
  }

  // -- sky ------------------------------------------------------------------

  void _sky(Canvas canvas, Size size, double horizon) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, horizon + 1),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(0, horizon),
          [_skyTop, _skyMid, _skyLow, _skyHorizon],
          const [0, .38, .74, 1],
        ),
    );
  }

  void _nebula(Canvas canvas, Size size, double horizon, double t, Offset par) {
    // x, y, radius, hue index, drift speed, opacity, horizontal stretch
    const List<List<double>> clouds = [
      [.13, .12, .40, 0, .045, 1.0, 1.5],
      [.85, .09, .36, 1, .037, 1.0, 1.4],
      [.50, .04, .32, 2, .028, .8, 1.9],
      [.04, .40, .26, 1, .052, .9, 1.3],
      [.96, .38, .28, 0, .041, .9, 1.3],
      [.31, .28, .20, 2, .033, .7, 1.6],
      [.68, .24, .18, 0, .049, .7, 1.7],
      [.44, .52, .16, 2, .057, .5, 2.2],
    ];
    final hues = [_HcPalette.nebulaA, _HcPalette.nebulaB, _HcPalette.nebulaC];
    for (var i = 0; i < clouds.length; i++) {
      final c = clouds[i];
      final drift = Offset(
        sin(t * c[4] * 2 * pi + i) * size.width * .035,
        cos(t * c[4] * 1.7 * pi + i * 1.3) * size.height * .022,
      );
      final center = Offset(c[0] * size.width, c[1] * horizon) + drift - par * 34 * (.4 + i * .12);
      final radius = c[2] * size.shortestSide;
      // Squashed horizontally so they read as cloud banks, not bubbles.
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.scale(c[6], 1 / c[6] * .85);
      canvas.drawCircle(
        Offset.zero,
        radius,
        Paint()
          ..color = hues[c[3].toInt()].withValues(alpha: .19 * c[5])
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * .5),
      );
      canvas.restore();
    }
  }

  void _stars(Canvas canvas, Size size, double horizon, double t, Offset par, Offset pointerPx) {
    final paint = Paint()..blendMode = BlendMode.plus;
    for (var i = 0; i < 210; i++) {
      final depth = .25 + _halcyonRnd(i, 9) * .75;
      final pos = Offset(
        _halcyonRnd(i) * size.width - par.dx * 20 * depth,
        _halcyonRnd(i, 1) * horizon * 1.02 - par.dy * 14 * depth,
      );
      if (pos.dy > horizon) continue;
      // Fade the field out as it approaches the bright horizon.
      final height = 1 - (pos.dy / horizon).clamp(0.0, 1.0);
      final twinkle =
          .42 + .58 * pow(sin(t * (.5 + _halcyonRnd(i, 2) * 1.5) + _halcyonRnd(i, 3) * 6.28), 2).toDouble();
      final near = max(0.0, 1 - (pos - pointerPx).distance / 240);
      final alpha =
          ((.18 + _halcyonRnd(i, 4) * .62) * twinkle * (.25 + height * .75) + near * .35).clamp(0.0, 1.0);
      final radius = .45 + _halcyonRnd(i, 5) * 1.15 + near * 1.1;
      paint.color =
          Color.lerp(_HcPalette.starWarm, _HcPalette.starCool, _halcyonRnd(i, 6))!.withValues(alpha: alpha);
      canvas.drawCircle(pos, radius, paint);
      // A few of them get a soft halo.
      if (i % 19 == 0) {
        _glow(canvas, pos, radius * 6, _HcPalette.starHalo.withValues(alpha: alpha * .40));
      }
    }
  }

  void _shootingStar(Canvas canvas, Size size, double horizon, double t) {
    const period = 11.0;
    const streak = 1.15;
    final cycle = (t / period).floor();
    final local = t - cycle * period;
    if (local > streak) return;
    final u = Curves.easeInOutSine.transform((local / streak).clamp(0.0, 1.0));
    final startX = _halcyonRnd(cycle, 31) * size.width * 1.1 - size.width * .05;
    final startY = _halcyonRnd(cycle, 32) * horizon * .45;
    final dir = _halcyonRnd(cycle, 33) > .5 ? 1.0 : -1.0;
    final len = size.width * (.22 + _halcyonRnd(cycle, 34) * .18);
    final travel = size.width * .55;
    final head = Offset(startX + dir * travel * u, startY + travel * u * .42);
    final tail = head - Offset(dir * len, len * .42);
    _streak(canvas, head, tail, sin(pi * u), 2.6);
  }

  /// Meteors summoned by clicking the sky.
  void _meteors(Canvas canvas, double t) {
    for (final m in model.meteors) {
      final age = (t - m.born) / m.life;
      if (age <= 0 || age >= 1) continue;
      final u = Curves.easeOutSine.transform(age);
      final head = m.origin + Offset(m.dir * m.travel * u, m.travel * u * m.slope);
      final tail = head - Offset(m.dir * m.len, m.len * m.slope);
      // Struck bright, then burning out — unlike the ambient one, which eases
      // in and out symmetrically.
      final fade = min(1.0, age * 9) * pow(1 - age, .85).toDouble();
      _streak(canvas, head, tail, fade, 3.4);
    }
  }

  /// A meteor: glowing head with a tail fading out behind it.
  void _streak(Canvas canvas, Offset head, Offset tail, double fade, double headSize) {
    if (fade <= .01) return;
    canvas.drawLine(
      tail,
      head,
      Paint()
        ..blendMode = BlendMode.plus
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 1.7
        ..shader = ui.Gradient.linear(tail, head, [
          _HcPalette.starCool.withValues(alpha: 0),
          _HcPalette.starCool.withValues(alpha: .45 * fade),
          Colors.white.withValues(alpha: .9 * fade),
        ], const [
          0,
          .55,
          1
        ]),
    );
    canvas.drawCircle(
      head,
      headSize,
      Paint()
        ..blendMode = BlendMode.plus
        ..color = Colors.white.withValues(alpha: .9 * fade)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    // A wider, softer halo so the head reads as burning, not as a dot.
    _glow(canvas, head, headSize * 5, _HcPalette.starHalo.withValues(alpha: .5 * fade));
  }

  // -- the gate -------------------------------------------------------------

  double _gateRx(Size size) => min(size.width * .30, size.height * .34);

  double _gateRy(Size size, double horizon) => min(horizon - size.height * .09, _gateRx(size) * 1.34);

  Path _gatePath(Size size, double horizon, double cx) {
    final rx = _gateRx(size);
    final ry = _gateRy(size, horizon);
    final oval = Rect.fromCenter(center: Offset(cx, horizon), width: rx * 2, height: ry * 2);
    // From the left foot, sweeping forward through 3pi/2 (screen-space top)
    // to the right foot — the upper half of the oval.
    return Path()..addArc(oval, pi, pi);
  }

  void _horizonBloom(Canvas canvas, Size size, double horizon, double cx, double t) {
    final pulse = 1 + sin(t * .55) * .04;
    final center = Offset(cx, horizon);
    _glow(canvas, center, size.width * .40 * pulse, _bloomMid.withValues(alpha: .26 * bloomScale));
    _glow(canvas, center, size.width * .20 * pulse, _bloom.withValues(alpha: .34 * bloomScale));
    // The white-hot core is what washes centred text out, so it fades fastest.
    _glow(canvas, center, size.width * .085 * pulse,
        Colors.white.withValues(alpha: .40 * bloomScale * bloomScale));
  }

  void _gate(Canvas canvas, Size size, double horizon, double cx, double t) {
    final path = _gatePath(size, horizon, cx);
    final rx = _gateRx(size);
    final ry = _gateRy(size, horizon);

    // Light pooled inside the arch — the gate reads as an opening, not a line.
    final inner = Path.from(path)
      ..lineTo(cx - rx, horizon)
      ..close();
    canvas.save();
    canvas.clipPath(inner);
    _glow(canvas, Offset(cx, horizon), ry * .95, _HcPalette.gateInner.withValues(alpha: .20 * bloomScale));
    canvas.restore();

    // Outer bloom, a dark frame to separate it from the sky, then the rim.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 30
        ..blendMode = BlendMode.plus
        ..color = _accent.withValues(alpha: .24)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = _HcPalette.gateFrame.withValues(alpha: .92)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..blendMode = BlendMode.plus
        ..color = _HcPalette.gateBloom.withValues(alpha: .34)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.7
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.linear(
          Offset(cx, horizon - ry),
          Offset(cx, horizon),
          [
            _HcPalette.gateRimTop.withValues(alpha: .95),
            _HcPalette.gateRimFoot.withValues(alpha: .62),
          ],
        ),
    );

    // Two highlights sliding around the rim, half a lap apart.
    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return;
    final metric = metrics.first;
    final len = metric.length;
    for (var k = 0; k < 2; k++) {
      final u = ((t * .09) + k * .5) % 1.0;
      final start = u * len;
      final seg = metric.extractPath(start, min(len, start + len * .11));
      canvas.drawPath(
        seg,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6
          ..strokeCap = StrokeCap.round
          ..blendMode = BlendMode.plus
          ..color = _HcPalette.gateShimmer.withValues(alpha: .45)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }
  }

  void _mist(Canvas canvas, Size size, double horizon, double cx, double t) {
    final band = size.height * .075;
    final sway = sin(t * .35) * size.width * .02;
    final radius = size.width * .55;
    canvas.save();
    canvas.translate(cx + sway, horizon);
    canvas.scale(1, band / radius);
    canvas.drawCircle(
      Offset.zero,
      radius,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.radial(Offset.zero, radius, [
          _HcPalette.mist.withValues(alpha: .16 * bloomScale),
          _HcPalette.mist.withValues(alpha: 0),
        ]),
    );
    canvas.restore();
  }

  // -- water ----------------------------------------------------------------

  void _waterBase(Canvas canvas, Size size, double horizon) {
    canvas.drawRect(
      Rect.fromLTWH(0, horizon, size.width, size.height - horizon),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, horizon),
          Offset(0, size.height),
          [_HcPalette.water0, _HcPalette.water1, _HcPalette.water2, _HcPalette.water3],
          const [0, .28, .68, 1],
        ),
    );
  }

  void _waterBloom(Canvas canvas, Size size, double horizon, double cx, double t) {
    final rx = size.width * .30;
    final ry = (size.height - horizon) * .82;
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
            _bloom.withValues(alpha: .32 * bloomScale),
            _bloomMid.withValues(alpha: .14 * bloomScale),
            _bloomMid.withValues(alpha: 0),
          ],
          const [0, .45, 1],
        ),
    );
    canvas.restore();
  }

  /// Horizontal displacement applied to anything floating on the surface at
  /// [p] by the live ripples — this is what makes the reflection wobble when
  /// a ring rolls through it.
  double _rippleShift(Offset p, double t) {
    if (model.ripples.isEmpty) return 0;
    var dx = 0.0;
    for (final r in model.ripples) {
      final age = (t - r.born) / r.life;
      if (age <= 0 || age >= 1) continue;
      final radius = Curves.easeOutCubic.transform(age) * r.maxRadius;
      final v = Offset(p.dx - r.center.dx, (p.dy - r.center.dy) / max(.05, r.squash));
      final dist = v.distance;
      final delta = dist - radius;
      const band = 30.0;
      if (delta.abs() > band) continue;
      final env = (1 - age) * (1 - delta.abs() / band) * r.strength;
      dx += (v.dx / max(dist, .001)) * sin(delta / band * pi) * 11 * env;
    }
    return dx;
  }

  void _gateReflection(Canvas canvas, Size size, double horizon, double cx, double t) {
    final rx = _gateRx(size);
    final waterH = size.height - horizon;
    for (var side = -1; side <= 1; side += 2) {
      final path = Path();
      const steps = 34;
      for (var i = 0; i <= steps; i++) {
        final u = i / steps;
        final y = horizon + u * waterH;
        // The legs fall away and spread a little as the surface nears us.
        final baseX = cx + side * rx * (1 + u * .30);
        final wobble = sin(y * .055 + t * 1.5 + side * 1.9) * (2.5 + u * 15) +
            sin(y * .021 - t * .9 + side) * (1.5 + u * 9);
        final x = baseX + wobble + _rippleShift(Offset(baseX, y), t);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.4
          ..strokeCap = StrokeCap.round
          ..shader = ui.Gradient.linear(
            Offset(0, horizon),
            Offset(0, size.height),
            [
              _HcPalette.reflect.withValues(alpha: .85),
              _HcPalette.reflect.withValues(alpha: .55),
              _HcPalette.reflect.withValues(alpha: 0),
            ],
            const [0, .55, 1],
          ),
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1
          ..blendMode = BlendMode.plus
          ..shader = ui.Gradient.linear(Offset(0, horizon), Offset(0, size.height), [
            _HcPalette.reflectGlow.withValues(alpha: .30),
            _HcPalette.reflectGlow.withValues(alpha: 0),
          ]),
      );
    }
  }

  /// One curved highlight lying on the water.
  void _crest(Canvas canvas, double cx, double y, double halfWidth, double bow, double thickness, Color color,
      double alpha, double t) {
    if (alpha <= .004 || halfWidth <= 2) return;
    const segments = 9;
    final p0 = Offset(cx - halfWidth, y);
    final p2 = Offset(cx + halfWidth, y);
    final ctrl = Offset(cx, y + bow);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..blendMode = BlendMode.plus
      ..strokeWidth = thickness;

    Offset at(double u) {
      final iu = 1 - u;
      final base = Offset(
        iu * iu * p0.dx + 2 * iu * u * ctrl.dx + u * u * p2.dx,
        iu * iu * p0.dy + 2 * iu * u * ctrl.dy + u * u * p2.dy,
      );
      return base.translate(_rippleShift(base, t), 0);
    }

    var prev = at(0);
    for (var i = 1; i <= segments; i++) {
      final u = i / segments;
      final next = at(u);
      // Bright in the middle, dissolving at both ends.
      final profile = sin(pi * (u - .5 / segments)).clamp(0.0, 1.0);
      paint.color = color.withValues(alpha: (alpha * profile).clamp(0.0, 1.0));
      canvas.drawLine(prev, next, paint);
      prev = next;
    }
  }

  void _crests(Canvas canvas, Size size, double horizon, double cx, double t) {
    final waterH = size.height - horizon;
    // Two interleaved families of concentric crests scrolling toward the
    // viewer at different rates — the surface never repeats visibly.
    for (var family = 0; family < 2; family++) {
      final count = family == 0 ? 22 : 12;
      final scroll = (t * (family == 0 ? .055 : .034) + family * .5) % 1.0;
      for (var i = 0; i < count; i++) {
        final d = (i + scroll) / count;
        if (d >= 1) continue;
        final y = horizon + pow(d, 1.65).toDouble() * waterH;
        if (y > size.height + 6) continue;
        final salt = family * 100 + i;
        // Narrow near the horizon, and scattering off the light column as the
        // surface comes closer — concentric rather than a stack of blinds.
        final spread = size.width * (.05 + d * .40) * (.55 + _halcyonRnd(salt, 11) * .8);
        final drift = sin(t * .55 + i * .9 + family) * (3 + d * 24) +
            (_halcyonRnd(salt, 12) - .5) * d * size.width * .22;
        final shimmer = .55 + .45 * sin(t * 1.25 + i * 1.7 + family * 2.1);
        // Fade out at the very top (crowded near the horizon) and at depth.
        final envelope = (d * 6).clamp(0.0, 1.0) * (1 - d * .72);
        // Keep some sparkle on the water even when the centre is turned down.
        final alpha = envelope * shimmer * (family == 0 ? .46 : .24) * (.45 + .55 * bloomScale);
        _crest(
          canvas,
          cx + drift,
          y,
          spread,
          4 + d * 40,
          1.1 + d * 4.2,
          Color.lerp(_bloom, _bloomMid, d * .8)!,
          alpha,
          t,
        );
      }
    }
  }

  void _starGlints(Canvas canvas, Size size, double horizon, double t) {
    final waterH = size.height - horizon;
    final paint = Paint()..blendMode = BlendMode.plus;
    for (var i = 0; i < 46; i++) {
      final d = _halcyonRnd(i, 41);
      final y = horizon + pow(d, 1.5).toDouble() * waterH;
      final x = _halcyonRnd(i, 42) * size.width + sin(t * .8 + i) * (2 + d * 10);
      final flicker = pow(sin(t * (1.1 + _halcyonRnd(i, 43)) + i * 2.3), 4).toDouble();
      paint.color = _HcPalette.glint.withValues(alpha: (.10 + flicker * .34) * (1 - d * .6));
      canvas.drawOval(
        Rect.fromCenter(center: Offset(x, y), width: 2.4 + d * 7, height: 1 + d * 1.4),
        paint,
      );
    }
  }

  void _ripples(Canvas canvas, double t) {
    for (final r in model.ripples) {
      final age = (t - r.born) / r.life;
      if (age <= 0 || age >= 1) continue;
      final radius = Curves.easeOutCubic.transform(age) * r.maxRadius;
      final fade = pow(1 - age, 1.7).toDouble();
      canvas.save();
      canvas.translate(r.center.dx, r.center.dy);
      canvas.scale(1, r.squash);
      for (var ring = 0; ring < 3; ring++) {
        final rr = radius - ring * 15.0;
        if (rr <= 3) continue;
        final alpha = (fade * r.strength * (.46 - ring * .13)).clamp(0.0, 1.0);
        if (alpha <= .004) continue;
        // The crest…
        canvas.drawCircle(
          Offset.zero,
          rr,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = (2.6 - ring * .6) * (1 - age * .45)
            ..blendMode = BlendMode.plus
            ..color = _HcPalette.rippleCrest.withValues(alpha: alpha),
        );
        // …and the shadowed trough just inside it.
        canvas.drawCircle(
          Offset.zero,
          rr - 4.5,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.2
            ..color = _HcPalette.rippleTrough.withValues(alpha: alpha * .45),
        );
      }
      canvas.restore();
    }
  }

  /// A thin bright seam right on the waterline — this is what sells "the sky
  /// is sitting on the water".
  void _shoreline(Canvas canvas, Size size, double horizon, double cx, double t) {
    final width = size.width * (.34 + sin(t * .5) * .015);
    canvas.drawRect(
      Rect.fromLTWH(cx - width * 1.6, horizon - 5, width * 3.2, 10),
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.linear(
          Offset(cx - width * 1.6, 0),
          Offset(cx + width * 1.6, 0),
          [
            Colors.white.withValues(alpha: 0),
            _HcPalette.shoreSoft.withValues(alpha: .22 * bloomScale),
            Colors.white.withValues(alpha: 0),
          ],
          const [0, .5, 1],
        )
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawRect(
      Rect.fromLTWH(cx - width, horizon - 1.1, width * 2, 2.2),
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.linear(
          Offset(cx - width, 0),
          Offset(cx + width, 0),
          [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: .55 * bloomScale),
            Colors.white.withValues(alpha: 0),
          ],
          const [0, .5, 1],
        )
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
    );
  }

  void _motes(Canvas canvas, Size size, double horizon, double t, Offset pointerPx) {
    final paint = Paint()..blendMode = BlendMode.plus;
    for (var i = 0; i < 30; i++) {
      final speed = .012 + _halcyonRnd(i, 51) * .02;
      final baseY = horizon * (.35 + _halcyonRnd(i, 52) * .68);
      // Slow rise, wrapping back down once they clear the top.
      final rise = ((t * speed + _halcyonRnd(i, 53)) % 1.0) * horizon * .55;
      var pos = Offset(
        _halcyonRnd(i, 54) * size.width + sin(t * (.25 + _halcyonRnd(i, 55) * .3) + i) * 26,
        baseY - rise,
      );
      if (pos.dy < 0) pos = Offset(pos.dx, pos.dy + horizon);
      // Motes shy away from the cursor.
      final away = pos - pointerPx;
      final dist = away.distance;
      if (dist < 130 && dist > .1) {
        pos += away / dist * (130 - dist) * .35;
      }
      final pulse = .35 + .65 * pow(sin(t * (.7 + _halcyonRnd(i, 56)) + i * 1.9), 2).toDouble();
      final radius = .9 + _halcyonRnd(i, 57) * 1.6;
      paint.color = _HcPalette.moteCore.withValues(alpha: .30 * pulse);
      canvas.drawCircle(pos, radius, paint);
      paint.color = _HcPalette.moteHalo.withValues(alpha: .16 * pulse);
      canvas.drawCircle(pos, radius * 3.4, paint);
    }
  }

  void _vignette(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(size.width * .5, size.height * .5),
          size.longestSide * .72,
          [
            Colors.transparent,
            _HcPalette.vignette.withValues(alpha: .30),
            _HcPalette.vignette.withValues(alpha: .62),
          ],
          const [0, .62, 1],
        ),
    );
  }

  void _glow(Canvas canvas, Offset center, double radius, Color color) {
    if (radius <= 0) return;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.radial(center, radius, [color, color.withValues(alpha: 0)]),
    );
  }

  @override
  bool shouldRepaint(covariant _HalcyonScenePainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// The sign-in card
// ---------------------------------------------------------------------------

/// Dark-glass input styling — [dsInput] is built for white cards.
InputDecoration _halcyonInput({IconData? icon, Widget? suffix, String? errorText, String? hint}) {
  OutlineInputBorder side(Color color, double width) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color, width: width),
      );
  return InputDecoration(
    hintText: hint,
    hintStyle:
        TextStyle(color: Colors.white.withValues(alpha: .34), fontSize: 13, fontWeight: FontWeight.w400),
    prefixIcon: icon == null ? null : Icon(icon, size: 19, color: _HcPalette.inputIcon),
    suffixIcon: suffix,
    errorText: errorText,
    errorStyle: const TextStyle(color: _HcPalette.errorText, fontSize: 11.5, fontWeight: FontWeight.w500),
    isDense: true,
    filled: true,
    fillColor: Colors.white.withValues(alpha: kHalcyonFieldFill),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    border: side(Colors.white.withValues(alpha: .16), 1.2),
    enabledBorder: side(Colors.white.withValues(alpha: .16), 1.2),
    focusedBorder: side(_HcPalette.inputFocus, 1.6),
    errorBorder: side(_HcPalette.errorLine, 1.3),
    focusedErrorBorder: side(_HcPalette.errorLine, 1.7),
  );
}

class _HalcyonLabel extends StatelessWidget {
  const _HalcyonLabel({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 7, left: 2),
        child: Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.1,
            color: Colors.white.withValues(alpha: .60),
          ),
        ),
      ),
      child,
    ]);
  }
}

/// Gradient (primary) or outlined (secondary) button that lifts on hover.
class _HalcyonButton extends StatefulWidget {
  const _HalcyonButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.leading,
    this.primary = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Widget? leading;
  final bool primary;

  @override
  State<_HalcyonButton> createState() => _HalcyonButtonState();
}

class _HalcyonButtonState extends State<_HalcyonButton> {
  bool hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final lift = enabled && hover;
    return MouseRegion(
      onEnter: (_) => setState(() => hover = true),
      onExit: (_) => setState(() => hover = false),
      child: AnimatedScale(
        scale: lift ? 1.02 : 1,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        child: AnimatedOpacity(
          opacity: enabled ? 1 : .45,
          duration: const Duration(milliseconds: 160),
          // Animated rather than a plain DecoratedBox: the scale beside it has
          // always eased over 160 ms while the fill and border snapped, and on
          // the secondary button those two are the whole hover state. Easing
          // them means that even if something does manage to flip `hover`
          // rapidly, the button crossfades instead of strobing.
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              gradient: widget.primary
                  ? LinearGradient(colors: [_HcPalette.buttonA, _HcPalette.buttonB])
                  : null,
              color: widget.primary ? null : Colors.white.withValues(alpha: hover ? .17 : .11),
              borderRadius: BorderRadius.circular(12),
              border: widget.primary
                  ? null
                  : Border.all(color: Colors.white.withValues(alpha: hover ? .34 : .20), width: 1.2),
              boxShadow: widget.primary
                  ? [
                      BoxShadow(
                        color: _HcPalette.buttonGlow.withValues(alpha: lift ? .55 : .34),
                        blurRadius: lift ? 30 : 20,
                        offset: const Offset(0, 10),
                      )
                    ]
                  : null,
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: widget.onPressed,
                child: SizedBox(
                  height: 48,
                  child: Center(
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (widget.leading != null)
                        widget.leading!
                      else if (widget.icon != null)
                        Icon(widget.icon, size: 19, color: Colors.white),
                      if (widget.leading != null || widget.icon != null) const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          widget.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            letterSpacing: .2,
                          ),
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Service status chip in the scene's palette.
class _HalcyonPill extends StatelessWidget {
  const _HalcyonPill({required this.label, required this.ok, required this.description});

  final String label;
  final bool ok;
  final String description;

  @override
  Widget build(BuildContext context) {
    final color = ok ? const Color(0xff6ee7b7) : const Color(0xfffcd34d);
    return Tooltip(
      message:
          '$label — $description\nStatus: ${ok ? 'online (working normally)' : 'offline (not reachable)'}',
      waitDuration: const Duration(milliseconds: 300),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: .14)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: color.withValues(alpha: .8), blurRadius: 7)],
            ),
          ),
          const SizedBox(width: 7),
          Text(
            '$label ${ok ? 'online' : 'offline'}',
            style: TextStyle(
                fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: .82)),
          ),
        ]),
      ),
    );
  }
}

/// The whole login stage: scene + frosted card. Wired to the shell's existing
/// controllers and callbacks, so the sign-in behaviour is unchanged.
class HalcyonLoginPage extends StatelessWidget {
  const HalcyonLoginPage({
    super.key,
    required this.email,
    required this.password,
    required this.passwordFocus,
    required this.obscurePassword,
    required this.onToggleObscure,
    required this.emailError,
    required this.passwordError,
    required this.onEmailChanged,
    required this.onPasswordChanged,
    required this.onEmailSubmitted,
    required this.busy,
    required this.microsoftEnabled,
    required this.onLogin,
    required this.onMicrosoftLogin,
    required this.apiOnline,
    required this.sqlOnline,
  });

  final TextEditingController email;
  final TextEditingController password;
  final FocusNode passwordFocus;
  final bool obscurePassword;
  final VoidCallback onToggleObscure;
  final String? emailError;
  final String? passwordError;
  final VoidCallback onEmailChanged;
  final VoidCallback onPasswordChanged;
  final VoidCallback onEmailSubmitted;
  final bool busy;
  final bool microsoftEnabled;
  final VoidCallback onLogin;
  final VoidCallback onMicrosoftLogin;
  final bool apiOnline;
  final bool sqlOnline;

  @override
  Widget build(BuildContext context) {
    const textStyle = TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500);

    final glass = Container(
      padding: const EdgeInsets.fromLTRB(30, 32, 30, 28),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: kHalcyonCardTintTop),
            Colors.white.withValues(alpha: kHalcyonCardTintBottom),
          ],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: kHalcyonCardBorder), width: 1.2),
        boxShadow: [
          BoxShadow(color: _HcPalette.cardShadow, blurRadius: 60, offset: const Offset(0, 28)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The same TPK × Automation lockup the splash uses. The TPK mark
          // is dark navy, so it keeps its white tile — on the glass alone
          // it disappears.
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              width: 72,
              height: 72,
              alignment: Alignment.center,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(19),
                boxShadow: const [
                  BoxShadow(color: Color(0x59060b28), blurRadius: 26, offset: Offset(0, 12)),
                ],
              ),
              // Both marks are far larger than the 52 px they land in
              // (Automation_Logo is 500x500), and Image's default
              // FilterQuality.low is plain bilinear: at a ~7x minification it
              // samples far too few texels, which reads as a blurry, shimmering
              // logo — worse here because the tilt resamples the card once more.
              // `medium` is mipmapped and costs nothing at this size.
              child: Image.asset('logo_tpk.png',
                  fit: BoxFit.contain, filterQuality: FilterQuality.medium),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 15),
              child: Text('×',
                  style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w300,
                      color: Color(0xb3ffffff),
                      shadows: [Shadow(color: Color(0x66000000), blurRadius: 8)])),
            ),
            Container(
              width: 72,
              height: 72,
              alignment: Alignment.center,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(19),
                boxShadow: const [
                  BoxShadow(color: Color(0x59060b28), blurRadius: 26, offset: Offset(0, 12)),
                ],
              ),
              child: Image.asset('Automation_Logo.png',
                  fit: BoxFit.contain, filterQuality: FilterQuality.medium),
            ),
            // const AutomationLogoMark(size: 72),
          ]),
          const SizedBox(height: 22),
          const Text(
            'Purchase Shipment Alert',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: -.3,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            'Import PO follow-up & shipment alerts',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: Colors.white.withValues(alpha: .62), height: 1.4),
          ),
          const SizedBox(height: 26),
          _HalcyonLabel(
            label: 'Email / Employee no',
            child: TextField(
              controller: email,
              style: textStyle,
              cursorColor: _HcPalette.cursor,
              textInputAction: TextInputAction.next,
              onChanged: (_) => onEmailChanged(),
              onSubmitted: (_) => onEmailSubmitted(),
              decoration: _halcyonInput(icon: Icons.badge_outlined, errorText: emailError),
            ),
          ),
          const SizedBox(height: 15),
          _HalcyonLabel(
            label: 'Password',
            child: TextField(
              controller: password,
              focusNode: passwordFocus,
              style: textStyle,
              cursorColor: _HcPalette.cursor,
              obscureText: obscurePassword,
              textInputAction: TextInputAction.done,
              onChanged: (_) => onPasswordChanged(),
              onSubmitted: (_) {
                if (!busy) onLogin();
              },
              decoration: _halcyonInput(
                icon: Icons.lock_outline,
                errorText: passwordError,
                // Excluded from focus so that revealing the password does
                // not take the keyboard away from the field it belongs to.
                // The shell hands focus back explicitly as well - see
                // toggleObscurePassword in app_shell.dart.
                suffix: ExcludeFocus(
                  child: IconButton(
                    onPressed: onToggleObscure,
                    icon: Icon(
                      obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      size: 19,
                      color: _HcPalette.eyeIcon,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          _HalcyonButton(
            label: 'Login',
            icon: Icons.login,
            primary: true,
            onPressed: busy ? null : onLogin,
          ),
          const SizedBox(height: 11),
          _HalcyonButton(
            label: 'Sign in with Microsoft 365',
            leading: const _MicrosoftLogo(size: 17),
            onPressed: (busy || !microsoftEnabled) ? null : onMicrosoftLogin,
          ),
          const SizedBox(height: 20),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              // Online presence stays off the pre-login page on purpose —
              // it would leak who is signed in to anyone who loads it.
              _HalcyonPill(label: 'API', ok: apiOnline, description: dsApiPillDescription),
              _HalcyonPill(label: 'SQL', ok: sqlOnline, description: dsSqlPillDescription),
            ],
          ),
        ],
      ),
    );

    // With the blur off there is nothing for a BackdropFilter to do, and
    // leaving one in would cost the card its cached raster layer — which is
    // exactly what keeps the tilt from shimmering. See [_HalcyonTilt].
    final card = ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: kHalcyonCardBlur > 0
          ? BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: kHalcyonCardBlur, sigmaY: kHalcyonCardBlur),
              child: glass,
            )
          : glass,
    );

    return Scaffold(
      backgroundColor: _HcPalette.pageBg,
      body: HalcyonScene(
        child: Stack(children: [
          Positioned.fill(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  // Settles into place on first paint.
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 900),
                    curve: Curves.easeOutCubic,
                    builder: (_, v, child) => Opacity(
                      opacity: v,
                      child: Transform.translate(offset: Offset(0, (1 - v) * 26), child: child),
                    ),
                    child: _HalcyonSceneShield(child: _HalcyonTilt(child: card)),
                  ),
                ),
              ),
            ),
          ),
          // Which water the scene is running. Sits above the card's stage so a
          // click on it is a click on the switch, not a stone in the pond.
          const Positioned(
              right: 20, top: 16, child: _HalcyonSceneShield(child: HalcyonWaterToggle())),
          Positioned(
            right: 20,
            bottom: 16,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.precision_manufacturing_outlined,
                  size: 15, color: Colors.white.withValues(alpha: .5)),
              const SizedBox(width: 7),
              Text(
                'Developed by Automation Department',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .62),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  letterSpacing: .2,
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Microsoft's four-square mark for the "Sign in with Microsoft 365" button.
class _MicrosoftLogo extends StatelessWidget {
  const _MicrosoftLogo({this.size = 17});

  final double size;

  @override
  Widget build(BuildContext context) {
    // Snapped to whole pixels: these four saturated squares are the only
    // hard-edged thing on the card, and sub-pixel edges shimmer while the card
    // leans (see [_HalcyonTilt]).
    final gap = max(1.0, (size / 9).roundToDouble());
    final cell = ((size - gap) / 2).floorToDouble();
    Widget square(Color color) => Container(
          width: cell,
          height: cell,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(.5)),
        );
    return SizedBox(
      width: cell * 2 + gap,
      height: cell * 2 + gap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            square(const Color(0xfff25022)),
            square(const Color(0xff7fba00)),
          ]),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            square(const Color(0xff00a4ef)),
            square(const Color(0xffffb900)),
          ]),
        ],
      ),
    );
  }
}
