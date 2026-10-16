part of '../main.dart';

/// Central design tokens + reusable widgets matching the Claude Design export.
/// Palette and component styling are derived from the "Bento Grid Dashboard
/// Redesign" export: IBM Plex Sans/Mono, indigo #5b53e0 accent, slate text,
/// white cards over an ambient wash on #f5f5f8.

/// The two app faces.
///
/// Anuphan draws Thai and Latin itself, so — unlike the IBM Plex + Noto Sans
/// Thai pairing it replaces — no fallback family is needed to keep Thai off
/// fonts.gstatic.com on a machine with no internet.
///
/// [dsFontFallback] is kept, and still worth naming on any TextStyle that sets
/// `fontFamily` outright, because JetBrains Mono has no Thai: a mono style
/// meeting a Thai character needs somewhere local to land.
const String dsFontSans = 'Anuphan';
const String dsFontMono = 'JetBrains Mono';
const List<String> dsFontFallback = [dsFontSans];

class DsColors {
  // Brand / accent.
  //
  // The accent is the design's indigo, not the old navy. [navy] keeps its name
  // because ~170 call sites read it as "the primary accent" — only the value
  // moved, so the rename would be churn with no meaning behind it.
  static const navy = Color(0xff5b53e0);
  static const navyHover = Color(0xff4a41c7);
  static const navyLight = Color(0xff6f66ee); // gradient start on filled buttons
  static const navyDeep = Color(0xff3a3390); // text/icons sitting on [navySoft]
  static const heading = Color(0xff14161f);
  static const headingAlt = Color(0xff1f2540);

  // App chrome: glass over [DsGlassShell]'s pane, which is itself glass over
  // the wash. Their weight is set by what is already under them — the pane
  // contributes 40 % white, so these only add the rest. Push them much past
  // this and the nav goes back to being a white slab with the wash stopping
  // dead at its edge; drop them much below and the tint reaches the labels.
  //
  // The nav takes no blur on purpose: nothing scrolls past it, so all it ever
  // has behind it is the smooth wash, and blurring a smooth gradient returns
  // the same gradient at full-height BackdropFilter cost. The top bar DOES
  // blur — content passes under it.
  static const sidebar = Color(0x42ffffff);
  static const sidebarBorder = Color(0x4dffffff);
  static const topbar = Color(0x4dffffff);
  static const topbarBorder = Color(0x42ffffff);
  // The selected menu item: a lit pill, not a lilac plate. Over glass an opaque
  // fill reads as a sticker; white catches the light the way the rest of the
  // surface does, and the indigo rail + icon still say which item it is.
  static const navPill = Color(0xb8ffffff);

  // Slate text scale.
  //
  // ── Why this is not white ──────────────────────────────────────────────────
  //
  // Most liquid glass in the wild sets its labels in white, and it is right to:
  // that glass is sitting on a DARK ground. This app is light-mode only — pale
  // panes over a daylight photograph — and white on that is invisible. Apple's
  // own light-mode glass sets near-black labels for the same reason. The rule is
  // not "glass means white text", it is "the label opposes the ground", and here
  // the ground is bright.
  //
  // ── Why the whole bottom of the ladder moved ───────────────────────────────
  //
  // The scale used to run six steps down to #a3a8b8 — 2.6:1 on white, against
  // the 4.5:1 small text is supposed to clear. That was survivable while every
  // card was a near-opaque white plate holding still. It is not survivable on
  // glass, because the ground under a label is no longer a constant: one card
  // lands over a bright roof and the next over dark trees, and the pale end of
  // the ladder dies on the second one.
  //
  // So the usable range is compressed and pulled down. Six tokens remain — 170
  // call sites read them by name — but they now span #2b3040…#575d70 instead of
  // #3c414f…#a3a8b8, and the lightest of them still clears 6:1 on white, which
  // is roughly 4:1 over the darkest ground a drop is likely to find.
  //
  // ── What carries hierarchy instead ─────────────────────────────────────────
  //
  // Weight and size, which is what this design already says it does ("the work
  // is done by WEIGHT more than by size" — see [DsType]). Lightness cannot carry
  // it here: there is not enough room left between "readable over a photograph"
  // and "black". Reach for w500 against w700, or 10.5 against 12.5, before
  // reaching for a paler grey.
  //
  // Not gated on the theme — these were under the floor on the flat theme too,
  // it was just quieter about it, and more contrast is never the worse bug.
  //
  // Contrast on white, top to bottom: 12.8 · 10.0 · 8.4 · 7.3 · 6.4 · 5.3.
  static const text = Color(0xff2b3040);
  static const text2 = Color(0xff3a4053);
  static const muted = Color(0xff454b5e);
  static const muted2 = Color(0xff4e5467);
  static const faint = Color(0xff4e5467);
  static const faint2 = Color(0xff575d70);
  static const icon = Color(0xff575d70);
  // Icons that decorate rather than inform — empty-state glyphs, the affordance
  // inside an input. The only step allowed to sit below the others.
  static const iconSoft = Color(0xff646a7d);

  // Borders / lines. Translucent slate rather than fixed near-whites: these are
  // drawn INSIDE glass, so a solid light grey is a smear of paint on a clear
  // surface — it reads as grime when the wash behind it is coloured. A tint of
  // the text colour instead stays a shade darker than whatever it is over.
  static const cardBorder = Color(0xffebecf2);
  static const inputBorder = Color(0xffd3d5e0);
  static const line = Color(0x14141620);
  static const lineSoft = Color(0x0f141620);
  static const track = Color(0x1a141620);

  // Glass. A card is a translucent PANE over [DsAmbient]'s wash, not a white
  // slab: the wash tints it, a light edge catches along the top-left, and two
  // shadows lift it off the page. Blur is deliberately NOT part of this — see
  // [DsCard] for why the panes stay unblurred and [DsFrosted] for the few
  // places that do earn it.
  //
  // [glass] is the pane itself; the gradient in [DsCard] runs from this down to
  // [glassLow] across the diagonal, which is what reads as light falling on a
  // sheet rather than as a flat wash of white.
  //
  // Two stops, kept CLOSE together. The wide 52→30 range they started at made
  // every card fade out across its own diagonal, which reads fine on a small
  // tile and badly on a wide table: one corner showed the backdrop through the
  // text while the other looked solid. The gradient is meant to say "light is
  // falling on this", not "this end is a window".
  //
  // The level itself is a bargain with the text: low enough that the backdrop
  // is present, high enough that a dense grid stays readable over it.
  static const glass = Color(0xb0ffffff); // 69 %
  static const glassLow = Color(0x9effffff); // 62 %
  // A DATA SHEET on the glass: a table, a grid, a Gantt. Dense text needs one
  // steady surface under it, so these get a single uniform fill instead of the
  // card's gradient — and never a second pane of [glass] on top of the card,
  // which is what left the wide tables looking patchy, transparent in one
  // corner and solid in another.
  static const sheet = Color(0xdbffffff); // 86 %
  // The pane the workspace itself sits on ([DsGlassShell]): lighter than a
  // card, so a card still reads as a layer above it rather than as the same
  // sheet.
  static const shellGlass = Color(0x42ffffff); // 26 %
  static const shellEdge = Color(0x99ffffff);
  static const shellShadow = Color(0x1a1c1630);
  // THE POPUP SURFACE — every dialog, dropdown, menu, date picker and the
  // fullscreen boards. **Fully opaque, on purpose.**
  //
  // It used to be 88 % white, on the theory that a popup is a pane of glass
  // like everything else. On the flat theme that was nearly invisible: 88 %
  // white over a pale lilac page resolves to near-white anyway. Under liquid
  // glass the thing behind it is a whole PAGE — a table, a Gantt, another
  // dialog's dark header — and 12 % of it came through every popup in the app
  // at once ("มองทะลุด้านหลัง"): the edit-detail form, add-todo, the period
  // picker, the fullscreen to-do board, the request-detail popup itself.
  //
  // A popup is the one surface in the app that must NOT be a window. It is
  // opened on top of the page precisely to take over from it, and anything
  // showing through is competing with the form the user is filling in. So this
  // is the app's single opaque surface, and it is deliberately the only place
  // the glass metaphor is dropped. Cards and strips INSIDE a popup stay
  // translucent — what they let through is this, which is what makes a popup
  // read as one stack of paper rather than as a hole in the page.
  //
  // The value is what the old 88 % resolved to over [scaffold], so nothing that
  // was tuned against it moves: near-white, carrying the page's lilac.
  static const popupSurface = Color(0xfffdfcff);
  // The lit edge. White, not the grey [cardBorder]: a pane is bounded by the
  // light it catches, and a grey line around a translucent card reads as a
  // drawn outline instead. It carries more of the card's definition now that
  // the fill is thin, so it runs brighter than the fill it borders.
  static const glassEdge = Color(0xa8ffffff);
  // Ambient depth + the tight contact shadow directly under the card.
  static const glassShadow = Color(0x12141620);
  static const glassContact = Color(0x08141620);
  // The light that crosses a skeleton bar. White rather than a lighter grey:
  // the bar itself is a translucent tint of the ink, so lifting it toward the
  // page is what "light passing over it" actually looks like on glass.
  static const skeletonSheen = Color(0x99ffffff);

  // ── The scrollbar. ──
  //
  // A tint of the text colour, like [line] and [track] — never a fixed grey.
  // The bar rides over glass, over tables, over the Gantt and over a photograph
  // in the liquid theme, and a solid grey that reads as "a scrollbar" on the
  // pale page reads as a smear of dirt on the dark parts of the photo. A tint
  // of the ink stays a shade darker than whatever it is over, wherever it is.
  //
  // Three states, because the bar earns its width: nearly invisible at rest, a
  // clear handle under the cursor, and unmistakable while being dragged.
  static const scrollThumb = Color(0x2b141620);
  static const scrollThumbHover = Color(0x59141620);
  static const scrollThumbDrag = Color(0x80141620);
  // The channel, shown only while the pointer is over the bar — a permanent
  // track is a permanent line down the side of every page.
  static const scrollTrack = Color(0x0a141620);
  static const scrollTrackBorder = Color(0x0f141620);

  // Text selection. Left at Flutter's default this was the framework's stock
  // blue, the one colour in the app that belonged to no one — and selection is
  // not a rare state on a page of request numbers people copy out all day.
  static const selection = Color(0x385b5bd6);

  // Behind a modal. Light on purpose: the page stays legible and keeps its
  // colour, and the dialog is separated by being glass, not by the room going
  // dark. Anything heavier and a translucent dialog picks up the dimming
  // through itself and reads as muddy.
  static const scrim = Color(0x33141620);

  // Surfaces
  //
  // The page is a pale lilac — the Halcyon login's night sky brought up to
  // daylight, so signing in and arriving in the app read as the same place at
  // different hours. A neutral grey under [DsAmbient]'s violet fields greyed
  // them out; the base has to carry a little of the same hue.
  //
  // Kept BRIGHT on purpose. Every pane in the app is white-over-this, so this
  // is what a card's colour actually resolves to — drop it a few points toward
  // grey and every surface in the app goes grey with it, which reads as dirty
  // glass rather than as a darker theme.
  //
  // Lightened once more (2026-08-21): every pane in the app is white-over-this
  // and the fields are laid over it, so this is the one value that moves the
  // whole page's weight at once. See [DsAmbient]'s wash lift and
  // [LiquidField.fieldLift] for the other two halves of the same adjustment.
  static const scaffold = Color(0xfff8f6fc);

  // ── Surfaces that sit ON a pane: table headers, hover fills, inset strips,
  // tag fills, detail blocks. ─────────────────────────────────────────────────
  //
  // These were tuned when the thing behind them was [DsAmbient]'s smooth wash. A
  // 35 % white strip over a slow violet gradient is a strip; the gradient barely
  // moves across it, so the strip reads as one even surface and the text on it
  // is safe.
  //
  // Under liquid glass the thing behind them is a PHOTOGRAPH, and the same 35 %
  // is a window onto whatever the photograph is doing — trees under this cell,
  // a bright roof under the next. That is one root cause behind every "อ่านไม่
  // ออก" on the dense pages at once: the approval detail block, the skill chips,
  // the weekly-plan grid, the work board columns.
  //
  // So they are all denser. They still let the ground through — a card is still
  // obviously glass — but enough of it is now the surface's own white that a
  // label sitting on one has a predictable ground under it wherever it lands.
  //
  // Not gated on the theme, because they cannot be: these are `const`, and
  // `DsType` builds `const TextStyle`s out of them. The flat theme therefore
  // gets slightly more solid strips too, which costs it a little airiness and
  // buys the same predictability.
  static const subtle = Color(0xc4ffffff); // 77 %
  static const subtleAlt = Color(0x9effffff); // 62 %

  // Tag / pill fill. This one INVERTS rather than densifies: it used to be a
  // dark 6 % tint — a recess in the glass — which works beautifully over a pale
  // wash and turns a row of skill chips into unreadable smudges over a dark
  // photograph. It is a light recess now: still a step away from the pane it is
  // cut into, but away in the direction the text can survive.
  static const chip = Color(0x87ffffff); // 53 %
  static const navySoft = Color(0x455b53e0);
  // Edge for a control that is switched on / selected — the accent at card
  // weight, so an active outline reads without going full indigo.
  static const navyBorder = Color(0xffc9c4f8);

  // Status: green
  static const greenBg = Color(0xffe4f3ec);
  static const greenFg = Color(0xff17845a);
  static const greenDot = Color(0xff22a06b);
  // Status: red
  static const redBg = Color(0xfffbeae7);
  static const redFg = Color(0xffc33f33);
  static const redBadge = Color(0xffc33f33);
  // The hovered half of a destructive control that already SITS in red at rest
  // (the nav's Logout). Two steps down from [redBg] / [redFg] rather than one:
  // the resting state is already tinted, so a single step would be a hover you
  // have to look for.
  static const redBgHover = Color(0xfff5cdc6);
  static const redFgHover = Color(0xff9b2c21);
  // Status: amber
  static const amberCardBg = Color(0xfffbf9f4);
  static const amberBorder = Color(0xfff6e09c);
  static const amberFg = Color(0xffa9720c);
  static const amberBg = Color(0xfffdf4d8);
  static const amberBar = Color(0xffc98d20);
  // Status: blue / purple
  static const blueFg = Color(0xff2f6bed);
  static const blueBg = Color(0xffe8f0fe);
  static const purpleFg = Color(0xff6d5ef0);
  static const purpleBg = Color(0xffefedfe);
  // Accent: teal — the design's fourth accent, used for secondary series in
  // charts and for avatars.
  static const tealFg = Color(0xff0f8f9e);
  static const tealBg = Color(0xffe3f4f6);
  // Status: on hold (warm grey / taupe — paused, distinct from pending amber)
  static const holdFg = Color(0xff8a6240);
  static const holdBg = Color(0xfff2ece5);
  static const holdBar = Color(0xffb08453);
}

/// The design's type scale, read off the export rather than invented.
///
/// The app is dense, so the steps are close together and the work is done by
/// WEIGHT more than by size: 700 for anything that names a thing, 600 for a
/// label, 500 for a value, 400 for prose. Sizes carry the half-points from the
/// design (12.5, 13.5, 11.5) because at this density a whole point is a
/// visible jump.
///
/// Colours are baked in so a call site is one token, not a token plus a colour
/// guess; use `.copyWith(color:)` where the meaning differs (status, accent).
class DsType {
  DsType._();

  static const _f = dsFontSans;
  static const _fb = dsFontFallback;

  /// Page name in the top bar.
  static const pageTitle = TextStyle(
      fontFamily: _f,
      fontFamilyFallback: _fb,
      fontSize: 17,
      fontWeight: FontWeight.w700,
      letterSpacing: -.4,
      height: 1.15,
      color: DsColors.heading);
  static const pageSub = TextStyle(
      fontFamily: _f,
      fontFamilyFallback: _fb,
      fontSize: 11,
      fontWeight: FontWeight.w500,
      color: DsColors.muted2);

  /// Greeting on the hero card. The only display-sized text on the page.
  static const hero = TextStyle(
      fontFamily: _f,
      fontFamilyFallback: _fb,
      fontSize: 19,
      fontWeight: FontWeight.w700,
      letterSpacing: -.4,
      height: 1.2,
      color: Colors.white);

  /// Names a card ("Project timeline") or, one step down, a panel inside one.
  static const cardTitle = TextStyle(
      fontFamily: _f,
      fontFamilyFallback: _fb,
      fontSize: 12.5,
      fontWeight: FontWeight.w700,
      letterSpacing: -.1,
      color: DsColors.heading);
  static const panelTitle = TextStyle(
      fontFamily: _f,
      fontFamilyFallback: _fb,
      fontSize: 11.5,
      fontWeight: FontWeight.w700,
      color: DsColors.heading);

  /// All-caps run-in above a group. Pair with [DsSectionLabel]'s spacing.
  static const eyebrow = TextStyle(
      fontFamily: _f,
      fontFamilyFallback: _fb,
      fontSize: 9.5,
      fontWeight: FontWeight.w700,
      letterSpacing: .8,
      color: DsColors.faint2);

  /// The thing a row is about — a request title, a person's name.
  static const rowTitle = TextStyle(
      fontFamily: _f,
      fontFamilyFallback: _fb,
      fontSize: 11.5,
      fontWeight: FontWeight.w600,
      color: DsColors.heading);

  /// What a number underneath means ("Active work items").
  static const label = TextStyle(
      fontFamily: _f,
      fontFamilyFallback: _fb,
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: DsColors.muted);
  static const body = TextStyle(
      fontFamily: _f, fontFamilyFallback: _fb, fontSize: 11.5, height: 1.45, color: DsColors.text);
  static const meta = TextStyle(
      fontFamily: _f,
      fontFamilyFallback: _fb,
      fontSize: 10.5,
      fontWeight: FontWeight.w500,
      color: DsColors.muted);
  static const metaSm = TextStyle(
      fontFamily: _f,
      fontFamilyFallback: _fb,
      fontSize: 9.5,
      fontWeight: FontWeight.w500,
      color: DsColors.faint2);

  /// Headline figures. Mono so a column of them lines up on the digit, which
  /// is the whole reason the design sets numbers in JetBrains.
  static TextStyle stat(double size, {Color color = DsColors.heading}) => TextStyle(
      fontFamily: dsFontMono,
      fontFamilyFallback: _fb,
      fontSize: size,
      fontWeight: FontWeight.w700,
      height: 1,
      color: color);

  /// The number on a hero card (30) / a stat tile (28) / a ring (19).
  static TextStyle get statXl => stat(25, color: Colors.white);
  static TextStyle get statLg => stat(22);
  static TextStyle get statMd => stat(17);
}

/// Shared motion vocabulary. This is a dense back-office app people click
/// through all day, so every transition stays under 300 ms and nothing travels
/// more than a few pixels — the movement exists to say WHAT changed, not to
/// perform. Always read a duration through [DsMotion.of] so the OS "reduce
/// motion" setting can flatten it to zero.
class DsMotion {
  // Hover, pressed states, colour changes.
  static const fast = Duration(milliseconds: 120);
  // App chrome: selection indicator, busy overlay.
  static const chrome = Duration(milliseconds: 180);
  // The side nav opening and closing. Longer than the rest of the chrome on
  // purpose: it is the largest thing that moves in the app (141 px of width,
  // with the whole page resizing behind it), and at chrome speed that much
  // travel arrives before the eye has followed it.
  static const nav = Duration(milliseconds: 240);
  // Swapping the page content from the side nav.
  static const page = Duration(milliseconds: 220);
  // The outgoing half of a fade-through (old page leaves before the new one
  // arrives, so the two never cross-dissolve into mush).
  static const pageOut = Duration(milliseconds: 90);
  // Entering a stage: workspace, section picker, dialogs.
  static const enter = Duration(milliseconds: 260);
  // The one deliberate exception to the "under 300 ms" rule above: a
  // once-per-session establishing shot. Only the section picker's cloud
  // descent uses it — it is a doorway people walk through when they arrive,
  // not a control they operate all day. Never reach for this in a dialog, a
  // page swap, or anything that can happen twice in a row.
  static const cinematic = Duration(milliseconds: 1500);

  /// A selection indicator SLIDING to where it was sent — the side nav's pill,
  /// the segmented thumb — under the liquid theme. Long and springy on purpose,
  /// against the rule above: this is the one movement the eye is meant to
  /// follow the whole way, and the overshoot is what says the thing was thrown
  /// rather than repainted. (`.55s cubic-bezier(.34,1.56,.64,1)` in the
  /// reference; [Curves.easeOutBack] is the same shape.)
  static const slide = Duration(milliseconds: 480);
  static const curveSlide = Curves.easeOutBack;

  static const curveIn = Curves.easeOutCubic;
  static const curveOut = Curves.easeInCubic;
  static const curveChrome = Curves.easeInOutCubic;

  /// [d], or zero when the platform asks for reduced motion.
  static Duration of(BuildContext context, Duration d) =>
      MediaQuery.maybeDisableAnimationsOf(context) == true ? Duration.zero : d;
}

/// Height of [TopBar]. The bar floats over the scrolling content rather than
/// sitting above it in a column, so the content area has to inset itself by
/// this much — both need the one number.
const double kDsTopBarHeight = 62;

/// The frosted pane behind the top bar: blurs whatever scrolls under it and
/// lifts that content's colour, the way `backdrop-filter: blur() saturate()`
/// does in the design.
///
/// Only ever wrap a small, fixed strip in this. A BackdropFilter re-reads and
/// re-blurs everything painted beneath it on every frame it changes, so the
/// cost scales with the area covered — over a 62 px bar it is a rounding
/// error, over a full-height panel it is not.
class DsFrosted extends StatelessWidget {
  const DsFrosted({super.key, required this.child, this.blur = 22, this.saturation = 1.7});

  final Widget child;

  /// Gaussian sigma. CSS `blur(Npx)` is stated as a standard deviation too, so
  /// the design's numbers carry over unchanged.
  final double blur;
  final double saturation;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        // Blur first, then push the saturation of the blurred result — the
        // other order would smear already-punched colour and read muddy.
        filter: ui.ImageFilter.compose(
          outer: ui.ColorFilter.matrix(dsSaturateMatrix(saturation)),
          inner: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        ),
        child: child,
      ),
    );
  }
}

/// The same matrix CSS `saturate()` uses: pull each channel toward the luminance
/// of the pixel, then push back out by [s]. Shared with [LiquidPane], which
/// lifts the backdrop the same way a drop of water does.
List<double> dsSaturateMatrix(double s) {
  const lr = .213, lg = .715, lb = .072;
  return [
    lr + (1 - lr) * s, lg - lg * s, lb - lb * s, 0, 0, //
    lr - lr * s, lg + (1 - lg) * s, lb - lb * s, 0, 0, //
    lr - lr * s, lg - lg * s, lb + (1 - lb) * s, 0, 0, //
    0, 0, 0, 1, 0, //
  ];
}

/// A modal that arrives as a SHEET laid over an untouched page.
///
/// The page behind is left exactly as it is — not blurred and not blacked out,
/// only shaded by [DsColors.scrim] enough to seat the dialog. The dialog itself
/// is [DsColors.popupSurface]: opaque, with the same lit edge and shadow as
/// every card. The page stays visible AROUND the dialog and stops dead at its
/// edge, which is the whole trade — context beside the popup, nothing showing
/// through it.
///
/// An earlier version frosted the whole window behind the dialog. It looked
/// right in isolation and wrong in use: blurring the entire viewport every
/// frame is the most expensive thing the app can do, and it threw away the
/// context the dialog is supposed to be opened ON TOP of.
///
/// Use it anywhere `showDialog` would be used.
Future<T?> showGlassDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  final still = MediaQuery.maybeDisableAnimationsOf(context) == true;
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: DsColors.scrim,
    transitionDuration: still ? Duration.zero : DsMotion.enter,
    pageBuilder: (context, animation, secondaryAnimation) => Builder(builder: builder),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final v = animation.value.clamp(0.0, 1.0);
      // Closing drops the overshoot and eases the other way, so the dialog
      // leaves the way it would fall rather than springing backwards. (The
      // route runs one duration in both directions — showGeneralDialog has no
      // reverse duration to set — so the curve is what carries the difference.)
      final closing = animation.status == AnimationStatus.reverse;
      // Rises 16 px and settles with a slight overshoot — [DsRise]'s vocabulary,
      // the same movement every card on the page arrives with. The travel is
      // small on purpose: this is a pane being laid down in front of you, not a
      // camera flying in.
      final t = (closing ? DsMotion.curveOut : Curves.easeOutBack).transform(v);
      return Opacity(
        // Its own curve, and clamped: easeOutBack overshoots past 1, which
        // Opacity rejects outright.
        opacity: Curves.easeOut.transform(v),
        child: Transform.translate(
          offset: Offset(0, 16 * (1 - t)),
          child: Transform.scale(scale: .96 + .04 * t, child: child),
        ),
      );
    },
  );
}

/// Raises a tappable CARD a little while the pointer is over it.
///
/// The app is built out of cards, and a card that does nothing at all under the
/// cursor is the difference between a picture of an interface and an interface.
/// The work board's [KanbanCard] was the clearest case: a plain
/// [GestureDetector], so the most-clicked surface in the app had no hover state
/// and not even a pointer cursor.
///
/// Deliberately small — 2 px and 0.6 % of scale. This fires under the cursor
/// hundreds of times an hour on a board of thirty cards; anything the eye can
/// actually measure becomes noise by the third column. What sells it is not the
/// distance but the SHADOW growing with it, which is what says the card came
/// toward you rather than merely moved.
///
/// In fast, out slow — the same asymmetry as [DsMagnetic]. Catching the cursor
/// should feel immediate; letting go should feel like settling.
class DsHoverLift extends StatefulWidget {
  const DsHoverLift({
    super.key,
    required this.child,
    this.onTap,
    this.radius = 14,
    this.lift = 2,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback? onTap;

  /// Must match the child's own corner — the lift shadow is drawn behind the
  /// card, so a mismatched radius shows as a dark sliver at each corner.
  final double radius;
  final double lift;
  final bool enabled;

  @override
  State<DsHoverLift> createState() => _DsHoverLiftState();
}

class _DsHoverLiftState extends State<DsHoverLift> {
  bool _over = false;

  @override
  Widget build(BuildContext context) {
    final Widget tappable = widget.onTap == null
        ? widget.child
        : GestureDetector(onTap: widget.onTap, child: widget.child);
    final bool still = MediaQuery.maybeDisableAnimationsOf(context) == true;
    if (!widget.enabled) return tappable;

    // Reduced motion still gets the cursor — that is affordance, not animation.
    final Widget hoverable = MouseRegion(
      cursor: widget.onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      onEnter: still ? null : (_) => setState(() => _over = true),
      onExit: still ? null : (_) => setState(() => _over = false),
      child: tappable,
    );
    if (still) return hoverable;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: _over ? 1 : 0),
      duration: _over ? DsMotion.fast : DsMotion.chrome,
      curve: DsMotion.curveChrome,
      builder: (context, t, child) => Transform.translate(
        offset: Offset(0, -widget.lift * t),
        child: Transform.scale(
          scale: 1 + 0.006 * t,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.radius),
              boxShadow: t == 0
                  ? null
                  : [
                      BoxShadow(
                        color: DsColors.glassShadow.withValues(
                            alpha: DsColors.glassShadow.a * (1 + 2.2 * t)),
                        blurRadius: 8 + 14 * t,
                        offset: Offset(0, 2 + 5 * t),
                      ),
                    ],
            ),
            child: child,
          ),
        ),
      ),
      child: hoverable,
    );
  }
}

/// Pulls toward the cursor while it is over the widget, then springs back.
///
/// The overshoot on the way back is the point: a linear return reads as the
/// element being dragged, an overshoot reads as it being sprung. Travel is
/// deliberately tiny (7 px across the full width) — enough to say "this is
/// live", not enough to move the hit target out from under the finger.
class DsMagnetic extends StatefulWidget {
  const DsMagnetic({super.key, required this.child, this.enabled = true});

  final Widget child;
  final bool enabled;

  @override
  State<DsMagnetic> createState() => _DsMagneticState();
}

class _DsMagneticState extends State<DsMagnetic> {
  Offset _shift = Offset.zero;
  bool _over = false;

  void _track(PointerEvent e) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || box.size.isEmpty) return;
    final local = box.globalToLocal(e.position);
    final dx = local.dx / box.size.width - .5;
    final dy = local.dy / box.size.height - .5;
    setState(() {
      _over = true;
      _shift = Offset(dx * 7, dy * 5 - 2);
    });
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeDisableAnimationsOf(context) == true;
    if (!widget.enabled || still) return widget.child;
    return MouseRegion(
      onHover: _track,
      onExit: (_) => setState(() {
        _over = false;
        _shift = Offset.zero;
      }),
      child: AnimatedScale(
        scale: _over ? 1.018 : 1,
        // Chasing the cursor is near-instant; letting go is the spring.
        duration: _over ? const Duration(milliseconds: 80) : const Duration(milliseconds: 500),
        curve: _over ? Curves.linear : Curves.easeOutBack,
        child: AnimatedSlide(
          offset: Offset(_shift.dx / 100, _shift.dy / 100),
          duration: _over ? const Duration(milliseconds: 80) : const Duration(milliseconds: 500),
          curve: _over ? Curves.linear : Curves.easeOutBack,
          child: widget.child,
        ),
      ),
    );
  }
}

/// A layer floating at its own depth inside a [DsTilt] — the "minimal 3D" in
/// the design. Depth only decides how far it slides against the tilt; the
/// illusion comes from layers moving by different amounts, not from shadows.
class DsTiltLayer {
  const DsTiltLayer({
    required this.child,
    required this.depth,
    this.rotation = 0,
    this.left,
    this.top,
    this.right,
    this.bottom,
    this.width,
    this.height,
  });

  final Widget child;

  /// Pixels of travel across the full width of the tilting card.
  final double depth;

  /// Resting angle in radians, kept under the parallax shift.
  final double rotation;
  final double? left, top, right, bottom, width, height;
}

/// Tips toward the cursor on two axes, with [layers] sliding at their own
/// depths on top. Rotation is capped at 4° — past that the text on the card
/// starts to visibly distort and the effect turns into a gimmick.
class DsTilt extends StatefulWidget {
  const DsTilt({super.key, required this.child, this.layers = const []});

  final Widget child;
  final List<DsTiltLayer> layers;

  @override
  State<DsTilt> createState() => _DsTiltState();
}

class _DsTiltState extends State<DsTilt> {
  // Pointer offset from the card's centre, -0.5..0.5 on each axis.
  final _pointer = ValueNotifier<Offset>(Offset.zero);

  @override
  void dispose() {
    _pointer.dispose();
    super.dispose();
  }

  void _track(PointerEvent e) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || box.size.isEmpty) return;
    final local = box.globalToLocal(e.position);
    _pointer.value = Offset(
      local.dx / box.size.width - .5,
      local.dy / box.size.height - .5,
    );
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeDisableAnimationsOf(context) == true;
    final stack = Stack(
      clipBehavior: Clip.none,
      children: [
        widget.child,
        for (final layer in widget.layers)
          Positioned(
            left: layer.left,
            top: layer.top,
            right: layer.right,
            bottom: layer.bottom,
            width: layer.width,
            height: layer.height,
            child: still
                ? Transform.rotate(angle: layer.rotation, child: layer.child)
                : ValueListenableBuilder<Offset>(
                    valueListenable: _pointer,
                    builder: (context, p, child) => Transform.translate(
                      // The design moves layers less vertically than
                      // horizontally — a card tilting on a desk swings wider
                      // side to side than it does toward you.
                      offset: Offset(p.dx * layer.depth * .5, p.dy * layer.depth * .35),
                      child: Transform.rotate(angle: layer.rotation, child: child),
                    ),
                    child: layer.child,
                  ),
          ),
      ],
    );
    if (still) return stack;
    return MouseRegion(
      onHover: _track,
      onExit: (_) => _pointer.value = Offset.zero,
      child: ValueListenableBuilder<Offset>(
        valueListenable: _pointer,
        builder: (context, p, child) {
          const maxTilt = 4 * pi / 180;
          final ry = (p.dx * 3 * pi / 180).clamp(-maxTilt, maxTilt);
          final rx = (-p.dy * 3 * pi / 180).clamp(-maxTilt, maxTilt);
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              // Perspective divisor: without it the rotations are an affine
              // squash and the card reads as skewed rather than turned.
              ..setEntry(3, 2, 1 / 1100)
              ..rotateY(ry)
              ..rotateX(rx),
            child: child,
          );
        },
        child: stack,
      ),
    );
  }
}

/// The design's `rise` entrance: up from 14 px with a slight overshoot at the
/// top, staggered down the page by position.
///
/// [index] is the card's place in its group. The delay is capped so a long
/// page never ends with cards still trickling in — past the cap everything
/// lands together, which is what the design's `Math.min(0.32, i * 0.05)` does.
class DsRise extends StatelessWidget {
  const DsRise({super.key, required this.child, this.index = 0});

  final Widget child;
  final int index;

  @override
  Widget build(BuildContext context) {
    final delay = Duration(milliseconds: min(320, index * 50));
    return DsEnter(
      shift: const Offset(0, 14),
      delay: delay,
      duration: const Duration(milliseconds: 550),
      // Overshoots ~10 % before settling, matching cubic-bezier(.2,.9,.3,1.1).
      curve: Curves.easeOutBack,
      child: child,
    );
  }
}

/// Grows a bar out from its left edge on first build — the design's `growX`.
/// Meant for anything whose LENGTH is the datum, so the bar draws itself
/// rather than appearing at full length.
class DsGrow extends StatelessWidget {
  const DsGrow({
    super.key,
    required this.child,
    this.alignment = Alignment.centerLeft,
    this.delay = Duration.zero,
  });

  final Widget child;
  final Alignment alignment;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    final duration = DsMotion.of(context, const Duration(milliseconds: 620));
    if (duration == Duration.zero) return child;
    final total = duration + delay;
    final start = delay.inMicroseconds / total.inMicroseconds;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: total,
      curve: Interval(start.clamp(0.0, .9), 1, curve: Curves.easeOutCubic),
      builder: (context, t, child) => Align(
        alignment: alignment,
        child: FractionallySizedBox(widthFactor: t, child: child),
      ),
      child: child,
    );
  }
}

/// Counts from zero to [value] once, when it first appears. Used on the
/// headline figures only — a number that animates every time data refreshes is
/// noise, so this keys off the widget's own lifetime, not the value: once the
/// first count has finished, later values (a scope switch, a search, a status
/// change) are shown as they are instead of ticking over again.
class DsCountUp extends StatefulWidget {
  const DsCountUp(this.value, {super.key, this.style, this.suffix = '', this.decimals = 0});

  final num value;
  final TextStyle? style;
  final String suffix;

  /// Decimal places to hold steady while counting, so "12.5 days" doesn't flick
  /// through 12.4999 on its way up.
  final int decimals;

  String _text(num v) => '${decimals == 0 ? v.round() : v.toStringAsFixed(decimals)}$suffix';

  @override
  State<DsCountUp> createState() => _DsCountUpState();
}

class _DsCountUpState extends State<DsCountUp> {
  // Set when the arrival count finishes; from then on the figure is plain text.
  bool _counted = false;

  @override
  Widget build(BuildContext context) {
    final duration = DsMotion.of(context, const Duration(milliseconds: 900));
    if (_counted || duration == Duration.zero) return Text(widget._text(widget.value), style: widget.style);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: widget.value.toDouble()),
      duration: duration,
      curve: Curves.easeOutCubic,
      onEnd: () => setState(() => _counted = true),
      builder: (context, v, _) => Text(widget._text(v), style: widget.style),
    );
  }
}

/// A headline figure that counts up when it arrives — but only when it IS a
/// figure. Anything already formatted (a percentage, a duration, an em dash for
/// "no data") is shown exactly as given, because counting up a string the app
/// composed elsewhere would mean re-parsing it and getting it wrong.
Widget dsAnimatedValue(String value, {TextStyle? style}) {
  final whole = int.tryParse(value);
  if (whole != null) return DsCountUp(whole, style: style);
  final fraction = double.tryParse(value);
  if (fraction != null) {
    final dot = value.indexOf('.');
    return DsCountUp(fraction, style: style, decimals: dot < 0 ? 0 : value.length - dot - 1);
  }
  return Text(value, style: style);
}

/// A bare trend line — no axes, no grid, no labels. It exists to say "rising"
/// or "falling" beside a number that already says how much.
class DsSparkline extends StatelessWidget {
  const DsSparkline({super.key, required this.values, required this.color, this.height = 26});

  final List<num> values;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) return SizedBox(height: height);
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _SparklinePainter(values, color)),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter(this.values, this.color);
  final List<num> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final lo = values.reduce(min).toDouble();
    final hi = values.reduce(max).toDouble();
    // A flat series would divide by zero; draw it down the middle instead.
    final span = (hi - lo).abs() < 1e-9 ? 1.0 : hi - lo;
    final step = size.width / (values.length - 1);
    final points = [
      for (var i = 0; i < values.length; i++)
        Offset(i * step, size.height - ((values[i] - lo) / span) * size.height)
    ];
    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      line.lineTo(p.dx, p.dy);
    }
    final fill = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: .18), color.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_SparklinePainter old) => old.values != values || old.color != color;
}

/// The branch photo the workspace sits on — the same image the section picker
/// shows, so the place you picked is the place you are working in.
///
/// The image is decoded at [_decodeWidth] and then painted across the whole
/// window, which is where the softness comes from: upscaling a small bitmap
/// blurs it for free, with none of the per-frame cost of running a real blur
/// filter over a full-screen image on every pointer move. It also keeps the
/// backdrop to a few tens of KB in memory instead of the multi-megapixel
/// original.
class BranchBackdrop {
  BranchBackdrop._();

  /// Wide enough to keep the branch recognisable — its roads, blocks and colour
  /// massing — and small enough that the upscale IS the blur.
  ///
  /// [Lg.photoField] puts the photograph behind the glass, and a lens can only
  /// show itself against DETAIL — 320 px stretched across a monitor has none
  /// left, which is the grey mush that version started out as. So that mode
  /// decodes a real one.
  static int get _decodeWidth => Lg.photoField ? 1600 : 320;

  static final ValueNotifier<ui.Image?> image = ValueNotifier(null);

  /// What [image] was decoded from, so re-selecting the same section doesn't
  /// decode again (and a late decode can't overwrite a newer one).
  static String? _key;

  static Future<void> setFromDataUrl(String? dataUrl, {required String? key}) async {
    if (key == _key) return;
    _key = key;
    if (dataUrl == null || !dataUrl.startsWith('data:')) {
      image.value = null;
      return;
    }
    try {
      final comma = dataUrl.indexOf(',');
      final bytes = base64Decode(dataUrl.substring(comma + 1));
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: _decodeWidth);
      final frame = await codec.getNextFrame();
      // A newer section was chosen while this was decoding — drop this one.
      if (_key != key) {
        frame.image.dispose();
        return;
      }
      image.value?.dispose();
      image.value = frame.image;
    } catch (_) {
      image.value = null;
    }
  }

  static void clear() {
    _key = null;
    image.value?.dispose();
    image.value = null;
  }
}

/// The workspace's ambient wash: three soft colour fields — indigo, teal and
/// amber — drifting behind everything at 16–28 % opacity.
///
/// This is what the side nav, the top bar and every [DsCard] are translucent
/// FOR. Without it the chrome and the cards sit over a flat grey and just read
/// as flat grey, so the two belong together: [DsColors.sidebar] /
/// [DsColors.topbar] / [DsColors.glass] all let this show through — which is
/// also why the fields are stated at these weights and not lower. A pane at
/// 56–80 % white swallows most of what is under it, so a wash faint enough to
/// look right on bare background disappears entirely behind a card.
///
/// The fields track the pointer by a few pixels, which is the whole reason the
/// depth reads at all — a perfectly still gradient looks like a texture, one
/// that lags the cursor looks like distance. Both the paint and the tracking
/// are cheap: the pointer position lives in a [ValueNotifier] the painter
/// repaints from, so moving the mouse never rebuilds the page on top.
class DsAmbient extends StatefulWidget {
  const DsAmbient({super.key, required this.child});

  final Widget child;

  @override
  State<DsAmbient> createState() => _DsAmbientState();
}

class _DsAmbientState extends State<DsAmbient> {
  /// Pointer offset from the centre of the window, in the range -0.5..0.5 on
  /// each axis — the same normalisation the design uses.
  final _pointer = ValueNotifier<Offset>(Offset.zero);

  @override
  void dispose() {
    _pointer.dispose();
    super.dispose();
  }

  void _onHover(PointerHoverEvent event) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || box.size.isEmpty) return;
    final local = box.globalToLocal(event.position);
    _pointer.value = Offset(
      local.dx / box.size.width - .5,
      local.dy / box.size.height - .5,
    );
  }

  @override
  Widget build(BuildContext context) {
    // The liquid theme's background HOLDS STILL. Under the flat theme the wash
    // drifting a few pixels behind the cursor is what gives it depth, but a
    // background that moves is a background the drops have to re-refract — every
    // drop samples it through one shared transform, so a pointer move repaints
    // the page. It also just reads as the floor sliding around under the glass.
    final still = MediaQuery.maybeDisableAnimationsOf(context) == true || Lg.on;
    return Stack(
      // The child used to BE the Scaffold body and so was sized tightly by it;
      // keep that, or the workspace Row falls back to loose constraints and
      // collapses to its intrinsic height.
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _DsAmbientPainter(_pointer, parallax: !still),
              isComplex: true,
              willChange: !still,
            ),
          ),
        ),
        // A Listener sees hover events even when the widget under the cursor
        // handles them — every entry on the hit-test path is dispatched to —
        // so the wash keeps tracking over buttons and menus alike.
        if (still) widget.child else Listener(onPointerHover: _onHover, child: widget.child),
      ],
    );
  }
}

/// One soft colour field: where it sits, how big, and how far it drifts.
///
/// The design states these in absolute pixels on a fixed 1920×1080 frame; here
/// the centre is a fraction of the window and the radius a fraction of its
/// shortest side, so the composition spreads with the window and the fields
/// stay circles instead of stretching into ovals on a wide monitor.
class _AmbientField {
  const _AmbientField({
    required this.color,
    required this.center,
    required this.radius,
    required this.drift,
  });

  final Color color;

  /// Where the colour peaks, as a fraction of the window. Values at or past
  /// 0/1 are intentional — the design hangs these off the edges so only an arc
  /// of each field reaches the screen.
  final Offset center;

  /// Distance from [center] to fully transparent, as a fraction of the
  /// window's shortest side.
  final double radius;

  /// Pixels of travel at the far edge of the pointer's range. Negative drifts
  /// against the cursor, which is what separates the layers.
  final double drift;
}

class _DsAmbientPainter extends CustomPainter {
  _DsAmbientPainter(this.pointer, {required this.parallax})
      : super(repaint: Listenable.merge([pointer, BranchBackdrop.image, LiquidField.version]));

  final ValueNotifier<Offset> pointer;
  final bool parallax;

  // The Halcyon login's palette, lit for daylight. Each field is one of that
  // page's night-sky colours raised to a tint a light workspace can carry:
  // violet nebulaA from the left, orchid nebulaC under the bottom edge, the
  // indigo nebulaB holding the right, and a starCool pink in the top corner.
  //
  // Taking the login's colours at their own values instead would have darkened
  // the page to the point where the glass panes and the dark text on them stop
  // separating — the login can be a night sky because everything on it is lit
  // FROM the dark; the workspace is dark-on-light and cannot.
  //
  // The weights answer to how much sits ON the wash: with [DsGlassShell]'s
  // pane over it, roughly a third of this reaches the eye, so the fields run
  // hotter than they would on a bare page. Take the pane away and these want
  // to come down by about a third, or the whole window takes the tint.
  //
  // Centre and radius are fractions of the window (the centre of its width and
  // height, the radius of its shortest side), so the composition spreads with
  // the window instead of being pinned to a reference frame.
  static const _fields = [
    _AmbientField(
      color: Color(0x94b49aec), // violet, 58 % — the key light
      center: Offset(-.02, .06),
      radius: .75,
      drift: 30,
    ),
    _AmbientField(
      color: Color(0x70dcaae4), // orchid, 44 % — bounce off the bottom edge
      center: Offset(.16, 1.06),
      radius: .65,
      drift: 16,
    ),
    _AmbientField(
      color: Color(0x709aa1de), // indigo, 44 % — the cool side
      center: Offset(1.04, .78),
      radius: .75,
      drift: -22,
    ),
    _AmbientField(
      color: Color(0x61f4cdec), // star pink, 38 % — top-right corner
      center: Offset(.92, -.08),
      radius: .55,
      drift: -14,
    ),
  ];

  /// ── DIAL: how strong the COLOUR is, flat theme. ──
  ///
  /// Scales all four fields above at once. See [LiquidField.blobStrength] for
  /// the reasoning — this is the same complaint answered in the same way, so the
  /// two themes stay recognisably the same room.
  static const _fieldStrength = .5;

  /// The sheen: one soft diagonal band of white across the composition, the way
  /// a light source rakes across a real sheet. It is what stops the wash from
  /// reading as four coloured blobs — the fields give the room its colour, this
  /// gives it a direction the light comes from.
  /// Kept faint on purpose: a white band laid over the whole window is haze,
  /// and haze is exactly what makes glass look dirty. It is here to say where
  /// the light comes from, not to add brightness.
  static const _sheen = LinearGradient(
    begin: Alignment(-1, -1.3),
    end: Alignment(1, 1.3),
    colors: [
      Color(0x00ffffff),
      Color(0x00ffffff),
      Color(0x1affffff),
      Color(0x00ffffff),
      Color(0x00ffffff),
    ],
    stops: [0, .34, .5, .68, 1],
  );

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    // The fields are deliberately larger than the window and hang off its
    // edges; without this they would paint over whatever sits outside.
    canvas.clipRect(Offset.zero & size);
    final p = parallax ? pointer.value : Offset.zero;
    if (Lg.on && _paintLiquidField(canvas, size, p)) return;
    final unit = size.shortestSide;
    // The branch photo, veiled back to a light surface. Everything in this app
    // is dark text on pale glass, so the picture can only ever be a memory of
    // itself — enough that the branch is recognisable, never enough to compete
    // with a label sitting on top of it.
    final photo = _paintBranchPhoto(canvas, size, p);
    for (final field in _fields) {
      final radius = field.radius * unit;
      final center = Offset(
            field.center.dx * size.width + p.dx * field.drift,
            field.center.dy * size.height + p.dy * field.drift,
          );
      // A circle's bounding square, so RadialGradient's radius — a fraction of
      // the shortest side — lands exactly on [radius] at 0.5.
      final rect = Rect.fromCircle(center: center, radius: radius);
      // With a photo underneath, the colour steps back: the fields are there to
      // light the room, and at full strength they turn the picture into a
      // stain. Without one they ARE the background and carry it alone — but
      // "alone" turned out to mean "visible as four coloured patches" behind a
      // table, so they are thinned by [_fieldStrength], the flat theme's twin of
      // [LiquidField.blobStrength].
      final tint = photo
          ? field.color.withValues(alpha: field.color.a * .45)
          : field.color.withValues(alpha: field.color.a * _fieldStrength);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
            radius: .5,
            colors: [tint, tint.withValues(alpha: 0)],
            // Each field fades out around seven tenths of the way, so the last
            // third is already clear — that long shoulder is what keeps the
            // edge from reading as a ring.
            stops: const [0, .7],
          ).createShader(rect),
      );
    }
    // ── THE LIGHTENING DIAL for the flat theme. ──
    //
    // The twin of [LiquidField.fieldLift], for the same reason and turned by
    // the same amount: the fields above are tuned as a composition, and one
    // veil over the finished wash lifts the page without pulling four field
    // alphas apart. Under a photo the fields have already stepped back, so the
    // veil steps back with them — the photo is dim enough as it is.
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Color(photo ? 0x24ffffff : 0x3dffffff),
    );

    // Over the top of the colour, so the sheen lights the fields rather than
    // being tinted by them. It rakes with the pointer too, at twice the drift
    // of the nearest field — a highlight moves further than what it lights.
    final full = Offset.zero & size;
    canvas.drawRect(
      full,
      Paint()
        ..shader = _sheen.createShader(full.shift(Offset(p.dx * 60, p.dy * 40))),
    );
  }

  /// The liquid theme's background: [LiquidField]'s baked image, cover-fitted.
  ///
  /// Returns false until the bake lands, so the first frame or two fall through
  /// to the flat wash below rather than flashing an empty page.
  ///
  /// The branch photo stays and is now the BASE — sharp, at
  /// [BranchBackdrop._decodeWidth]'s liquid resolution — with the colour field
  /// laid over it rather than a grey veil laid over everything.
  ///
  /// Veiling the photo back to [DsColors.scaffold] is what made the whole page
  /// read as grey, and a grey page is what made every rim come out white: a rim
  /// built by brightening the backdrop has nowhere to go from near-white. What
  /// goes over the photo instead is one light wash — enough that 11 px labels
  /// still win against it — and then the field's colour and line work, which is
  /// what the drops bend.
  bool _paintLiquidField(Canvas canvas, Size size, Offset p) {
    // Published BEFORE the bake check, so a drop painting on the same frame
    // knows where to sample even if the image only lands next frame.
    LiquidField.viewport = size;
    LiquidField.ensure();
    final field = LiquidField.image;
    if (field == null) return false;

    // One image, drawn through the same transform every drop refracts it by —
    // the branch photograph is baked INTO it rather than drawn under it, so
    // what a drop bends is exactly what the page is showing.
    canvas.save();
    canvas.transform(LiquidField.coverMatrix());
    canvas.drawImage(field, Offset.zero, Paint()..filterQuality = FilterQuality.medium);
    canvas.restore();
    return true;
  }

  /// Draws [BranchBackdrop] cover-fitted across [size] and veils it back to a
  /// working surface. Returns whether there was a photo to draw.
  bool _paintBranchPhoto(Canvas canvas, Size size, Offset p) {
    final image = BranchBackdrop.image.value;
    if (image == null) return false;
    final src = Offset.zero & Size(image.width.toDouble(), image.height.toDouble());
    // Cover: fill the window on both axes and let the long side crop, so the
    // photo is never letterboxed against the page colour.
    final scale = max(size.width / image.width, size.height / image.height);
    final w = image.width * scale;
    final h = image.height * scale;
    // Drifts with the pointer like the fields, but least of all — it is the
    // furthest thing away, and distant things move least.
    final dst = Rect.fromLTWH(
      (size.width - w) / 2 + p.dx * 14,
      (size.height - h) / 2 + p.dy * 10,
      w,
      h,
    );
    canvas.drawImageRect(image, src, dst, Paint()..filterQuality = FilterQuality.high);
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = DsColors.scaffold.withValues(alpha: .84),
    );
    return true;
  }

  @override
  bool shouldRepaint(_DsAmbientPainter old) => old.parallax != parallax;
}

/// The pane of glass the whole workspace sits on: the side nav, the top bar
/// and the page all live INSIDE this, with [DsAmbient]'s wash running past its
/// edges.
///
/// The pane earns its keep by being a LAYER, not by the margin around it. It
/// puts one light surface between the cards and the wash, which is what gives
/// a card something to sit on and be brighter than; without it the cards float
/// straight on the coloured background and the page flattens out. So [inset] is
/// deliberately small — just enough for the rounded corner to read and for the
/// shadow to have somewhere to fall.
///
/// No BackdropFilter: what is behind this is [DsAmbient]'s smooth gradient, and
/// blurring a smooth gradient returns the same gradient — at the cost of
/// re-reading the entire window every frame. Blur is for [DsFrosted], over
/// content that actually moves.
class DsGlassShell extends StatelessWidget {
  const DsGlassShell({super.key, required this.child, this.inset = 8, this.radius = 18});

  final Widget child;
  final double inset;
  final double radius;

  @override
  Widget build(BuildContext context) {
    // The pane the workspace sits on is the largest piece of glass in the app,
    // so its rim runs at roughly half strength and on a narrower band — at card
    // weight a 20 px halo down all four sides of the window reads as a vignette.
    final corner = BorderRadius.circular(Lg.on ? radius * 1.4 : radius);
    return Padding(
      padding: EdgeInsets.all(inset),
      child: Container(
        decoration: BoxDecoration(
          // NO PANE under the liquid theme.
          //
          // This layer exists to give cards something to be brighter than —
          // essential when a card is a near-solid plate on a flat wash. When a
          // card is a drop it is doing that itself, and this becomes a sheet of
          // translucent white lying across the whole window, visible in every
          // gap between cards. On the Approval Inbox that is exactly what it
          // looked like: a background running BETWEEN the groups and joining
          // them into one slab.
          //
          // The rim below stays — the workspace still wants an edge, it just
          // doesn't want a floor.
          gradient: Lg.on
              ? null
              : const LinearGradient(
                  // Lit at the top-left corner, in shade at the bottom-right —
                  // the same rake as [DsCard], one layer down and half strength.
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [DsColors.shellGlass, Color(0x24ffffff)],
                ),
          borderRadius: corner,
          // Kept short on purpose: at this inset a long cast would run off the
          // window and clip flat against the edge, which reads as a seam.
          boxShadow: Lg.on
              ? null
              : [
                  const BoxShadow(color: DsColors.shellShadow, blurRadius: 20, offset: Offset(0, 5)),
                ],
        ),
        // Drawn OVER the child, so the lit edge stays unbroken where the nav's
        // border and the top bar run into it.
        foregroundDecoration: BoxDecoration(
          borderRadius: corner,
          border: Lg.on
              ? const LiquidRim(band: 13, strength: .5)
              : Border.all(color: DsColors.shellEdge),
        ),
        child: ClipRRect(borderRadius: corner, child: child),
      ),
    );
  }
}

/// Plays a one-shot "arrive" animation (fade + a short travel) the first time it
/// is built — used to stagger the shell when a section is opened. Give it a
/// [key] that changes when the entrance should play again (e.g. the section
/// code); with a stable key it stays put through ordinary rebuilds.
class DsEnter extends StatelessWidget {
  const DsEnter({
    super.key,
    required this.child,
    this.shift = const Offset(0, 10),
    this.delay = Duration.zero,
    this.duration = DsMotion.enter,
    this.curve = DsMotion.curveIn,
  });

  final Widget child;

  /// Where the child starts, in logical pixels, relative to its final spot.
  final Offset shift;
  final Duration delay;
  final Duration duration;
  final Curve curve;

  @override
  Widget build(BuildContext context) {
    final total = DsMotion.of(context, delay + duration);
    if (total == Duration.zero) return child;
    final start = delay.inMicroseconds / total.inMicroseconds;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: total,
      curve: Interval(start.clamp(0.0, .95), 1, curve: curve),
      builder: (context, t, child) => Opacity(
        // easeOutBack overshoots past 1, which Opacity rejects outright.
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(offset: shift * (1 - t), child: child),
      ),
      child: child,
    );
  }
}

/// IBM Plex Mono text style for codes, dates, numbers (e.g. request_no).
TextStyle mono({double size = 12, FontWeight weight = FontWeight.w500, Color? color}) => TextStyle(
    fontFamily: dsFontMono, fontFamilyFallback: dsFontFallback, fontSize: size, fontWeight: weight, color: color);

class StatusStyle {
  const StatusStyle(this.fg, this.bg, this.bar, this.label);
  final Color fg;
  final Color bg;
  final Color bar;
  final String label;
}

StatusStyle statusStyle(String status) {
  return switch (status.toUpperCase()) {
    'IN_PROGRESS' => const StatusStyle(DsColors.blueFg, DsColors.blueBg, DsColors.blueFg, 'In progress'),
    'ON_HOLD' => const StatusStyle(DsColors.holdFg, DsColors.holdBg, DsColors.holdBar, 'On hold'),
    'WAITING_CLOSE' => const StatusStyle(DsColors.purpleFg, DsColors.purpleBg, DsColors.purpleFg, 'Waiting close'),
    'COMPLETED' => const StatusStyle(DsColors.greenFg, DsColors.greenBg, DsColors.greenDot, 'Completed'),
    'PENDING_APPROVAL' => const StatusStyle(DsColors.amberFg, DsColors.amberBg, DsColors.amberBar, 'Pending'),
    'REJECTED' => const StatusStyle(DsColors.redFg, DsColors.redBg, DsColors.redBadge, 'Rejected'),
    'CANCELLED' => const StatusStyle(DsColors.muted, DsColors.track, DsColors.faint2, 'Cancelled'),
    _ => StatusStyle(DsColors.navy, DsColors.navySoft, DsColors.navy, _titleCase(status)),
  };
}

const _priorityRank = {'LOW': 0, 'NORMAL': 1, 'HIGH': 2, 'URGENT': 3};

List<String> priorityOrder(List<String> raw) {
  final list = [...raw];
  list.sort((a, b) => (_priorityRank[a.toUpperCase()] ?? 99).compareTo(_priorityRank[b.toUpperCase()] ?? 99));
  return list;
}

Color priorityColor(String priority) {
  return switch (priority.toUpperCase()) {
    'LOW' => DsColors.greenDot,
    'NORMAL' => DsColors.blueFg,
    'HIGH' => DsColors.amberBar,
    'URGENT' => DsColors.redBadge,
    _ => DsColors.faint2,
  };
}

String _titleCase(String raw) {
  final cleaned = raw.replaceAll('_', ' ').toLowerCase().trim();
  if (cleaned.isEmpty) return raw;
  return cleaned[0].toUpperCase() + cleaned.substring(1);
}

String initialsFrom(String? raw) {
  final value = (raw ?? '').trim();
  if (value.isEmpty) return '?';
  final parts = value.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.length == 1) {
    return parts.first.substring(0, min(2, parts.first.length)).toUpperCase();
  }
  return (parts.first[0] + parts[1][0]).toUpperCase();
}

/// Avatar initials: when a full name is set, use the first letter of the first
/// and last word (e.g. "Sirawit Kaewchoo" → "SK"). Otherwise fall back to the
/// first two letters of the display name.
String avatarInitials(String? fullName, String? displayName) {
  final full = (fullName ?? '').trim();
  if (full.isNotEmpty) {
    final parts = full.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) return (parts.first[0] + parts.last[0]).toUpperCase();
    if (parts.isNotEmpty) return parts.first.substring(0, min(2, parts.first.length)).toUpperCase();
  }
  final name = (displayName ?? '').trim();
  if (name.isEmpty) return '?';
  return name.substring(0, min(2, name.length)).toUpperCase();
}

/// Avatar colours stay on the ORIGINAL pre-indigo palette on purpose. People
/// learn a colleague's avatar by its colour, so re-tinting it to the new accent
/// family changed who a chip looked like — the one place where following the
/// redesign costs more than it gains.
const _avatarPalette = [
  Color(0xff1f2a63),
  Color(0xff2f6bed),
  Color(0xff6d5ef0),
  Color(0xff15803d),
  Color(0xffb4690e),
  Color(0xffc0322b),
  Color(0xff0e7490),
  Color(0xff7c3aed),
];

Color avatarColorFor(String? seed) {
  final value = seed ?? '';
  // Nameless fallback comes from the same palette, not the app accent.
  if (value.isEmpty) return _avatarPalette.first;
  var hash = 0;
  for (final code in value.codeUnits) {
    hash = (hash * 31 + code) & 0x7fffffff;
  }
  return _avatarPalette[hash % _avatarPalette.length];
}

// ----------------------------------------------------------------------------
// Reusable widgets
// ----------------------------------------------------------------------------

/// The app's one card surface: a pane of glass over [DsAmbient]'s wash.
///
/// Every card in the app comes through here (directly, or via `Panel` /
/// `MetricTile`), so the glass treatment lives at this one point rather than
/// being re-declared at ~25 call sites.
///
/// Three things make it read as glass, and only the first is about opacity:
/// the pane is translucent so the wash tints it, [DsColors.glassEdge] catches
/// light along the border, and the two shadows separate it from the page.
///
/// What it does NOT do is blur. A BackdropFilter re-reads and re-blurs
/// everything painted beneath it every frame, and behind a card there is only
/// the smooth ambient gradient — blurring a smooth gradient returns the same
/// gradient, so a per-card filter would buy nothing at real cost across a page
/// of them. Blur belongs where content genuinely passes behind: the top bar,
/// dialogs, menus. Reach for [DsFrosted] there.
///
/// Pass `glass: false` for a card that must be opaque — one sitting on white,
/// or one whose own [color] is the point.
class DsCard extends StatelessWidget {
  const DsCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.color = Colors.white,
    // The design's card corner. Deliberately large — at 12 the cards read as
    // table cells, which is the look this redesign is moving away from, and a
    // pane of glass with a tight corner reads as a cut tile rather than a
    // rounded sheet.
    this.radius = 20,
    this.border,
    this.clip = false,
    this.glass = true,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final double radius;
  final Border? border;
  final bool clip;
  final bool glass;

  @override
  Widget build(BuildContext context) {
    // Under the liquid theme a card is a DROP, and a drop cannot be a
    // decoration: the body of it is the background blurred through it, which
    // takes a BackdropFilter of its own. See [LiquidPane].
    if (glass && Lg.on) {
      return LiquidPane(
        radius: radius,
        color: color,
        padding: padding,
        border: border,
        // The blur is always clipped to the drop; [clip] is about the CONTENT,
        // and most cards want their menus and badges to hang past the edge.
        clipContent: clip,
        child: child,
      );
    }
    return Container(
      clipBehavior: clip ? Clip.antiAlias : Clip.none,
      // The lit gradient, the white edge and the two shadows all live in
      // [dsGlassDecoration] so the hand-rolled cards elsewhere can share them.
      decoration: glass
          ? dsGlassDecoration(radius: radius, color: color).copyWith(border: border)
          : BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(radius),
              border: border ?? Border.all(color: DsColors.cardBorder),
            ),
      padding: padding,
      child: child,
    );
  }
}

/// [DsCard]'s surface as a bare decoration, for the places that hand-roll their
/// own card because they need a Container for something else (a margin, a clip,
/// an animated colour). Same pane, same lit edge, same pair of shadows — so a
/// hand-rolled card never drifts back to being an opaque white rectangle.
BoxDecoration dsGlassDecoration({
  double radius = 20,
  Color color = Colors.white,
  Color? borderColor,
  double borderWidth = 1,

  /// Multiplies the liquid theme's fill. Above 1 for a card that is stacked
  /// INSIDE another pane — a card on the field can be 55 % white and still read
  /// as white, but 55 % white over a second pane is 55 % of the way to grey.
  /// Ignored by the flat theme, whose panes are near-solid either way.
  double scale = 1,
}) {
  // The one place the two themes fork for cards: every DsCard and every
  // hand-rolled pane in the app comes through here, so the liquid theme needs
  // no edit at the call sites. See shared/liquid_glass.dart.
  if (Lg.on) {
    return lgGlass(
        radius: radius, color: color, scale: scale, borderColor: borderColor, borderWidth: borderWidth);
  }
  return _dsFlatGlassDecoration(radius: radius, color: color, borderColor: borderColor, borderWidth: borderWidth);
}

/// The original flat-glassmorphism pane, kept whole so the theme switch has
/// something to switch back to.
BoxDecoration _dsFlatGlassDecoration({
  double radius = 20,
  Color color = Colors.white,
  Color? borderColor,
  double borderWidth = 1,
}) =>
    BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          color.withValues(alpha: DsColors.glass.a),
          color.withValues(alpha: DsColors.glassLow.a),
        ],
      ),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: borderColor ?? DsColors.glassEdge, width: borderWidth),
      boxShadow: const [
        BoxShadow(color: DsColors.glassShadow, blurRadius: 26, offset: Offset(0, 10)),
        BoxShadow(color: DsColors.glassContact, blurRadius: 2, offset: Offset(0, 1)),
      ],
    );

class DsCardTitle extends StatelessWidget {
  const DsCardTitle(this.title, {super.key, this.trailing, this.icon});
  final String title;
  final Widget? trailing;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      if (icon != null) ...[
        Icon(icon, color: DsColors.navy, size: 18),
        const SizedBox(width: 8),
      ],
      Expanded(child: Text(title, style: DsType.cardTitle)),
      if (trailing != null) trailing!,
    ]);
  }
}

class DsStatusBadge extends StatelessWidget {
  const DsStatusBadge({super.key, required this.status});
  final String status;
  @override
  Widget build(BuildContext context) {
    final s = statusStyle(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: s.bg, borderRadius: BorderRadius.circular(20)),
      child: Text(s.label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: s.fg)),
    );
  }
}

/// Gold pill marking a request as KPI-tracked. Subtle glow + a slow shine sweep
/// (animated) so it stands out from the plain status/type tags. Use
/// `compact: true` inside dense table rows and `animated: false` in long lists.
class KpiBadge extends StatefulWidget {
  const KpiBadge({super.key, this.compact = false, this.animated = true});
  final bool compact;
  final bool animated;
  @override
  State<KpiBadge> createState() => _KpiBadgeState();
}

class _KpiBadgeState extends State<KpiBadge> with SingleTickerProviderStateMixin {
  AnimationController? _shine;

  @override
  void initState() {
    super.initState();
    if (widget.animated) {
      _shine = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..repeat();
    }
  }

  @override
  void dispose() {
    _shine?.dispose();
    super.dispose();
  }

  static const _gold = Color(0xffb8860b);
  static const _goldText = Color(0xff8a5a00);

  @override
  Widget build(BuildContext context) {
    final fontSize = widget.compact ? 9.5 : 11.0;
    final hPad = widget.compact ? 6.0 : 9.0;
    final vPad = widget.compact ? 1.5 : 3.0;
    const radius = 999.0;

    return Tooltip(
      message: 'KPI-tracked request',
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [BoxShadow(color: _gold.withValues(alpha: .18), blurRadius: 8, spreadRadius: .3)],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Stack(children: [
            Container(
              padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xfffdf4d8), Color(0xfff6e09c)],
                ),
                borderRadius: BorderRadius.circular(radius),
                border: Border.all(color: _gold.withValues(alpha: .55), width: 1),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.insights_rounded, size: fontSize + 2, color: _gold),
                SizedBox(width: widget.compact ? 3 : 4),
                Text('KPI',
                    style: TextStyle(
                        fontSize: fontSize, fontWeight: FontWeight.w800, color: _goldText, letterSpacing: .3)),
              ]),
            ),
            if (_shine != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: LayoutBuilder(builder: (context, constraints) {
                    return AnimatedBuilder(
                      animation: _shine!,
                      builder: (context, child) {
                        final travel = constraints.maxWidth + 40;
                        return Transform.translate(
                          offset: Offset(-40 + travel * _shine!.value, 0),
                          child: child,
                        );
                      },
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          width: 26,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: [
                              Colors.white.withValues(alpha: 0),
                              Colors.white.withValues(alpha: .55),
                              Colors.white.withValues(alpha: 0),
                            ]),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

class DsTag extends StatelessWidget {
  const DsTag(this.text, {super.key, this.color, this.bg});
  final String text;
  final Color? color;
  final Color? bg;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: bg ?? DsColors.chip, borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: color ?? DsColors.muted)),
    );
  }
}

class DsDot extends StatelessWidget {
  const DsDot(this.color, {super.key, this.size = 8});
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) =>
      Container(width: size, height: size, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
}

class DsPriority extends StatelessWidget {
  const DsPriority(this.priority, {super.key, this.showLabel = true});
  final String priority;
  final bool showLabel;
  @override
  Widget build(BuildContext context) {
    final dot = DsDot(priorityColor(priority), size: 7);
    if (!showLabel) return dot;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      dot,
      const SizedBox(width: 5),
      Text('${_titleCase(priority)} priority', style: const TextStyle(fontSize: 11, color: DsColors.faint2)),
    ]);
  }
}

class DsSectionLabel extends StatelessWidget {
  const DsSectionLabel(this.text, {super.key, this.color = DsColors.icon});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return Text(text.toUpperCase(),
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color, letterSpacing: .4));
  }
}

class DsProgressBar extends StatelessWidget {
  const DsProgressBar({super.key, required this.value, this.color = DsColors.navy, this.height = 7});
  final double value; // 0..1
  final Color color;
  final double height;

  Widget _bar(double v) => ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: LinearProgressIndicator(
          value: v,
          minHeight: height,
          backgroundColor: DsColors.track,
          valueColor: AlwaysStoppedAnimation(color),
        ),
      );

  @override
  Widget build(BuildContext context) {
    // Fills from empty when it first appears — the length IS the datum, so the
    // bar draws itself rather than being there already. On later rebuilds the
    // tween runs from wherever the bar is now, so a progress change slides
    // instead of jumping.
    final duration = DsMotion.of(context, const Duration(milliseconds: 620));
    final target = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    if (duration == Duration.zero) return _bar(target);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: target),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => _bar(v),
    );
  }
}

/// Global online-presence state, fed by the shell from `presence.updated`
/// socket events. Every DsAvatar listens to [onlineNames] so presence dots
/// update live everywhere without threading state through each page.
class PresenceStore {
  PresenceStore._();
  // Display names of users with an open realtime connection right now.
  static final ValueNotifier<Set<String>> onlineNames = ValueNotifier(<String>{});
  // Distinct online users — shown in the top bar and on the login page.
  static final ValueNotifier<int> onlineCount = ValueNotifier(0);
  // Who those people are ({'name', 'fullName'}) — feeds the online pill's
  // hover preview and its "who's online" popup. Filled from the socket once
  // logged in, and from /health on the login page (no socket there yet).
  static final ValueNotifier<List<Map<String, String>>> onlineUsers = ValueNotifier(const <Map<String, String>>[]);

  // Replaces every presence value from one list of online users. Each notifier
  // is only assigned when its CONTENT changed: presence ticks on every focus
  // change now, and a fresh Set/List instance would notify every DsAvatar in
  // the app on each tick (a full-page rebuild storm) even when nobody moved.
  static void setUsers(List<Map<String, String>> users) {
    final names = {
      for (final u in users)
        if ((u['name'] ?? '').trim().isNotEmpty) u['name']!.trim(),
    };
    final current = onlineNames.value;
    if (names.length != current.length || !names.every(current.contains)) {
      onlineNames.value = names;
    }
    if (!_sameUsers(users, onlineUsers.value)) onlineUsers.value = users;
    onlineCount.value = users.length; // int compares by value — safe to assign
  }

  static bool _sameUsers(List<Map<String, String>> a, List<Map<String, String>> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i]['name'] != b[i]['name'] || a[i]['fullName'] != b[i]['fullName'] || a[i]['section'] != b[i]['section']) {
        return false;
      }
    }
    return true;
  }

  static void reset() {
    onlineNames.value = <String>{};
    onlineCount.value = 0;
    onlineUsers.value = const <Map<String, String>>[];
  }
}

/// Live "who is where" state (SharePoint-style), fed by the shell from
/// `presence.updated` socket events. The shell already filters out the current
/// user, so every list here means OTHER people.
class FocusStore {
  FocusStore._();
  // requestId -> users with that request-detail dialog open right now.
  static final ValueNotifier<Map<int, List<Map<String, String>>>> requestViewers =
      ValueNotifier(const <int, List<Map<String, String>>>{});
  // todoId -> users editing that todo right now.
  static final ValueNotifier<Map<int, List<Map<String, String>>>> todoEditors =
      ValueNotifier(const <int, List<Map<String, String>>>{});
  // Weekly-plan cell key ("<weekStart>|u<userId>|<day>") -> users editing it —
  // already scoped to the CURRENT section by the shell.
  static final ValueNotifier<Map<String, List<Map<String, String>>>> planEditors =
      ValueNotifier(const <String, List<Map<String, String>>>{});

  // Assign through these so a presence tick that changed nothing doesn't notify
  // every badge/cell listening — a fresh Map instance always would.
  static void setRequestViewers(Map<int, List<Map<String, String>>> next) {
    if (!_same(requestViewers.value, next)) requestViewers.value = next;
  }

  static void setTodoEditors(Map<int, List<Map<String, String>>> next) {
    if (!_same(todoEditors.value, next)) todoEditors.value = next;
  }

  static void setPlanEditors(Map<String, List<Map<String, String>>> next) {
    if (!_same(planEditors.value, next)) planEditors.value = next;
  }

  // Same keys, same people (by display name) in the same order.
  static bool _same<K>(Map<K, List<Map<String, String>>> a, Map<K, List<Map<String, String>>> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      final other = b[entry.key];
      if (other == null || other.length != entry.value.length) return false;
      for (var i = 0; i < other.length; i++) {
        if (other[i]['name'] != entry.value[i]['name']) return false;
      }
    }
    return true;
  }

  static void reset() {
    requestViewers.value = const <int, List<Map<String, String>>>{};
    todoEditors.value = const <int, List<Map<String, String>>>{};
    planEditors.value = const <String, List<Map<String, String>>>{};
  }
}

/// Overlapping mini avatars of people live inside something right now (viewing
/// a request, editing a cell…), with a tooltip naming them. Renders nothing
/// when [users] is empty, so it can sit unconditionally in any row.
class DsLiveAvatars extends StatelessWidget {
  const DsLiveAvatars({super.key, required this.users, this.size = 22, this.action = 'viewing'});
  final List<Map<String, String>> users;
  final double size;
  // Verb used in the tooltip: "<names> is/are <action> now".
  final String action;

  @override
  Widget build(BuildContext context) {
    if (users.isEmpty) return const SizedBox.shrink();
    final shown = users.take(3).toList();
    final extra = users.length - shown.length;
    final names = [
      for (final u in users) (u['fullName'] ?? '').trim().isNotEmpty ? u['fullName']! : (u['name'] ?? ''),
    ].where((n) => n.trim().isNotEmpty).join(', ');
    final overlap = size * .62;
    return Tooltip(
      message: '$names ${users.length == 1 ? 'is' : 'are'} $action now',
      child: SizedBox(
        height: size + 4,
        width: overlap * (shown.length - 1) + size + 4 + (extra > 0 ? size * .9 : 0),
        child: Stack(clipBehavior: Clip.none, children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * overlap,
              top: 2,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xff22c55e), width: 1.6),
                ),
                child:
                    DsAvatar(name: shown[i]['name'], fullName: shown[i]['fullName'], size: size, showPresence: false),
              ),
            ),
          if (extra > 0)
            Positioned(
              left: shown.length * overlap,
              top: 2,
              child: Container(
                width: size,
                height: size,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: DsColors.chip, shape: BoxShape.circle),
                child: Text('+$extra',
                    style: TextStyle(fontSize: size * .38, fontWeight: FontWeight.w700, color: DsColors.text2)),
              ),
            ),
        ]),
      ),
    );
  }
}

/// [DsLiveAvatars] bound to [FocusStore.requestViewers] for one request — drop
/// it into any request row and it lights up whenever someone else is inside.
class RequestViewersBadge extends StatelessWidget {
  const RequestViewersBadge({super.key, required this.requestId, this.size = 22});
  final int? requestId;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (requestId == null) return const SizedBox.shrink();
    return ValueListenableBuilder<Map<int, List<Map<String, String>>>>(
      valueListenable: FocusStore.requestViewers,
      builder: (context, viewers, _) =>
          DsLiveAvatars(users: viewers[requestId] ?? const [], size: size, action: 'in this request'),
    );
  }
}

/// Global profile-picture state, loaded by the shell from `/users/avatars`
/// (display name → image data URL). Every DsAvatar listens to [byName] so an
/// uploaded picture replaces the initials everywhere without threading state
/// through each page — same name-keyed pattern as [PresenceStore].
class AvatarStore {
  AvatarStore._();
  static final ValueNotifier<Map<String, String>> byName = ValueNotifier(<String, String>{});

  static void reset() {
    byName.value = <String, String>{};
  }
}

/// `frameBuilder` for a photo that REPLACES something — an avatar's initials, a
/// badge's empty portrait: the placeholder fades out as the photo fades in, and
/// is gone once it has arrived.
///
/// The "and is gone" is the point. Leaving the placeholder underneath is free
/// while photos are opaque, and wrong the moment one is not: a PNG saved with a
/// transparent background is meant to show the surface behind it.
Widget dsPhotoOverInitials(
  BuildContext context,
  Widget child,
  int? frame,
  bool wasSynchronouslyLoaded, {
  required Widget placeholder,
}) {
  if (wasSynchronouslyLoaded) return child;
  final ready = frame != null;
  final d = DsMotion.of(context, DsMotion.chrome);
  return Stack(fit: StackFit.expand, children: [
    AnimatedOpacity(opacity: ready ? 0 : 1, duration: d, curve: DsMotion.curveOut, child: placeholder),
    AnimatedOpacity(opacity: ready ? 1 : 0, duration: d, curve: DsMotion.curveIn, child: child),
  ]);
}

/// `frameBuilder` for any [Image] that arrives over the network: fades the first
/// decoded frame in instead of snapping it to full opacity.
///
/// The `wasSynchronouslyLoaded` check is the part that is easy to leave out and
/// wrong to leave out. An image already in the cache is handed over complete on
/// the very first build, and fading THAT in turns a free, instant paint into a
/// quarter-second of translucency every time the widget is rebuilt — every page
/// change, every scroll that recycles the row. Cached means no animation.
Widget dsImageFadeIn(BuildContext context, Widget child, int? frame, bool wasSynchronouslyLoaded) {
  if (wasSynchronouslyLoaded) return child;
  return AnimatedOpacity(
    opacity: frame == null ? 0 : 1,
    duration: DsMotion.of(context, DsMotion.chrome),
    curve: DsMotion.curveIn,
    child: child,
  );
}

class DsAvatar extends StatelessWidget {
  const DsAvatar(
      {super.key,
      required this.name,
      this.fullName,
      this.size = 30,
      this.color,
      this.radius,
      this.showPresence = false});
  final String? name;
  // When set, initials use the first + last name; otherwise the display name.
  final String? fullName;
  final double size;
  final Color? color;
  final double? radius; // null => circle
  // Presence dot (green = online, grey = offline). On by default everywhere.
  final bool showPresence;
  @override
  Widget build(BuildContext context) {
    // Uploaded profile pictures come from the global AvatarStore (keyed by
    // display name, like presence); listening here means every avatar in the
    // app swaps initials for the photo the moment it loads or changes.
    final avatar = ValueListenableBuilder<Map<String, String>>(
      valueListenable: AvatarStore.byName,
      builder: (context, avatars, _) {
        final initials = Text(avatarInitials(fullName, name),
            style: TextStyle(color: Colors.white, fontSize: size * .36, fontWeight: FontWeight.w700));
        final photo = avatars[(name ?? '').trim()];
        final shape = radius == null ? BoxShape.circle : BoxShape.rectangle;
        final borderRadius = radius == null ? null : BorderRadius.circular(radius!);
        // The person's colour belongs to the initials only. Painted on the
        // avatar itself it sat behind the photo too, so a cut-out PNG came out
        // on a coloured disc instead of showing the surface behind it.
        final disc = Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: color ?? avatarColorFor(name), shape: shape, borderRadius: borderRadius),
          child: initials,
        );
        if (photo == null) return disc;
        return Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(shape: shape, borderRadius: borderRadius),
          // The initials are not CUT for the photo, the two cross-fade: photos
          // arrive from [AvatarStore] after the page has already drawn, each
          // whenever its own request finishes, and cut straight in a wall of
          // avatars on the Dashboard or the org chart turns from letters into
          // faces in a ragged little cascade — the clearest "this is a web page
          // loading" tell the app had. A failed or slow image keeps the
          // coloured, named circle, so the avatar is never empty at any point.
          //
          // The initials do have to END at nothing, though, rather than staying
          // under the photo as they used to: a profile picture saved as a PNG
          // with a transparent background shows whatever is behind it, and what
          // was behind it was a pair of letters.
          child: Image.network(photo,
              width: size,
              height: size,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
              frameBuilder: (context, child, frame, wasSynchronouslyLoaded) =>
                  dsPhotoOverInitials(context, child, frame, wasSynchronouslyLoaded, placeholder: disc),
              // Back to the coloured letters — they are the fallback.
              errorBuilder: (context, error, stack) => disc),
        );
      },
    );
    if (!showPresence) return avatar;
    final dotSize = (size * .34).clamp(8.0, 12.0);
    return ValueListenableBuilder<Set<String>>(
      valueListenable: PresenceStore.onlineNames,
      builder: (context, online, _) {
        final key = (name ?? '').trim();
        final isOnline = key.isNotEmpty && online.contains(key);
        return Stack(clipBehavior: Clip.none, children: [
          avatar,
          Positioned(
            right: -1.5,
            bottom: -1.5,
            child: Container(
              width: dotSize,
              height: dotSize,
              decoration: BoxDecoration(
                color: isOnline ? const Color(0xff22c55e) : const Color(0xffb8bfd1),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.6),
              ),
            ),
          ),
        ]);
      },
    );
  }
}

class DsIconButton extends StatelessWidget {
  const DsIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.size = 38,
    this.color = DsColors.text2,
    this.iconSize = 20,
  });
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final double size;
  final Color color;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(Lg.r(9, max: 14));
    // No fill and no edge at rest — the top bar's controls read as icons, and
    // only the hover state draws a surface. This matches the notification bell,
    // which never had a tile.
    //
    // Under liquid glass they DO get a resting surface: a well sunk into the
    // pane, the way every icon control in the reference sits in one. An icon
    // floating on bare glass has nothing to be in front of.
    final btn = Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: radius),
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        hoverColor: Lg.on ? const Color(0x59ffffff) : DsColors.chip,
        child: Lg.on
            ? DecoratedBox(
                decoration: lgWell(radius: 9, scale: .8),
                child: SizedBox(width: size, height: size, child: Icon(icon, size: iconSize, color: color)),
              )
            : SizedBox(width: size, height: size, child: Icon(icon, size: iconSize, color: color)),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}

class DsHealthPill extends StatelessWidget {
  const DsHealthPill({super.key, required this.label, required this.ok, this.compact = false, this.description});
  final String label;
  final bool ok;
  final bool compact;
  // Plain-language explanation of what this service is, shown on hover.
  final String? description;
  @override
  Widget build(BuildContext context) {
    final fg = ok ? DsColors.greenFg : DsColors.amberFg;
    final bg = ok ? DsColors.greenBg : DsColors.amberCardBg;
    final dot = ok ? DsColors.greenDot : DsColors.amberFg;
    final pill = Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 9 : 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        DsDot(dot, size: compact ? 6 : 7),
        const SizedBox(width: 6),
        Text(compact ? label : '$label ${ok ? 'online' : 'offline'}',
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: fg)),
      ]),
    );
    if (description == null) return pill;
    return Tooltip(
      message: '$label — $description\nStatus: ${ok ? 'online (working normally)' : 'offline (not reachable)'}',
      waitDuration: const Duration(milliseconds: 300),
      child: pill,
    );
  }
}

// Hover text for the two service pills, shared by the top bar and the login
// page so both explain the same thing.
const String dsApiPillDescription = 'the backend service that runs the app';
const String dsSqlPillDescription = 'the database that stores all data';

class DsEmptyState extends StatelessWidget {
  const DsEmptyState({super.key, required this.icon, required this.message, this.padding = 44});
  final IconData icon;
  final String message;
  final double padding;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(padding),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 42, color: DsColors.iconSoft),
          const SizedBox(height: 10),
          Text(message, style: const TextStyle(fontSize: 14, color: DsColors.faint2)),
        ]),
      ),
    );
  }
}

/// Drag state shared between a [Draggable] and the card floating under the
/// cursor, so the ghost can be told how fast it is moving.
///
/// Flutter's `feedback` widget is built once and then simply follows the
/// pointer: it never learns the drag's speed or direction, which is why the
/// default ghost is a rectangle sliding around at a constant attitude. Pushing
/// each `onDragUpdate` delta through here gives [DsDragGhost] the one number it
/// needs to behave like something being carried.
class DsDragGhostController extends ChangeNotifier {
  /// Pointer movement since the last frame, in logical pixels.
  Offset delta = Offset.zero;

  /// Milliseconds-since-epoch of the last push — the ghost levels off when the
  /// deltas stop arriving, which is what happens when the hand stops moving
  /// without letting go.
  int at = 0;

  void push(Offset d) {
    delta = d;
    at = DateTime.now().millisecondsSinceEpoch;
    notifyListeners();
  }
}

/// The card in the air. Tilts into the direction it is being thrown, rises as
/// it goes faster, and levels off when the hand stops.
///
/// ── Why bother ─────────────────────────────────────────────────────────────
///
/// A drag is the one interaction in this app where the user is holding
/// something rather than pressing it, and a ghost that stays perfectly flat and
/// perfectly still tells them they are pushing a decal around. Everything
/// physical leans when it is swung: the lean is what makes the weight legible,
/// and the weight is what makes the drop feel deliberate.
///
/// ── What it does, in order of how much it matters ──────────────────────────
///
/// 1. **Tilt** from horizontal speed, capped at about five degrees. Past that
///    it stops reading as momentum and starts reading as a bug.
/// 2. **Shadow** that deepens and drops further with speed — the card is
///    higher off the board when it is travelling.
/// 3. **Scale**, barely: one or two percent. Enough to separate it from the
///    hole it left behind.
///
/// All three are driven off ONE smoothed velocity, so they can never disagree
/// with each other.
class DsDragGhost extends StatefulWidget {
  const DsDragGhost({super.key, required this.controller, required this.child});

  final DsDragGhostController controller;
  final Widget child;

  @override
  State<DsDragGhost> createState() => _DsDragGhostState();
}

class _DsDragGhostState extends State<DsDragGhost> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;

  /// Smoothed horizontal speed, px/frame. Smoothed rather than used raw because
  /// a trackpad delivers deltas in bursts, and a tilt driven by the raw value
  /// jitters instead of leaning.
  double _vx = 0;
  double _speed = 0;

  /// Radians. Follows [_vx] with its own lag so the card keeps leaning for a
  /// moment after the hand changes direction, the way a held object would.
  double _angle = 0;

  static const double _maxTilt = .085; // ~5°

  @override
  void initState() {
    super.initState();
    _ticker = Ticker(_onFrame)..start();
  }

  void _onFrame(Duration _) {
    // Deltas older than ~80 ms mean the hand has stopped; decay to level rather
    // than holding the last lean, which would look stuck.
    final bool fresh = DateTime.now().millisecondsSinceEpoch - widget.controller.at < 80;
    final Offset d = fresh ? widget.controller.delta : Offset.zero;
    _vx += (d.dx - _vx) * .25;
    _speed += (d.distance - _speed) * .25;
    final double target = (_vx / 26).clamp(-1.0, 1.0) * _maxTilt;
    final double next = _angle + (target - _angle) * .16;
    // Below a tenth of a degree nothing is visible; skip the rebuild so a
    // stationary ghost is not repainting sixty times a second.
    if ((next - _angle).abs() < .0015 && (next - _angle) != 0) return;
    setState(() => _angle = next);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double lift = (_speed / 22).clamp(0.0, 1.0);
    return Transform.rotate(
      angle: _angle,
      child: Transform.scale(
        scale: 1.02 + .02 * lift,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .10 + .12 * lift),
                blurRadius: 14 + 22 * lift,
                offset: Offset(0, 6 + 10 * lift),
              ),
            ],
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Cross-fade between a loading placeholder and the thing it stood in for.
///
/// Every skeleton in this app used to be a bare ternary — `loading ? ghost :
/// content` — which means the ghost is replaced by real data in the gap between
/// two frames. The effect at a normal request latency is a hard cut: grey bars
/// for 400 ms, then a table, with nothing connecting them. It reads as a
/// glitch, and on a slow query it reads as two separate page loads.
///
/// Fading between them costs one widget and says the obvious true thing — that
/// the ghost WAS the table, waiting.
///
/// The layout rule is the part worth knowing: the outgoing child is painted but
/// does not vote on the size. Without that, a 5-row skeleton standing in for a
/// 40-row table makes the panel snap to the taller of the two for the length of
/// the fade and then collapse. Here the panel takes the shape of whatever is
/// ARRIVING, and only the paint dissolves.
class DsSwap extends StatelessWidget {
  const DsSwap({super.key, required this.loading, required this.skeleton, required this.child});

  final bool loading;

  /// Shown while [loading]. Give it roughly the shape of [child] — the point of
  /// the fade is that the two are recognisably the same thing.
  final Widget skeleton;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: DsMotion.of(context, DsMotion.page),
      switchInCurve: DsMotion.curveIn,
      switchOutCurve: DsMotion.curveOut,
      // Slightly faster out than in, so the content is never fading up through
      // a still-solid ghost.
      reverseDuration: DsMotion.of(context, DsMotion.pageOut),
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topLeft,
        children: [
          for (final old in previous)
            Positioned(left: 0, right: 0, top: 0, child: old),
          if (current != null) current,
        ],
      ),
      child: KeyedSubtree(
        // The key is the STATE, not the content: rebuilding the same table with
        // one more row must not re-run the fade.
        key: ValueKey<bool>(loading),
        child: loading ? skeleton : child,
      ),
    );
  }
}

/// Grey placeholder bar for skeleton loading states.
/// One clock for every skeleton on screen.
///
/// Each bar sweeping on its own `AnimationController` is a dozen controllers on
/// a loading page, all started at whatever millisecond their widget happened to
/// mount — which reads as static, because a panel full of highlights at random
/// phases averages out to no highlight at all. One shared phase makes the panel
/// breathe as a single surface, which is the whole effect.
///
/// The ticker is reference-counted: it starts when the first skeleton appears
/// and stops when the last one leaves, so a loaded page is not paying a frame
/// callback forever to animate nothing.
class _DsShimmerClock {
  static final ValueNotifier<double> phase = ValueNotifier<double>(0);
  static const Duration _period = Duration(milliseconds: 1500);

  static Ticker? _ticker;
  static int _users = 0;

  static void attach() {
    if (_users++ > 0) return;
    _ticker = Ticker((Duration elapsed) {
      phase.value = (elapsed.inMilliseconds % _period.inMilliseconds) / _period.inMilliseconds;
    })
      ..start();
  }

  static void detach() {
    if (--_users > 0) return;
    _ticker?.dispose();
    _ticker = null;
    phase.value = 0;
  }
}

/// A grey placeholder bar with a light sweeping across it.
///
/// The sweep is what separates "this is loading" from "this is broken". A row
/// of flat grey blocks is indistinguishable from a page that rendered empty,
/// and users wait a lot longer for something that is visibly alive.
class DsSkeletonBar extends StatefulWidget {
  const DsSkeletonBar({super.key, this.width = 60, this.height = 10, this.radius = 6, this.color});
  final double width;
  final double height;

  /// Corner of the placeholder. The default suits a line of text; a card- or
  /// tile-shaped block wants its own radius so the ghost matches the shape it
  /// is standing in for.
  final double radius;

  /// The bar's tint. [DsColors.line] by default; a ghost sitting on a coloured
  /// surface (the dashboard's purple hero) wants a tint of that surface's own
  /// ink instead, or it reads as a grey hole punched through it.
  final Color? color;

  @override
  State<DsSkeletonBar> createState() => _DsSkeletonBarState();
}

class _DsSkeletonBarState extends State<DsSkeletonBar> {
  bool _attached = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduced motion gets the flat bar, and does not start the ticker at all —
    // an accessibility setting should cost less, not the same.
    final bool animate = MediaQuery.maybeDisableAnimationsOf(context) != true;
    if (animate == _attached) return;
    animate ? _DsShimmerClock.attach() : _DsShimmerClock.detach();
    _attached = animate;
  }

  @override
  void dispose() {
    if (_attached) _DsShimmerClock.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius = BorderRadius.circular(widget.radius);
    final Widget base = Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(color: widget.color ?? DsColors.line, borderRadius: radius),
    );
    if (!_attached) return base;
    return ClipRRect(
      borderRadius: radius,
      child: Stack(children: [
        base,
        Positioned.fill(
          child: ValueListenableBuilder<double>(
            valueListenable: _DsShimmerClock.phase,
            builder: (context, phase, _) {
              // Travels from fully off the left to fully off the right, so the
              // bar spends part of the cycle plain — a highlight that never
              // leaves reads as a gradient, not as a sweep.
              final double t = -0.4 + phase * 1.8;
              double stop(double v) => v.clamp(0.0, 1.0);
              return DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: const [Colors.transparent, DsColors.skeletonSheen, Colors.transparent],
                    stops: [stop(t - 0.26), stop(t), stop(t + 0.26)],
                  ),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

/// Table-shaped skeleton shown while a panel loads, so the layout keeps its
/// shape instead of collapsing into a spinner: a header band + grey bar rows.
class DsSkeletonTable extends StatelessWidget {
  const DsSkeletonTable({super.key, this.rows = 5, this.columns = 4});
  final int rows;
  final int columns;

  @override
  Widget build(BuildContext context) {
    Widget cell({required bool first}) => Expanded(
          flex: first ? 5 : 3,
          child: Align(
            alignment: first ? Alignment.centerLeft : Alignment.center,
            child: DsSkeletonBar(width: first ? 120 : 48),
          ),
        );
    Widget band({required bool header}) => Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: header ? DsColors.chip : null,
            borderRadius: header ? BorderRadius.circular(8) : null,
            border: header ? null : const Border(bottom: BorderSide(color: DsColors.lineSoft)),
          ),
          child: Row(children: [for (var c = 0; c < columns; c++) cell(first: c == 0)]),
        );
    return Column(children: [
      band(header: true),
      for (var i = 0; i < rows; i++) band(header: false),
    ]);
  }
}

/// A list of ghost rows, for a panel whose content is a stack of records —
/// a to-do list, a set of approval cards, a dialog listing positions.
///
/// Row widths are varied by index rather than uniform. A column of identical
/// bars reads as a barcode — as a pattern, which is to say as a DECORATION —
/// and the point of a skeleton is to be mistaken for the shape of the content
/// that is coming.
class DsSkeletonList extends StatelessWidget {
  const DsSkeletonList({
    super.key,
    this.rows = 4,
    this.avatar = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
  });

  final int rows;

  /// Leading circle, for lists whose rows are people.
  final bool avatar;
  final EdgeInsetsGeometry padding;

  // Fixed, not random: a skeleton that reshuffles on every rebuild flickers.
  static const List<double> _titles = [168, 132, 196, 148, 176, 120];
  static const List<double> _subs = [96, 124, 78, 110, 88, 136];

  static const double _gap = 16;

  @override
  Widget build(BuildContext context) {
    // [rows] is a MAXIMUM, not a promise. A skeleton is dropped into whatever
    // panel is loading, and the panel is usually an Expanded of a height nobody
    // measured — the dashboard's to-do tile takes two rows, not three, and
    // asking for three there overflowed it by 42 px on every page open. Fitting
    // the count to the box is the only version of this that is safe to reuse.
    //
    // An unbounded height (a load-more footer inside a scrolling list) keeps
    // the count it was given.
    return LayoutBuilder(builder: (context, constraints) {
      final double rowHeight = avatar ? 30 : 27;
      var count = rows;
      if (constraints.maxHeight.isFinite) {
        final double free =
            constraints.maxHeight - padding.resolve(Directionality.of(context)).vertical;
        count = ((free + _gap) / (rowHeight + _gap)).floor().clamp(1, rows);
      }
      return Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < count; i++)
              Padding(
                padding: EdgeInsets.only(bottom: i == count - 1 ? 0 : _gap),
                child: Row(children: [
                  if (avatar) ...[
                    const DsSkeletonBar(width: 30, height: 30, radius: 15),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      DsSkeletonBar(width: _titles[i % _titles.length], height: 11),
                      const SizedBox(height: 7),
                      DsSkeletonBar(width: _subs[i % _subs.length], height: 9),
                    ]),
                  ),
                ]),
              ),
          ],
        ),
      );
    });
  }
}

/// Columns of ghost cards, for the panels whose content is a BOARD rather than
/// a list — the personal to-do popup, the org chart, the branch-map editor.
///
/// A centred spinner in a 720 px panel is the worst of both: it throws the
/// layout away AND gives the eye a single tiny thing to stare at in the middle
/// of a large empty space. Keeping the columns means the panel is the right
/// shape before and after, so nothing jumps when the data lands.
class DsSkeletonBoard extends StatelessWidget {
  const DsSkeletonBoard({super.key, this.columns = 3, this.cards = 3, this.cardHeight = 58});

  final int columns;
  final int cards;
  final double cardHeight;

  @override
  Widget build(BuildContext context) {
    // Same rule as [DsSkeletonList]: [cards] is what fits, at most.
    return LayoutBuilder(builder: (context, constraints) {
      var count = cards;
      if (constraints.maxHeight.isFinite) {
        // 28 for the padding, 11 + 12 for the column's own title bar.
        final double free = constraints.maxHeight - 28 - 23;
        count = ((free + 10) / (cardHeight + 10)).floor().clamp(1, cards);
      }
      return Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var c = 0; c < columns; c++) ...[
              if (c > 0) const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  DsSkeletonBar(width: 84 + (c % 3) * 22, height: 11),
                  const SizedBox(height: 12),
                  for (var i = 0; i < count; i++)
                    Padding(
                      padding: EdgeInsets.only(bottom: i == count - 1 ? 0 : 10),
                      child: SizedBox(
                        width: double.infinity,
                        child: DsSkeletonBar(
                            width: double.infinity, height: cardHeight, radius: 10),
                      ),
                    ),
                ]),
              ),
            ],
          ],
        ),
      );
    });
  }
}

/// Ghosts of the app's small widgets, for page skeletons that are built in the
/// shape of the page they stand in for rather than as a generic list.
///
/// Each helper is the size of the real thing: [tag] is a [DsTag], [chip] a
/// [DueChip], [lines] a row title over its meta line. A skeleton assembled from
/// these lines up with the content to the pixel, so the cross-fade into data
/// reads as the page filling in, not as one layout being swapped for another.
abstract final class DsSkel {
  /// A line of text. Wider than its box is fine: the bar is clamped to it.
  static Widget line(double width, {double height = 10, Color? color}) =>
      DsSkeletonBar(width: width, height: height, color: color);

  /// A row title over its meta line — the most common cell in the app.
  static Widget lines(double title, double sub,
          {CrossAxisAlignment align = CrossAxisAlignment.start, double titleH = 11}) =>
      Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: align, children: [
        DsSkeletonBar(width: title, height: titleH),
        const SizedBox(height: 7),
        DsSkeletonBar(width: sub, height: 8),
      ]);

  static Widget circle(double size, {Color? color}) =>
      DsSkeletonBar(width: size, height: size, radius: size / 2, color: color);

  static Widget box(double width, double height, {double radius = 8, Color? color}) =>
      DsSkeletonBar(width: width, height: height, radius: radius, color: color);

  /// A [DsTag]: 20 high, corner 6.
  static Widget tag(double width) => DsSkeletonBar(width: width, height: 20, radius: 6);

  /// A fully rounded chip ([DueChip], a status pill).
  static Widget chip(double width, {double height = 18}) =>
      DsSkeletonBar(width: width, height: height, radius: height / 2);

  /// A square icon or icon button.
  static Widget icon([double size = 18]) => DsSkeletonBar(width: size, height: size, radius: size * .3);

  /// A block as wide as its box.
  static Widget fill(double height, {double radius = 8}) => SizedBox(
      width: double.infinity, child: DsSkeletonBar(width: double.infinity, height: height, radius: radius));

  /// A [DsCardTitle]: navy icon, then the title.
  static Widget cardTitle(double width, {Widget? trailing}) => Row(children: [
        icon(18),
        const SizedBox(width: 8),
        DsSkeletonBar(width: width, height: 13),
        const Spacer(),
        if (trailing != null) trailing,
      ]);

  /// A width that changes from row to row but never between rebuilds. A
  /// column of identical bars reads as a pattern; real data is ragged.
  static double vary(int i, double base, [double spread = .4]) =>
      base * (1 - spread / 2 + spread * _jitter[i % _jitter.length]);
  static const List<double> _jitter = [.62, .18, .9, .4, .75, .05, .55, .3, .98, .22, .68, .45];
}

/// One column of a [DsSkeletonRows] table: a fixed [width] or a [flex] share,
/// and the ghost to draw in it for row `i`.
class DsSkelCol {
  const DsSkelCol(this.cell, {this.width, this.flex = 1, this.align = Alignment.centerLeft});
  final Widget Function(int i) cell;
  final double? width;
  final int flex;
  final Alignment align;
}

/// The body of a table while it loads — the same columns, the same row height
/// and the same hairline between rows as the real thing, under the real header.
///
/// Rows fill the box they are given (an Expanded table body, a DsFitRows
/// builder) and no more, so a page never scrolls or overflows while it waits.
/// The lower rows fade out: a full page of solid ghosts is heavy, and a fade
/// says "more below" without promising a count.
class DsSkeletonRows extends StatelessWidget {
  const DsSkeletonRows({
    super.key,
    required this.columns,
    this.rowHeight = 50,
    this.rows = 14,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
    this.divider = true,
    this.fade = true,
  });

  final List<DsSkelCol> columns;
  final double rowHeight;

  /// At most this many; fewer when the box is shorter.
  final int rows;
  final EdgeInsetsGeometry padding;
  final bool divider;
  final bool fade;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      var count = rows;
      if (box.maxHeight.isFinite) {
        count = (box.maxHeight / rowHeight + 0.001).floor().clamp(1, rows);
      }
      return Column(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < count; i++)
          Opacity(
            opacity: fade && count > 3 ? 1 - .6 * (i / (count - 1)) : 1,
            child: Container(
              height: rowHeight,
              padding: padding,
              decoration: divider
                  ? const BoxDecoration(border: Border(bottom: BorderSide(color: DsColors.lineSoft)))
                  : null,
              child: Row(children: [
                for (final c in columns)
                  if (c.width != null)
                    SizedBox(width: c.width, child: Align(alignment: c.align, child: c.cell(i)))
                  else
                    Expanded(flex: c.flex, child: Align(alignment: c.align, child: c.cell(i))),
              ]),
            ),
          ),
      ]);
    });
  }
}

/// A labeled field block: small label above a child input box.
class DsLabeledField extends StatelessWidget {
  const DsLabeledField({super.key, required this.label, required this.child, this.labelSize = 12});
  final String label;
  final Widget child;
  final double labelSize;
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(label, style: TextStyle(fontSize: labelSize, fontWeight: FontWeight.w600, color: DsColors.text)),
      ),
      child,
    ]);
  }
}

/// Primary navy button with optional leading icon, sized to the design.
class DsPrimaryButton extends StatelessWidget {
  const DsPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.height = 42,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final double height;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: icon == null ? null : Icon(icon, size: 19),
        // One line always: when the button is narrower than its label (a
        // tile column, "Everyone (4)"), the label shrinks a touch instead of
        // wrapping onto a second line.
        label: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(label, maxLines: 1, softWrap: false, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: DsColors.navy,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        ),
      ),
    );
  }
}

/// Outline (secondary) button matching the design.
class DsOutlineButton extends StatelessWidget {
  const DsOutlineButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.height = 42,
    this.foreground = DsColors.text,
    this.borderColor = DsColors.inputBorder,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final double height;
  final Color foreground;
  final Color borderColor;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      // No icon given -> no icon (RAP drew a stray dot here).
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: icon == null ? null : Icon(icon, size: 18),
        // One line always: when the button is narrower than its label (a
        // tile column, "Everyone (4)"), the label shrinks a touch instead of
        // wrapping onto a second line.
        label: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(label, maxLines: 1, softWrap: false, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: foreground,
          backgroundColor: DsColors.glass,
          side: BorderSide(color: borderColor, width: 1.4),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        ),
      ),
    );
  }
}

/// The app's one segmented control: a track holding N options with a single
/// lit "thumb" behind the selected one.
///
/// The thumb SLIDES between options instead of being repainted under the new
/// one. That is the whole point of this widget existing — six hand-rolled
/// copies of this control all cut instantly, which reads as the page swapping
/// rather than as you moving a switch. The thumb also grows/shrinks between
/// options of different widths on the way, so "Created by me" → "All in
/// section" is one continuous movement rather than a jump plus a resize.
///
/// [itemBuilder] is handed a `selectedness` from 0 to 1 for its option, which
/// crosses 0.5 exactly when the thumb is halfway. Lerp every colour that
/// differs between selected and unselected through it — a label that snaps to
/// its selected colour while the thumb is still travelling gives the movement
/// away.
///
/// The builder supplies its own padding: the thumb is sized to the option, so
/// padding inside the option is what the thumb covers.
class DsSegmented extends StatelessWidget {
  const DsSegmented({
    super.key,
    required this.selected,
    required this.length,
    required this.itemBuilder,
    required this.onSelect,
    this.padding = const EdgeInsets.all(3),
    this.spacing = 0,
    this.radius = 9,
    this.thumbRadius = 7,
    this.background = DsColors.chip,
    this.borderColor = DsColors.cardBorder,
    this.thumbColor = Colors.white,
    this.thumbShadow = defaultThumbShadow,
    this.duration,
  });

  /// The lift under the thumb on a pale track. Named so a caller that only
  /// wants to drop it on a dark ground can still ask for the default back.
  static const defaultThumbShadow = [
    BoxShadow(color: Color(0x14000000), blurRadius: 6, offset: Offset(0, 1))
  ];

  final int selected;
  final int length;

  /// `(context, index, selectedness)` — see the class doc for `selectedness`.
  final Widget Function(BuildContext context, int index, double selectedness) itemBuilder;
  final ValueChanged<int> onSelect;

  /// Inset of the track, i.e. how much of it shows around the thumb.
  final EdgeInsets padding;
  final double spacing;
  final double radius;
  final double thumbRadius;
  final Color? background;
  final Color? borderColor;
  final Color thumbColor;
  final List<BoxShadow>? thumbShadow;

  /// Defaults to [DsMotion.chrome] — this is app chrome, not a page change.
  final Duration? duration;

  @override
  Widget build(BuildContext context) {
    // Under liquid glass the thumb is thrown rather than moved: same control,
    // same travel, the reference's spring on the end of it. The render object
    // clamps [position] to the option range, so the overshoot is free — it
    // shows between options and is simply absorbed at either end.
    //
    // The GLASS half only applies where the control is on a light ground: the
    // work board's focused header hands this a dark track and white labels, and
    // a lit white thumb under white text is unreadable. The spring applies
    // either way — motion doesn't care what colour the ground is.
    final liquid = Lg.on && thumbColor == Colors.white;
    final travel = DsMotion.of(context, duration ?? (Lg.on ? DsMotion.slide : DsMotion.chrome));
    final target = length == 0 ? 0.0 : selected.clamp(0, length - 1).toDouble();
    final track = Container(
      padding: padding,
      decoration: liquid
          // Nearly the fill a card carries. A well is a CHANNEL, so the instinct
          // is to leave it thin and let the surface it is cut into show through —
          // but the unselected options are the only labels in the app printed
          // straight onto a well, and over a photograph a thin one leaves them
          // on whatever happens to be underneath. It sits on a drop as well (see
          // below), so between the two the ground under "Assigned to me" is as
          // quiet as the ground inside a card.
          ? lgWell(radius: radius, scale: .95)
          : BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(radius),
              border: borderColor == null ? null : Border.all(color: borderColor!),
            ),
      child: TweenAnimationBuilder<double>(
        // Only `end` matters after the first build: TweenAnimationBuilder
        // restarts from wherever the thumb currently IS, so tapping mid-slide
        // redirects it instead of snapping back.
        tween: Tween<double>(begin: target, end: target),
        duration: travel,
        curve: Lg.on ? DsMotion.curveSlide : DsMotion.curveChrome,
        builder: (context, position, _) => _SegmentedStrip(
          position: position,
          spacing: spacing,
          children: [
            DecoratedBox(
              decoration: liquid
                  ? lgRaised(radius: thumbRadius, shadow: thumbShadow)
                  : BoxDecoration(
                      color: thumbColor,
                      borderRadius: BorderRadius.circular(thumbRadius),
                      boxShadow: thumbShadow,
                    ),
            ),
            for (var i = 0; i < length; i++)
              // The transparent Material is what gives the ripple somewhere to
              // paint. Without one the nearest Material is the page itself,
              // which is BEHIND the thumb and the track — so the splash would
              // be invisible on the option you just tapped.
              Material(
                type: MaterialType.transparency,
                borderRadius: BorderRadius.circular(thumbRadius),
                child: InkWell(
                  borderRadius: BorderRadius.circular(thumbRadius),
                  onTap: () => onSelect(i),
                  child: itemBuilder(context, i, (1 - (position - i).abs()).clamp(0.0, 1.0)),
                ),
              ),
          ],
        ),
      ),
    );
    // On a drop, like a card — so the well is cut into the same material the
    // rest of the page is made of rather than floating on the photograph.
    return liquid
        ? LiquidDrop(radius: Lg.r(radius, max: 22), strength: .5, child: track)
        : track;
  }
}

/// Lays the options out in a row and puts the thumb — the first child — behind
/// whichever fractional [position] says, sized by lerping between the two
/// options it currently spans.
///
/// This is a render object rather than a Stack + AnimatedPositioned because the
/// options size themselves to their own content: nothing above layout knows how
/// wide "Assigned to me" is, so nothing above layout can place the thumb.
class _SegmentedStrip extends MultiChildRenderObjectWidget {
  const _SegmentedStrip({required this.position, required this.spacing, required super.children});

  /// Fractional option index the thumb sits at.
  final double position;
  final double spacing;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSegmentedStrip(position: position, spacing: spacing);

  @override
  void updateRenderObject(BuildContext context, covariant _RenderSegmentedStrip renderObject) {
    renderObject
      ..position = position
      ..spacing = spacing;
  }
}

class _SegmentedParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderSegmentedStrip extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _SegmentedParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _SegmentedParentData> {
  _RenderSegmentedStrip({required double position, required double spacing})
      : _position = position,
        _spacing = spacing;

  double _position;
  set position(double value) {
    if (_position == value) return;
    _position = value;
    markNeedsLayout();
  }

  double _spacing;
  set spacing(double value) {
    if (_spacing == value) return;
    _spacing = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _SegmentedParentData) child.parentData = _SegmentedParentData();
  }

  /// Everything after the thumb.
  List<RenderBox> get _options => getChildrenAsList().skip(1).toList();

  @override
  double computeMinIntrinsicHeight(double width) => _intrinsicHeight(width);

  @override
  double computeMaxIntrinsicHeight(double width) => _intrinsicHeight(width);

  double _intrinsicHeight(double width) {
    var height = 0.0;
    for (final option in _options) {
      height = max(height, option.getMaxIntrinsicHeight(double.infinity));
    }
    return height;
  }

  @override
  double computeMinIntrinsicWidth(double height) => _intrinsicWidth(height, min: true);

  @override
  double computeMaxIntrinsicWidth(double height) => _intrinsicWidth(height, min: false);

  double _intrinsicWidth(double height, {required bool min}) {
    final options = _options;
    if (options.isEmpty) return 0;
    var width = _spacing * (options.length - 1);
    for (final option in options) {
      width += min ? option.getMinIntrinsicWidth(height) : option.getMaxIntrinsicWidth(height);
    }
    return width;
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) => _measure(constraints);

  @override
  void performLayout() {
    size = _measure(constraints, dry: false);
    var x = 0.0;
    final lefts = <double>[];
    final widths = <double>[];
    for (final option in _options) {
      (option.parentData! as _SegmentedParentData).offset =
          Offset(x, (size.height - option.size.height) / 2);
      lefts.add(x);
      widths.add(option.size.width);
      x += option.size.width + _spacing;
    }

    final thumb = firstChild;
    if (thumb == null) return;
    if (lefts.isEmpty) {
      thumb.layout(BoxConstraints.tight(Size.zero));
      return;
    }
    // Between two options the thumb is the lerp of both their rects, so it
    // stretches or narrows as it travels rather than resizing on arrival.
    final p = _position.clamp(0, lefts.length - 1).toDouble();
    final lo = p.floor();
    final hi = p.ceil();
    final f = p - lo;
    final left = ui.lerpDouble(lefts[lo], lefts[hi], f)!;
    final width = ui.lerpDouble(widths[lo], widths[hi], f)!;
    thumb.layout(BoxConstraints.tight(Size(width, size.height)));
    (thumb.parentData! as _SegmentedParentData).offset = Offset(left, 0);
  }

  Size _measure(BoxConstraints constraints, {bool dry = true}) {
    final options = _options;
    if (options.isEmpty) return constraints.smallest;

    // Options size to their own content. A finite max width is passed through
    // so a long label can still ellipsize instead of overflowing the track.
    var child = BoxConstraints(maxWidth: constraints.maxWidth);
    var total = _spacing * (options.length - 1);
    var height = 0.0;
    final sizes = <Size>[];
    for (final option in options) {
      final s = dry ? option.getDryLayout(child) : (option..layout(child, parentUsesSize: true)).size;
      sizes.add(s);
      total += s.width;
      height = max(height, s.height);
    }

    // Too wide for the space we were given: hand every option the same
    // fraction of what it asked for and re-measure, so the row shrinks evenly
    // instead of the last one overflowing.
    if (constraints.maxWidth.isFinite && total > constraints.maxWidth) {
      final spacing = _spacing * (options.length - 1);
      final available = max(0.0, constraints.maxWidth - spacing);
      final scale = available / max(1.0, total - spacing);
      total = spacing;
      height = 0;
      for (var i = 0; i < options.length; i++) {
        child = BoxConstraints(maxWidth: sizes[i].width * scale);
        final s = dry
            ? options[i].getDryLayout(child)
            : (options[i]..layout(child, parentUsesSize: true)).size;
        total += s.width;
        height = max(height, s.height);
      }
    }
    return constraints.constrain(Size(total, height));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    // Thumb first — it is the surface the options sit ON.
    defaultPaint(context, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

/// Input decoration matching the design (rounded 9px, slate border, navy focus).
///
/// [DsColors.glass] for the fill, which is the same pane the option chips beside
/// these fields are cut from — so a form reads as one set of surfaces rather
/// than as paper boxes sitting next to glass ones.
///
/// This used to be opaque `Colors.white`, and it was the outlier: the app's own
/// `inputDecorationTheme` has filled with glass all along, and says why —
/// "inside a glass card an opaque white input is the one thing that still reads
/// as paper". Only the fields built through this helper missed the memo.
InputDecoration dsInput({String? hint, IconData? icon, Widget? suffix, String? errorText}) {
  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: DsColors.faint2, fontWeight: FontWeight.w400, fontSize: 13),
    prefixIcon: icon == null ? null : Icon(icon, size: 19, color: DsColors.iconSoft),
    suffixIcon: suffix,
    errorText: errorText,
    isDense: true,
    filled: true,
    fillColor: DsColors.glass,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: DsColors.inputBorder, width: 1.4)),
    enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: DsColors.inputBorder, width: 1.4)),
    focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: DsColors.navy, width: 1.6)),
  );
}
