part of '../main.dart';

class ExpandedFlex extends StatelessWidget {
  const ExpandedFlex({super.key, required this.compact, required this.child});
  final bool compact;
  final Widget child;
  @override
  Widget build(BuildContext context) => compact ? child : Expanded(child: child);
}

class MetricTile extends StatelessWidget {
  const MetricTile(
      {super.key,
      required this.width,
      required this.icon,
      required this.label,
      required this.value,
      required this.color,
      this.sub,
      this.iconBg,
      this.onTap});
  final double width;
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final String? sub;
  final Color? iconBg;

  /// When set, the whole tile becomes clickable (dashboard tiles jump to the
  /// request list / work board).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // The design stacks these rather than putting the icon beside the number:
    // a small colour chip and the label on one line, the figure on its own
    // below. That lets the number start at the tile's left edge, so a row of
    // tiles reads as a row of numbers instead of a row of icons.
    final card = DsCard(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          // No-op at the tile's natural height. Where the tile is handed MORE
          // height than it needs — the dashboard strip, which shares the hero
          // card's height — the label keeps the top and the figure drops to
          // the bottom, instead of both stacking under a band of dead space.
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: iconBg ?? color.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 15),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(label,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: DsType.label),
                ),
              ],
            ),
            // The figure and its sub-label travel together as ONE child, so
            // spaceBetween has two things to push apart rather than spreading
            // the gap through the middle of the number.
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Counts up on arrival when the value is a plain number;
                  // anything formatted (a percentage, a dash) is shown as given.
                  dsAnimatedValue(value, style: DsType.statLg),
                  if (sub != null) ...[
                    const SizedBox(height: 4),
                    Text(sub!, maxLines: 1, overflow: TextOverflow.ellipsis, style: DsType.metaSm),
                  ],
                ],
              ),
            ),
          ],
        ),
    );
    return SizedBox(
      width: width,
      child: onTap == null
          ? card
          : MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(onTap: onTap, child: card),
            ),
    );
  }
}

/// White card with an optional title row, matching the design system.
class Panel extends StatelessWidget {
  const Panel({super.key, this.title, this.trailing, this.icon, this.fill = false, required this.child});
  final String? title;
  final Widget? trailing;
  final IconData? icon;
  // Give the body whatever height is left under the title instead of letting it
  // size itself. Only for panels placed in a box of a known height — a panel in
  // a scroll view has no height to hand out.
  final bool fill;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DsCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (title != null) ...[
          DsCardTitle(title!, trailing: trailing, icon: icon),
          const SizedBox(height: 14),
        ],
        if (fill) Expanded(child: child) else child,
      ]),
    );
  }
}

/// Prev/page-number/next bar for tables paginated at a fixed page size.
/// [page] is 0-based; renders nothing when there's only one page.
class PaginationBar extends StatelessWidget {
  const PaginationBar(
      {super.key, required this.page, required this.totalItems, required this.pageSize, required this.onChanged});
  final int page;
  final int totalItems;
  final int pageSize;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final totalPages = max(1, (totalItems / pageSize).ceil());
    if (totalPages <= 1) return const SizedBox.shrink();
    final clampedPage = page.clamp(0, totalPages - 1);
    final start = clampedPage * pageSize + 1;
    final end = min(totalItems, start + pageSize - 1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: DsColors.line))),
      child: Row(children: [
        Text('$start–$end of $totalItems', style: const TextStyle(fontSize: 12, color: DsColors.faint)),
        const Spacer(),
        DsIconButton(
          icon: Icons.chevron_left,
          size: 32,
          iconSize: 18,
          tooltip: 'Previous page',
          onTap: clampedPage > 0 ? () => onChanged(clampedPage - 1) : null,
        ),
        const SizedBox(width: 6),
        Text('Page ${clampedPage + 1} of $totalPages',
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: DsColors.text)),
        const SizedBox(width: 6),
        DsIconButton(
          icon: Icons.chevron_right,
          size: 32,
          iconSize: 18,
          tooltip: 'Next page',
          onTap: clampedPage < totalPages - 1 ? () => onChanged(clampedPage + 1) : null,
        ),
      ]),
    );
  }
}

/// A pill button that opens a tick-list filter (Calendar's Type / Status /
/// Incharge, Request List's Status / Type). null filter = "all"; otherwise it
/// shows how many are selected.
class MultiFilterButton extends StatelessWidget {
  const MultiFilterButton({
    super.key,
    required this.icon,
    required this.allLabel,
    required this.filter,
    required this.options,
    required this.labelOf,
    required this.dialogTitle,
    required this.onApply,
    this.height = 30,
  });

  final IconData icon;
  final String allLabel;
  final Set<String>? filter;
  final List<String> options;
  final String Function(String) labelOf;
  final String dialogTitle;
  final ValueChanged<Set<String>?> onApply;
  final double height;

  @override
  Widget build(BuildContext context) {
    final isAll = filter == null;
    final label = isAll ? allLabel : '${filter!.length} selected';
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: options.isEmpty ? null : () => _open(context),
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: isAll ? DsColors.chip : DsColors.navySoft,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isAll ? DsColors.cardBorder : DsColors.navy),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: isAll ? DsColors.muted : DsColors.navy),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: isAll ? DsColors.text : DsColors.navy)),
          const SizedBox(width: 2),
          Icon(Icons.expand_more, size: 16, color: isAll ? DsColors.muted : DsColors.navy),
        ]),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    final temp = {...(filter ?? options.toSet())};
    await showGlassDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setD) => AlertDialog(
          titlePadding: const EdgeInsets.fromLTRB(22, 22, 22, 8),
          contentPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          actionsPadding: const EdgeInsets.fromLTRB(22, 8, 22, 18),
          title: Row(children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: DsColors.navySoft, borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: DsColors.navy, size: 21),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(dialogTitle)),
          ]),
          content: SizedBox(
            width: 380,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(children: [
                  TextButton(
                      onPressed: () => setD(() => temp
                        ..clear()
                        ..addAll(options)),
                      child: const Text('Select all')),
                  TextButton(onPressed: () => setD(temp.clear), child: const Text('Clear')),
                ]),
              ),
              const Divider(height: 1),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: SingleChildScrollView(
                  child: Column(children: [
                    for (final opt in options)
                      CheckboxListTile(
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        activeColor: DsColors.navy,
                        value: temp.contains(opt),
                        title: Text(labelOf(opt), style: const TextStyle(fontSize: 13.5)),
                        onChanged: (v) => setD(() => v == true ? temp.add(opt) : temp.remove(opt)),
                      ),
                  ]),
                ),
              ),
            ]),
          ),
          actions: [
            DsOutlineButton(
                label: 'Cancel', icon: Icons.close, height: 40, onPressed: () => Navigator.pop(dialogContext)),
            DsPrimaryButton(
              label: 'Apply',
              icon: Icons.check,
              height: 40,
              onPressed: () {
                onApply((temp.isEmpty || temp.length == options.length) ? null : {...temp});
                Navigator.pop(dialogContext);
              },
            ),
          ],
        ),
      ),
    );
  }
}
