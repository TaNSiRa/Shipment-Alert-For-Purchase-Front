part of '../main.dart';

/// Keeps tooltips from popping up under a pointer that never moved.
///
/// A wheel scroll moves the CONTENT, not the mouse. Flutter re-runs the hover
/// hit test after any frame whose layout changed, so whatever slides in under
/// the stationary cursor gets a perfectly genuine `PointerEnter` — and a
/// tooltip a moment after that. On the to-do board, where a card's "..."
/// button is one of the things that can drift under the cursor mid-scroll,
/// that reads as the app pointing at itself: a "Card options" bubble on a card
/// nobody touched.
///
/// The app's own wheel glide makes it worse rather than better — see
/// [SmoothScrollBinding]. The board keeps moving for a third of a second after
/// the wheel has stopped, so the bubble usually surfaces once everything is
/// already still, with nothing left on screen to explain it.
///
/// Scrolling is not the only way the layout moves on its own: a card opening
/// into the place it was just dropped on the to-do board slides its neighbours
/// under the cursor in exactly the same way, and produces exactly the same
/// phantom. Anything that moves the layout by itself says so with [hush].
///
/// So: while anything in the app is scrolling or hushing, tooltips are
/// switched off, and one already on screen is taken down. Nothing else about
/// hovering changes — a pointer the user actually moves onto the button still
/// gets its tooltip.
class DsScrollTooltipGuard extends StatefulWidget {
  const DsScrollTooltipGuard({super.key, required this.child});

  final Widget child;

  /// "The layout is about to move under a pointer that is not moving."
  ///
  /// Silences tooltips for [duration] plus the usual settle. Cheap to call
  /// over and over — each call simply pushes the deadline out again — so an
  /// animation or a drag can hold the silence open by saying it every frame
  /// rather than having to know in advance how long it will last.
  static void hush([Duration duration = Duration.zero]) {
    _hushFor = duration;
    // The tick is what the guard listens to; the duration rides along beside
    // it, because a notifier holding the same duration twice in a row would
    // not fire.
    _hushes.value++;
  }

  static Duration _hushFor = Duration.zero;
  static final ValueNotifier<int> _hushes = ValueNotifier<int>(0);

  @override
  State<DsScrollTooltipGuard> createState() => _DsScrollTooltipGuardState();
}

class _DsScrollTooltipGuardState extends State<DsScrollTooltipGuard> {
  /// A notifier rather than `setState`: scroll notifications arrive every
  /// frame, and rebuilding the app under them would be a stutter that lasts as
  /// long as the scroll. This flips twice per gesture at most, and only
  /// [TooltipVisibility] and the tooltips reading it rebuild — the child is
  /// the same instance either way.
  final ValueNotifier<bool> _silent = ValueNotifier<bool>(false);

  Timer? _settle;

  /// Set when the movement has stopped but the pointer still has not moved.
  ///
  /// Letting tooltips back under a cursor that is sitting still does not end
  /// the phantom, it only delays it: turning [TooltipVisibility] back on hands
  /// every tooltip a brand new mouse region, Flutter posts a perfectly genuine
  /// enter into whichever one is under the cursor, and the bubble the guard
  /// just suppressed opens anyway a beat later. So the last word belongs to
  /// the pointer — one real movement, and tooltips are back.
  bool _needsMove = false;

  /// How long after the last scroll notification tooltips are allowed back.
  ///
  /// A [ScrollEndNotification] is NOT the end of anything here: the glide
  /// hands over one slice per frame and each slice is its own `pointerScroll`,
  /// which dispatches start / update / end of its own. The only dependable
  /// signal that scrolling has finished is that nothing has arrived for a
  /// while. Long enough to bridge a dropped frame, short enough that a
  /// deliberate hover straight after a scroll is not left waiting.
  static const Duration _settleDelay = Duration(milliseconds: 250);

  @override
  void initState() {
    super.initState();
    DsScrollTooltipGuard._hushes.addListener(_onHush);
  }

  @override
  void dispose() {
    DsScrollTooltipGuard._hushes.removeListener(_onHush);
    _settle?.cancel();
    _silent.dispose();
    super.dispose();
  }

  void _onHush() => _silence(DsScrollTooltipGuard._hushFor);

  void _silence(Duration hold) {
    if (!_silent.value) {
      _silent.value = true;
      // TooltipVisibility only stops the NEXT one from opening; one already
      // on screen has to be dismissed by hand.
      Tooltip.dismissAllToolTips();
    }
    _settle?.cancel();
    _settle = Timer(hold + _settleDelay, () {
      if (!mounted) return;
      // A mouse can be waited on; a finger cannot — a long press is how a
      // tooltip is asked for on a touch screen, and it never hovers first, so
      // there would be nothing left to switch tooltips back on.
      if (RendererBinding.instance.mouseTracker.mouseIsConnected) {
        _needsMove = true;
      } else {
        _release();
      }
    });
  }

  void _release() {
    _settle?.cancel();
    _needsMove = false;
    _silent.value = false;
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification is ScrollStartNotification || notification is ScrollUpdateNotification) {
      _silence(Duration.zero);
    }
    // Never swallowed — scrollbars, the sticky headers and the edge
    // auto-scroll all listen for these too.
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      // Hover only: a pointer with a button down reports moves instead, and
      // those belong to a drag, which is one of the things being guarded
      // against. Nothing is consumed here — see [HitTestBehavior.deferToChild].
      onPointerHover: (_) {
        if (_needsMove) _release();
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: ValueListenableBuilder<bool>(
          valueListenable: _silent,
          child: widget.child,
          builder: (context, silent, child) =>
              TooltipVisibility(visible: !silent, child: child!),
        ),
      ),
    );
  }
}
