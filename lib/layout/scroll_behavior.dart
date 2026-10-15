part of '../main.dart';

// Scroll behaviours and drag guards, taken from RAP's app shell unchanged.

class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<ui.PointerDeviceKind> get dragDevices => {
        ui.PointerDeviceKind.touch,
        ui.PointerDeviceKind.mouse,
        ui.PointerDeviceKind.stylus,
        ui.PointerDeviceKind.unknown,
      };

  // RangeMaintainingScrollPhysics is the parent Material itself uses, and it is
  // not optional: it is what stops a list from jumping when its contents change
  // height underneath it — which, on pages that stream in live updates over a
  // socket, is most of them.
  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(parent: RangeMaintainingScrollPhysics());

  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) =>
      child;
}

/// [AppScrollBehavior] with mouse drag-to-pan taken back out.
///
/// [AppScrollBehavior.dragDevices] lists the mouse so a view can be panned by
/// dragging it — which the boards and grids genuinely want. The exception is a
/// TEXT FIELD inside such a scroller: dragging across text to select it is also
/// a drag across the scroller, and the scroller wins, so selecting a word in a
/// card scrolled the board sideways under the cursor at the same time
/// ("ถ้าจะลากคลุมข้อความ มันไปเลื่อน card ซ้ายขวาพร้อมกันด้วย").
///
/// This is not applied to a whole page — see [DsDragPanScope], which swaps it
/// in only while the pointer is actually over a field.
class NoMouseDragScrollBehavior extends AppScrollBehavior {
  const NoMouseDragScrollBehavior();

  @override
  Set<ui.PointerDeviceKind> get dragDevices =>
      super.dragDevices.where((kind) => kind != ui.PointerDeviceKind.mouse).toSet();
}

/// [AppScrollBehavior] that does NOT add a scrollbar of its own.
///
/// Material puts a scrollbar on every scrollable on desktop and web, from
/// `ScrollBehavior.buildScrollbar`. Writing a [Scrollbar] widget by hand around
/// a scroll view therefore gives it TWO — stacked in the same channel, sharing
/// the same notifications, drawn one over the other. It is easy to miss while
/// both are thin grey hairlines with identical settings, and impossible to miss
/// once one of them is `thumbVisibility: true` and the other fades in and out
/// on its own schedule ("scroll มัน ซ้อนกันอะ อันนึงอยู่ค้างตลอด อีกอันแสดงแล้วก็หายไป").
///
/// So: **an explicit [Scrollbar] must be wrapped in a `ScrollConfiguration`
/// with this behaviour.** Everything else about the app's scrolling — physics,
/// drag devices, no overscroll glow — is inherited unchanged, and the theme in
/// `main.dart` still styles the hand-written bar, because that is a
/// ScrollbarTheme and not part of this.
///
/// Write an explicit [Scrollbar] only when the automatic one cannot do the job:
/// when it must always be visible, when it belongs to a scroller other than the
/// nearest one (see the skill-matrix grid, whose rows scroll inside a
/// horizontal viewport), or when it has to sit outside something.
class NoAutoScrollbarBehavior extends AppScrollBehavior {
  const NoAutoScrollbarBehavior();

  @override
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails details) => child;
}

/// Marks a widget the pointer must be able to drag INSIDE without the scroller
/// around it panning — in practice, a text field in a board or a grid.
///
/// Pair with [DsDragPanScope] on the scroller. The link between them is a
/// single static owner rather than plumbing: only one pointer has a hover
/// position, so only one guard can be under it, and a board is a lot of widgets
/// to thread a notifier through.
///
/// **The two rules are deliberately asymmetric, and both are load-bearing:**
///
///  * ENTER is ignored while a button is down. Otherwise dragging the board
///    past a card's field would cut the pan off halfway, mid-gesture, because
///    the scroller's recognizers are rebuilt underneath it.
///  * EXIT always clears. If it deferred to the button the same way, releasing
///    outside the field would leave panning switched off over the whole board
///    until the pointer happened to cross a field again.
///
/// Ownership is by identity, not a counter, so moving from one field straight
/// to the next is safe whichever order the enter and exit callbacks arrive in —
/// the new owner simply replaces the old, and the old one's exit is a no-op.
class DsTextDragGuard extends StatefulWidget {
  const DsTextDragGuard({super.key, required this.child});

  final Widget child;

  /// True while the pointer is inside some guard. Watched by [DsDragPanScope].
  static final ValueNotifier<bool> active = ValueNotifier<bool>(false);

  static Object? _owner;

  @override
  State<DsTextDragGuard> createState() => _DsTextDragGuardState();
}

class _DsTextDragGuardState extends State<DsTextDragGuard> {
  @override
  void dispose() {
    // A field can be removed while the pointer is still over it — a card
    // deleted, a column closed — and no exit event follows.
    if (identical(DsTextDragGuard._owner, this)) {
      DsTextDragGuard._owner = null;
      DsTextDragGuard.active.value = false;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      opaque: false,
      onEnter: (event) {
        if (event.down) return;
        DsTextDragGuard._owner = this;
        DsTextDragGuard.active.value = true;
      },
      onExit: (_) {
        if (!identical(DsTextDragGuard._owner, this)) return;
        DsTextDragGuard._owner = null;
        DsTextDragGuard.active.value = false;
      },
      child: widget.child,
    );
  }
}

/// Wraps the OUTERMOST scroller of an area whose content contains text fields:
/// mouse drag-to-pan works everywhere in it except while the pointer is inside
/// a [DsTextDragGuard].
///
/// The scroller subtree is passed through `child` and is NOT rebuilt when the
/// guard flips — only the [ScrollConfiguration] above it is, which is the point:
/// changing it makes the Scrollable rebuild its gesture recognizers, and that
/// rebuild is the whole mechanism. Everything below stays as it was.
///
/// Nested scrollers inherit the configuration, so one of these at the top of a
/// board covers its columns too.
class DsDragPanScope extends StatelessWidget {
  const DsDragPanScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: DsTextDragGuard.active,
      builder: (context, overText, child) => ScrollConfiguration(
        behavior: overText ? const NoMouseDragScrollBehavior() : const AppScrollBehavior(),
        child: child!,
      ),
      child: child,
    );
  }
}

