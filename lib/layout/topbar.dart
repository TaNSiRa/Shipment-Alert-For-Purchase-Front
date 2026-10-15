part of '../main.dart';

/// The idle auto-logout deadline, re-armed by the shell on every pointer or
/// key event. The nav's countdown reads it so the number shown is the real one.
class IdleClock {
  IdleClock._();
  static DateTime? deadline;
  static Duration warnLead = const Duration(minutes: 2);
  static Duration? get remaining {
    final at = deadline;
    if (at == null) return null;
    final left = at.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }
}

class TopBar extends StatelessWidget {
  const TopBar({
    super.key,
    required this.title,
    required this.subtitle,
    required this.me,
    required this.health,
    required this.alerts,
    required this.sectionCount,
    required this.onRefresh,
    required this.onChangeSection,
    required this.onProfile,
    required this.onOpenAlert,
    required this.onSeeAllAlerts,
  });

  final String title;
  final String subtitle;
  final Map<String, dynamic>? me;
  final Map<String, dynamic> health;
  final List<dynamic> alerts;
  final int sectionCount;
  final Future<void> Function() onRefresh;
  final VoidCallback onChangeSection;
  final VoidCallback onProfile;
  final void Function(Map<String, dynamic> po) onOpenAlert;
  final VoidCallback onSeeAllAlerts;

  @override
  Widget build(BuildContext context) {
    final name = '${me?['displayName'] ?? me?['email'] ?? ''}';
    final role = roleLabel('${me?['roleCode'] ?? ''}');
    final width = MediaQuery.of(context).size.width;
    final bar = Container(
      height: kDsTopBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: BoxDecoration(
        color: Lg.on ? const Color(0x45ffffff) : DsColors.topbar,
        border: Lg.on ? null : const Border(bottom: BorderSide(color: DsColors.topbarBorder)),
      ),
      foregroundDecoration: Lg.on ? const BoxDecoration(border: LiquidRim(band: 12, strength: .6)) : null,
      child: Row(
        children: [
          Expanded(
            child: AnimatedSwitcher(
              duration: DsMotion.of(context, DsMotion.page),
              switchInCurve: DsMotion.curveIn,
              switchOutCurve: DsMotion.curveOut,
              layoutBuilder: (currentChild, previousChildren) => Stack(
                alignment: Alignment.centerLeft,
                children: [...previousChildren, if (currentChild != null) currentChild],
              ),
              child: Column(
                key: ValueKey(title),
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: DsType.pageTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: DsType.pageSub),
                ],
              ),
            ),
          ),
          if (width >= 860) ...[
            DsHealthPill(label: 'API', ok: health['api'] == 'ok', compact: true, description: dsApiPillDescription),
            const SizedBox(width: 6),
            DsHealthPill(
                label: 'SQL', ok: health['database'] == 'ok', compact: true, description: dsSqlPillDescription),
            const SizedBox(width: 6),
          ],
          const LiquidThemeToggle(),
          AlertsBell(alerts: alerts, onOpen: onOpenAlert, onSeeAll: onSeeAllAlerts),
          DsIconButton(icon: Icons.refresh, onTap: () => unawaited(onRefresh()), tooltip: 'Refresh'),
          if (sectionCount > 1) DsIconButton(icon: Icons.apartment, onTap: onChangeSection, tooltip: 'Change section'),
          Container(
              width: 1, height: 26, color: DsColors.inputBorder, margin: const EdgeInsets.symmetric(horizontal: 8)),
          InkWell(
            borderRadius: BorderRadius.circular(9),
            onTap: onProfile,
            hoverColor: DsColors.chip,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  UserAvatar(user: me, size: 34, radius: 9),
                  if (width >= 980) ...[
                    const SizedBox(width: 9),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 170),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: DsColors.heading)),
                          Text(role, style: const TextStyle(fontSize: 11, color: DsColors.faint)),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
    return DsFrosted(child: bar);
  }
}

/// Bell in the top bar: the POs that are overdue or due today. Clicking one
/// opens it.
class AlertsBell extends StatelessWidget {
  const AlertsBell({super.key, required this.alerts, required this.onOpen, required this.onSeeAll});
  final List<dynamic> alerts;
  final void Function(Map<String, dynamic> po) onOpen;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final count = alerts.length;
    return MenuAnchor(
      alignmentOffset: const Offset(-320, 6),
      style: MenuStyle(
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        backgroundColor: const WidgetStatePropertyAll(DsColors.popupSurface),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
      ),
      menuChildren: [
        SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: Row(children: [
                  const Icon(Icons.notifications_active_outlined, size: 18, color: DsColors.navy),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('Needs attention', style: DsType.cardTitle)),
                  DsTag('$count',
                      color: count > 0 ? DsColors.redFg : DsColors.greenFg,
                      bg: count > 0 ? DsColors.redBg : DsColors.greenBg),
                ]),
              ),
              const Divider(height: 1),
              if (alerts.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Column(children: [
                    Icon(Icons.task_alt, color: DsColors.greenFg, size: 30),
                    SizedBox(height: 8),
                    Text('Nothing is overdue or due today', style: DsType.meta),
                  ]),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 380),
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    children: [
                      for (final raw in alerts.take(40))
                        MenuItemButton(
                          onPressed: () => onOpen(Map<String, dynamic>.from(raw)),
                          child: SizedBox(
                            width: 340,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(children: [
                                DueDot(state: '${raw['dueState']}'),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text('PO ${raw['poNo']} · ${raw['supplierShort'] ?? raw['supplierName'] ?? ''}',
                                        maxLines: 1, overflow: TextOverflow.ellipsis, style: DsType.rowTitle),
                                    Text('${raw['currentStepName'] ?? ''}',
                                        maxLines: 1, overflow: TextOverflow.ellipsis, style: DsType.metaSm),
                                  ]),
                                ),
                                const SizedBox(width: 8),
                                DueChip(po: Map<String, dynamic>.from(raw), dense: true),
                              ]),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              const Divider(height: 1),
              TextButton(onPressed: onSeeAll, child: const Text('Open the shipment list')),
            ],
          ),
        ),
      ],
      builder: (context, controller, _) => Stack(clipBehavior: Clip.none, children: [
        DsIconButton(
          icon: count > 0 ? Icons.notifications_active_outlined : Icons.notifications_none,
          tooltip: 'Alerts',
          onTap: () => controller.isOpen ? controller.close() : controller.open(),
        ),
        if (count > 0)
          Positioned(
            right: 2,
            top: 2,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                constraints: const BoxConstraints(minWidth: 16),
                decoration: BoxDecoration(
                  color: DsColors.redFg,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                alignment: Alignment.center,
                child: Text(count > 99 ? '99+' : '$count',
                    style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w800, height: 1.1)),
              ),
            ),
          ),
      ]),
    );
  }
}
