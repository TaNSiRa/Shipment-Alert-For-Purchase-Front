part of '../main.dart';

/// Mouse-wheel smoothing for every scroll view in the app.
///
/// Flutter turns each wheel notch into a single `position.pointerScroll()` —
/// an instant ~100 px jump with no easing at all. That is what makes wheel
/// scrolling feel stiff and steppy on web even when the frame rate is fine;
/// the browser's own smooth-scroll animation never gets a say inside the
/// canvas. This binding swallows those events and re-emits them as small
/// per-frame slices, so one notch reads as a glide instead of a teleport.
///
/// Doing it in the binding is what makes it app-wide: the synthesized events
/// run through the normal hit test, so every Scrollable — pages, tables,
/// dialogs, the Gantt — inherits it without a single page-level change.
///
/// ## The glide is a spring, not a fade (2026-08-21)
///
/// The first version eased the remaining distance out exponentially: every
/// frame it moved a fixed FRACTION of what was left. That is smooth in the
/// sense of continuous, but it has no weight, and weight is what was actually
/// being asked for — "smooth กว่านี้อีก มันดู premium ดี". Two reasons the shape
/// itself reads cheap, neither of which a bigger time constant can fix:
///
///  * **It is fastest at the instant the notch lands.** Velocity jumps from 0
///    to its peak between two frames and only ever decays from there. Nothing
///    with mass moves like that, and slowing the decay to compensate just adds
///    lag to the same shape — which is why the old comment had to warn that
///    tau 0.13 was already the top of the usable range.
///  * **Every notch restarts the curve.** Spinning the wheel three times fast
///    is three overlapping fades, not one gathering movement, so a fast spin
///    feels the same as a slow one, only longer.
///
/// So the state is now a POSITION and a VELOCITY, run as a critically damped
/// spring toward the target — critically damped meaning it decelerates into the
/// target rather than oscillating around it. Each notch adds distance AND kicks
/// the velocity, the way a flick imparts momentum to a real scroll surface.
/// That buys three things at once: an immediate response on the first frame, a
/// long soft deceleration into the stop, and momentum that ACCUMULATES across
/// notches, so a fast spin genuinely travels faster instead of merely longer.
class SmoothScrollBinding extends WidgetsFlutterBinding {
  /// A wheel notch is ~100 px. Trackpads send a stream of much smaller deltas
  /// and are already smooth, so anything below this passes straight through
  /// untouched. Kept low so high-resolution / free-spin wheels, which land
  /// somewhere in between, are smoothed too.
  static const double _notchThreshold = 12;

  /// ── DIAL 1 of 2: how long the glide takes to settle. ──
  ///
  /// Roughly the time the spring needs to close the remaining distance. Bigger
  /// is heavier and floatier, smaller is tighter and closer to the old jump.
  /// Unlike the exponential version this can be raised without the view lagging
  /// behind the wheel, because [_impulse] governs the START of the movement and
  /// this only governs the tail.
  static const double _smoothTime = 0.34;

  /// ── DIAL 2 of 2: how hard a notch kicks. ──
  ///
  /// Velocity added per pixel of notch, in 1/s — a 100 px notch imparts
  /// `100 * _impulse` px/s. This is the flick: it is what makes the first frame
  /// after a notch move immediately instead of easing up from a standstill, and
  /// what lets a fast spin build speed.
  ///
  /// Raise it and scrolling gets eager and darty; drop it to 0 and the spring
  /// starts from rest every time, which is soft but noticeably late.
  static const double _impulse = 4.5;

  /// Below this the remainder is dispatched in one go rather than trickling
  /// out sub-pixel slices forever.
  static const double _epsilon = 0.5;

  static bool _initialized = false;

  Offset _pending = Offset.zero;

  /// Rate of change of [_pending], px/s. Negative while the view is catching up
  /// to a downward notch — [_pending] is what is LEFT to travel, so closing the
  /// gap means driving it toward zero.
  ///
  /// It survives across notches on purpose: that carry-over is the momentum.
  Offset _velocity = Offset.zero;

  PointerScrollEvent? _source;
  Duration _lastFrame = Duration.zero;
  bool _frameScheduled = false;

  /// Installs this binding. Must run before [runApp] — the first binding
  /// created wins, so `WidgetsFlutterBinding.ensureInitialized()` must not
  /// have run yet.
  static void ensureInitialized() {
    if (_initialized) return;
    _initialized = true;
    SmoothScrollBinding();
  }

  @override
  void handlePointerEvent(PointerEvent event) {
    if (event is PointerScrollEvent && _shouldSmooth(event)) {
      if (_pending == Offset.zero) {
        _lastFrame = Duration.zero;
      }
      _pending += event.scrollDelta;
      // The flick. Toward the target, hence the minus: a positive notch grows
      // [_pending] positive, and closing it means moving negative.
      _velocity -= event.scrollDelta * _impulse;
      _source = event;
      _scheduleGlide();
      // Swallowed on purpose: re-emitted a slice at a time below. Not
      // responding also leaves the engine's default in place, which is to
      // preventDefault the wheel event, so the page behind the canvas stays put.
      return;
    }
    // A drag or an inertia cancel starting mid-glide would fight the leftover
    // delta, so hand the remainder over first.
    if (_pending != Offset.zero &&
        (event is PointerDownEvent || event is PointerScrollInertiaCancelEvent)) {
      final Offset rest = _pending;
      _pending = Offset.zero;
      _velocity = Offset.zero;
      _emit(rest, event.timeStamp);
    }
    super.handlePointerEvent(event);
  }

  bool _shouldSmooth(PointerScrollEvent event) {
    if (event.kind != ui.PointerDeviceKind.mouse) return false;
    final Offset delta = event.scrollDelta;
    return delta.dy.abs() >= _notchThreshold || delta.dx.abs() >= _notchThreshold;
  }

  void _scheduleGlide() {
    if (_frameScheduled) return;
    _frameScheduled = true;
    scheduleFrameCallback((Duration stamp) {
      _frameScheduled = false;
      _glide(stamp);
    });
  }

  void _glide(Duration stamp) {
    // Frame-rate independent decay, so a 120 Hz screen feels the same as 60 Hz.
    final double dt = _lastFrame == Duration.zero
        ? 1 / 60
        : ((stamp - _lastFrame).inMicroseconds / 1000000).clamp(1 / 240, 1 / 15);
    _lastFrame = stamp;

    final (double nextX, double vx) = _spring(_pending.dx, _velocity.dx, dt);
    final (double nextY, double vy) = _spring(_pending.dy, _velocity.dy, dt);
    Offset rest = Offset(nextX, nextY);
    _velocity = Offset(vx, vy);

    // Close enough — hand the last fraction of a pixel over in one go rather
    // than trickling sub-pixel slices out forever, and drop the momentum with
    // it: the gesture is over, and leftover velocity would kick the NEXT notch
    // off at a speed nobody asked for.
    if (rest.distance <= _epsilon) {
      rest = Offset.zero;
      _velocity = Offset.zero;
    }

    final Offset step = _pending - rest;
    _pending = rest;
    _emit(step, stamp);
    if (_pending != Offset.zero) {
      _scheduleGlide();
    }
  }

  /// One critically damped spring step on a single axis, returning the new
  /// remaining distance and the new velocity.
  ///
  /// The integrator is the closed-form solution of a critically damped spring
  /// with the exponential replaced by a rational approximation — cheaper, and
  /// more importantly stable at any `dt`, so a dropped frame slows the glide
  /// down instead of blowing it up the way a naive Euler step would.
  static (double, double) _spring(double x, double v, double dt) {
    if (x == 0) return (0, 0);
    // Natural frequency of a critically damped spring that settles in roughly
    // [_smoothTime].
    const double omega = 2 / _smoothTime;
    final double k = omega * dt;
    final double decay = 1 / (1 + k + 0.48 * k * k + 0.235 * k * k * k);
    final double temp = (v + omega * x) * dt;
    final double nextV = (v - omega * temp) * decay;
    final double nextX = (x + temp) * decay;
    // A hard flick can carry the spring PAST the target — critically damped
    // means no ringing, not no overshoot when it starts with velocity behind it.
    // Sailing past the resting point and creeping back is the one artefact here
    // that would read as a bug rather than as weight, so the crossing is
    // clamped: land on the target and stop.
    if (x.sign != nextX.sign) return (0, 0);
    return (nextX, nextV);
  }

  void _emit(Offset delta, Duration timeStamp) {
    final PointerScrollEvent? source = _source;
    if (source == null || delta == Offset.zero) return;
    super.handlePointerEvent(PointerScrollEvent(
      viewId: source.viewId,
      timeStamp: timeStamp,
      kind: source.kind,
      device: source.device,
      position: source.position,
      scrollDelta: delta,
      embedderId: source.embedderId,
    ));
  }
}

/// Zoom for the day-grid timelines — the calendar page and the request-detail
/// Gantt, which both lay their content out from a "pixels per day" width.
///
/// Two things it exists for:
///
/// * **It eases between levels.** Setting the day width outright made every
///   zoom a hard cut. Here each change retargets a short animation from
///   wherever the previous one had got to, so holding Ctrl and spinning the
///   wheel reads as one continuous glide rather than a stack of jumps.
/// * **It counts wheel travel, not events.** [SmoothScrollBinding] above slices
///   one wheel notch into a dozen per-frame events; the old handlers took a
///   zoom step per event, so a single notch tore through the whole zoom range.
///   Steps are spent per [_pxPerStep] of accumulated scroll instead, and
///   trackpad pinches per [_pinchPerStep] of accumulated scale.
///
/// The host must call [initZoom] from `initState` and [disposeZoom] from
/// `dispose`, and read [dayWidth] — never `zoomSteps[zoomIndex]` — in `build`.
mixin SteppedZoom<T extends StatefulWidget> on State<T>, SingleTickerProviderStateMixin<T> {
  /// Day widths in pixels, smallest first. Geometric series read best: every
  /// step is then the same visual jump, however far in you are.
  List<double> get zoomSteps;

  /// Index of the step the percentage readout calls 100 %.
  int get zoomBaseIndex;

  /// localStorage key remembering the last level, or null to not persist.
  /// The stored value is the day WIDTH, not the index, so the step list can be
  /// retuned later without throwing everyone to a random zoom level.
  String? get zoomStorageKey => null;

  /// Wheel pixels that buy one zoom step. A notch is ~100 px, so a notch is
  /// about two steps — fine-grained, but not so fine that crossing the range
  /// takes a minute of scrolling.
  static const double _pxPerStep = 50;

  /// Accumulated scale that buys one step. On the web this is the path Ctrl +
  /// wheel actually takes: the browser calls it a pinch and the engine hands
  /// over `exp(-delta / 200)`, i.e. ~0.61 for one notch. At 1.44 that spends
  /// one step per notch (~1.28× overall), in line with the wheel branch below;
  /// a real trackpad pinch, which arrives as a stream of small scales, still
  /// tracks the fingers.
  static const double _pinchPerStep = 1.44;

  static const Duration _glide = Duration(milliseconds: 220);

  late final AnimationController _zoomAnim = AnimationController(vsync: this, duration: _glide)
    ..addListener(() {
      if (mounted) setState(() {});
    });

  int _zoomIndex = 0;
  double _zoomFrom = 0;
  double _zoomTo = 0;
  double _scrollAccum = 0;
  double _pinchAccum = 1;

  /// Call from `initState`. [fallback] is the step to open at when nothing has
  /// been stored yet.
  void initZoom(int fallback) {
    final key = zoomStorageKey;
    final saved = key == null ? null : double.tryParse(html.window.localStorage[key] ?? '');
    _zoomIndex = saved == null ? fallback.clamp(0, zoomSteps.length - 1) : _nearestStep(saved);
    _zoomFrom = _zoomTo = zoomSteps[_zoomIndex];
  }

  void disposeZoom() => _zoomAnim.dispose();

  int _nearestStep(double width) {
    var best = 0;
    for (var i = 1; i < zoomSteps.length; i++) {
      if ((zoomSteps[i] - width).abs() < (zoomSteps[best] - width).abs()) best = i;
    }
    return best;
  }

  int get zoomIndex => _zoomIndex;
  bool get canZoomIn => _zoomIndex < zoomSteps.length - 1;
  bool get canZoomOut => _zoomIndex > 0;

  /// The live, animating day width — what layout must be built from.
  double get dayWidth {
    final t = Curves.easeOutCubic.transform(_zoomAnim.value);
    return _zoomFrom + (_zoomTo - _zoomFrom) * t;
  }

  /// Percentage readout; animates along with [dayWidth] so the number and the
  /// grid never disagree mid-glide.
  int get zoomPercent => (dayWidth / zoomSteps[zoomBaseIndex] * 100).round();

  void zoomIn() => setZoomIndex(_zoomIndex + 1);
  void zoomOut() => setZoomIndex(_zoomIndex - 1);

  void setZoomIndex(int next) {
    final clamped = next.clamp(0, zoomSteps.length - 1);
    if (clamped == _zoomIndex) return;
    // Start from where the eye is now, not from the last target — otherwise a
    // second step mid-glide snaps back to the previous level first.
    _zoomFrom = dayWidth;
    _zoomTo = zoomSteps[clamped];
    _zoomIndex = clamped;
    _zoomAnim
      ..value = 0
      ..forward();
    setState(() {});
    final key = zoomStorageKey;
    if (key != null) html.window.localStorage[key] = '${zoomSteps[clamped]}';
  }

  /// Ctrl + wheel and trackpad pinch, both accumulated so the zoom tracks how
  /// far the input actually travelled.
  void handleZoomPointerSignal(PointerSignalEvent event) {
    if (event is PointerScaleEvent) {
      if (event.scale <= 0) return;
      _pinchAccum *= event.scale;
      while (_pinchAccum >= _pinchPerStep) {
        _pinchAccum /= _pinchPerStep;
        zoomIn();
      }
      while (_pinchAccum <= 1 / _pinchPerStep) {
        _pinchAccum *= _pinchPerStep;
        zoomOut();
      }
      return;
    }
    if (event is PointerScrollEvent && HardwareKeyboard.instance.isControlPressed) {
      if (event.scrollDelta.dy == 0) return;
      // A reversal is a new gesture — drop whatever was left over the other way.
      if (_scrollAccum.sign != event.scrollDelta.dy.sign) _scrollAccum = 0;
      _scrollAccum += event.scrollDelta.dy;
      while (_scrollAccum <= -_pxPerStep) {
        _scrollAccum += _pxPerStep;
        zoomIn();
      }
      while (_scrollAccum >= _pxPerStep) {
        _scrollAccum -= _pxPerStep;
        zoomOut();
      }
    }
  }
}
