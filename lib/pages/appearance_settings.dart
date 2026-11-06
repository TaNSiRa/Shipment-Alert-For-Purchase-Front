part of '../main.dart';

/// The profile page's Appearance tab: what is behind the glass.
///
/// Two choices, each saved on this computer by [LgScene]:
///
/// * the PATTERN — [LgBackdrop], with Default always the first tile;
/// * the COLOUR TONE the pattern is painted in — [LgTone], Original first.
///
/// Every thumbnail here is the real scene drawn small ([LiquidField.paintScene]),
/// so what you click is what the page becomes.
class AppearanceSettings extends StatelessWidget {
  const AppearanceSettings({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: LgScene.changes,
      builder: (context, _) {
        final style = LgScene.current.value;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Panel(
            title: 'Background pattern',
            icon: Icons.wallpaper_outlined,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text(
                'Pick the scene behind the glass. It changes at once and is remembered on this computer.',
                style: TextStyle(fontSize: 12.5, color: DsColors.muted, height: 1.5),
              ),
              const SizedBox(height: 14),
              _grid(
                minTile: 140,
                children: [
                  for (final s in LgBackdrop.values)
                    _PatternTile(style: s, selected: s == style, onTap: () => LgScene.current.value = s),
                ],
              ),
            ]),
          ),
          const SizedBox(height: 12),
          Panel(
            title: 'Colour tone',
            icon: Icons.palette_outlined,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                'Paint ${style.label} in another set of colours. Original keeps the pattern’s own.',
                style: const TextStyle(fontSize: 12.5, color: DsColors.muted, height: 1.5),
              ),
              const SizedBox(height: 14),
              _grid(
                minTile: 96,
                spacing: 10,
                children: [
                  for (final t in LgTone.values)
                    _ToneChip(
                      style: style,
                      tone: t,
                      selected: t == LgScene.tone.value,
                      onTap: () => LgScene.tone.value = t,
                    ),
                ],
              ),
            ]),
          ),
        ]);
      },
    );
  }

  /// As many equal columns as fit at [minTile] each.
  static Widget _grid({required double minTile, required List<Widget> children, double spacing = 12}) {
    return LayoutBuilder(builder: (context, constraints) {
      final cols = max(1, ((constraints.maxWidth + spacing) / (minTile + spacing)).floor());
      final tileW = (constraints.maxWidth - spacing * (cols - 1)) / cols;
      return Wrap(spacing: spacing, runSpacing: spacing + 2, children: [
        for (final c in children) SizedBox(width: tileW, child: c),
      ]);
    });
  }
}

/// One pattern: a thumbnail of the real bake with a small pane of glass on it,
/// then the name and a line about it.
class _PatternTile extends StatelessWidget {
  const _PatternTile({required this.style, required this.selected, required this.onTap});

  final LgBackdrop style;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _Thumb(style: style, tone: LgScene.tone.value, selected: selected, radius: 12, pane: true),
          const SizedBox(height: 7),
          Row(children: [
            Expanded(
              child: Text(style.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: DsColors.heading)),
            ),
            if (selected) const Icon(Icons.check_circle, size: 17, color: DsColors.navy),
          ]),
          const SizedBox(height: 2),
          Text(style.blurb,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: DsColors.faint2, height: 1.35)),
        ]),
      ),
    );
  }
}

/// One colour tone, shown as the CURRENT pattern painted in it.
class _ToneChip extends StatelessWidget {
  const _ToneChip({required this.style, required this.tone, required this.selected, required this.onTap});

  final LgBackdrop style;
  final LgTone tone;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Column(children: [
          _Thumb(style: style, tone: tone, selected: selected, radius: 9, pane: false),
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (selected) ...[
              const Icon(Icons.check_circle, size: 14, color: DsColors.navy),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(tone.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                      color: selected ? DsColors.navyDeep : DsColors.text)),
            ),
          ]),
        ]),
      ),
    );
  }
}

/// A bordered thumbnail of [style] in [tone].
class _Thumb extends StatelessWidget {
  const _Thumb(
      {required this.style, required this.tone, required this.selected, required this.radius, required this.pane});

  final LgBackdrop style;
  final LgTone tone;
  final bool selected;
  final double radius;
  final bool pane;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius + 3),
        border: Border.all(color: selected ? DsColors.navy : DsColors.cardBorder, width: selected ? 2 : 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: AspectRatio(
          aspectRatio: 16 / 10,
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _ThumbPainter(style, tone, pane: pane),
              isComplex: true,
            ),
          ),
        ),
      ),
    );
  }
}

class _ThumbPainter extends CustomPainter {
  _ThumbPainter(this.style, this.tone, {required this.pane});

  final LgBackdrop style;
  final LgTone tone;
  final bool pane;

  @override
  void paint(Canvas canvas, Size size) {
    LiquidField.paintScene(canvas, size, style, tone: tone);
    if (!pane) return;
    // A pane of glass on it, so the tile reads as "the page", not a swatch.
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width * .1, size.height * .24, size.width * .52, size.height * .5),
      Radius.circular(size.shortestSide * .08),
    );
    canvas.drawRRect(rect, Paint()..color = Colors.white.withValues(alpha: .42));
    canvas.drawRRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.white.withValues(alpha: .9),
    );
    final bar = Paint()..color = DsColors.navy.withValues(alpha: .28);
    final x = rect.left + rect.width * .1;
    for (var i = 0; i < 3; i++) {
      final y = rect.top + rect.height * (.24 + i * .2);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, rect.width * (i == 0 ? .5 : .74 - i * .12), size.height * .035),
          const Radius.circular(3),
        ),
        bar,
      );
    }
  }

  @override
  bool shouldRepaint(_ThumbPainter old) =>
      old.style != style || old.tone != tone || old.pane != pane;
}
