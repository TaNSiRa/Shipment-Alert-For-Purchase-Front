part of '../main.dart';

// ---------------------------------------------------------------------------
// App scope: what every page needs (API client, who is signed in, which
// section is open, what they may do) without threading it through every
// constructor. The shell rebuilds it whenever any of these change.
// ---------------------------------------------------------------------------

class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.api,
    required this.me,
    required this.section,
    required this.refreshTick,
    required this.navigate,
    required this.openPo,
    required this.onMeChanged,
    required super.child,
  });

  final ApiClient api;
  final Map<String, dynamic> me;
  final Map<String, dynamic> section;

  /// Bumped by the shell on every realtime "something changed" event and on
  /// the Refresh button; pages reload when it moves.
  final int refreshTick;
  final void Function(AppPage page, {Map<String, dynamic>? args}) navigate;
  final Future<void> Function(int poId) openPo;
  final void Function(Map<String, dynamic> me) onMeChanged;

  static AppScope of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!;

  static AppScope? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>();

  /// Reads without subscribing (for callbacks).
  static AppScope read(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!;

  bool get isAdmin => me['roleCode'] == 'ADMIN';
  bool get isSectionAdmin => section['isSectionAdmin'] == true;
  bool get canEdit => section['canEdit'] == true;
  bool get isViewer => me['roleCode'] == 'VIEWER';
  int get userId => intFrom(me['id']) ?? 0;
  String get sectionCode => '${section['code']}';

  @override
  bool updateShouldNotify(AppScope old) =>
      api != old.api || me != old.me || section != old.section || refreshTick != old.refreshTick;
}

// ---------------------------------------------------------------------------
// Formatting
// ---------------------------------------------------------------------------

int? intFrom(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('${value ?? ''}');
}

double? numFrom(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse('${value ?? ''}');
}

DateTime? parseIsoDate(dynamic value) {
  final text = '${value ?? ''}';
  if (text.length < 10) return null;
  return DateTime.tryParse(text.substring(0, 10));
}

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String todayIso() => isoDate(DateTime.now());

final _dateFmt = intl.DateFormat('d MMM yyyy');
final _dateShort = intl.DateFormat('d MMM');
final _dateTimeFmt = intl.DateFormat('d MMM yyyy HH:mm');
final _monthFmt = intl.DateFormat('MMMM yyyy');
final _numFmt = intl.NumberFormat('#,##0.##');
final _moneyFmt = intl.NumberFormat('#,##0.00');

/// '2026-02-18' -> '18 Feb 2026'. Empty -> '-'.
String fmtDate(dynamic iso) {
  final d = parseIsoDate(iso);
  return d == null ? '-' : _dateFmt.format(d);
}

String fmtDateShort(dynamic iso) {
  final d = parseIsoDate(iso);
  return d == null ? '-' : _dateShort.format(d);
}

/// Thai wall-clock timestamps arrive without a zone ('2026-10-15T14:03:00')
/// and are shown exactly as given.
String fmtDateTime(dynamic value) {
  final text = '${value ?? ''}';
  if (text.isEmpty || text == 'null') return '-';
  final d = DateTime.tryParse(text);
  return d == null ? text : _dateTimeFmt.format(d);
}

String fmtMonth(String month) {
  final d = DateTime.tryParse('$month-01');
  return d == null ? month : _monthFmt.format(d);
}

String fmtNum(dynamic value) {
  final n = numFrom(value);
  return n == null ? '-' : _numFmt.format(n);
}

String fmtMoney(dynamic value) {
  final n = numFrom(value);
  return n == null ? '-' : _moneyFmt.format(n);
}

String plural(int n, String one, [String? many]) => '$n ${n == 1 ? one : (many ?? '${one}s')}';

String roleLabel(String code) => switch (code) {
      'ADMIN' => 'System Admin',
      'SECTION_ADMIN' => 'Section Admin',
      'USER' => 'User',
      'VIEWER' => 'Viewer',
      _ => code,
    };

String shipModeLabel(dynamic mode) => switch ('${mode ?? ''}') {
      'SEA' => 'Sea',
      'AIR' => 'Air',
      'TRUCK' => 'Truck',
      'COURIER' => 'Courier',
      _ => '-',
    };

IconData shipModeIcon(dynamic mode) => switch ('${mode ?? ''}') {
      'SEA' => Icons.directions_boat_outlined,
      'AIR' => Icons.flight_outlined,
      'TRUCK' => Icons.local_shipping_outlined,
      'COURIER' => Icons.local_post_office_outlined,
      _ => Icons.help_outline,
    };

/// Material icon for a workflow step's icon name (stored in the database).
IconData stepIcon(dynamic name) => switch ('${name ?? ''}') {
      'receipt_long' => Icons.receipt_long_outlined,
      'mark_email_read' => Icons.mark_email_read_outlined,
      'document_scanner' => Icons.document_scanner_outlined,
      'directions_boat' => Icons.directions_boat_outlined,
      'description' => Icons.description_outlined,
      'local_shipping' => Icons.local_shipping_outlined,
      'assignment' => Icons.assignment_outlined,
      'warehouse' => Icons.warehouse_outlined,
      'summarize' => Icons.summarize_outlined,
      _ => Icons.radio_button_unchecked,
    };

// ---------------------------------------------------------------------------
// Due-state colours: one vocabulary for the whole app (table, cards, mail).
//   overdue  red     · today  amber · soon  amber
//   ontrack  green   · completed  blue · cancelled  grey
// ---------------------------------------------------------------------------

(Color, Color) dueColors(String state) => switch (state) {
      'overdue' => (DsColors.redFg, DsColors.redBg),
      'today' || 'soon' => (DsColors.amberFg, DsColors.amberBg),
      'completed' => (DsColors.blueFg, DsColors.blueBg),
      'cancelled' => (DsColors.muted, DsColors.chip),
      _ => (DsColors.greenFg, DsColors.greenBg),
    };

String dueLabel(Map<String, dynamic> po) {
  final state = '${po['dueState']}';
  final overdue = intFrom(po['overdueDays']) ?? 0;
  final left = intFrom(po['daysLeft']);
  return switch (state) {
    'overdue' => '${plural(overdue, 'day')} late',
    'today' => 'Due today',
    'soon' => left == 1 ? 'Due tomorrow' : 'In ${plural(left ?? 0, 'day')}',
    'completed' => 'Completed',
    'cancelled' => 'Cancelled',
    _ => left == null ? 'On track' : 'In ${plural(left, 'day')}',
  };
}

class DueDot extends StatelessWidget {
  const DueDot({super.key, required this.state, this.size = 9});
  final String state;
  final double size;
  @override
  Widget build(BuildContext context) => DsDot(dueColors(state).$1, size: size);
}

class DueChip extends StatelessWidget {
  const DueChip({super.key, required this.po, this.dense = false});
  final Map<String, dynamic> po;
  final bool dense;
  @override
  Widget build(BuildContext context) {
    final (fg, bg) = dueColors('${po['dueState']}');
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 7 : 9, vertical: dense ? 2 : 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(dueLabel(po),
          maxLines: 1,
          style: TextStyle(color: fg, fontSize: dense ? 10.5 : 11.5, fontWeight: FontWeight.w700)),
    );
  }
}

/// Shipping modes for the pickers, "Not set" first.
const shipModeItems = [
  SearchableDropdownItem<String>(value: null, label: 'Not set'),
  SearchableDropdownItem<String>(value: 'SEA', label: 'Sea'),
  SearchableDropdownItem<String>(value: 'AIR', label: 'Air'),
  SearchableDropdownItem<String>(value: 'TRUCK', label: 'Truck'),
  SearchableDropdownItem<String>(value: 'COURIER', label: 'Courier'),
];

/// Steps in the purchase workflow (the backend's STEP_COUNT). The month-end
/// report is an email, not a step, so a PO is done once its goods arrive.
const kStepCount = 9;

/// The step the PO is waiting at, in large type, over a progress bar with
/// the count of steps done.
class StepProgress extends StatelessWidget {
  const StepProgress({super.key, required this.po, this.width = 150});
  final Map<String, dynamic> po;
  final double width;
  @override
  Widget build(BuildContext context) {
    final step = intFrom(po['currentStep']) ?? 1;
    final done = step > kStepCount;
    final status = '${po['status']}';
    final color = status == 'CANCELLED'
        ? DsColors.faint2
        : done
            ? DsColors.greenFg
            : dueColors('${po['dueState']}').$1 == DsColors.redFg
                ? DsColors.redFg
                : DsColors.navy;
    final name = done ? 'Done' : '${po['currentStepShort'] ?? '-'}';
    final fullName = '${po['currentStepName'] ?? ''}';
    final nameText = Text(name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: DsType.rowTitle.copyWith(
            fontSize: 13.5,
            fontWeight: FontWeight.w800,
            color: status == 'CANCELLED' ? DsColors.faint2 : color == DsColors.navy ? DsColors.navyDeep : color));
    return SizedBox(
      width: width,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        // The name is the step the PO is waiting at; the count is steps DONE,
        // the same thing the bar fills to.
        fullName.isEmpty || fullName == name ? nameText : Tooltip(message: fullName, child: nameText),
        const SizedBox(height: 5),
        Row(children: [
          Expanded(
            child: DsProgressBar(
                value: done ? 1 : ((step - 1) / kStepCount).clamp(0, 1).toDouble(), color: color, height: 5),
          ),
          const SizedBox(width: 6),
          Text(done ? '$kStepCount/$kStepCount' : '${step - 1}/$kStepCount',
              style: mono(size: 10, weight: FontWeight.w700, color: color)),
        ]),
      ]),
    );
  }
}

class ShipModeTag extends StatelessWidget {
  const ShipModeTag({super.key, required this.mode});
  final dynamic mode;
  @override
  Widget build(BuildContext context) {
    if ('${mode ?? ''}'.isEmpty || mode == null) return const Text('-', style: DsType.meta);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(shipModeIcon(mode), size: 14, color: DsColors.tealFg),
      const SizedBox(width: 4),
      Text(shipModeLabel(mode), style: const TextStyle(fontSize: 11.5, color: DsColors.text2, fontWeight: FontWeight.w600)),
    ]);
  }
}

/// Profile picture when the user has one, coloured initials otherwise.
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.user, this.size = 34, this.radius});
  final Map<String, dynamic>? user;
  final double size;
  final double? radius;

  static final Map<String, Uint8List> _cache = {};

  @override
  Widget build(BuildContext context) {
    final name = '${user?['displayName'] ?? user?['email'] ?? '?'}';
    final fullName = '${user?['fullName'] ?? ''}';
    final avatar = '${user?['avatar'] ?? ''}';
    final initials = DsAvatar(name: name, fullName: fullName, size: size, radius: radius);
    if (!avatar.startsWith('data:image/')) return initials;
    final bytes = _cache.putIfAbsent(avatar, () {
      try {
        return base64Decode(avatar.substring(avatar.indexOf(',') + 1));
      } catch (_) {
        return Uint8List(0);
      }
    });
    if (bytes.isEmpty) return initials;
    final shape = radius == null ? BorderRadius.circular(size) : BorderRadius.circular(radius!);
    return ClipRRect(
      borderRadius: shape,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(fit: StackFit.expand, children: [
          initials,
          Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Page frame
// ---------------------------------------------------------------------------

/// Standard page body: padded, scrollable, with an optional toolbar row.
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.children, this.padding = const EdgeInsets.fromLTRB(22, 18, 22, 28)});
  final List<Widget> children;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) {
    return ListView(padding: padding, children: children);
  }
}

class ErrorPanel extends StatelessWidget {
  const ErrorPanel({super.key, required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) {
    return DsCard(
      padding: const EdgeInsets.all(28),
      child: Column(children: [
        const Icon(Icons.cloud_off_outlined, color: DsColors.redFg, size: 34),
        const SizedBox(height: 10),
        Text(message, textAlign: TextAlign.center, style: const TextStyle(color: DsColors.text, fontSize: 13)),
        if (onRetry != null) ...[
          const SizedBox(height: 14),
          DsOutlineButton(label: 'Try again', icon: Icons.refresh, height: 38, onPressed: onRetry),
        ],
      ]),
    );
  }
}

/// Small coloured info strip (tips, warnings) used inside cards and dialogs.
class InfoStrip extends StatelessWidget {
  const InfoStrip({super.key, required this.text, this.icon = Icons.info_outline, this.color = DsColors.navy, this.bg});
  final String text;
  final IconData icon;
  final Color color;
  final Color? bg;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg ?? color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: .18)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 17, color: color),
        const SizedBox(width: 9),
        Expanded(child: Text(text, style: TextStyle(fontSize: 12.5, color: DsColors.text, height: 1.45))),
      ]),
    );
  }
}

/// A dialog frame in the app's style: title row with icon, scrollable body,
/// right-aligned actions.
class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.title,
    required this.body,
    this.icon,
    this.subtitle,
    this.actions = const [],
    this.width = 560,
    this.scrollable = true,
  });
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget body;
  final List<Widget> actions;
  final double width;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width, maxHeight: size.height - 48),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 12, 12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (icon != null) ...[
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: DsColors.navySoft, borderRadius: BorderRadius.circular(11)),
                  child: Icon(icon, color: DsColors.navyDeep, size: 19),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title,
                      style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700, color: DsColors.heading)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: DsType.meta),
                  ],
                ]),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close, size: 20, color: DsColors.faint2),
                tooltip: 'Close',
              ),
            ]),
          ),
          Flexible(
            child: scrollable
                ? SingleChildScrollView(padding: const EdgeInsets.fromLTRB(22, 4, 22, 8), child: body)
                : Padding(padding: const EdgeInsets.fromLTRB(22, 4, 22, 8), child: body),
          ),
          if (actions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 10, 22, 18),
              child: Wrap(alignment: WrapAlignment.end, spacing: 10, runSpacing: 8, children: actions),
            ),
        ]),
      ),
    );
  }
}

Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  bool danger = false,
  IconData icon = Icons.help_outline,
}) async {
  final ok = await showGlassDialog<bool>(
    context: context,
    builder: (ctx) => AppDialog(
      title: title,
      icon: icon,
      width: 440,
      body: Text(message, style: const TextStyle(fontSize: 13.5, color: DsColors.text, height: 1.5)),
      actions: [
        DsOutlineButton(label: 'Cancel', height: 40, onPressed: () => Navigator.pop(ctx, false)),
        danger
            ? FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: DsColors.redFg),
                onPressed: () => Navigator.pop(ctx, true),
                icon: const Icon(Icons.warning_amber_rounded, size: 18),
                label: Text(confirmLabel))
            : DsPrimaryButton(label: confirmLabel, height: 40, onPressed: () => Navigator.pop(ctx, true)),
      ],
    ),
  );
  return ok == true;
}

/// Asks for one line (or paragraph) of text. Null = cancelled.
Future<String?> askText(
  BuildContext context, {
  required String title,
  required String label,
  String initial = '',
  String confirmLabel = 'Save',
  int minLength = 0,
  int maxLines = 1,
  bool obscure = false,
  String? hint,
  String? helper,
}) {
  final controller = TextEditingController(text: initial);
  String? error;
  return showGlassDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        void submit() {
          final value = controller.text.trim();
          if (value.length < minLength) {
            setState(() => error = minLength <= 1 ? 'Required' : 'At least $minLength characters');
            return;
          }
          Navigator.pop(ctx, value);
        }

        return AppDialog(
          title: title,
          width: 460,
          body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (helper != null) ...[
              Text(helper, style: DsType.meta),
              const SizedBox(height: 10),
            ],
            DsLabeledField(
              label: label,
              child: TextField(
                controller: controller,
                autofocus: true,
                obscureText: obscure,
                maxLines: obscure ? 1 : maxLines,
                decoration: dsInput(hint: hint, errorText: error),
                onSubmitted: maxLines == 1 ? (_) => submit() : null,
              ),
            ),
          ]),
          actions: [
            DsOutlineButton(label: 'Cancel', height: 40, onPressed: () => Navigator.pop(ctx)),
            DsPrimaryButton(label: confirmLabel, height: 40, onPressed: submit),
          ],
        );
      },
    ),
  );
}

/// Runs an API call and shows the error as a toast instead of throwing.
/// Returns null when it failed.
Future<T?> guard<T>(BuildContext context, Future<T> Function() action, {String? success}) async {
  try {
    final result = await action();
    if (success != null && context.mounted) AppToast.success(context, success);
    return result;
  } on ApiException catch (e) {
    if (context.mounted && e.statusCode != 401) AppToast.error(context, friendlyError(e.message));
  } catch (e) {
    if (context.mounted) AppToast.error(context, 'Could not reach the server. Check your connection and try again.');
  }
  return null;
}

String friendlyError(String message) => switch (message) {
      'CSRF_REQUIRED' => 'Your session needs to be refreshed — please reload the page.',
      'PDPA_CONSENT_REQUIRED' => 'Please accept the privacy notice first.',
      'SESSION_REVOKED' => 'You were signed out (password changed or signed out elsewhere).',
      'ACCOUNT_DISABLED' => 'This account has been deactivated.',
      _ => message,
    };

// ---------------------------------------------------------------------------
// Files: pick an .xlsx, download bytes
// ---------------------------------------------------------------------------

class PickedFile {
  PickedFile(this.name, this.base64, this.size);
  final String name;
  final String base64;
  final int size;
}

/// Opens the browser's file picker for one Excel file. Null when cancelled.
Future<PickedFile?> pickExcelFile() {
  final completer = Completer<PickedFile?>();
  final input = html.FileUploadInputElement()
    ..accept = '.xlsx,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
  input.onChange.listen((_) {
    final file = input.files?.isNotEmpty == true ? input.files!.first : null;
    if (file == null) {
      if (!completer.isCompleted) completer.complete(null);
      return;
    }
    final reader = html.FileReader();
    reader.onLoadEnd.listen((_) {
      final result = '${reader.result ?? ''}';
      final comma = result.indexOf(',');
      if (!completer.isCompleted) {
        completer.complete(comma < 0 ? null : PickedFile(file.name, result.substring(comma + 1), file.size));
      }
    });
    reader.onError.listen((_) {
      if (!completer.isCompleted) completer.complete(null);
    });
    reader.readAsDataUrl(file);
  });
  input.click();
  return completer.future;
}

/// Image picker for the profile picture (returns a data URL).
Future<String?> pickImageDataUrl() {
  final completer = Completer<String?>();
  final input = html.FileUploadInputElement()..accept = 'image/png,image/jpeg,image/webp';
  input.onChange.listen((_) {
    final file = input.files?.isNotEmpty == true ? input.files!.first : null;
    if (file == null) {
      if (!completer.isCompleted) completer.complete(null);
      return;
    }
    final reader = html.FileReader();
    reader.onLoadEnd.listen((_) {
      if (!completer.isCompleted) completer.complete('${reader.result ?? ''}');
    });
    reader.readAsDataUrl(file);
  });
  input.click();
  return completer.future;
}

void saveBytes(Uint8List bytes, String fileName,
    {String mime = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'}) {
  final blob = html.Blob([bytes], mime);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..download = fileName
    ..style.display = 'none';
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  Timer(const Duration(seconds: 5), () => html.Url.revokeObjectUrl(url));
}

/// Downloads an authenticated file from the API.
Future<void> downloadFromApi(BuildContext context, String path, String fileName) async {
  final api = AppScope.read(context).api;
  final bytes = await guard(context, () => api.getBytes(path));
  if (bytes != null) {
    saveBytes(bytes, fileName);
    if (context.mounted) AppToast.success(context, 'Downloaded $fileName');
  }
}

String qs(Map<String, dynamic> params) {
  final parts = <String>[];
  params.forEach((k, v) {
    if (v == null || '$v'.isEmpty) return;
    parts.add('${Uri.encodeQueryComponent(k)}=${Uri.encodeQueryComponent('$v')}');
  });
  return parts.isEmpty ? '' : '?${parts.join('&')}';
}

/// Stat-number style for KPI values.
TextStyle statStyle(double size, {Color color = DsColors.heading}) => DsType.stat(size, color: color);

/// Section header row inside a page: title + optional trailing widgets.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.subtitle, this.trailing = const []});
  final String title;
  final String? subtitle;
  final List<Widget> trailing;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: DsColors.heading)),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(subtitle!, style: DsType.meta),
            ],
          ]),
        ),
        ...trailing,
      ]),
    );
  }
}

/// Gives a wide table a minimum width and lets it scroll sideways on small
/// screens, instead of squeezing its flexible columns down to nothing.
class MinWidthScroll extends StatelessWidget {
  const MinWidthScroll({super.key, required this.minWidth, required this.child});
  final double minWidth;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      if (box.maxWidth >= minWidth) return child;
      return Scrollbar(
        thumbVisibility: true,
        notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(width: minWidth, height: box.maxHeight.isFinite ? box.maxHeight : null, child: child),
        ),
      );
    });
  }
}

/// A browser tab opened straight away — inside the click, so no popup blocker
/// stops it — and filled in once the content has arrived from the server.
class PendingTab {
  PendingTab._(this._window);
  final JSObject? _window;

  static PendingTab open() {
    JSObject? w;
    try {
      w = globalContext.callMethod<JSObject?>('open'.toJS, ''.toJS, '_blank'.toJS);
    } catch (_) {}
    return PendingTab._(w);
  }

  /// False when the browser refused to open it (popups blocked).
  bool get isOpen => _window != null;

  void close() {
    try {
      _window?.callMethod<JSAny?>('close'.toJS);
    } catch (_) {}
  }

  /// Writes [document] into the tab. With [print] the browser's print dialog
  /// opens on it, where "Save as PDF" makes the PDF.
  void show(String document, {String? title, bool print = false}) {
    final w = _window;
    if (w == null) return;
    var page = document;
    if (print) {
      // Keep the email's colours on paper, and give it an A4 margin.
      const css = '<style>@page{size:A4;margin:12mm}'
          'html,body{-webkit-print-color-adjust:exact;print-color-adjust:exact}</style>';
      page = page.contains('</head>') ? page.replaceFirst('</head>', '$css</head>') : '$css$page';
    }
    if (title != null) {
      final safe = const HtmlEscape().convert(title);
      page = page.contains('<title>')
          ? page.replaceFirst(RegExp(r'<title>[^<]*</title>'), '<title>$safe</title>')
          : '<title>$safe</title>$page';
    }
    try {
      final doc = w.getProperty<JSObject>('document'.toJS);
      doc.callMethod<JSAny?>('open'.toJS);
      doc.callMethod<JSAny?>('write'.toJS, page.toJS);
      doc.callMethod<JSAny?>('close'.toJS);
      if (print) {
        // A beat for the layout to settle before the print preview is taken.
        Timer(const Duration(milliseconds: 400), () {
          try {
            w.callMethod<JSAny?>('focus'.toJS);
            w.callMethod<JSAny?>('print'.toJS);
          } catch (_) {}
        });
      }
    } catch (_) {}
  }
}
