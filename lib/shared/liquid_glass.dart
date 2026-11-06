part of '../main.dart';

/// The app's SECOND face: liquid glass.
///
/// This does not replace the flat glassmorphism theme — it sits beside it. Every
/// surface that can wear both asks [Lg.on] first and falls back to the original
/// look when it says no, so the old theme stays reachable for a machine that
/// can't afford the extra strokes. Nothing here is deleted when the flag flips;
/// see [Lg.enabled] for how to expose it as a switch.
///
/// ── What is being reproduced, and what is being faked ──────────────────────
///
/// The reference is `liquid_glass.html` at the repo root. There the glass is
/// real refraction: a rounded-rectangle SDF is baked into a displacement map and
/// pushed through `backdrop-filter: url(#filter)`, so the pane bends the actual
/// pixels behind it.
///
/// That FILTER does not exist here. This is Flutter Web on CanvasKit (Skia):
/// `backdrop-filter: url(#…)` is a browser feature and `ui.ImageFilter.shader` —
/// its Flutter counterpart — is Impeller-only.
///
/// The refraction itself does exist here, though, and it is real. It is done
/// with [Canvas.drawVertices] instead: a texture coordinate per vertex IS a
/// displacement map, so the same SDF and the same droplet dome drive the same
/// bend. See [LiquidDrop] for the engine, [LiquidField] for the background it
/// bends — which the whole thing lives or dies on — and [paintLiquidRim] for the
/// light along the edge, which is the background brightened and dimmed, never a
/// colour laid on top.
///
/// The one thing that is genuinely lost: a drop bends the BACKGROUND, not other
/// widgets sitting behind it. In this app those are the same thing nearly
/// everywhere — cards sit on the field, not on each other.
class Lg {
  Lg._();

  /// The master switch. A `ValueNotifier` rather than a `const` so the top bar's
  /// toggle can flip it at runtime; [RequestAndPlanningApp] listens and rebuilds
  /// the whole tree from it.
  ///
  /// The choice sticks. It is a preference about how the machine in front of you
  /// copes, not a per-session mood, so it lives in `localStorage` and is read
  /// back before the first frame — see [restore].
  static final ValueNotifier<bool> enabled = ValueNotifier<bool>(true)..addListener(_remember);

  static bool get on => enabled.value;

  static const String _key = 'rap.liquidGlass';

  /// The colorful theme is the only one now (the top bar's "plain grey"
  /// toggle is gone). A browser that still remembers "off" from that toggle
  /// is put back on. Call once, before `runApp`.
  static void restore() {
    try {
      if (html.window.localStorage[_key] == '0') html.window.localStorage.remove(_key);
    } catch (_) {}
    enabled.value = true;
  }

  static void _remember() {
    try {
      html.window.localStorage[_key] = enabled.value ? '1' : '0';
    } catch (_) {
      // Private-mode browsers refuse to write. The theme still works; it just
      // forgets, which is not worth taking the app down for.
    }
  }

  // ── The reference panel's values, light mode ──────────────────────────────
  // These are the numbers the control panel in liquid_glass.html was left on:
  // refraction ON, animated background OFF.

  /// `distortion` — how hard the lens pulls at the rim. Drives the peak
  /// brightness of the band, since a stronger pull squeezes more background
  /// into the same few pixels.
  static const double distortion = .62;

  /// `distortionWidth` — how far the lens reaches in from the edge, in px. The
  /// VISIBLE ring is a fraction of it: the reference takes
  /// `min(distortionWidth * .55, 20)`, which at 70 px lands on [rimBand].
  static const double distortionWidth = 70;

  /// `magnification` — the whole pane's optical power. Nothing on CanvasKit can
  /// magnify a backdrop, so this is spent on the rim instead: a stronger lens
  /// widens the band and lifts the crisp inner highlight.
  static const double magnification = 1.06;

  /// `chromaticAberration` — the slider's own 0..1 value (the panel displays it
  /// as 0.0011 after scaling). Sets the warm/cool fringe on opposite edges.
  static const double chromatic = .38;

  /// `blur` — deliberately tiny in the reference, because the glassiness comes
  /// from the refraction and not from frosting. At 3 px over this app's smooth
  /// ambient wash a BackdropFilter would return the wash unchanged at the cost
  /// of re-reading the window every frame, so cards don't take one; only the
  /// chrome that content actually scrolls under does. See [DsFrosted].
  static const double blur = 3;

  /// `saturation` — the lift the backdrop gets through the glass.
  static const double saturation = 1.5;

  /// `lightIntensity` — how hard the rim is lit. In the reference this is a
  /// gain on the refracted backdrop (`1 + light * 1.15` bright,
  /// `1 - light * .7` dark); here it is the alpha of the painted band.
  static const double light = .70;

  /// Bake the branch PHOTOGRAPH into [LiquidField] instead of the synthetic
  /// field, as this theme did until 2026-08-13.
  ///
  /// **Kept on purpose, and off on purpose.** Glass on a photograph is the
  /// closest this has come to the reference — that is what the source package's
  /// own examples do, the drops had a real image to bend, and the rim took its
  /// colour from the roofs and trees behind it. It is off because it was never
  /// usable for a working day: small grey type over an aerial photo is hard to
  /// read however much the lens is lightened, and every attempt to fix that
  /// ended up veiling the photograph into the grey it was brought in to replace.
  ///
  /// **What this flag does and does not restore.** It restores the BACKGROUND
  /// only — the photo at [BranchBackdrop._decodeWidth]'s larger size with a
  /// single 18 % haze, no synthetic field. It does NOT restore the theme as a
  /// whole as it stood then, and turning it on will not look like those
  /// screenshots: the surfaces above it have moved on since, and those changes
  /// are shared with the current look rather than gated. At that point
  /// [DsGlassShell] still laid a pane across the window, [lgGlass] filled with a
  /// three-stop rake instead of a flat tint, [lgShadow] threw 24 px instead of
  /// 5, and the approval / kanban cards sat at 55 % white instead of 88 %.
  /// Together those read considerably softer and hazier than this flag alone
  /// will give you. There is no snapshot of that state — it was never committed.
  static const bool photoField = false;

  /// The visible bright ring, in px — `min(distortionWidth * .55, 20)`.
  static const double rimBand = 20;

  /// Corner radius. The reference is built on droplet radii (`--r-lg: 32px`)
  /// where this app is built on 20, so every radius is scaled and capped rather
  /// than restated at ~200 call sites. Radii never affect layout, only paint,
  /// so this is safe to apply blind.
  static double r(double radius, {double max = 32}) => on ? min(radius * 1.6, max) : radius;

  /// The rim band for a pane of [size]: capped so a 38 px control gets a rim
  /// proportional to itself instead of a 20 px band swallowing it whole.
  static double bandFor(double shortestSide) => min(rimBand, shortestSide * .34);
}

// ═══════════════════════════════════════════════════════════════════════════
// THE FIELD — what the glass has to look at
// ═══════════════════════════════════════════════════════════════════════════

/// The scenes [LiquidField] can bake. Picked on the profile page's
/// Appearance tab; see [LgScene].
///
/// [classic] is the system's own default and stays FIRST, in this list and so
/// on the picker — whatever else is added, the way back is the first tile.
enum LgBackdrop {
  classic('Default', 'The system’s own field — colour pools, light curves and rings', LiquidField.fieldLift),
  aurora('Aurora silk', 'Pastel aurora crossed by twisting ribbons of fine light', Color(0x1affffff)),
  contour('Contour', 'Soft gradient drawn over with topographic lines', Color(0x1affffff)),
  bubbles('Bubbles', 'Floating glass bubbles over a soft haze', Color(0x1fffffff));

  const LgBackdrop(this.label, this.blurb, this.lift);

  final String label;
  final String blurb;

  /// The white veil laid over the finished scene — how pale the page reads.
  /// The newer scenes are built lighter to begin with, so they take less.
  final Color lift;
}

/// A colour set the patterned scenes can be painted in. [original] — each
/// scene's own colours — is first and the default, for the same reason as
/// [LgBackdrop.classic].
///
/// [accents] are six saturated colours in a fixed order — main, cool partner,
/// third, warm partner, light, deep — so every scene can ask for "the main
/// colour" or "the warm one" and get a sensible answer from any tone. [base]
/// is three near-white tints for the ground under them.
enum LgTone {
  original('Original', null, null),
  lavender('Lavender', [0xfff2eefe, 0xffefedfd, 0xfff4effc],
      [0xff8b7cf6, 0xff818cf8, 0xffc084fc, 0xfff0a1d6, 0xffa78bfa, 0xff6d7cf0]),
  ocean('Ocean', [0xffeaf3fd, 0xffe8f1fc, 0xffe9f6fa],
      [0xff3b9eea, 0xff22c3d6, 0xff5b7cf0, 0xff38bdf8, 0xff2dd4bf, 0xff3f6fd8]),
  mint('Mint', [0xffebf8f3, 0xffeaf6f1, 0xffeef9ee],
      [0xff34c79a, 0xff4cc9c0, 0xff84d65a, 0xff2fb5a5, 0xffa3d977, 0xff1f9e7e]),
  sunset('Sunset', [0xfffdf2ec, 0xfffcefee, 0xfffdf4e9],
      [0xfffb923c, 0xfff472b6, 0xfffbbf24, 0xfff87171, 0xfffda4af, 0xffe0762c]),
  rose('Rose', [0xfffdeff4, 0xfffbedf3, 0xfffcf0f6],
      [0xfff472b6, 0xffe879f9, 0xfffb7185, 0xfff9a8d4, 0xffc084fc, 0xffdb4b8f]),
  sky('Sky', [0xffeef6fe, 0xffeef3fe, 0xfff1f8fd],
      [0xff60a5fa, 0xff93c5fd, 0xff7dd3fc, 0xffa5b4fc, 0xffbae6fd, 0xff3b82f6]),
  graphite('Graphite', [0xfff1f2f5, 0xffeef0f3, 0xfff2f3f5],
      [0xff8b93a7, 0xff9aa3b5, 0xff6b7489, 0xffa3abbd, 0xffb4bac8, 0xff5d6578]);

  const LgTone(this.label, this.base, this.accents);

  final String label;
  final List<int>? base;
  final List<int>? accents;
}

/// What is behind the glass: the pattern and its colour tone. Preferences about
/// the machine in front of you, like [Lg.enabled], so they live in
/// `localStorage`.
class LgScene {
  LgScene._();

  static final ValueNotifier<LgBackdrop> current = ValueNotifier<LgBackdrop>(LgBackdrop.classic);
  static final ValueNotifier<LgTone> tone = ValueNotifier<LgTone>(LgTone.original);

  /// Everything a bake depends on, so one notifier change re-bakes.
  static Listenable get changes => Listenable.merge([current, tone]);

  static const String _key = 'psa.backdrop';
  static const String _toneKey = 'psa.backdropTone';

  /// Reads the remembered choice and starts listening. Call once, before
  /// `runApp`.
  static void restore() {
    try {
      final store = html.window.localStorage;
      // A name that is no longer offered (the plain-colour scene, removed
      // 2026-11-04) matches nothing here and leaves the default in place.
      for (final s in LgBackdrop.values) {
        if (s.name == store[_key]) current.value = s;
      }
      for (final t in LgTone.values) {
        if (t.name == store[_toneKey]) tone.value = t;
      }
      // Write back what was actually applied, so a stale name is replaced.
      if (store.containsKey(_key)) store[_key] = current.value.name;
      if (store.containsKey(_toneKey)) store[_toneKey] = tone.value.name;
      store.remove('psa.backdropColor');
    } catch (_) {}
    changes.addListener(() {
      try {
        final store = html.window.localStorage;
        store[_key] = current.value.name;
        store[_toneKey] = tone.value.name;
      } catch (_) {
        // Private-mode browsers refuse to write; the choice just won't stick.
      }
      // Re-bake; [_DsAmbientPainter] repaints when [LiquidField.version] bumps.
      LiquidField.ensure();
    });
  }

  /// Identifies one bake.
  static String keyFor(LgBackdrop style, LgTone tone) => '${style.name}|${tone.name}';

  static String get currentKey => keyFor(current.value, tone.value);
}

/// The patterned background the drops sit on, baked once into an image.
///
/// This is not decoration. It is the single thing the whole theme depends on,
/// and the reference says so twice over: *"พื้นหลังต้องมีลาย ไม่งั้นต่อให้หักเห
/// แรงแค่ไหนก็มองไม่เห็น"*, and again after a failed round — *"ปัญหาไม่ได้อยู่ที่
/// ว่ามีการหักเหหรือไม่ แต่พื้นหลังผมเป็นสีไล่เรียบ ๆ ต่อให้เลนส์แรงแค่ไหนก็ไม่มี
/// อะไรให้บิดให้เห็น"*.
///
/// The same trap catches the RIM, which is why the edges kept coming out white
/// no matter how carefully they were blended: a rim made by brightening the
/// backdrop can only be white if the backdrop is already near-white. Over a
/// pale grey wash, `1.8 × colour` clips to paper. Over a mid-tone violet it
/// comes out a lighter violet — a coloured edge, from the background, which is
/// the entire point.
///
/// So the wash is replaced with the reference's own painted field: a coloured
/// base, six soft blobs at real saturation, bezier light curves, nested rings, a
/// dot grid and grain. Baked ONCE into a [ui.Image] (the reference bakes it to a
/// data URL for the same reason) and blitted every frame — the alternative is
/// four thousand draw calls per repaint, and this painter repaints on every
/// mouse move.
class LiquidField {
  LiquidField._();

  /// 1500 × 1100, the reference's own canvas size. Drawn cover-fitted, so the
  /// composition spreads with the window instead of tiling.
  // The reference bakes 1500 × 1100. This is smaller on purpose: the sharp copy
  // is only ever drawn cover-fitted behind everything, and the copy the drops
  // read is blurred by 12 anyway, so the extra pixels buy nothing and cost two
  // `toImage` calls on the frame the theme is switched.
  static const int _w = 1000;
  static const int _h = 740;

  static ui.Image? _image;
  static ui.Image? _blurred;
  static bool _baking = false;
  // Only meaningful with [Lg.photoField] on: which photo the current bake used.
  static ui.Image? _bakedPhoto;
  // Which [LgScene.currentKey] the current bake drew.
  static String? _bakedKey;

  /// Bumped when the bake lands, so painters listening to it repaint.
  static final ValueNotifier<int> version = ValueNotifier<int>(0);

  static ui.Image? get image => _image;

  /// What a DROP samples, as opposed to what the page shows.
  ///
  /// Looking through glass is not looking through a window: the thickness
  /// scatters what is behind it. Baking a blurred twin of the field and sampling
  /// THAT inside the drops does three things at once —
  ///
  /// * it is what finally makes small grey type readable, because the ground
  ///   under a label stops being an aerial photograph and becomes a wash;
  /// * it is what makes the glass legible AS glass, since sharp outside the drop
  ///   against soft inside it is the whole tell;
  /// * and it costs nothing per frame. The reference pays for its `blur(3px)`
  ///   on every backdrop read; this is baked once beside the sharp copy.
  ///
  /// The refraction still shows, because a bent gradient is still visibly bent.
  static ui.Image? get lens => _blurred ?? _image;

  /// The viewport the field was last drawn across.
  ///
  /// Every drop needs it. A drop refracts THE BACKGROUND, so it has to sample
  /// the same image at the same place the page is showing it — and it is painted
  /// far away from the painter that put it there. [_DsAmbientPainter] writes it
  /// once per frame, before any drop paints.
  static Size viewport = Size.zero;

  /// Image space → screen space. Cover-fit, so the composition spreads with the
  /// window instead of tiling.
  ///
  /// No pointer drift. The flat theme's wash lags the cursor by a few pixels for
  /// depth; here the background holds still, because every drop samples it
  /// through this one transform — moving it means re-refracting the whole page
  /// on every mouse move, and it reads as the floor sliding under the glass.
  static Float64List coverMatrix() {
    final image = _image;
    if (image == null || viewport.isEmpty) return Matrix4.identity().storage;
    final scale = max(viewport.width / image.width, viewport.height / image.height);
    final w = image.width * scale, h = image.height * scale;
    return (Matrix4.identity()
          ..translateByDouble((viewport.width - w) / 2, (viewport.height - h) / 2, 0, 1)
          ..scaleByDouble(scale, scale, 1, 1))
        .storage;
  }

  /// Kicks the bake off the first time anything asks for the field. Once only,
  /// unless [Lg.photoField] is on — then again whenever the branch changes.
  static void ensure() {
    final photo = Lg.photoField ? BranchBackdrop.image.value : null;
    final key = LgScene.currentKey;
    if (_baking || (_image != null && identical(photo, _bakedPhoto) && key == _bakedKey)) return;
    _baking = true;
    _bakedPhoto = photo;
    _bakedKey = key;
    final recorder = ui.PictureRecorder();
    _paint(Canvas(recorder), Size(_w.toDouble(), _h.toDouble()), photo);
    unawaited(() async {
      try {
        final sharp = await recorder.endRecording().toImage(_w, _h);
        _image = sharp;
        // The twin the drops look through — see [lens]: blurred and lifted, so a
        // drop is quiet enough to carry type while the PAGE keeps the field
        // sharp. Sharp outside, soft inside: that contrast is what reads as
        // glass, and it is the only thing that does now that both are the same
        // picture.
        final blurRecorder = ui.PictureRecorder();
        final blurCanvas = Canvas(blurRecorder);
        blurCanvas.drawImage(
          sharp,
          Offset.zero,
          Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12, tileMode: TileMode.clamp),
        );
        // ── DIAL 1 of 2 for how milky the glass looks. ──
        // How far the inside of a drop is lifted toward paper. Raise it and the
        // whole app fogs over; drop it to zero and a drop is just a blurred
        // window. The type scale was darkened so this could stay low.
        blurCanvas.drawRect(
          Offset.zero & Size(_w.toDouble(), _h.toDouble()),
          Paint()..color = const Color(0x45ffffff), // 27 %
        );
        _blurred = await blurRecorder.endRecording().toImage(_w, _h);
        version.value++;
      } finally {
        _baking = false;
        // The scene was changed again while this one was baking — catch up.
        if (LgScene.currentKey != _bakedKey) ensure();
      }
    }());
  }

  /// The reference's `rng` — a plain LCG, seeded the same, so the composition
  /// comes out identical to the HTML rather than merely similar.
  static double Function() _rng(int seed) {
    var s = seed;
    return () {
      s = (s * 1664525 + 1013904223) & 0xFFFFFFFF;
      return s / 4294967296;
    };
  }

  static void _paint(Canvas canvas, Size size, ui.Image? photo) {
    final w = size.width, h = size.height;

    // ── The photo-backed field, kept behind [Lg.photoField]. ──
    //
    // The whole field is the branch photograph and one light haze — no gradient,
    // no blobs, no line work. A photograph already has more for a lens to bend
    // than any of that could invent, and painting a gradient over a photograph
    // is a stain on a photograph.
    //
    // It is baked in here rather than drawn underneath because a drop samples
    // ONE image: anything a drop should be able to bend has to be inside it.
    if (photo != null) {
      final scale = max(w / photo.width, h / photo.height);
      final pw = photo.width * scale, ph = photo.height * scale;
      canvas.drawImageRect(
        photo,
        Offset.zero & Size(photo.width.toDouble(), photo.height.toDouble()),
        Rect.fromLTWH((w - pw) / 2, (h - ph) / 2, pw, ph),
        Paint()..filterQuality = FilterQuality.high,
      );
      // Takes the top off its contrast without touching its detail. Readability
      // is not paid for here — that is [lens]'s job — so it stays light.
      canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0x2effffff)); // 18 %
      return;
    }

    // ── The synthetic field: whichever scene [LgScene] has picked. ──
    paintScene(canvas, size, LgScene.current.value);
  }

  /// Draws [style] cover-fitted across [size] — the bake, and the picker's
  /// thumbnails, which is why it is public: the tile you click is the same
  /// picture the page will get, only smaller. [tone] defaults to what
  /// [LgScene] holds now.
  static void paintScene(Canvas canvas, Size size, LgBackdrop style, {LgTone? tone}) {
    final scale = max(size.width / _w, size.height / _h);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate((size.width - _w * scale) / 2, (size.height - _h * scale) / 2);
    canvas.scale(scale);
    canvas.drawPicture(_picture(style, tone ?? LgScene.tone.value));
    canvas.restore();
  }

  /// Each scene × tone recorded once, at the bake's own size. Contour in
  /// particular is a marching-squares pass over the whole field — it should be
  /// paid for once, not every time a thumbnail repaints.
  static final Map<String, ui.Picture> _pictures = {};

  static ui.Picture _picture(LgBackdrop style, LgTone tone) =>
      _pictures[LgScene.keyFor(style, tone)] ??= () {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        final size = Size(_w.toDouble(), _h.toDouble());
        switch (style) {
          case LgBackdrop.classic:
            _paintClassic(canvas, size, tone);
          case LgBackdrop.aurora:
            _paintAurora(canvas, size, tone);
          case LgBackdrop.contour:
            _paintContour(canvas, size, tone);
          case LgBackdrop.bubbles:
            _paintBubbles(canvas, size, tone);
        }
        // See the lightening dial at the end of [_paintClassic].
        canvas.drawRect(Offset.zero & size, Paint()..color = style.lift);
        return recorder.endRecording();
      }();

  /// A scene's colours under [tone]: the tone's own if it has them, otherwise
  /// the scene's [fallback] — which is what [LgTone.original] means.
  static List<Color> _accents(LgTone tone, List<int> fallback) =>
      [for (final v in tone.accents ?? fallback) Color(v)];
  static List<Color> _base(LgTone tone, List<int> fallback) => [for (final v in tone.base ?? fallback) Color(v)];

  static void _paintClassic(Canvas canvas, Size size, LgTone tone) {
    final w = size.width, h = size.height;
    final rnd = _rng(20260812);
    final base = _base(tone, const [0xfff0f2fd, 0xffe9edfa]);
    final accents =
        _accents(tone, const [0xff7f8cff, 0xffc77bff, 0xff46cfc4, 0xffff89b0, 0xffffc069, 0xff8f9dff]);

    // ── The original synthetic field. ──
    //
    // A working day is spent on these pages, and a picture of the plant behind
    // every table is a lot of picture to look at. This is the reference's own
    // field, built for exactly this job — enough colour and enough line work to
    // show a lens doing something, and nothing that asks to be looked at.
    //
    // Light mode only, so `source-over` throughout — the reference's dark theme
    // uses `lighter`, and using it here is what bleaches a light field to white
    // ("ธีมสว่างต้องใช้ source-over ไม่งั้นสีบวกกันจนฟอกเป็นขาว").
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          // The base, lifted 2026-08-21 from e4e8fa→d8def5. This pair is the
          // BLUE the user was seeing: it covers the whole window, so it sets the
          // page's cast on its own before a single blob is drawn.
          colors: base,
        ).createShader(Rect.fromLTWH(0, 0, w * .3, h)),
    );

    const spots = [
      [.16, .10, .62],
      [.86, .16, .52],
      [.24, .44, .50],
      [.94, .60, .50],
      [.42, .86, .55],
      [.66, .98, .45],
    ];
    // The six pools' colours come from [accents] (the original six unless a
    // tone is picked); their weights stay the composition's own.
    const blobAlpha = [.55, .50, .42, .46, .36, .44];
    for (var i = 0; i < blobAlpha.length; i++) {
      final x = spots[i][0] * w, y = spots[i][1] * h, r = spots[i][2] * w * .72;
      final color = accents[i].withValues(alpha: blobAlpha[i] * blobStrength);
      final rect = Rect.fromCircle(center: Offset(x, y), radius: r);
      canvas.drawCircle(
        Offset(x, y),
        r,
        Paint()
          ..shader = RadialGradient(colors: [color, color.withValues(alpha: 0)])
              .createShader(rect),
      );
    }

    // ── The detail. This is what a lens actually bends. ──
    const lineAlpha = .6;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Sweeping light curves.
    for (var i = 0; i < 26; i++) {
      final y0 = rnd() * h;
      final len = (.3 + rnd() * .8) * w;
      final x0 = rnd() * w - len * .3;
      stroke
        ..color = Colors.white.withValues(alpha: lineAlpha * (.25 + rnd() * .75))
        ..strokeWidth = rnd() < .3 ? 2 : 1;
      canvas.drawPath(
        Path()
          ..moveTo(x0, y0)
          ..cubicTo(
            x0 + len * .3, y0 - 90 + rnd() * 180, //
            x0 + len * .7, y0 - 90 + rnd() * 180, //
            x0 + len, y0 - 60 + rnd() * 120,
          ),
        stroke,
      );
    }

    // Nested rings.
    stroke
      ..color = Colors.white.withValues(alpha: lineAlpha * .5)
      ..strokeWidth = 1;
    for (var i = 0; i < 7; i++) {
      final cx = rnd() * w, cy = rnd() * h, r0 = 60 + rnd() * 260;
      for (var k = 0; k < 5; k++) {
        canvas.drawCircle(Offset(cx, cy), r0 + k * 16, stroke);
      }
    }

    // Dot grid.
    final dot = Paint()..color = Colors.white.withValues(alpha: .34);
    for (var y = 12.0; y < h; y += 34) {
      for (var x = 12.0; x < w; x += 34) {
        canvas.drawRect(Rect.fromLTWH(x, y, 1.6, 1.6), dot);
      }
    }

    // Grain. Per-pixel in the reference; here it is a scatter of specks, which
    // is the same job — give flat areas something to show a distortion with.
    final speck = Paint();
    for (var i = 0; i < 2600; i++) {
      final v = rnd();
      speck.color = (v < .5 ? Colors.black : Colors.white).withValues(alpha: .03 + rnd() * .04);
      canvas.drawRect(Rect.fromLTWH(rnd() * w, rnd() * h, 1.4, 1.4), speck);
    }

    // ── THE LIGHTENING DIAL — how pale the page reads. ──
    //
    // Everything above is the reference's composition, and the reference is a
    // showcase page: a few big glass panels on a rich field, where the field is
    // meant to be looked at. A working screen is the opposite — tables, 11 px
    // labels, a nav column — and against that the same field came out heavy
    // ("มันเข้มไป").
    //
    // One veil over the finished field rather than a re-tune of the gradient,
    // six blob alphas, the line work and the grain: the composition stays
    // exactly as designed and there is a single number to turn. Raise it and
    // the page keeps going toward paper; drop it to zero for the reference's
    // own weight.
    //
    // It goes on the BAKED image, so the drops bend a lightened field too —
    // the page and the glass on it stay the same picture, which is the one
    // thing this whole theme rests on.
    //
    // The veil itself is laid in [_picture], per scene — see [LgBackdrop.lift].
  }

  // ═══════════════════════════════════════════════════════════════════════
  // The newer scenes (2026-11). All three keep what the classic field taught:
  // a lens needs LINE WORK to bend, and the rims need a mid-tone to brighten.
  // What changes is the line work — one idea per scene instead of curves,
  // rings, dots and blobs all at once — so the page reads calmer and the
  // refraction reads stronger.
  // ═══════════════════════════════════════════════════════════════════════

  /// Shared by every scene: a fine scatter of specks, so flat areas still give
  /// a lens something to distort.
  static void _grain(Canvas canvas, Size size, double Function() rnd, {int count = 2600}) {
    final speck = Paint();
    for (var i = 0; i < count; i++) {
      final v = rnd();
      speck.color = (v < .5 ? Colors.black : Colors.white).withValues(alpha: .025 + rnd() * .035);
      canvas.drawRect(Rect.fromLTWH(rnd() * size.width, rnd() * size.height, 1.4, 1.4), speck);
    }
  }

  /// Soft colour pools, positions as fractions of the field and the radius as
  /// a fraction of its width.
  ///
  /// [geometry] is `[x, y, radius, alpha]` per pool; [colors] are matched to
  /// it in order.
  static void _pools(Canvas canvas, Size size, List<List<double>> geometry, List<Color> colors) {
    for (var i = 0; i < geometry.length; i++) {
      final p = geometry[i];
      final c = Offset(p[0] * size.width, p[1] * size.height);
      final r = p[2] * size.width;
      final color = colors[i % colors.length].withValues(alpha: p[3]);
      final rect = Rect.fromCircle(center: c, radius: r);
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [color, color.withValues(alpha: color.a * .45), color.withValues(alpha: 0)],
            stops: const [0, .5, 1],
          ).createShader(rect),
      );
    }
  }

  /// ── AURORA SILK ──
  ///
  /// A pastel aurora with three twisting ribbons of fine parallel strands
  /// running across it. Parallel lines are the best thing there is for showing
  /// refraction — a lens bends a bundle of them into a visible curve — and a
  /// ribbon gathers them where the page wants movement instead of spreading
  /// clutter everywhere.
  static void _paintAurora(Canvas canvas, Size size, LgTone tone) {
    final w = size.width, h = size.height;
    final rnd = _rng(20261104);
    final a = tone.accents == null ? null : _accents(tone, const []);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _base(tone, const [0xfff2eefe, 0xffedf1fd, 0xfff0f6fc]),
        ).createShader(Offset.zero & size),
    );
    _pools(
      canvas,
      size,
      const [
        [.06, .10, .58, .40],
        [.94, .16, .50, .34],
        [.52, .50, .40, .18],
        [.16, .94, .52, .28],
        [.86, .98, .54, .32],
      ],
      a == null
          ? const [Color(0xff9b87f5), Color(0xff7cc4f8), Color(0xffc6a5fa), Color(0xff7ddccd), Color(0xfff4a6cc)]
          : [a[0], a[1], a[2], a[4], a[3]],
    );
    final ribbons =
        a == null ? const [Color(0xff8b7cf6), Color(0xff5ab4ee), Color(0xffef8bbf)] : [a[0], a[1], a[3]];

    void ribbon({
      required double y0,
      required double amp,
      required double freq,
      required double phase,
      required double half,
      required double twist,
      required double twistPhase,
      required Color tint,
      required double strength,
      int strands = 34,
    }) {
      const step = 6.0;
      const tau = 2 * pi;
      double spine(double x) =>
          y0 + amp * sin(freq * x / w * tau + phase) + amp * .32 * sin(freq * 2.3 * x / w * tau + phase * 1.7);
      // The half-width swings through zero — that is the twist, where every
      // strand crosses at one point and the ribbon turns over.
      double off(double x) => half * cos(twist * x / w * tau + twistPhase);

      // The body: a faint wash of the ribbon's colour between its two edges.
      final body = Path()..moveTo(-20, spine(-20) + off(-20));
      for (var x = -20.0 + step; x <= w + 20; x += step) {
        body.lineTo(x, spine(x) + off(x));
      }
      for (var x = w + 20; x >= -20; x -= step) {
        body.lineTo(x, spine(x) - off(x));
      }
      body.close();
      canvas.drawPath(body, Paint()..color = tint.withValues(alpha: .2 * strength));

      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..isAntiAlias = true;
      for (var i = 0; i < strands; i++) {
        final t = -1 + 2 * i / (strands - 1);
        // White on a pale page is invisible, so the strands carry the ribbon's
        // own colour through the middle and turn to bright white at the edges,
        // like light catching the fold of a sheet.
        final edge = t * t;
        stroke.color = Color.lerp(tint, Colors.white, .35 + .65 * edge)!
            .withValues(alpha: (.3 + .55 * edge) * strength);
        final path = Path()..moveTo(-20, spine(-20) + t * off(-20));
        for (var x = -20.0 + step; x <= w + 20; x += step) {
          path.lineTo(x, spine(x) + t * off(x));
        }
        canvas.drawPath(path, stroke);
      }
    }

    ribbon(
        y0: h * .28, amp: 70, freq: .8, phase: .6, half: 82, twist: 1.1, twistPhase: .3,
        tint: ribbons[0], strength: 1);
    ribbon(
        y0: h * .64, amp: 88, freq: .6, phase: 2.4, half: 106, twist: .8, twistPhase: 1.9,
        tint: ribbons[1], strength: .95);
    ribbon(
        y0: h * .9, amp: 46, freq: 1, phase: 4.1, half: 58, twist: 1.4, twistPhase: .9,
        tint: ribbons[2], strength: .75, strands: 26);

    // Where the light comes from: a soft lift in the top-left.
    final sheen = Rect.fromCircle(center: Offset(w * .22, -h * .12), radius: w * .7);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const RadialGradient(colors: [Color(0x59ffffff), Color(0x00ffffff)])
            .createShader(sheen),
    );
    _grain(canvas, size, rnd);
  }

  /// ── CONTOUR ──
  ///
  /// A soft pastel gradient drawn over with topographic lines — iso-lines of a
  /// smooth height field, every fifth one heavier, the way a survey map marks
  /// its index contours. Closed, nested, never crossing: the calmest line work
  /// there is, and a drop sliding over it pulls the rings visibly out of shape.
  static void _paintContour(Canvas canvas, Size size, LgTone tone) {
    final w = size.width, h = size.height;
    final rnd = _rng(7340211);
    final a = tone.accents == null ? null : _accents(tone, const []);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _base(tone, const [0xffeeeafd, 0xfff1eefc, 0xffe8f3fb]),
        ).createShader(Offset.zero & size),
    );
    _pools(
      canvas,
      size,
      const [
        [.10, .16, .52, .34],
        [.80, .06, .42, .26],
        [.90, .78, .52, .28],
        [.30, .98, .46, .26],
      ],
      a == null
          ? const [Color(0xff9d8af6), Color(0xffffc49e), Color(0xff6fd3c6), Color(0xfff4a2c8)]
          : [a[0], a[3], a[1], a[2]],
    );
    // The ink: the tone's deep colour, or the original violet.
    final ink = a == null ? const Color(0xff6d5fd6) : a[5];

    // The height field: a handful of hills and hollows plus one long swell.
    final hills = [
      for (var i = 0; i < 9; i++)
        [rnd() * w, rnd() * h, 90 + rnd() * 210, (rnd() < .35 ? -1 : 1) * (.5 + rnd())],
    ];
    double f(double x, double y) {
      var v = .14 * sin(x / w * 5 + y / h * 3);
      for (final hl in hills) {
        final dx = x - hl[0], dy = y - hl[1], s = hl[2];
        v += hl[3] * exp(-(dx * dx + dy * dy) / (2 * s * s));
      }
      return v;
    }

    const step = 5.0;
    final cols = (w / step).ceil() + 1, rows = (h / step).ceil() + 1;
    final g = Float64List(cols * rows);
    var lo = double.infinity, hi = -double.infinity;
    for (var j = 0; j < rows; j++) {
      for (var i = 0; i < cols; i++) {
        final v = f(i * step, j * step);
        g[j * cols + i] = v;
        if (v < lo) lo = v;
        if (v > hi) hi = v;
      }
    }

    // Marching squares, one path per level.
    const levels = 26;
    // Ink, not light: a white line on a page this pale disappears, so the lines
    // are a faint violet, the way a survey map prints its contours. The index
    // lines also get a white highlight beside them, which reads as a ridge.
    final thin = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = ink.withValues(alpha: .2);
    final bold = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = ink.withValues(alpha: .34);
    final ridge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = Colors.white.withValues(alpha: .85);
    for (var k = 1; k < levels; k++) {
      final level = lo + (hi - lo) * k / levels;
      final path = Path();
      for (var j = 0; j < rows - 1; j++) {
        for (var i = 0; i < cols - 1; i++) {
          final tl = g[j * cols + i], tr = g[j * cols + i + 1];
          final bl = g[(j + 1) * cols + i], br = g[(j + 1) * cols + i + 1];
          final code = (tl > level ? 8 : 0) | (tr > level ? 4 : 0) | (br > level ? 2 : 0) | (bl > level ? 1 : 0);
          if (code == 0 || code == 15) continue;
          final x0 = i * step, y0 = j * step, x1 = x0 + step, y1 = y0 + step;
          Offset edge(int e) => switch (e) {
                0 => Offset(x0 + step * (level - tl) / (tr - tl), y0), // top
                1 => Offset(x1, y0 + step * (level - tr) / (br - tr)), // right
                2 => Offset(x0 + step * (level - bl) / (br - bl), y1), // bottom
                _ => Offset(x0, y0 + step * (level - tl) / (bl - tl)), // left
              };
          void seg(int a, int b) {
            final p = edge(a), q = edge(b);
            path
              ..moveTo(p.dx, p.dy)
              ..lineTo(q.dx, q.dy);
          }

          switch (code) {
            case 1 || 14:
              seg(3, 2);
            case 2 || 13:
              seg(2, 1);
            case 3 || 12:
              seg(3, 1);
            case 4 || 11:
              seg(0, 1);
            case 6 || 9:
              seg(0, 2);
            case 7 || 8:
              seg(3, 0);
            case 5:
              seg(3, 0);
              seg(2, 1);
            case 10:
              seg(0, 1);
              seg(3, 2);
          }
        }
      }
      if (k % 5 == 0) {
        canvas.drawPath(path.shift(const Offset(-1.2, -1.2)), ridge);
        canvas.drawPath(path, bold);
      } else {
        canvas.drawPath(path, thin);
      }
    }
    _grain(canvas, size, rnd, count: 2000);
  }

  /// ── BUBBLES ──
  ///
  /// Glass bubbles floating over a lilac haze, with a few out-of-focus ones
  /// behind for depth. The theme's own vocabulary — a drop of glass on the page
  /// looking at drops of glass in the background — and each bubble is a crisp
  /// bright ring, which is exactly what a lens shows off best.
  static void _paintBubbles(Canvas canvas, Size size, LgTone tone) {
    final w = size.width, h = size.height;
    final rnd = _rng(4242026);
    final a = tone.accents == null ? null : _accents(tone, const []);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: _base(tone, const [0xfff1effe, 0xffeaf0fd]),
        ).createShader(Offset.zero & size),
    );
    _pools(
      canvas,
      size,
      const [
        [.12, .18, .55, .36],
        [.88, .22, .46, .30],
        [.70, .92, .52, .30],
        [.20, .90, .44, .26],
      ],
      a == null
          ? const [Color(0xff8f86f4), Color(0xff6fc6ef), Color(0xfff19ccb), Color(0xff86dccf)]
          : [a[0], a[1], a[3], a[2]],
    );

    final tints = a == null
        ? const [Color(0xff7c6cf0), Color(0xff4fb2e8), Color(0xffe882b8), Color(0xff4cc3b2)]
        : [a[5], a[1], a[3], a[2]];

    // Far away and out of focus.
    for (var i = 0; i < 14; i++) {
      final r = 40 + rnd() * 120;
      final c = Offset(rnd() * w, rnd() * h);
      final tint = i.isEven ? Colors.white : tints[i % tints.length];
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = tint.withValues(alpha: i.isEven ? .28 : .12)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * .22),
      );
    }

    // In focus. Big ones first, so the small ones sit on top.
    final bubbles = [
      for (var i = 0; i < 34; i++) (Offset(rnd() * w, rnd() * h), 8 + pow(rnd(), 2) * 92.0, tints[i % tints.length]),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    for (final (c, r, tint) in bubbles) {
      final rect = Rect.fromCircle(center: c, radius: r);
      // Clear in the middle, tinted toward the edge — the way a sphere of
      // glass looks, thicker the more obliquely you look through it.
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-.25, -.3),
            colors: [
              Colors.white.withValues(alpha: .14),
              tint.withValues(alpha: .07),
              tint.withValues(alpha: .24),
            ],
            stops: const [0, .7, 1],
          ).createShader(rect),
      );
      // The rim, and a coloured inner edge just inside it.
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r > 30 ? 1.4 : 1
          ..color = Colors.white.withValues(alpha: .8),
      );
      if (r > 14) {
        canvas.drawCircle(
          c,
          r - 2.4,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = tint.withValues(alpha: .3),
        );
      }
      // The specular: a bright arc on the upper left, a faint one opposite.
      final arc = rect.deflate(r * .2);
      canvas.drawArc(
        arc,
        pi * 1.05,
        pi * .42,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = max(1.2, r * .07)
          ..color = Colors.white.withValues(alpha: .85),
      );
      canvas.drawArc(
        rect.deflate(r * .12),
        pi * .12,
        pi * .3,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = max(1, r * .035)
          ..color = Colors.white.withValues(alpha: .4),
      );
    }

    // A few pinpricks of light between them.
    final spark = Paint()..color = Colors.white.withValues(alpha: .6);
    for (var i = 0; i < 70; i++) {
      canvas.drawCircle(Offset(rnd() * w, rnd() * h), .8 + rnd() * 1.4, spark);
    }
    _grain(canvas, size, rnd, count: 2000);
  }

  /// ── DIAL: how strong the COLOUR is. ──
  ///
  /// Scales all six blob alphas at once — the blue, purple, teal, pink, amber
  /// and indigo pools of [_paint]. The reference's own values (.36–.55) are set
  /// for a page whose job is to show off a lens; behind a working table the same
  /// pools read as tinted patches ("สีพื้นหลังที่เป็นฟ้า ชมพู … มันเข้มไป").
  ///
  /// Separate from [fieldLift] on purpose, because they are different
  /// complaints: [fieldLift] is how DARK the page is, this is how COLOURED it
  /// is. Whitening a page to fix colour costs contrast everywhere and still
  /// leaves the pools showing; thinning the pools leaves the whites white.
  ///
  /// The line work, grain and gradient are untouched — a lens still has plenty
  /// to bend, it is just bending something paler.
  static const blobStrength = .5;

  /// See the dial at the end of [_paint].
  static const fieldLift = Color(0x3dffffff); // 24 %
}

// ═══════════════════════════════════════════════════════════════════════════
// THE REFRACTION
// ═══════════════════════════════════════════════════════════════════════════

/// A drop of water, doing what a drop of water does to what is under it.
///
/// This is the reference's engine, moved from an SVG filter onto a triangle
/// mesh, because the SVG route does not exist here: `feDisplacementMap` in a
/// `backdrop-filter` is a browser feature, and `ui.ImageFilter.shader` — the
/// Flutter equivalent — is Impeller-only, where this app is CanvasKit.
///
/// What IS available is [Canvas.drawVertices], which takes a position per
/// vertex and a texture coordinate per vertex. That is a displacement map by
/// another name: put the background in an [ui.ImageShader], then hand each
/// vertex a texture coordinate pulled AWAY from where it sits, and Skia
/// interpolates the bend across the triangle. Same maths, same dome, real
/// refraction — and no backdrop read at all, which makes it cheaper than the
/// blur it replaces.
///
/// The maths is the reference's, term for term (§1.1 of the brief):
///
/// * signed distance to a rounded rectangle, giving depth `d` and surface
///   normal `n`;
/// * the droplet dome — `t` runs 0 at the top of the dome to 1 at the rim, and
///   the surface slope of a sphere is `t / √(1 - t²)`, so the middle of the drop
///   barely bends and the last few pixels bend hard. This is what makes it a
///   drop and not a flat tile with rounded corners;
/// * sampling along **+n**, outward — *"ดูดภาพจากนอกกรอบเข้ามา"*. Pulling inward
///   gives a thin, tidy edge; pulling outward is what makes the rim look thick
///   and puts the world outside the card visibly squeezed into it;
/// * plus magnification, which pulls every sample toward the centre.
///
/// The one thing it cannot bend is other WIDGETS behind the drop — it samples
/// the background image, not the live scene. In this app that is the same thing
/// nearly everywhere: cards sit on the field, not on each other.
class LiquidDrop extends SingleChildRenderObjectWidget {
  const LiquidDrop({super.key, required this.radius, this.strength = 1, super.child});

  final double radius;
  final double strength;

  @override
  RenderLiquidDrop createRenderObject(BuildContext context) =>
      RenderLiquidDrop(radius: radius, strength: strength);

  @override
  void updateRenderObject(BuildContext context, RenderLiquidDrop renderObject) {
    renderObject
      ..radius = radius
      ..strength = strength;
  }
}

class RenderLiquidDrop extends RenderProxyBox {
  RenderLiquidDrop({required double radius, required double strength})
      : _radius = radius,
        _strength = strength;

  double _radius;
  set radius(double value) {
    if (_radius == value) return;
    _radius = value;
    markNeedsPaint();
  }

  double _strength;
  set strength(double value) {
    if (_strength == value) return;
    _strength = value;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    LiquidField.version.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    LiquidField.version.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final image = LiquidField.lens;
    final canvas = context.canvas;
    if (image != null && !size.isEmpty && LiquidField.viewport.width > 0) {
      // Where this drop sits on the page, so it samples the background at the
      // place the page is actually showing it.
      final origin = localToGlobal(Offset.zero);
      final corner = min(_radius, min(size.width, size.height) / 2);
      canvas.save();
      // Everything below is in the drop's OWN coordinates, which is what lets
      // the mesh be cached: it then depends only on the drop's size and corner,
      // not on where the page has scrolled it to.
      canvas.translate(offset.dx, offset.dy);
      canvas.clipRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(corner)),
        doAntiAlias: true,
      );
      // …and the page offset moves to the SHADER instead. Sampling at a local
      // texture coordinate `t` has to return the background at page point
      // `origin + t`, which is the cover transform pre-translated by -origin.
      final shaderMatrix = Matrix4.identity()
        ..translateByDouble(-origin.dx, -origin.dy, 0, 1)
        ..multiply(Matrix4.fromFloat64List(LiquidField.coverMatrix()));
      canvas.drawVertices(
        _mesh(corner),
        BlendMode.srcOver,
        Paint()
          ..filterQuality = FilterQuality.medium
          ..shader = ui.ImageShader(
            image,
            TileMode.clamp,
            TileMode.clamp,
            shaderMatrix.storage,
            filterQuality: FilterQuality.medium,
          ),
      );
      canvas.restore();
    }
    super.paint(context, offset);
  }

  /// One grid of triangles across the drop, each vertex carrying the texture
  /// coordinate the lens pulls it to.
  ///
  /// The grid is finer along the short side than the long one, and is dense
  /// enough that the bend near the rim reads as a curve. Straight interpolation
  /// between vertices is fine everywhere else, because everywhere else the drop
  /// is nearly flat.
  /// The mesh only changes when the drop's shape does, so it is built once and
  /// kept. Rebuilding forty rows of trigonometry on every scroll frame is the
  /// difference between this being cheaper than the blur it replaced and being
  /// far more expensive.
  ui.Vertices? _cached;
  Size? _cachedSize;
  double? _cachedCorner;

  ui.Vertices _mesh(double corner) {
    if (_cached != null && _cachedSize == size && _cachedCorner == corner) return _cached!;
    _cachedSize = size;
    _cachedCorner = corner;
    return _cached = _buildMesh(corner);
  }

  ui.Vertices _buildMesh(double corner) {
    final w = size.width, h = size.height;
    final cols = max(6, min(40, (w / 7).round()));
    final rows = max(6, min(40, (h / 7).round()));

    final hw = w / 2, hh = h / 2;
    // The lens band, and the furthest a sample is ever pulled. Both capped the
    // way the reference caps them: a band wider than half the short side eats
    // the clear middle, and a pull much past the band gives a smear instead of
    // a lens.
    final band = min(Lg.distortionWidth, min(w, h) * .5);
    final maxPull = min(Lg.distortion * 74, band * 1.5) * _strength;
    final invMag = 1 / Lg.magnification - 1;

    final count = (cols + 1) * (rows + 1);
    final positions = Float32List(count * 2);
    final texture = Float32List(count * 2);

    var v = 0;
    for (var iy = 0; iy <= rows; iy++) {
      final y = h * iy / rows;
      final py = y - hh;
      final qy = py.abs() - (hh - corner);
      for (var ix = 0; ix <= cols; ix++) {
        final x = w * ix / cols;
        final px = x - hw;
        final qx = px.abs() - (hw - corner);

        // Signed distance to the rounded rectangle, and the surface normal.
        final mx = max(qx, 0.0), my = max(qy, 0.0);
        final d = sqrt(mx * mx + my * my) + min(max(qx, qy), 0.0) - corner;
        double nx = 0, ny = 0;
        if (qx > 0 && qy > 0) {
          final l = sqrt(mx * mx + my * my);
          if (l > 0) {
            nx = mx / l;
            ny = my / l;
          }
        } else if (qx > qy) {
          nx = 1;
        } else {
          ny = 1;
        }
        nx *= px < 0 ? -1 : 1;
        ny *= py < 0 ? -1 : 1;

        // The dome: 0 at the top of the drop, 1 at the rim.
        var t = 0.0;
        if (d < 0 && d > -band) {
          t = 1 + d / band;
        } else if (d >= 0) {
          t = 1;
        }
        final slope = t / sqrt(max(1e-3, 1 - t * t));
        final pull = min(maxPull, maxPull * slope * .5);

        var dx = nx * pull + px * invMag;
        var dy = ny * pull + py * invMag;
        dx = dx.clamp(-maxPull, maxPull);
        dy = dy.clamp(-maxPull, maxPull);

        positions[v] = x;
        positions[v + 1] = y;
        texture[v] = x + dx;
        texture[v + 1] = y + dy;
        v += 2;
      }
    }

    final indices = Uint16List(cols * rows * 6);
    var i = 0;
    for (var iy = 0; iy < rows; iy++) {
      for (var ix = 0; ix < cols; ix++) {
        final a = iy * (cols + 1) + ix;
        final b = a + 1;
        final c = a + cols + 1;
        final e = c + 1;
        indices[i] = a;
        indices[i + 1] = b;
        indices[i + 2] = c;
        indices[i + 3] = b;
        indices[i + 4] = e;
        indices[i + 5] = c;
        i += 6;
      }
    }

    return ui.Vertices.raw(
      ui.VertexMode.triangles,
      positions,
      textureCoordinates: texture,
      indices: indices,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// THE RIM
// ═══════════════════════════════════════════════════════════════════════════

/// Paints the lens edge of a pane of liquid glass inside [rrect].
///
/// **Nothing here paints a colour.** That is the whole design of it, and it is
/// what the reference is emphatic about: *"ขอบไม่ได้ทาสีขาว แต่เป็นการเร่ง/หรี่
/// พื้นหลังที่หักเหแล้ว สีขอบจึงมาจากสิ่งที่อยู่ข้างหลังเสมอ"* — the edge is not
/// painted white, it is the already-refracted background turned up and down, so
/// the colour of the edge always comes from whatever is behind it.
///
/// A white line over glass is paint on glass. So this is one line and it is a
/// DARKENING — [BlendMode.multiply], the reference's `1 - light × .7`, the light
/// bending away off the far side of the dome. Over the violet field the edge
/// comes out violet; over the branch photo it comes out whatever the photo is.
///
/// See the comment in the body for why the reference's bright half is absent
/// rather than merely faint.
void paintLiquidRim(
  Canvas canvas,
  RRect rrect, {
  double band = Lg.rimBand,
  double light = Lg.light,

  /// Overall multiplier. Chrome (the nav, the shell) runs under 1 so the rim
  /// stays a suggestion; cards and dialogs run at 1.
  double strength = 1,
}) {
  final rect = rrect.outerRect;
  if (rect.width <= 2 || rect.height <= 2) return;

  // ── There is NO bright band. ──
  //
  // The reference has one — `feComponentTransfer slope 1 + light × 1.15`, the
  // refracted backdrop turned up inside the rim mask. It works there because
  // that page's background is a mid-tone: turning violet up gives lighter
  // violet.
  //
  // It does not work here and it cannot be made to. This app's background is a
  // pale field over a veiled photograph, and ANY brightening of something
  // already near-white lands on white — additive, screen, overlay, all of them.
  // Every attempt at it came back as "ขอบยังขาว", correctly. So the light half
  // of the dome is simply gone, and what is left is the half that works on a
  // light ground: the shaded side.
  //
  // The rim still reads, because the rim is no longer painted at all — it is
  // [LiquidDrop] compressing the real background into the last few pixels. This
  // only has to close the shape.
  //
  // Darkening is safe where brightening is not: [BlendMode.multiply] can only
  // take brightness OUT, it keeps the hue exactly, and it has nowhere to clip
  // to. Over the violet field the edge is a deeper violet; over the branch photo
  // it is a deeper whatever-is-there. Never a colour of its own, and never
  // white.
  final dim = 1 - (.10 + .16 * light) * strength;
  canvas.drawRRect(
    rrect.deflate(.6),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..blendMode = BlendMode.multiply
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        // Lit corner barely touched, shaded corner carrying it — the light in
        // this app comes from the top left.
        colors: [
          const Color(0xffffffff).withValues(
              red: 1 - (1 - dim) * .35, green: 1 - (1 - dim) * .35, blue: 1 - (1 - dim) * .3),
          const Color(0xffffffff)
              .withValues(red: dim, green: dim, blue: min(1.0, dim + .04)),
        ],
      ).createShader(rect),
  );
}

/// The lit lip of a raised pane: one crisp 1 px line along the top edge that
/// fades out before the middle, and a whisper of shade along the bottom.
///
/// This is [LiquidWellEdge] turned the right way up. The well's line is bright
/// at the BOTTOM because a channel catches the light on its far wall; a card
/// stands proud of the page, so its lit edge is the one facing the light. Same
/// stroke, same white, opposite end.
///
/// [lip] scales the whole thing; 0 is the old edge, rim only.
void paintLiquidLip(Canvas canvas, RRect rrect, {double lip = 1}) {
  final rect = rrect.outerRect;
  if (rect.width <= 2 || rect.height <= 2 || lip <= 0) return;
  canvas.drawRRect(
    rrect.deflate(.5),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          // Gone well before the middle, so the SIDES of a card stay the
          // refracted background rather than becoming a drawn outline.
          Colors.white.withValues(alpha: (.62 * lip).clamp(0.0, 1.0)),
          Colors.white.withValues(alpha: 0),
          const Color(0xff141620).withValues(alpha: (.078 * lip).clamp(0.0, 1.0)),
        ],
        stops: const [0, .45, 1],
      ).createShader(rect),
  );
}

/// [paintLiquidRim] as a [Border], so every surface already built on a
/// `BoxDecoration` picks the rim up by swapping one field.
///
/// It extends [Border] rather than [BoxBorder] for one specific reason:
/// `BoxBorder.lerp` throws on a type it doesn't recognise, and an implicitly
/// animated decoration anywhere in the app would take the whole page down with
/// it. As a [Border] subclass it lerps to a plain hairline for the length of the
/// animation and comes back — invisible in practice, and it cannot crash.
class LiquidRim extends Border {
  const LiquidRim({
    this.band = Lg.rimBand,
    this.light = Lg.light,
    this.strength = 1,
  }) : super(top: _side, right: _side, bottom: _side, left: _side);

  /// What the border reports for LAYOUT. The rim paints far wider than this, but
  /// a `Container` insets its child by `decoration.padding`, which is the sum of
  /// these — so it has to stay at the 1 px the flat theme's border also took, or
  /// every card in the app would lose 20 px of content width.
  static const BorderSide _side = BorderSide(color: Color(0x00ffffff), width: 1);

  final double band;
  final double light;
  final double strength;

  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    TextDirection? textDirection,
    BoxShape shape = BoxShape.rectangle,
    BorderRadius? borderRadius,
  }) {
    final rrect = shape == BoxShape.circle
        ? RRect.fromRectXY(rect, rect.shortestSide / 2, rect.shortestSide / 2)
        : (borderRadius ?? BorderRadius.zero).toRRect(rect);
    paintLiquidRim(canvas, rrect, band: band, light: light, strength: strength);
  }

  @override
  bool operator ==(Object other) =>
      other is LiquidRim && other.band == band && other.light == light && other.strength == strength;

  // Every LiquidRim shares one BorderSide, so Border's own == would call two
  // differently-tuned rims equal and skip the repaint.
  @override
  int get hashCode => Object.hash(band, light, strength);
}

/// The rim as a [ShapeBorder], for the Material surfaces that take a `shape`
/// instead of a decoration — dialogs, menus, popup cards.
class LiquidShape extends RoundedRectangleBorder {
  const LiquidShape({
    super.borderRadius = const BorderRadius.all(Radius.circular(28)),
    this.band = Lg.rimBand,
    this.strength = 1,
  });

  final double band;
  final double strength;

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final rrect = borderRadius.resolve(textDirection).toRRect(rect);
    paintLiquidRim(canvas, rrect, band: band, strength: strength);
    // A dialog is a pane like a card is, so it carries the card's lit lip too —
    // otherwise the dialog would be the one flat-edged surface left.
    paintLiquidLip(canvas, rrect);
  }

  @override
  bool operator ==(Object other) =>
      other is LiquidShape &&
      other.borderRadius == borderRadius &&
      other.band == band &&
      other.strength == strength;

  @override
  int get hashCode => Object.hash(borderRadius, band, strength);
}

// ═══════════════════════════════════════════════════════════════════════════
// SURFACES
// ═══════════════════════════════════════════════════════════════════════════

/// The body of the drop.
///
/// These are the reference's own light-mode numbers —
/// `linear-gradient(150deg, .44, .20 46%, .34)` — and they are LOW on purpose.
/// What makes a drop read as a drop is that you can see through it: the body is
/// the blurred backdrop ([LiquidPane]), and this is only the sheen of light
/// crossing the surface on the way.
///
/// Three stops, not two: bright at the lit corner, DIPPING through the middle,
/// bright again at the far corner. The dip is the whole difference between "a
/// curved surface with light crossing it" and "a white card with a gradient" — a
/// monotonic ramp reads as the second no matter how faint it is.
/// ── DIAL 2 of 2 for how milky the glass looks. ──
/// The sheen ON the surface, where [LiquidField.lens]'s lift is the fog INSIDE
/// it. Both read as white; this one is the reference's own `.44 / .20 / .34`,
/// and the middle stop is the one that matters — it is the clear part of the
/// pane, and raising it is what turns a drop back into a white card.
LinearGradient lgTint(Color color, {double scale = 1}) => LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      stops: const [0, .46, 1],
      colors: [
        color.withValues(alpha: (.40 * scale).clamp(0.0, 1.0)),
        color.withValues(alpha: (.19 * scale).clamp(0.0, 1.0)),
        color.withValues(alpha: (.31 * scale).clamp(0.0, 1.0)),
      ],
    );

/// One short cast plus a contact shadow.
///
/// The reference throws its shadow a long way — `0 24px 54px -26px` — and it can
/// afford to: its cards float on a page with room around them. These do not.
/// Stacked 16 px apart inside a group, a cast that reaches 24 px down and blurs
/// 46 lands ON the next card, and the pile of them reads as a grey band running
/// under everything. Short and tight is what actually says "lifted" at this
/// density.
const List<BoxShadow> lgShadow = [
  BoxShadow(color: Color(0x33282850), blurRadius: 16, spreadRadius: -6, offset: Offset(0, 5)),
  BoxShadow(color: Color(0x1f282850), blurRadius: 4, spreadRadius: -2, offset: Offset(0, 1)),
];

/// The lighter cast for chrome and for small controls, which sit closer to what
/// they are on.
const List<BoxShadow> lgShadowSoft = [
  BoxShadow(color: Color(0x33282850), blurRadius: 20, spreadRadius: -12, offset: Offset(0, 8)),
];

/// A DROP of liquid glass: the backdrop blurred through it, the dome rim around
/// it, a cast under it — and no paint of its own beyond the sheen.
///
/// This is the piece a decoration cannot be. `BoxDecoration` can tint and can
/// draw an edge, but it cannot BLUR what is behind it, and the reference is
/// explicit that the body of the glass is the background seen through it rather
/// than a white fill. So the card stops being a `Container` with a decoration
/// and becomes this: a clipped [BackdropFilter] with the content laid over it.
///
/// Three things are deliberately kept apart, because they belong to different
/// layers of the sandwich:
///
/// * the **cast** is outermost, under everything, or the blur would eat it;
/// * the **blur** is clipped to the shape and holds nothing — it is a lens, not
///   a container, so the content is NOT inside it and NOT clipped by it (cards
///   in this app let menus and badges hang past their edge);
/// * the **rim** is outermost-but-one, painted as a `foregroundDecoration` so it
///   lands on the canvas AFTER the blur has been composited — which is what lets
///   [BlendMode.plus] and [BlendMode.multiply] modulate the real backdrop
///   instead of blending against nothing.
///
/// One BackdropFilter per drop. That is the cost of the theme and the reason
/// [Lg.enabled] exists: a page of twenty cards is twenty backdrop reads a frame.
class LiquidPane extends StatelessWidget {
  const LiquidPane({
    super.key,
    required this.child,
    this.radius = 20,
    this.padding,
    this.color = Colors.white,
    this.tint = 1,
    this.strength = 1,
    this.shadow,
    this.border,
    this.clipContent = false,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final Color color;

  /// Scales [lgTint]. A drop that has to carry dense text runs higher than one
  /// that carries a number.
  final double tint;
  final double strength;

  /// There is no `blur` here on purpose. A drop does not blur anything itself —
  /// it samples [LiquidField.lens], which is blurred once at bake time for the
  /// whole app. The dial is in [LiquidField.ensure].
  final List<BoxShadow>? shadow;

  /// A caller asking for a specific edge colour means it, and gets a plain
  /// border in place of the dome.
  final BoxBorder? border;

  /// Whether the CONTENT is cut off at the drop's edge. The blur always is.
  final bool clipContent;

  @override
  Widget build(BuildContext context) {
    final r = Lg.r(radius);
    final corner = BorderRadius.circular(r);
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: corner, boxShadow: shadow ?? lgShadow),
      child: LiquidDrop(
        radius: r,
        strength: strength,
        child: Container(
          clipBehavior: clipContent ? Clip.antiAlias : Clip.none,
          decoration: BoxDecoration(borderRadius: corner, gradient: lgTint(color, scale: tint)),
          foregroundDecoration: BoxDecoration(
            borderRadius: corner,
            // [LiquidPaneEdge] is the rim PLUS the lit lip — the edge the icon
            // tiles and segmented tracks carry. Every DsCard comes through here.
            border: border ?? LiquidPaneEdge(strength: strength),
          ),
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}

/// A pane of liquid glass as a decoration: tinted body, lens rim, droplet
/// shadow — for the surfaces that cannot be a [LiquidPane] because something
/// above them needs a `BoxDecoration` (an animated colour, a hand-rolled
/// container). No blur; the rim and the sheen carry it alone.
BoxDecoration lgGlass({
  double radius = 20,
  Color color = Colors.white,
  double scale = 1,
  double strength = 1,
  double band = Lg.rimBand,

  /// A caller asking for a specific edge colour (a red error card, a selected
  /// outline) means it, so it gets a plain border instead of the rim.
  Color? borderColor,
  double borderWidth = 1,
  List<BoxShadow>? shadow,
}) =>
    BoxDecoration(
      // A FLAT fill, not [lgTint]'s three-stop rake.
      //
      // That rake is light crossing a curved surface, and it only reads that way
      // on something curved — a [LiquidPane], which has a drop under it bending
      // the background. On a plain plate stacked INSIDE one there is no curve
      // for it to describe, so it just reads as what it physically is: a sheet
      // that is bright in one corner and grey in the other. Every "ยังเป็นสีเทา
      // อยู่" on the kanban cards and the approval blocks was this gradient.
      color: color.withValues(alpha: (.55 * scale).clamp(0.0, 1.0)),
      borderRadius: BorderRadius.circular(Lg.r(radius)),
      border: borderColor != null
          ? Border.all(color: borderColor, width: borderWidth)
          // Same edge as [LiquidPane]'s, so a hand-rolled card (kanban cards,
          // approval blocks) never reads flatter than a real one.
          : LiquidPaneEdge(band: band, strength: strength),
      boxShadow: shadow ?? lgShadow,
    );

/// The edge of a well: dark where the surface drops away at the top, light
/// where it comes back up at the bottom.
///
/// One stroke with a vertical gradient rather than two differently-coloured
/// sides, because a `Border` with per-side colours and a `borderRadius` is a
/// paint-time exception in Flutter ("a borderRadius can only be given on borders
/// with uniform colors") — which takes the whole control's subtree down with it,
/// children included.
class LiquidWellEdge extends Border {
  const LiquidWellEdge() : super(top: _side, right: _side, bottom: _side, left: _side);

  static const BorderSide _side = BorderSide(color: Color(0x00ffffff), width: 1);

  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    TextDirection? textDirection,
    BoxShape shape = BoxShape.rectangle,
    BorderRadius? borderRadius,
  }) {
    if (rect.width <= 2 || rect.height <= 2) return;
    final rrect = (borderRadius ?? BorderRadius.zero).toRRect(rect);
    canvas.drawRRect(
      rrect.deflate(.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x1a141620), Color(0x00141620), Color(0xa8ffffff)],
          stops: [0, .55, 1],
        ).createShader(rect),
    );
  }
}

/// The edge of a PANE — a card, a dialog, the top bar — drawn in the same
/// language as [LiquidWellEdge], which is the edge on the icon tiles and the
/// segmented tracks.
///
/// The wells got a defined edge and the cards did not: [paintLiquidRim] alone is
/// a darkening, so a card closes its shape but never catches the light, and next
/// to a control that does it reads as the flatter of the two. This adds the
/// missing half — the crisp lit lip the reference gives every glass surface
/// (`inset 0 1px 0 var(--inner-top)`).
///
/// A card is RAISED where a well is sunk, so the lighting is the well's,
/// inverted: the lit lip is at the top, where the sheet turns up out of the
/// page, and the faint shaded line is at the bottom. That keeps it the same
/// edge — the same crispness, the same 1 px, the same white — without lighting
/// a raised sheet as if it were a channel.
///
/// The darkening rim still runs underneath: it is the only thing tying the edge
/// colour to whatever is behind the card (see [paintLiquidRim]), and the lip is
/// deliberately weaker than the well's .66 white, because a card is ten times
/// the size and a full-strength white line on one is the "ขอบขาว" this theme
/// spent so long getting rid of.
class LiquidPaneEdge extends Border {
  const LiquidPaneEdge({this.band = Lg.rimBand, this.strength = 1, this.lip = 1})
      : super(top: _side, right: _side, bottom: _side, left: _side);

  static const BorderSide _side = BorderSide(color: Color(0x00ffffff), width: 1);

  final double band;
  final double strength;

  /// Scales the lit lip alone, for a surface that wants the rim but only a
  /// whisper of highlight (chrome, a pane stacked inside another pane).
  final double lip;

  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    TextDirection? textDirection,
    BoxShape shape = BoxShape.rectangle,
    BorderRadius? borderRadius,
  }) {
    final rrect = shape == BoxShape.circle
        ? RRect.fromRectXY(rect, rect.shortestSide / 2, rect.shortestSide / 2)
        : (borderRadius ?? BorderRadius.zero).toRRect(rect);
    paintLiquidRim(canvas, rrect, band: band, strength: strength);
    paintLiquidLip(canvas, rrect, lip: lip);
  }

  @override
  bool operator ==(Object other) =>
      other is LiquidPaneEdge && other.band == band && other.strength == strength && other.lip == lip;

  @override
  int get hashCode => Object.hash(band, strength, lip);
}

/// A channel SUNK into the glass — the reference's `.well`, used for anything a
/// control sits inside: a segmented track, a search field, an icon tile.
///
/// A well has no rim. It is the inverse of one — see [LiquidWellEdge]. Flutter
/// has no inset shadow, so the edge carries the whole illusion.
BoxDecoration lgWell({double radius = 12, double scale = 1, Color? color}) => BoxDecoration(
      color: (color ?? Colors.white).withValues(alpha: (.34 * scale).clamp(0.0, 1.0)),
      borderRadius: BorderRadius.circular(Lg.r(radius, max: 22)),
      border: const LiquidWellEdge(),
    );

/// A raised control ON the glass — a nav pill, a segmented thumb, a hovered
/// tile. Denser than a card because these are small and have to read as lit at
/// a glance.
BoxDecoration lgRaised({
  double radius = 14,
  double scale = 1,
  double strength = .85,
  List<BoxShadow>? shadow,
}) =>
    BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        stops: const [0, .46, 1],
        colors: [
          Colors.white.withValues(alpha: (.90 * scale).clamp(0.0, 1.0)),
          Colors.white.withValues(alpha: (.66 * scale).clamp(0.0, 1.0)),
          Colors.white.withValues(alpha: (.80 * scale).clamp(0.0, 1.0)),
        ],
      ),
      borderRadius: BorderRadius.circular(Lg.r(radius, max: 22)),
      border: LiquidRim(band: 10, strength: strength),
      boxShadow: shadow ?? lgShadowSoft,
    );
