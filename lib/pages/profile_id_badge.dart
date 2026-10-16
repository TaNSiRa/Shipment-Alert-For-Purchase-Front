part of '../main.dart';

/// Which card the Profile page shows on the left: the printed employee badge or
/// the plain information card the page has always had.
///
/// Remembered per machine (browser storage) like the liquid-glass switch: it is
/// a "how this app looks to me" answer, not an account setting. Default ON: the
/// badge is the one that says whose account this is at a glance, and the
/// classic card is there for anyone who would rather read a list.
class ProfileCardStyle {
  ProfileCardStyle._();

  static const _key = 'psa.profileIdBadge';

  static final ValueNotifier<bool> idBadge = ValueNotifier<bool>(_read())..addListener(_remember);

  static bool _read() {
    try {
      return html.window.localStorage[_key] != '0';
    } catch (_) {
      return true;
    }
  }

  static void _remember() {
    try {
      html.window.localStorage[_key] = idBadge.value ? '1' : '0';
    } catch (_) {}
  }
}

/// The company ID badge, drawn as the physical object: lanyard, clip, plastic
/// holder, and the printed card inside it.
///
/// ── What is on which face ──────────────────────────────────────────────────
///
/// The front carries exactly what the real badge carries at arm's length — the
/// company line, your face, your name, and the department band along the
/// bottom. Nothing else. Everything you would have to walk up and read is on
/// the back: contact, organisation, section access, activity, all of it the
/// same [_ProfileFacts] block the classic card shows, so the two can never
/// disagree.
///
/// Click the card to turn it over.
///
/// ── Why a real object and not a panel ──────────────────────────────────────
///
/// This is the one page in the app that is about a person rather than about
/// work, and the badge is the thing every person here already has in their
/// hand. The lanyard and the plastic are what make it read as that object
/// instead of as another rounded rectangle — they cost one painter and are the
/// whole reason the card is recognisable before it is read.
class _ProfileIdBadge extends StatefulWidget {
  const _ProfileIdBadge({
    required this.name,
    this.fullName,
    this.namePrefix = '',
    required this.role,
    this.position = '',
    required this.section,
    required this.department,
    this.employeeNo = '',
    required this.facts,
    required this.hasAvatar,
    required this.onAvatarAction,
    this.photo,
    this.placement,
    this.onPlacementChanged,
  });

  final String name;
  final String? fullName;
  final String namePrefix;
  final String role;
  final String position;
  final String section;
  final String department;
  final String employeeNo;

  /// The back of the card: the same [_ProfileFacts] block the classic card
  /// shows (built dense, without its leading rule), so the two never disagree.
  final Widget facts;
  final bool hasAvatar;
  final ValueChanged<String> onAvatarAction;

  /// The saved profile picture as a data URL, or null for the empty portrait.
  final String? photo;

  /// Where the photo was last dragged to, as `"dx,dy,zoom"`, or null for the
  /// centred default. Saved on the account (`users.badge_photo_pos`).
  final String? placement;

  /// Called when a drag or a zoom finishes, with the new `"dx,dy,zoom"` (or
  /// null once it is reset). The page saves it.
  final ValueChanged<String?>? onPlacementChanged;

  @override
  State<_ProfileIdBadge> createState() => _ProfileIdBadgeState();
}

class _ProfileIdBadgeState extends State<_ProfileIdBadge> with SingleTickerProviderStateMixin {
  // The printed card. ID-1 portrait is 54×86 mm; this is that ratio, sized to
  // sit inside the page's 300 px left column with the holder around it.
  static const double _cardW = 246;
  static const double _cardH = 386;

  // The plastic holder: a margin of clear plastic around the card, plus the
  // strip above it that the hole is punched through.
  static const double _holderPadX = 8;
  static const double _holderTop = 24;
  static const double _holderBottom = 12;

  // Lanyard height above the holder — the straps and the clip live here.
  static const double _strapH = 74;

  // The printed portrait: centred, standing on the band. This is only where it
  // STARTS — it can be dragged anywhere on the card.
  static const double _photoW = 196;
  static const double _photoH = 250;

  // The section band along the foot of the card.
  static const double _bandH = 44;

  static const double _minZoom = .5;
  static const double _maxZoom = 3;

  // Where the uploaded picture sits inside the portrait slot, and how big.
  // Dragged on the card itself and saved to the account by the page, so the
  // badge looks the same on every machine.
  Offset _pan = Offset.zero;
  double _zoom = 1;
  bool get _placed => _pan != Offset.zero || _zoom != 1;

  /// The last value handed to [_ProfileIdBadge.onPlacementChanged]. Kept so the
  /// saved row coming back around (the page reloads the session after writing
  /// it) is recognised as our own work and does not restart the picture.
  String? _sent;

  late final AnimationController _flip = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );

  @override
  void initState() {
    super.initState();
    _applyPlacement(widget.placement);
  }

  @override
  void didUpdateWidget(covariant _ProfileIdBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A placement arriving from anywhere other than this card — another machine,
    // another tab, the session reloading — is adopted. Our own last write is
    // not, or the picture would jump back to where it already is.
    if (widget.placement != oldWidget.placement && widget.placement != _sent) {
      setState(() => _applyPlacement(widget.placement));
    }
  }

  @override
  void dispose() {
    _flip.dispose();
    super.dispose();
  }

  /// Reads `"dx,dy,zoom"` back into the two numbers that draw it. A value that
  /// is missing or malformed leaves the picture centred rather than throwing —
  /// this string comes off a database row and has to survive being nonsense.
  void _applyPlacement(String? value) {
    final parts = (value ?? '').split(',');
    if (parts.length != 3) {
      _pan = Offset.zero;
      _zoom = 1;
      return;
    }
    final dx = double.tryParse(parts[0]);
    final dy = double.tryParse(parts[1]);
    final zoom = double.tryParse(parts[2]);
    _pan = dx == null || dy == null ? Offset.zero : Offset(dx, dy);
    _zoom = zoom == null ? 1 : zoom.clamp(_minZoom, _maxZoom);
  }

  void _savePlacement() {
    // Null puts the row back to "never moved", which is also what the reset
    // button means — a default worth storing three numbers for is not a default.
    _sent = _placed
        ? '${_pan.dx.toStringAsFixed(1)},${_pan.dy.toStringAsFixed(1)},${_zoom.toStringAsFixed(3)}'
        : null;
    widget.onPlacementChanged?.call(_sent);
  }

  void _resetPlacement() {

    setState(() {
      _pan = Offset.zero;
      _zoom = 1;
    });
    _savePlacement();
  }

  // Dragging can push the picture around inside the slot but never out of it —
  // a photo you cannot find again is not a feature.
  void _dragBy(Offset delta) {
    setState(() {
      _pan = Offset(
        (_pan.dx + delta.dx).clamp(-_cardW * .7, _cardW * .7),
        (_pan.dy + delta.dy).clamp(-_cardH * .8, _cardH * .4),
      );
    });
  }

  void _zoomBy(double factor) {
    setState(() => _zoom = (_zoom * factor).clamp(_minZoom, _maxZoom));
  }

  void _toggleFlip() {
    // A turning card is the kind of thing the tick was made for: small,
    // physical, caused by the click that just happened.

    if (_flip.value >= .5) {
      _flip.reverse();
    } else {
      _flip.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    final holderW = _cardW + _holderPadX * 2;
    final holderH = _cardH + _holderTop + _holderBottom;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        width: holderW + 10,
        height: _strapH + holderH,
        child: Stack(clipBehavior: Clip.none, children: [
          // Straps first: everything else hangs in front of them.
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: _strapH + 6,
            child: CustomPaint(painter: _LanyardPainter()),
          ),
          Positioned(
            left: 5,
            top: _strapH,
            width: holderW,
            height: holderH,
            child: _holder(),
          ),
          // The clip clamps the holder, so it is painted over the top of it.
          Positioned(left: 0, right: 0, top: _strapH - 40, child: Center(child: _clip())),
        ]),
      ),
      const SizedBox(height: 14),
      // Rebuilt with the flip so the button can say which face it will bring
      // back, rather than naming an action whose result you cannot see.
      AnimatedBuilder(animation: _flip, builder: (context, _) => _controls()),
    ]);
  }

  // ── The plastic ────────────────────────────────────────────────────────────

  Widget _holder() {
    return Container(
      decoration: BoxDecoration(
        // Clear plastic over a page that is already pale: a whisper of white
        // with a brighter rim is all that reads as a sheet of it. Any more and
        // it turns into a second card behind the card.
        color: Colors.white.withValues(alpha: .34),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: .85), width: 1.4),
        boxShadow: [
          BoxShadow(
            color: const Color(0xff1b2447).withValues(alpha: .16),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(children: [
        // The punched hole the clip goes through.
        Positioned(
          top: 9,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              width: 62,
              height: 8,
              decoration: BoxDecoration(
                color: const Color(0xff2a3358).withValues(alpha: .16),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: Colors.white.withValues(alpha: .55)),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(_holderPadX, _holderTop, _holderPadX, _holderBottom),
          child: _flipper(),
        ),
      ]),
    );
  }

  // The silver reel at the top of the strap, with the company mark on it.
  Widget _clip() {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 42,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xfffdfefe), Color(0xffd2d8e2), Color(0xffeef1f6)],
            stops: [0, .55, 1],
          ),
          border: Border.all(color: const Color(0xffb3bbc9), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: const Color(0xff1b2447).withValues(alpha: .22),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: _logoMark(width: 26),
      ),
      // The hook: the little tongue that passes through the punched hole.
      Container(
        width: 13,
        height: 26,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xffe4e8ef), Color(0xffc6cdd9)],
          ),
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(6)),
          border: Border.all(color: const Color(0xffb3bbc9), width: 1),
        ),
      ),
    ]);
  }

  // ── The card itself ────────────────────────────────────────────────────────

  Widget _flipper() {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _toggleFlip,
        child: AnimatedBuilder(
          animation: _flip,
          builder: (context, _) {
            final angle = _flip.value * pi;
            final showFront = _flip.value < .5;
            return Transform(
              alignment: Alignment.center,
              // A small amount of perspective is the difference between a card
              // TURNING and a card being squashed horizontally.
              transform: Matrix4.identity()
                ..setEntry(3, 2, .0011)
                ..rotateY(angle),
              child: showFront
                  ? _face(child: _front())
                  : Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()..rotateY(pi),
                      child: _face(child: _back()),
                    ),
            );
          },
        ),
      ),
    );
  }

  // The printed sheet both faces are laid on.
  Widget _face({required Widget child}) {
    return Container(
      width: _cardW,
      height: _cardH,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(11),
        boxShadow: [
          BoxShadow(
            color: const Color(0xff1b2447).withValues(alpha: .12),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _front() {
    final latin = _latinLine();
    // The band names the SECTION, not the department — that is the line the
    // real badge carries, and it is the answer to "who do I go to" here. The
    // word "section" itself is left off: it is a badge, not a form field.
    final band = widget.section.trim().isNotEmpty ? widget.section.trim() : widget.department.trim();
    return Stack(children: [
      // The printed background: the company's diagonal chevrons and the blue
      // corner over the company line.
      Positioned.fill(child: CustomPaint(painter: _BadgePrintPainter())),
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _companyHeader(),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Scaled down rather than wrapped: a printed name sits on one line,
            // and a long one is set smaller — it does not become two lines.
            SizedBox(
              width: _cardW - 28,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(widget.name, style: _badgeText(27, FontWeight.w700, _ink, height: 1.16)),
              ),
            ),
            if (latin.isNotEmpty) ...[
              const SizedBox(height: 5),
              SizedBox(
                width: _cardW - 28,
                child: Text(latin,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: _badgeText(8.5, FontWeight.w600, const Color(0xff8a93a6),
                        letterSpacing: 1.6, height: 1.5)),
              ),
            ],
          ]),
        ),
      ]),
      // The photo is the top layer, over the name and over the company line. It
      // starts low, standing on the band, but it can be dragged the whole
      // height and width of the card: on the printed badge the head reaches the
      // name, and where exactly it should sit depends on the photograph.
      Positioned(left: 0, right: 0, top: 0, bottom: _bandH, child: _photo()),
      // The band is painted over the photo: the person is CUT by it, the way
      // the printed one is, instead of standing in front of it.
      Positioned(left: 0, right: 0, bottom: 0, child: _sectionBand(band)),
      // The picture controls live in the empty lower-left corner, clear of the
      // name and of the photo's usual place.
      Positioned(
        left: 11,
        bottom: _bandH + 11,
        child: Row(children: [
          _AvatarMenuButton(hasAvatar: widget.hasAvatar, onAction: widget.onAvatarAction, size: 26),
          // Only once the photo has been moved — an always-present reset is a
          // button that does nothing almost every time it is seen.
          if (_placed) ...[
            const SizedBox(width: 7),
            Tooltip(
              message: 'Put the photo back',
              child: InkWell(
                borderRadius: BorderRadius.circular(13),
                onTap: _resetPlacement,
                child: Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xffd3dae6), width: 1.4),
                  ),
                  child: const Icon(Icons.restart_alt, size: 14, color: _ink),
                ),
              ),
            ),
          ],
        ]),
      ),
    ]);
  }

  Widget _back() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        color: _ink,
        child: Row(children: [
          Expanded(
            child: Text('EMPLOYEE INFORMATION',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _badgeText(8.5, FontWeight.w700, Colors.white, letterSpacing: 1.5)),
          ),
          const SizedBox(width: 10),
          // The role code as it would be printed — SECTION_ADMIN is a database
          // value, not something anyone writes on a card.
          Text(widget.role.replaceAll('_', ' '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _badgeText(7.5, FontWeight.w600, Colors.white.withValues(alpha: .7), letterSpacing: .7)),
        ]),
      ),
      // A card has a fixed height and this list does not, so the list is the
      // part that gives: it scrolls inside the card rather than stretching it.
      // Someone in six sections overruns even the dense setting, and the fade
      // below is what says so — a row sliced in half by the footer reads as a
      // bug, the same row fading out reads as "there is more".
      Expanded(
        child: Stack(children: [
          Scrollbar(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: widget.facts,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 16,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.white, Colors.white.withValues(alpha: 0)],
                  ),
                ),
              ),
            ),
          ),
        ]),
      ),
      Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [_ink, _inkLight]),
        ),
        child: Row(children: [
          Text('EMP. NO',
              style:
                  _badgeText(7.5, FontWeight.w700, Colors.white.withValues(alpha: .65), letterSpacing: 1.2)),
          const SizedBox(width: 7),
          Text(widget.employeeNo.trim().isEmpty ? '-' : widget.employeeNo.trim(),
              style: const TextStyle(
                fontFamily: dsFontMono,
                fontFamilyFallback: dsFontFallback,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: .5,
              )),
          const Spacer(),
          Text('THAI PARKERIZING',
              style:
                  _badgeText(7.5, FontWeight.w700, Colors.white.withValues(alpha: .65), letterSpacing: 1.1)),
        ]),
      ),
    ]);
  }

  Widget _companyHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _logoMark(width: 46),
          const SizedBox(width: 8),
          Flexible(
            child: Text('THAI PARKERIZING CO., LTD.',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _badgeText(8.2, FontWeight.w700, _ink, letterSpacing: .55)),
          ),
        ]),
      ]),
    );
  }

  Widget _sectionBand(String label) {
    return SizedBox(
      height: _bandH,
      child: Stack(children: [
        Positioned.fill(child: CustomPaint(painter: _BandPainter())),
        // The name keeps to the left two-thirds so it can never run into the
        // slashes at the other end.
        Padding(
          padding: const EdgeInsets.only(left: 16, right: 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: _cardW * .62,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(label.toUpperCase(),
                    style: _badgeText(12, FontWeight.w700, Colors.white, letterSpacing: 1.8)),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  // The photo as it is printed: a portrait, not the app's round avatar.
  //
  // Nothing is drawn behind it and nothing is drawn over it — no panel, no
  // avatar colour, and no faded edges. Feathering the edges was an attempt to
  // blend a rectangle into the card; it reads as a white haze over the face,
  // it keeps the picture from ever reaching the card's own edge, and it is
  // unnecessary for what this card is meant to carry: a cut-out on a
  // transparent background.
  //
  // It is draggable. A square crop dropped into a tall frame never lands where
  // a face wants to be, and the alternative — reopening the crop dialog and
  // guessing — is guessing. Drag to move it, wheel to size it. It can be taken
  // to any edge and over the name; the card clips it, nothing else does.
  Widget _photo() {
    return Builder(
      builder: (context) {
        final photo = widget.photo;
        // The picture's own box: the size it is printed at, at the foot of the
        // slot. The slot is the whole card so a drag can take the photo
        // anywhere in it — and so the hand that drags it can follow.
        final picture = Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            height: _photoH,
            width: _photoW,
            child: Transform.translate(
              offset: _pan,
              child: Transform.scale(
                scale: _zoom,
                child: photo == null
                    ? _emptyPortrait()
                    : Image.network(photo,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                        filterQuality: FilterQuality.medium,
                        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) => dsPhotoOverInitials(
                            context, child, frame, wasSynchronouslyLoaded,
                            placeholder: _emptyPortrait()),
                        errorBuilder: (context, error, stack) => _emptyPortrait()),
              ),
            ),
          ),
        );
        if (photo == null) return picture;
        return MouseRegion(
          cursor: SystemMouseCursors.move,
          child: Listener(
            onPointerSignal: (event) {
              if (event is! PointerScrollEvent) return;
              _zoomBy(pow(1.0015, -event.scrollDelta.dy).toDouble());
            },
            child: GestureDetector(
              // The card flips on a TAP, so a drag that starts on the photo is
              // the photo's: the pan recogniser takes the gesture off the tap
              // as soon as the pointer actually travels.
              onPanUpdate: (details) => _dragBy(details.delta),
              onPanEnd: (_) => _savePlacement(),
              child: Tooltip(
                message: 'Drag to place your photo · scroll to size it',
                waitDuration: const Duration(milliseconds: 700),
                child: picture,
              ),
            ),
          ),
        );
      },
    );
  }

  // What the portrait shows before there is a photograph: a silhouette and the
  // initials, in the card's own ink rather than the avatar's colour.
  Widget _emptyPortrait() {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.person, size: 78, color: _ink.withValues(alpha: .16)),
        Text(avatarInitials(widget.fullName, widget.name),
            style: _badgeText(26, FontWeight.w700, _ink.withValues(alpha: .55), letterSpacing: 2)),
      ]),
    );
  }

  // ── Under the badge ────────────────────────────────────────────────────────

  Widget _controls() {
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      _CardStyleLink(
        icon: Icons.sync_alt,
        label: _flip.value >= .5 ? 'Show front' : 'Show details',
        onTap: _toggleFlip,
      ),
      const SizedBox(width: 8),
      _CardStyleLink(
        icon: Icons.credit_card_outlined,
        label: 'Classic card',
        onTap: () {

          ProfileCardStyle.idBadge.value = false;
        },
      ),
    ]);
  }

  /// The Latin line under the name: the formal name as it is printed on the
  /// real badge — capitals, letter-spaced, under the big name. Falls back to
  /// the job position so the line is never empty for someone who has not filled
  /// a full name in.
  String _latinLine() {
    final formal =
        [widget.namePrefix, widget.fullName ?? ''].map((v) => v.trim()).where((v) => v.isNotEmpty).join(' ');
    if (formal.isNotEmpty && formal.toLowerCase() != widget.name.trim().toLowerCase()) {
      return formal.toUpperCase();
    }
    return widget.position.trim().toUpperCase();
  }
}

/// One of the small ghost buttons under the card: turn it over, or swap the
/// whole card for the other style.
class _CardStyleLink extends StatelessWidget {
  const _CardStyleLink({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: .6),
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 15, color: DsColors.navy),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: DsColors.navy)),
          ]),
        ),
      ),
    );
  }
}

/// The company mark WITHOUT the "THAI PARKERIZING" wordmark printed under it.
///
/// `logo_tpk.png` is the full lockup, 164×86, and the wordmark in it is only a
/// few pixels tall: anywhere small — a badge header, a 42 px clip — it lands as
/// an illegible grey smudge under the symbol. The symbol ends at 64/86 of the
/// height, so this crops there and shows the mark alone.
///
/// [width] sizes it, and the height is computed rather than left to the image:
/// an [Image] given one axis has NO size at all until its bytes have decoded,
/// so a header built the lazy way lays itself out once without the logo and
/// again with it — a visible jump on every page open.
Widget _logoMark({required double width}) {
  // Cropped by the IMAGE, not by a clip around it: a box of the mark's own
  // aspect ratio plus `cover` and a top alignment leaves the wordmark outside
  // the frame. Both axes are given, because an [Image] handed one axis has no
  // size at all until its bytes decode — a header built that way lays itself
  // out once without the logo and again with it.
  return SizedBox(
    width: width,
    height: width * _markH / _logoW,
    child: Image.asset('logo_tpk.png', fit: BoxFit.cover, alignment: Alignment.topCenter),
  );
}

// logo_tpk.png is 164×86 with the symbol ending at y=64; the rest is the
// "THAI PARKERIZING" wordmark, which is a few pixels tall and illegible
// anywhere small.
const double _logoW = 164;
const double _markH = 64;

/// The badge's own ink: the navy the company prints in, sampled out of
/// `logo_tpk.png` itself rather than guessed at (#22225c, the mark's own
/// colour). Deliberately NOT [DsColors.navy] — the app's accent is an indigo
/// chosen for screens, and a screen-blue here makes the replica look like a
/// themed panel instead of a printed card.
const Color _ink = Color(0xff22225c);

/// One step up from [_ink] for the foot band's gradient. Still navy: the card
/// has no royal or sky blue on it anywhere except the two accent slashes.
const Color _inkLight = Color(0xff2e2e75);

/// The two slashes across the empty right end of the foot band.
const Color _slashPale = Color(0xff6fc4ec);
const Color _slashBlue = Color(0xff2f5fb0);

/// Every string printed on the badge, in the app's one face ([dsFontSans] —
/// Anuphan draws Thai and Latin alike). Named on each style rather than
/// inherited, because the badge is a picture of a printed object: it must not
/// change shape when an ancestor's text theme does.
TextStyle _badgeText(double size, FontWeight weight, Color color, {double? letterSpacing, double? height}) {
  return TextStyle(
    fontFamily: dsFontSans,
    fontSize: size,
    fontWeight: weight,
    color: color,
    letterSpacing: letterSpacing,
    height: height,
  );
}

/// The foot band: navy, with the two slashes across the empty end of it.
///
/// The slashes are the one place on this card where a blue that is not navy is
/// allowed — they are the printed accent, and they are why the band does not
/// read as a plain coloured strip.
class _BandPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    canvas.drawRect(
      Offset.zero & size,
      Paint()..shader = const LinearGradient(colors: [_ink, _inkLight]).createShader(Offset.zero & size),
    );

    // Leaning the same way as the chevron above them: down from the right, off
    // the bottom-left of the band.
    void slash(double x, double width, Color color) {
      final lean = h * .55;
      canvas.drawPath(
        Path()
          ..moveTo(x, 0)
          ..lineTo(x + width, 0)
          ..lineTo(x + width - lean, h)
          ..lineTo(x - lean, h)
          ..close(),
        Paint()..color = color,
      );
    }

    slash(w * .74, 9, _slashPale);
    slash(w * .74 + 15, 22, _slashBlue);
    slash(w * .74 + 45, 7, _slashPale);
  }

  @override
  bool shouldRepaint(covariant _BandPainter oldDelegate) => false;
}

/// The two straps running off the top of the page into the clip.
///
/// Painted rather than built from rotated boxes: the straps taper as they
/// converge, and a tapering quadrilateral is a path, not a rectangle anyone can
/// rotate into place.
class _LanyardPainter extends CustomPainter {
  // Royal blue woven tape, with the weave read as a single lighter sheen line
  // down the middle of each strap rather than as texture — at this size texture
  // would only be noise.
  static const Color _tape = Color(0xff2a2a6d);
  static const Color _tapeDark = Color(0xff1d1d52);
  static const Color _sheen = Color(0xff45459a);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final joinY = size.height - 4;

    void strap({required double topA, required double topB, required double botA, required double botB}) {
      final path = Path()
        ..moveTo(topA, -1)
        ..lineTo(topB, -1)
        ..lineTo(botB, joinY)
        ..lineTo(botA, joinY)
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_tapeDark, _tape],
          ).createShader(Offset.zero & size),
      );
      // The sheen: a hairline a third of the way across the tape.
      canvas.drawLine(
        Offset(topA + (topB - topA) * .34, 0),
        Offset(botA + (botB - botA) * .34, joinY),
        Paint()
          ..color = _sheen.withValues(alpha: .55)
          ..strokeWidth = 2,
      );
    }

    // Right first so the left one crosses over it at the clip, the way a
    // lanyard folds.
    strap(topA: size.width - 70, topB: size.width - 38, botA: cx - 2, botB: cx + 22);
    strap(topA: 38, topB: 70, botA: cx - 22, botB: cx + 2);
  }

  @override
  bool shouldRepaint(covariant _LanyardPainter oldDelegate) => false;
}

/// What is PRINTED on a blank card before anyone's name goes on it: one grey
/// chevron across the body, and the pale corner that runs off the top-right
/// behind the company line.
///
/// ONE line, not a field of stripes. It enters at the top right, crosses to the
/// middle of the left edge and turns back down to the bottom right — a single
/// stroke with a corner in it, which is what is on the real card. A set of
/// parallel diagonals was tried first and reads as a pattern; this reads as a
/// printed mark.
///
/// Painted rather than shipped as an image so it stays crisp at any size and
/// costs nothing to load.
class _BadgePrintPainter extends CustomPainter {
  // Grey, and barely there: this is the paper. Paper that competes with the
  // name printed on it is a mistake in the artwork.
  static const Color _line = Color(0xffecf0f5);
  static const Color _corner = Color(0xffe9eef6);
  static const Color _cornerSoft = Color(0xfff4f7fb);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // The corner: two overlapping wedges running off the top-right, the paler
    // one behind. They sit BEHIND the company line, which is why they stop
    // short of the logo.
    void wedge(double fromX, double depth, Color color) {
      final path = Path()
        ..moveTo(fromX, 0)
        ..lineTo(w, 0)
        ..lineTo(w, depth)
        ..lineTo(fromX - depth * .42, depth)
        ..close();
      canvas.drawPath(path, Paint()..color = color);
    }

    wedge(w * .46, 54, _cornerSoft);
    wedge(w * .66, 34, _corner);

    // The chevron. Stroked rather than filled so the corner at the left edge
    // stays one continuous band of the same width all the way round.
    canvas.drawPath(
      Path()
        ..moveTo(w + 20, h * .16)
        ..lineTo(-12, h * .55)
        ..lineTo(w + 20, h * .99),
      Paint()
        ..color = _line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 24
        ..strokeJoin = StrokeJoin.miter
        ..strokeCap = StrokeCap.butt,
    );
  }

  @override
  bool shouldRepaint(covariant _BadgePrintPainter oldDelegate) => false;
}
