part of '../main.dart';

/// Width of the side nav in each of its two states. Everything in the nav is
/// positioned by lerping between them, so these two numbers are the only place
/// the geometry is stated.
const double kNavCollapsedWidth = 95;
const double kNavExpandedWidth = 236;

/// Everything to the right of a menu item's icon when the nav is open: the
/// [kNavExpandedWidth] less the ListView's padding (12 each side), the icon's
/// own inset (11) and the icon itself (19). The gap before the label and the
/// one after the badge live INSIDE this.
const double _kNavLabelWidth = kNavExpandedWidth - 24 - 11 - 19;

/// The header block beside the logo — section name plus the collapse button.
/// Fixed, so it can be wiped as a non-flex child and the logo can take whatever
/// is left; it is what keeps the mark centred in the collapsed strip.
const double _kNavHeaderTrailWidth = 132;

/// Menu geometry, stated rather than measured.
///
/// The liquid theme's selection is ONE pill that slides between items instead of
/// a plate fading in under each of them, and a pill that slides has to know
/// where it is going before it gets there. Measuring the target item would mean
/// a post-frame pass, a scroll listener and a frame of lag every time; laying
/// the menu out on numbers we control instead means the pill's destination is
/// just arithmetic over the same list the rows are built from.
///
/// So every row is a fixed height. [_kNavItemHeight] is the item's own 38 px
/// plus the 2 px of breathing room above and below it, and the group label is
/// boxed at [_kNavGroupLabelHeight] so its wipe is `t` of a known number rather
/// than `t` of whatever the font decided.
const double _kNavItemHeight = 42;
const double _kNavItemGap = 2;
const double _kNavGroupLabelHeight = 26;
const double _kNavGroupGap = 10;

/// Wipes a piece of the nav in and out as the panel opens, instead of letting
/// it appear the instant the flag flips.
///
/// This is the whole trick behind both fixes. The old nav rebuilt itself into
/// the expanded layout on the first frame of the animation while the box was
/// still 95 px wide — which is what threw the overflow, and what made the
/// motion read as a pop followed by a slide rather than one movement.
/// [Align.widthFactor] takes a fraction of the child's own width and
/// [ClipRect] hides the rest, so the child is always laid out at its full size
/// and no Flex is ever asked to fit in less room than it needs.
class _NavReveal extends StatelessWidget {
  const _NavReveal({required this.t, required this.child, this.axis = Axis.horizontal});

  /// 0 = fully hidden, 1 = fully shown.
  final double t;
  final Widget child;
  final Axis axis;

  @override
  Widget build(BuildContext context) {
    if (t <= 0) return const SizedBox.shrink();
    final horizontal = axis == Axis.horizontal;
    return ClipRect(
      child: Align(
        alignment: horizontal ? Alignment.centerLeft : Alignment.topCenter,
        widthFactor: horizontal ? t : null,
        heightFactor: horizontal ? null : t,
        // Text fades in over the back half of the wipe. Fading it in step with
        // the width means reading it while it is still half-cut, which is what
        // makes a sliding panel feel busy.
        child: Opacity(opacity: Curves.easeIn.transform((t * 1.8 - .8).clamp(0.0, 1.0)), child: child),
      ),
    );
  }
}


/// Every page of the app, in sidebar order.
enum AppPage { dashboard, pos, roadmap, calendar, workflow, suppliers, materials, users, settings, profile }

/// Title + one-line subtitle shown in the top bar for each page.
(String, String) pageHeading(AppPage page) => switch (page) {
      AppPage.dashboard => ('Dashboard', 'Where every shipment stands today'),
      AppPage.pos => ('Shipments', 'Purchase orders — import, follow up and update each step'),
      AppPage.roadmap => ('Road Map', 'Progress of every open shipment across the 9 steps'),
      AppPage.calendar => ('Calendar', 'Due dates, completed steps and expected arrivals'),
      AppPage.workflow => ('Workflow', 'The 9-step purchase process and its lead times'),
      AppPage.suppliers => ('Supplier Master', 'Suppliers and their default lead time'),
      AppPage.materials => ('Material Master', 'Materials, vendor material names and lead times'),
      AppPage.users => ('Manage Users', 'Accounts, roles and section access'),
      AppPage.settings => ('Settings', 'Email alerts, scheduling and system administration'),
      AppPage.profile => ('Profile', 'Your account, password and email preferences'),
    };

class SideNav extends StatelessWidget {
  const SideNav({
    super.key,
    required this.collapsed,
    required this.selected,
    required this.section,
    required this.overdue,
    required this.onToggle,
    required this.onSelect,
    required this.onLogout,
  });

  final bool collapsed;
  final AppPage selected;
  final Map<String, dynamic>? section;
  final int overdue;
  final VoidCallback onToggle;
  final ValueChanged<AppPage> onSelect;
  final VoidCallback onLogout;

  List<(AppPage, IconData, String, int)> visibleItems(List<(AppPage, IconData, String, int)> items) => items;

  @override
  Widget build(BuildContext context) {
    final isSectionAdmin = section?['isSectionAdmin'] == true;
    final sectionName = '${section?['name'] ?? 'Purchase'}';
    final groups = <(String, List<(AppPage, IconData, String, int)>)>[
      (
        'Workspace',
        [
          (AppPage.dashboard, Icons.space_dashboard_outlined, 'Dashboard', 0),
          (AppPage.pos, Icons.inventory_2_outlined, 'Shipments', overdue),
          (AppPage.roadmap, Icons.route_outlined, 'Road Map', 0),
          (AppPage.calendar, Icons.calendar_month_outlined, 'Calendar', 0),
        ]
      ),
      (
        'Process',
        [
          (AppPage.workflow, Icons.account_tree_outlined, 'Workflow', 0),
        ]
      ),
      (
        'Master Data',
        [
          (AppPage.suppliers, Icons.storefront_outlined, 'Supplier Master', 0),
          (AppPage.materials, Icons.science_outlined, 'Material Master', 0),
        ]
      ),
      if (isSectionAdmin)
        (
          'Admin',
          [
            (AppPage.users, Icons.manage_accounts_outlined, 'Manage Users', 0),
            (AppPage.settings, Icons.settings_outlined, 'Settings', 0),
          ]
        ),
      ('Account', [(AppPage.profile, Icons.person_outline, 'Profile', 0)]),
    ];
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: collapsed ? 0 : 1),
      duration: DsMotion.of(context, DsMotion.nav),
      curve: DsMotion.curveChrome,
      builder: (context, t, _) => _build(context, t, groups, sectionName),
    );
  }

  Widget _build(
    BuildContext context,
    double t,
    List<(String, List<(AppPage, IconData, String, int)>)> groups,
    String sectionName,
  ) {
    // The nav is the one large surface with NOTHING scrolling behind it, which
    // makes it the ideal drop: it can refract the background outright instead of
    // blurring live content. Square corners, so it stays flush inside
    // [DsGlassShell] — the dome still forms along all four edges.
    final panel = Container(
      width: ui.lerpDouble(kNavCollapsedWidth, kNavExpandedWidth, t),
      decoration: BoxDecoration(
        color: Lg.on ? const Color(0x3dffffff) : DsColors.sidebar,
        border: Lg.on ? null : const Border(right: BorderSide(color: DsColors.sidebarBorder)),
      ),
      foregroundDecoration: Lg.on ? const BoxDecoration(border: LiquidRim(strength: .75)) : null,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
              child: Row(
                children: [
                  // Collapsed, the mark sits in the middle of the strip; opened,
                  // it slides to the left edge as the section name arrives
                  // beside it. Alignment does the travel, so nothing has to be
                  // measured.
                  Expanded(
                    child: Align(
                      alignment: Alignment.lerp(Alignment.center, Alignment.centerLeft, t)!,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                        decoration: BoxDecoration(
                          // A lit tile on the glass, like every other raised
                          // thing in the shell — white enough to carry the mark,
                          // with the wash still showing through behind it.
                          color: DsColors.glass,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: DsColors.glassEdge),
                          boxShadow: const [
                            BoxShadow(color: DsColors.glassContact, blurRadius: 8, offset: Offset(0, 2))
                          ],
                        ),
                        child: Image.asset('logo_tpk.png', height: 24),
                      ),
                    ),
                  ),
                  _NavReveal(
                    t: t,
                    child: SizedBox(
                      width: _kNavHeaderTrailWidth,
                      child: Row(children: [
                        const SizedBox(width: 11),
                        Expanded(
                          child: Text(
                            sectionName,
                            style: const TextStyle(
                                color: DsColors.heading,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                height: 1.1),
                          ),
                        ),
                        IconButton(
                            onPressed: onToggle,
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.chevron_left, color: DsColors.faint2, size: 20),
                            tooltip: 'Collapse menu'),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
            // The expand button is the collapse button's opposite number, so it
            // wipes vertically on the same clock rather than blinking in once
            // the panel has finished closing.
            _NavReveal(
              t: 1 - t,
              axis: Axis.vertical,
              child: IconButton(
                  onPressed: onToggle,
                  icon: const Icon(Icons.chevron_right, color: DsColors.faint2, size: 20),
                  tooltip: 'Expand menu'),
            ),
            Expanded(child: _menu(context, t, groups)),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Container(
                decoration: const BoxDecoration(border: Border(top: BorderSide(color: DsColors.line))),
                padding: const EdgeInsets.only(top: 12),
                child: _NavLogoutButton(t: t, onTap: onLogout),
              ),
            ),
            Padding(
              padding: EdgeInsets.only(left: 12, right: 12, bottom: ui.lerpDouble(10, 12, t)!),
              child: t < .5
                  ? const Tooltip(
                      message: 'Developed by Automation Department',
                      child: Icon(Icons.precision_manufacturing_outlined, size: 16, color: DsColors.faint2),
                    )
                  : Opacity(
                      opacity: ((t - .5) * 2).clamp(0.0, 1.0),
                      child: const Text(
                        'Developed by Automation Department',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: DsColors.faint2,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w500,
                            letterSpacing: .1),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
    return Lg.on ? LiquidDrop(radius: 0, strength: .75, child: panel) : panel;
  }

  /// The scrolling menu itself.
  ///
  /// Two builds of the same list. The flat theme keeps the original: each item
  /// owns its highlight, and the selection crosses the menu by one plate fading
  /// out while another fades in. The liquid theme hands the highlight to a
  /// SINGLE pill that travels — sent with [DsMotion.curveSlide], so it runs past
  /// its target and settles back the way the reference's rail does.
  ///
  /// The pill lives inside the scrolled content, not over it, which is what
  /// saves this from needing to track the scroll offset: it is laid out in the
  /// same coordinate space as the rows, so it scrolls with them for free.
  Widget _menu(
    BuildContext context,
    double t,
    List<(String, List<(AppPage, IconData, String, int)>)> groups,
  ) {
    const padding = EdgeInsets.fromLTRB(12, 4, 12, 18);

    Widget label(String text) => _NavReveal(
          t: t,
          axis: Axis.vertical,
          child: SizedBox(
            height: _kNavGroupLabelHeight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 7),
              child: Align(
                alignment: Alignment.bottomLeft,
                child: DsSectionLabel(text, color: DsColors.faint2),
              ),
            ),
          ),
        );

    if (!Lg.on) {
      return ListView(
        padding: padding,
        children: [
          for (final group in groups) ...[
            // Drop items a viewer can't see; skip the whole group if empty.
            if (visibleItems(group.$2).isNotEmpty) ...[
              // Collapsed, the group label collapses to plain spacing — as a
              // vertical wipe, so the items below drift down into place instead
              // of jumping when the label appears.
              const SizedBox(height: _kNavGroupGap),
              label(group.$1),
              for (final item in visibleItems(group.$2))
                NavItem(
                  icon: item.$2,
                  label: item.$3,
                  t: t,
                  selected: selected == item.$1,
                  badge: item.$4,
                  onTap: () => onSelect(item.$1),
                ),
            ],
          ],
        ],
      );
    }

    // Walk the same list the rows are built from, adding up the heights as we
    // go, and note where the selected row lands. Nothing here is measured — see
    // [_kNavItemHeight] for why.
    final rows = <Widget>[];
    var y = 0.0;
    double? pillTop;
    for (final group in groups) {
      final items = visibleItems(group.$2);
      if (items.isEmpty) continue;
      rows.add(const SizedBox(height: _kNavGroupGap));
      y += _kNavGroupGap;
      rows.add(label(group.$1));
      // The label is wiped to a FRACTION of its box, so it takes that fraction
      // of the height with it.
      y += _kNavGroupLabelHeight * t;
      for (final item in items) {
        if (item.$1 == selected) pillTop = y + _kNavItemGap;
        rows.add(NavItem(
          icon: item.$2,
          label: item.$3,
          t: t,
          selected: selected == item.$1,
          badge: item.$4,
          onTap: () => onSelect(item.$1),
          // The highlight is the travelling pill's job now.
          pill: false,
        ));
        y += _kNavItemHeight;
      }
    }

    return SingleChildScrollView(
      padding: padding,
      child: Stack(
        children: [
          if (pillTop != null)
            TweenAnimationBuilder<double>(
              // Only `end` matters after the first build: TweenAnimationBuilder
              // restarts from wherever the pill currently IS, so clicking a
              // third item mid-flight redirects it instead of snapping.
              tween: Tween<double>(begin: pillTop, end: pillTop),
              // While the PANEL is opening or closing the group labels are
              // wiping, so every row above the pill is changing height on every
              // frame. Springing after that would leave the pill drifting for
              // half a second after the nav had finished; it tracks the wipe
              // exactly instead, and only springs when it is the SELECTION that
              // moved.
              duration: t == (collapsed ? 0.0 : 1.0) ? DsMotion.of(context, DsMotion.slide) : Duration.zero,
              curve: DsMotion.curveSlide,
              child: const _NavPill(),
              builder: (context, top, child) => Positioned(
                top: top,
                left: 0,
                right: 0,
                height: _kNavItemHeight - _kNavItemGap * 2,
                child: child!,
              ),
            ),
          // Stretch, because a Column hands its children loose constraints where
          // a ListView hands them the full width — without this every row would
          // shrink-wrap to its label.
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
        ],
      ),
    );
  }
}

/// The travelling selection pill: a lit pane of glass with the accent bar the
/// reference hangs off its leading edge.
class _NavPill extends StatelessWidget {
  const _NavPill();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: lgRaised(radius: 11, scale: .92),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          width: 3,
          height: 22,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [DsColors.navyLight, DsColors.navy],
            ),
            borderRadius: BorderRadius.circular(3),
            boxShadow: [
              BoxShadow(color: DsColors.navy.withValues(alpha: .55), blurRadius: 9, spreadRadius: 1),
            ],
          ),
        ),
      ),
    );
  }
}

/// Where a menu icon starts at openness [t].
///
/// Collapsed it is centred in the strip — the item is the nav width less the
/// ListView's 12 px either side, and the icon is 19 wide — and expanded it sits
/// at a plain 11 px inset. Every icon in the nav reads this one function, which
/// is what keeps the column of them travelling together.
double _navIconInset(double t) {
  const centred = (kNavCollapsedWidth - 24 - 19) / 2;
  return ui.lerpDouble(centred, 11, t)!;
}

/// The nav's Logout button. Unlike every other item in the nav it sits in red
/// AT REST — signing out is the one destructive thing on the panel, and a grey
/// row that only turns red once the cursor is already on it announces that too
/// late. The row itself is unfilled at rest; hovering brings in a soft red wash
/// and deepens the label, so the hint is "this is the one" and the hover is
/// "yes, this".
class _NavLogoutButton extends StatefulWidget {
  const _NavLogoutButton({required this.t, required this.onTap});

  /// Nav openness, 0 collapsed → 1 open.
  final double t;
  final VoidCallback onTap;

  @override
  State<_NavLogoutButton> createState() => _NavLogoutButtonState();
}

class _NavLogoutButtonState extends State<_NavLogoutButton> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final fade = DsMotion.of(context, DsMotion.fast);
    return MouseRegion(
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      // One 0→1 value drives the fill AND the icon/label, so the whole button
      // deepens together instead of the box beating the text to it.
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: hovered ? 1 : 0),
        duration: fade,
        curve: DsMotion.curveChrome,
        builder: (context, h, child) => _body(h, child!),
        child: _NavReveal(
          t: widget.t,
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(width: 10),
            Text('Logout', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            SizedBox(width: 10),
          ]),
        ),
      ),
    );
  }

  Widget _body(double h, Widget label) {
    final foreground = Color.lerp(DsColors.redFg, DsColors.redFgHover, h)!;
    return DecoratedBox(
      decoration: BoxDecoration(
        // No fill at rest — the red icon and label carry the signal on their
        // own. The wash only appears under the cursor, and it fades in on the
        // ALPHA of the red itself: lerping from Colors.transparent would walk
        // the RGB up from black and flash grey on the way in.
        color: DsColors.redBg.withValues(alpha: h),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: widget.onTap,
          // The fill above already carries the hover; a second wash on top of
          // it would just mute the colour we just deepened.
          hoverColor: Colors.transparent,
          child: SizedBox(
            height: 42,
            child: Row(
              children: [
                // Same inset the menu icons ride on, so the logout icon
                // tracks them exactly as the panel opens.
                SizedBox(width: _navIconInset(widget.t)),
                Icon(Icons.logout, color: foreground, size: 19),
                // The label is built once and passed through the tween — only
                // its colour changes, via DefaultTextStyle.
                DefaultTextStyle.merge(
                  style: TextStyle(
                    color: foreground,
                    fontFamily: dsFontSans,
                    fontFamilyFallback: dsFontFallback,
                  ),
                  child: label,
                ),
                // How long the session has left, pinned to the right edge of
                // the same row: the clock belongs with the button that ends the
                // session by hand. Collapsed nav has no room for it, so it
                // fades out on the same curve the label wipes on.
                if (widget.t > 0)
                  Expanded(
                    child: Opacity(
                      opacity: Curves.easeIn.transform((widget.t * 1.8 - .8).clamp(0.0, 1.0)),
                      child: const Align(
                        alignment: Alignment.centerRight,
                        child: _NavIdleCountdown(),
                      ),
                    ),
                  ),
                SizedBox(width: ui.lerpDouble(0, 12, widget.t)!),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The idle auto-logout clock, at the right edge of the Logout row. It counts
/// down to [IdleClock.deadline] — which the app shell re-arms on every pointer
/// event — so the number a user sees is the real one, not a second copy of the
/// rule that could drift from it.
///
/// Grey while there is time, RED once the remaining time is inside
/// [IdleClock.warnLead]: the same moment the "Still there?" dialog appears, so
/// the colour is a warning the user has already learned to read.
class _NavIdleCountdown extends StatefulWidget {
  const _NavIdleCountdown();

  @override
  State<_NavIdleCountdown> createState() => _NavIdleCountdownState();
}

class _NavIdleCountdownState extends State<_NavIdleCountdown> {
  Timer? _tick;
  Duration? _left;

  @override
  void initState() {
    super.initState();
    _left = IdleClock.remaining;
    // One second is the resolution shown, so that is the rate — the deadline
    // itself moves far more often than this (every mouse move), but repainting
    // the same digits sixty times a second would buy nothing.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _left = IdleClock.remaining);
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  static String _clock(Duration d) {
    final total = d.inSeconds;
    return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final left = _left;
    // No session being timed (signed out, or the shell has not armed it yet).
    if (left == null) return const SizedBox.shrink();
    final urgent = left <= IdleClock.warnLead;
    return Tooltip(
      message: 'Signed out automatically in ${_clock(left)} of no activity.\n'
          'Moving the mouse or clicking anywhere starts the count again.',
      child: Text(
        _clock(left),
        maxLines: 1,
        style: mono(
          size: 11.5,
          weight: urgent ? FontWeight.w800 : FontWeight.w600,
          color: urgent ? DsColors.redFg : DsColors.faint2,
        ),
      ),
    );
  }
}

class NavItem extends StatelessWidget {
  const NavItem(
      {super.key,
      required this.icon,
      required this.label,
      required this.t,
      required this.selected,
      required this.badge,
      required this.onTap,
      this.pill = true});
  final IconData icon;
  final String label;

  /// How far the side nav is open, 0..1 — see [SideNav]. The item reads it
  /// rather than a collapsed flag so the icon glides from the centre of the
  /// strip to its inset instead of jumping there on the first frame.
  final double t;
  final bool selected;
  final int badge;
  final VoidCallback onTap;

  /// Whether the item draws its OWN highlight. False under the liquid theme,
  /// where one shared pill travels between items instead — see [SideNav._menu].
  final bool pill;

  bool get _collapsed => t < .5;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? DsColors.navyHover : DsColors.text2;
    // The selection travels between menu items rather than blinking on and off:
    // the navy plate and the accent rail grow in while the previous item's fade
    // out, so the eye can follow where the highlight went.
    final move = DsMotion.of(context, DsMotion.chrome);
    return Tooltip(
      message: _collapsed ? label : '',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: AnimatedContainer(
          duration: move,
          curve: DsMotion.curveChrome,
          decoration: BoxDecoration(
            // Selected is a lit pill lifted off the glass, not a lilac plate:
            // over a translucent nav an opaque fill reads as a sticker. The
            // indigo rail and icon still carry which item it is.
            color: selected && pill ? DsColors.navPill : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
            boxShadow: selected && pill
                ? [const BoxShadow(color: DsColors.glassContact, blurRadius: 10, offset: Offset(0, 3))]
                : null,
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(11),
            child: InkWell(
              borderRadius: BorderRadius.circular(11),
              onTap: onTap,
              // Hover LIGHTENS on glass. The old dark scrim worked on a white
              // nav; over the wash it just dirtied the pane.
              hoverColor: const Color(0x4dffffff),
              child: SizedBox(
                height: 38,
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    Positioned(
                      left: 0,
                      top: 8,
                      bottom: 8,
                      child: AnimatedContainer(
                        duration: move,
                        curve: DsMotion.curveChrome,
                        width: selected && pill ? 3 : 0,
                        decoration:
                            BoxDecoration(color: DsColors.navy, borderRadius: BorderRadius.circular(3)),
                      ),
                    ),
                    // The collapsed strip has no room for the count, so it
                    // shows a dot instead — faded on the same clock as the
                    // label it stands in for.
                    if (_collapsed && badge > 0)
                      Positioned(
                        right: 14,
                        top: 6,
                        child: Opacity(
                          opacity: (1 - t * 2).clamp(0.0, 1.0),
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(color: DsColors.redBadge, shape: BoxShape.circle),
                          ),
                        ),
                      ),
                    Row(
                      children: [
                        SizedBox(width: _navIconInset(t)),
                        AnimatedScale(
                          scale: selected ? 1.1 : 1,
                          duration: move,
                          curve: DsMotion.curveChrome,
                          child: TweenAnimationBuilder<Color?>(
                            tween: ColorTween(end: fg),
                            duration: DsMotion.of(context, DsMotion.fast),
                            builder: (context, color, _) => Icon(icon, color: color ?? fg, size: 19),
                          ),
                        ),
                        // The label block is always built at the width it has
                        // when the nav is open, and wiped to [t] of it. Laying
                        // it out at the CURRENT width instead is what used to
                        // overflow: at the first frame of the expansion the
                        // text, badge and gaps were being asked to fit in 95 px.
                        Flexible(
                          child: _NavReveal(
                            t: t,
                            child: SizedBox(
                              width: _kNavLabelWidth,
                              child: Row(children: [
                                const SizedBox(width: 11),
                                Expanded(
                                  child: AnimatedDefaultTextStyle(
                                    duration: DsMotion.of(context, DsMotion.fast),
                                    style: TextStyle(
                                        color: fg,
                                        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                                        // AnimatedDefaultTextStyle REPLACES the inherited style instead of merging,
                                        // so the theme's family is lost unless named again here. Without it the label
                                        // falls through to the engine default (Roboto), which Flutter fetches from
                                        // fonts.gstatic.com at runtime — absent offline, and blocked by our CSP, and
                                        // text with no font renders as nothing at all.
                                        fontFamily: dsFontSans,
                                        fontFamilyFallback: dsFontFallback,
                                        fontSize: 13),
                                    child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                                  ),
                                ),
                                if (badge > 0)
                                  Container(
                                    constraints: const BoxConstraints(minWidth: 18),
                                    height: 18,
                                    alignment: Alignment.center,
                                    padding: const EdgeInsets.symmetric(horizontal: 5),
                                    decoration: BoxDecoration(
                                        color: DsColors.redBg, borderRadius: BorderRadius.circular(10)),
                                    child: Text('$badge',
                                        style: const TextStyle(
                                            color: DsColors.redFg,
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w700)),
                                  ),
                                const SizedBox(width: 10),
                              ]),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

