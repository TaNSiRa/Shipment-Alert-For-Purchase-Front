part of '../main.dart';

class AppToastData {
  const AppToastData({
    required this.id,
    required this.message,
    required this.kind,
    this.onUndo,
    this.undoLabel = 'Undo',
  });

  final int id;
  final String message;
  final AppToastKind kind;

  /// Put the thing back. When this is set the toast grows a button and stays on
  /// screen for [_AppToastItemState.undoDuration] instead of the usual few
  /// seconds — see [AppToast.undo].
  final VoidCallback? onUndo;
  final String undoLabel;
}

enum AppToastKind { success, error, info }

class AppToast {
  static final ValueNotifier<List<AppToastData>> _toasts = ValueNotifier<List<AppToastData>>([]);
  static OverlayEntry? _overlay;
  static int _nextId = 0;

  static void success(BuildContext context, String message) => show(context, message, AppToastKind.success);

  static void error(BuildContext context, String message) => show(context, message, AppToastKind.error);

  static void info(BuildContext context, String message) => show(context, message, AppToastKind.info);

  /// A toast that can be TAKEN BACK.
  ///
  /// The pattern this replaces is "Delete this card?" → [Yes] [No]: a modal that
  /// stops the work, is answered without reading nine times out of ten, and
  /// still cannot help the tenth time when the answer was wrong. Doing the
  /// thing immediately and offering the way back costs one click in the rare
  /// case instead of one click in every case.
  ///
  /// [onUndo] must genuinely restore what was removed — put the row back in the
  /// list AND on the server. A button that only clears the toast is worse than
  /// no button, because the user will trust it.
  ///
  /// The window is deliberately longer than a normal toast: long enough to
  /// notice a mistake, short enough that the corner is clear before the next
  /// action finishes.
  static void undo(
    BuildContext context,
    String message,
    VoidCallback onUndo, {
    String label = 'Undo',
  }) =>
      show(context, message, AppToastKind.info, onUndo: onUndo, undoLabel: label);

  static void show(
    BuildContext context,
    String message,
    AppToastKind kind, {
    VoidCallback? onUndo,
    String undoLabel = 'Undo',
  }) {
    final overlay = Overlay.of(context, rootOverlay: true);
    final data = AppToastData(
        id: ++_nextId, message: message, kind: kind, onUndo: onUndo, undoLabel: undoLabel);
    _toasts.value = [data, ..._toasts.value].take(4).toList();

    if (_overlay == null) {
      _overlay = OverlayEntry(builder: (_) => _AppToastStack(notifier: _toasts));
      overlay.insert(_overlay!);
    } else {
      _overlay!.markNeedsBuild();
    }
  }

  static void dismiss(int id) {
    _toasts.value = _toasts.value.where((toast) => toast.id != id).toList();
    if (_toasts.value.isEmpty) {
      _overlay?.remove();
      _overlay = null;
    } else {
      _overlay?.markNeedsBuild();
    }
  }
}

class _AppToastStack extends StatelessWidget {
  const _AppToastStack({required this.notifier});

  final ValueNotifier<List<AppToastData>> notifier;

  static const double _toastHeight = 76;
  static const double _gap = 10;
  static const double _top = 22;
  static const double _right = 22;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<AppToastData>>(
      valueListenable: notifier,
      builder: (_, toasts, __) {
        return Stack(
          children: [
            for (final entry in toasts.asMap().entries)
              AnimatedPositioned(
                key: ValueKey(entry.value.id),
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                top: _top + entry.key * (_toastHeight + _gap),
                right: _right,
                child: _AppToastItem(
                  data: entry.value,
                  onDismiss: () => AppToast.dismiss(entry.value.id),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _AppToastItem extends StatefulWidget {
  const _AppToastItem({required this.data, required this.onDismiss});

  final AppToastData data;
  final VoidCallback onDismiss;

  @override
  State<_AppToastItem> createState() => _AppToastItemState();
}

class _AppToastItemState extends State<_AppToastItem> with TickerProviderStateMixin {
  late final AnimationController enterController;
  late final AnimationController progressController;
  late final Animation<double> opacity;
  late final Animation<Offset> slide;
  bool dismissing = false;

  static const Duration enterDuration = Duration(milliseconds: 300);
  static const Duration displayDuration = Duration(milliseconds: 3200);

  /// How long an undoable toast waits. Long enough to look up from what you
  /// were doing, read it, and reach the button; short enough that the corner is
  /// clear again before the next action lands there.
  static const Duration undoDuration = Duration(milliseconds: 7000);

  bool get undoable => widget.data.onUndo != null;

  @override
  void initState() {
    super.initState();
    enterController = AnimationController(vsync: this, duration: enterDuration);
    progressController =
        AnimationController(vsync: this, duration: undoable ? undoDuration : displayDuration);
    opacity = CurvedAnimation(parent: enterController, curve: Curves.easeOut);
    slide = Tween<Offset>(begin: const Offset(.24, 0), end: Offset.zero)
        .animate(CurvedAnimation(parent: enterController, curve: Curves.easeOutCubic));
    enterController.forward();
    progressController.forward().then((_) => dismiss());
  }

  Future<void> dismiss() async {
    if (dismissing || !mounted) return;
    dismissing = true;
    progressController.stop();
    await enterController.reverse();
    widget.onDismiss();
  }

  void _undo() {
    if (dismissing) return;
    widget.data.onUndo!();
    dismiss();
  }

  /// The countdown PAUSES under the pointer. Someone who has moved the mouse
  /// onto the toast is reading it, and a window that expires while it is being
  /// read is the one way this pattern fails people.
  void _hover(bool over) {
    if (dismissing || !undoable) return;
    over ? progressController.stop() : progressController.forward().then((_) => dismiss());
  }

  @override
  void dispose() {
    enterController.dispose();
    progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = switch (widget.data.kind) {
      AppToastKind.success => (const Color(0xff15803d), Icons.check_circle_outline_rounded),
      AppToastKind.error => (const Color(0xffdc2626), Icons.error_outline_rounded),
      AppToastKind.info => (const Color(0xff2563eb), Icons.info_outline_rounded),
    };
    final color = colors.$1;
    final icon = colors.$2;

    return FadeTransition(
      opacity: opacity,
      child: SlideTransition(
        position: slide,
        child: MouseRegion(
          onEnter: (_) => _hover(true),
          onExit: (_) => _hover(false),
          child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            // Tapping the body dismisses — but not while there is an Undo to
            // hit, where a stray click on the card would throw away the only
            // way back.
            onTap: undoable ? null : dismiss,
            child: Container(
              // Wider with a button in it, so the message keeps its two lines
              // instead of being squeezed into one and a half.
              width: undoable ? 400 : 340,
              constraints: const BoxConstraints(minHeight: 70),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color.withValues(alpha: .34)),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: .16), blurRadius: 24, offset: const Offset(0, 8)),
                  BoxShadow(color: color.withValues(alpha: .10), blurRadius: 16, offset: const Offset(0, 2)),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Icon(icon, color: color, size: 18),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.data.message,
                          maxLines: undoable ? 2 : 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xff0f172a),
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      if (undoable) ...[
                        // A real button, not a link: this is the control the
                        // whole toast exists for when it is there at all.
                        TextButton.icon(
                          onPressed: _undo,
                          icon: const Icon(Icons.undo_rounded, size: 16),
                          label: Text(widget.data.undoLabel,
                              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                          style: TextButton.styleFrom(
                            foregroundColor: DsColors.navy,
                            backgroundColor: DsColors.navySoft,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                        const SizedBox(width: 4),
                        DsIconButton(
                            icon: Icons.close_rounded,
                            iconSize: 15,
                            size: 26,
                            tooltip: 'Dismiss',
                            onTap: dismiss),
                      ] else
                        Icon(Icons.close_rounded,
                            size: 16, color: const Color(0xff64748b).withValues(alpha: .65)),
                    ]),
                  ),
                  AnimatedBuilder(
                    animation: progressController,
                    builder: (_, __) {
                      return Stack(children: [
                        Container(height: 3, color: color.withValues(alpha: .08)),
                        FractionallySizedBox(
                          widthFactor: 1 - progressController.value,
                          alignment: Alignment.centerLeft,
                          child: Container(height: 3, color: color.withValues(alpha: .65)),
                        ),
                      ]);
                    },
                  ),
                ]),
              ),
            ),
          ),
        ),
        ),
      ),
    );
  }
}
