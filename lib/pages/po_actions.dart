part of '../main.dart';

/// The section's workflow steps, cached per section and refreshed when the
/// workflow changes (realtime tick).
class WorkflowCache {
  static String? _section;
  static int _tick = -1;
  static List<Map<String, dynamic>> _steps = const [];

  static Future<List<Map<String, dynamic>>> steps(BuildContext context) async {
    final scope = AppScope.read(context);
    if (_section == scope.sectionCode &&
        _tick == scope.refreshTick &&
        _steps.isNotEmpty) {
      return _steps;
    }
    final result = await scope.api.getJson('/workflow');
    _steps = (result['steps'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    _section = scope.sectionCode;
    _tick = scope.refreshTick;
    return _steps;
  }

  static Map<String, dynamic>? stepOf(int stepNo) {
    for (final s in _steps) {
      if (intFrom(s['stepNo']) == stepNo) return s;
    }
    return null;
  }
}

/// "Mark step done" for one PO or several at the same step. Returns true when
/// at least one PO moved.
Future<bool> showAdvanceDialog(
    BuildContext context, List<Map<String, dynamic>> pos) async {
  if (pos.isEmpty) return false;
  final stepNo = intFrom(pos.first['currentStep']) ?? 0;
  if (pos.any((p) => intFrom(p['currentStep']) != stepNo)) {
    AppToast.error(context, 'Select POs that are waiting at the same step');
    return false;
  }
  final steps = await guard(context, () => WorkflowCache.steps(context));
  if (steps == null || !context.mounted) return false;
  final step = WorkflowCache.stepOf(stepNo);
  if (step == null) return false;
  final next = WorkflowCache.stepOf(stepNo + 1);
  final api = AppScope.read(context).api;

  DateTime actual = DateTime.now();
  // Earliest allowed: the latest "previous step" date among the POs, which the
  // server enforces too. Unknown in the list view, so fall back to PO date.
  final minDate = pos
      .map((p) => parseIsoDate(p['prevActualDate'] ?? p['documentDate']))
      .whereType<DateTime>()
      .fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
  final ref = TextEditingController(text: pos.length == 1 ? '' : '');
  final remark = TextEditingController();
  bool busy = false;
  final bulk = pos.length > 1;

  // Past the S/I step a shipment (same Acknowledgment No.) moves as one: the
  // server closes the step on its other POs too, or refuses while one of them
  // is not past the S/I step yet.
  Map<String, dynamic>? shipment;
  if (!bulk) {
    try {
      final r = await api.getJson('/pos/${pos.first['id']}/shipment');
      shipment = Map<String, dynamic>.from(r['data'] as Map);
    } on ApiException {
      shipment = null;
    }
    if (!context.mounted) return false;
  }
  final together = shipment?['together'] == true;
  final moveWith = ((shipment?['moveWith'] as List?) ?? const [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
  final blocked = together && shipment?['message'] != null;
  String poLabel(Map p) =>
      '${p['poNo']}${(intFrom(p['splitNo']) ?? 0) > 0 ? ' #${p['splitNo']}' : ''}';

  final ok = await showGlassDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
      Future<void> submit() async {
        setState(() => busy = true);
        try {
          final body = {
            'expectedStep': stepNo,
            'actualDate': isoDate(actual),
            if (ref.text.trim().isNotEmpty) 'referenceNo': ref.text.trim(),
            if (remark.text.trim().isNotEmpty) 'remark': remark.text.trim(),
          };
          if (bulk) {
            final result = await api.postJson('/pos/bulk-advance', {
              ...body,
              'ids': pos.map((p) => intFrom(p['id'])).toList(),
            });
            final done = intFrom(result['done']) ?? 0;
            final failed = (result['results'] as List)
                .where((r) => r['ok'] != true)
                .toList();
            if (ctx.mounted) {
              if (failed.isEmpty) {
                AppToast.success(
                    ctx, '${step['shortName']} done on ${plural(done, 'PO')}');
              } else {
                AppToast.error(ctx,
                    '$done done, ${failed.length} skipped: ${failed.first['message']}');
              }
              Navigator.pop(ctx, done > 0);
            }
          } else {
            final result =
                await api.postJson('/pos/${pos.first['id']}/advance', body);
            final also = ((result['withShipment'] as List?) ?? const []).length;
            if (ctx.mounted) {
              AppToast.success(
                  ctx,
                  (result['completed'] == true
                          ? 'PO ${pos.first['poNo']} is complete 🎉'
                          : 'PO ${pos.first['poNo']}: ${step['shortName']} done') +
                      (also > 0
                          ? ' — with ${plural(also, 'other PO')} of shipment ${result['shipment']}'
                          : ''));
              Navigator.pop(ctx, true);
            }
          }
        } on ApiException catch (e) {
          setState(() => busy = false);
          if (ctx.mounted) AppToast.error(ctx, friendlyError(e.message));
        }
      }

      final late = pos.first['nextDueDate'] != null
          ? actual.difference(parseIsoDate(pos.first['nextDueDate'])!).inDays
          : 0;
      final fileStep = step['code'] == 'ACK' || step['code'] == 'SI';
      return AppDialog(
        title: bulk ? 'Mark step done on ${pos.length} POs' : 'Mark step done',
        subtitle: bulk
            ? pos.map((p) => p['poNo']).join(', ')
            : 'PO ${pos.first['poNo']} · ${pos.first['supplierShort'] ?? pos.first['supplierName'] ?? ''}',
        icon: stepIcon(step['icon']),
        width: 520,
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: DsColors.subtle,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: DsColors.cardBorder),
            ),
            child: Row(children: [
              _StepBadge(no: stepNo, color: DsColors.navy),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${step['name']}', style: DsType.cardTitle),
                      if ('${step['description'] ?? ''}'.isNotEmpty)
                        Text('${step['description']}', style: DsType.metaSm),
                    ]),
              ),
              if (!bulk && pos.first['nextDueDate'] != null)
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  const Text('Due', style: DsType.metaSm),
                  Text(fmtDate(pos.first['nextDueDate']),
                      style: DsType.rowTitle),
                ]),
            ]),
          ),
          if (fileStep) ...[
            const SizedBox(height: 12),
            InfoStrip(
              icon: Icons.upload_file_outlined,
              color: DsColors.amberFg,
              text:
                  'This step is normally closed by uploading the ${step['code'] == 'ACK' ? 'OCR ACK' : 'OCR SI'} file on the Import page '
                  '(it also checks quantities${step['code'] == 'SI' ? ' and stores ETD / ETA' : ' and groups the shipment'}). '
                  'Mark it here only when the file has a problem.',
            ),
          ],
          if (blocked) ...[
            const SizedBox(height: 12),
            InfoStrip(
              icon: Icons.block,
              color: DsColors.redFg,
              text: '${shipment!['message']}.',
            ),
          ] else if (moveWith.isNotEmpty) ...[
            const SizedBox(height: 12),
            InfoStrip(
              icon: Icons.local_shipping_outlined,
              color: DsColors.purpleFg,
              text:
                  'Shipment ${shipment!['ackNo']}: this step is also marked done on '
                  '${moveWith.length == 1 ? 'PO' : 'POs'} ${moveWith.map(poLabel).join(', ')} '
                  '(same Acknowledgment No.), with the same date${'${step['referenceLabel'] ?? ''}'.isNotEmpty ? ', reference' : ''} and remark.',
            ),
          ],
          const SizedBox(height: 16),
          DsLabeledField(
            label: 'Date it happened',
            child: InkWell(
              borderRadius: BorderRadius.circular(9),
              onTap: () async {
                final picked = await showDatePicker(
                  context: ctx,
                  initialDate: actual,
                  firstDate: minDate ?? DateTime(2020),
                  lastDate: DateTime.now(),
                  helpText: 'When was "${step['shortName']}" done?',
                );
                if (picked != null) setState(() => actual = picked);
              },
              child: InputDecorator(
                decoration: dsInput(icon: Icons.event_outlined),
                child: Row(children: [
                  Text(fmtDate(isoDate(actual)),
                      style: const TextStyle(
                          fontSize: 13.5, color: DsColors.heading)),
                  const SizedBox(width: 8),
                  if (isoDate(actual) == todayIso()) const DsTag('Today'),
                  const Spacer(),
                  if (!bulk && late > 0)
                    DsTag('$late day${late == 1 ? '' : 's'} late',
                        color: DsColors.redFg, bg: DsColors.redBg)
                  else if (!bulk && pos.first['nextDueDate'] != null)
                    const DsTag('On time',
                        color: DsColors.greenFg, bg: DsColors.greenBg),
                ]),
              ),
            ),
          ),
          if ('${step['referenceLabel'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: 12),
            DsLabeledField(
              label: '${step['referenceLabel']} (optional)',
              child: TextField(
                controller: ref,
                maxLength: 80,
                decoration: dsInput(
                        hint: step['code'] == 'SI'
                            ? 'e.g. EX-26-W87'
                            : step['code'] == 'ACK'
                                ? 'e.g. 141-02-W051'
                                : null,
                        icon: Icons.tag)
                    .copyWith(counterText: ''),
              ),
            ),
          ],
          const SizedBox(height: 12),
          DsLabeledField(
            label: 'Remark (optional)',
            child: TextField(
              controller: remark,
              maxLength: 500,
              maxLines: 2,
              decoration: dsInput(hint: 'e.g. ETD 17 Apr, ETA 28 Apr')
                  .copyWith(counterText: ''),
            ),
          ),
          const SizedBox(height: 12),
          InfoStrip(
            icon: Icons.east,
            text: next == null
                ? 'This is the last step — the PO will be marked complete.'
                : 'Next: step ${next['stepNo']} · ${next['name']}. Its due date is worked out from the date above.',
          ),
        ]),
        actions: [
          DsOutlineButton(
              label: 'Cancel',
              height: 40,
              onPressed: busy ? null : () => Navigator.pop(ctx, false)),
          DsPrimaryButton(
            label: busy
                ? 'Saving…'
                : moveWith.isNotEmpty && !blocked
                    ? 'Mark done on ${moveWith.length + 1} POs'
                    : 'Mark done',
            icon: Icons.check,
            height: 40,
            onPressed: busy || blocked ? null : submit,
          ),
        ],
      );
    }),
  );
  return ok == true;
}

Future<bool> undoLastStep(BuildContext context, Map<String, dynamic> po) async {
  final last = (intFrom(po['currentStep']) ?? 2) - 1;
  final step = WorkflowCache.stepOf(last);
  final api = AppScope.read(context).api;
  // Past the S/I step the server reopens the step on the whole shipment
  // (same Acknowledgment No.); name those POs before asking.
  var undoWith = const <Map<String, dynamic>>[];
  String? ackNo;
  try {
    final r = await api.getJson('/pos/${po['id']}/shipment');
    final data = Map<String, dynamic>.from(r['data'] as Map);
    ackNo = data['ackNo'] as String?;
    undoWith = ((data['undoWith'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  } on ApiException {
    undoWith = const [];
  }
  if (!context.mounted) return false;
  String label(Map p) =>
      '${p['poNo']}${(intFrom(p['splitNo']) ?? 0) > 0 ? ' #${p['splitNo']}' : ''}';
  final others = undoWith.map(label).join(', ');
  final ok = await confirmAction(
    context,
    title: undoWith.isEmpty
        ? 'Undo the last step?'
        : 'Undo the last step on ${undoWith.length + 1} POs?',
    message:
        'Step $last${step == null ? '' : ' · ${step['name']}'} of PO ${po['poNo']}'
        '${undoWith.isEmpty ? '' : ' and of ${undoWith.length == 1 ? 'PO' : 'POs'} $others (same shipment $ackNo)'}'
        ' goes back to "not done", and the due dates after it are worked out again.',
    confirmLabel: undoWith.isEmpty ? 'Undo step' : 'Undo on ${undoWith.length + 1} POs',
    icon: Icons.undo,
  );
  if (!ok || !context.mounted) return false;
  final result = await guard(
      context, () => api.postJson('/pos/${po['id']}/undo', {}),
      success: undoWith.isEmpty
          ? 'Step $last reopened'
          : 'Step $last reopened on ${undoWith.length + 1} POs of shipment $ackNo');
  return result != null;
}

Future<bool> cancelPoDialog(
    BuildContext context, Map<String, dynamic> po) async {
  final reason = await askText(
    context,
    title: 'Cancel PO ${po['poNo']}?',
    label: 'Reason',
    hint: 'e.g. order cancelled by supplier',
    helper:
        'A cancelled PO stops appearing in alerts and emails. A section admin can reopen it.',
    confirmLabel: 'Cancel PO',
    minLength: 3,
    maxLines: 3,
  );
  if (reason == null || !context.mounted) return false;
  final api = AppScope.read(context).api;
  return await guard(context,
          () => api.postJson('/pos/${po['id']}/cancel', {'reason': reason}),
          success: 'PO ${po['poNo']} cancelled') !=
      null;
}

Future<bool> reopenPo(BuildContext context, Map<String, dynamic> po) async {
  final api = AppScope.read(context).api;
  return await guard(context, () => api.postJson('/pos/${po['id']}/reopen', {}),
          success: 'PO ${po['poNo']} reopened') !=
      null;
}

Future<bool> deletePo(BuildContext context, Map<String, dynamic> po) async {
  final ok = await confirmAction(
    context,
    title: 'Delete PO ${po['poNo']} permanently?',
    message:
        'The PO, its lines and its whole history are removed. This cannot be undone. '
        'Use Cancel instead if you only want it out of the way.',
    confirmLabel: 'Delete',
    danger: true,
    icon: Icons.delete_outline,
  );
  if (!ok || !context.mounted) return false;
  final api = AppScope.read(context).api;
  return await guard(context, () => api.deleteJson('/pos/${po['id']}'),
          success: 'PO ${po['poNo']} deleted') !=
      null;
}

/// Edit the PO header. Remark, mode and shipment ref for editors; PO date and
/// (which re-plans the PO) for section admins only.
Future<bool> editPoDialog(BuildContext context, Map<String, dynamic> po) async {
  final scope = AppScope.read(context);
  final remark = TextEditingController(text: '${po['remark'] ?? ''}');
  final ref = TextEditingController(text: '${po['shipmentRef'] ?? ''}');
  final ack = TextEditingController(text: '${po['ackNo'] ?? ''}');
  DateTime? delivery = parseIsoDate(po['deliveryDate']);
  String? mode = po['shipMode'] as String?;
  DateTime docDate = parseIsoDate(po['documentDate']) ?? DateTime.now();
  bool busy = false;
  String? error;
  final admin = scope.isSectionAdmin;
  final ok = await showGlassDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
      Future<void> save() async {
        final body = <String, dynamic>{
          'remark': remark.text.trim(),
          'shipMode': mode ?? '',
          'shipmentRef': ref.text.trim(),
          'ackNo': ack.text.trim(),
          if (delivery != null && isoDate(delivery!) != po['deliveryDate'])
            'deliveryDate': isoDate(delivery!),
        };
        if (admin) {
          if (isoDate(docDate) != po['documentDate']) {
            body['documentDate'] = isoDate(docDate);
          }
        }
        setState(() => busy = true);
        try {
          await scope.api.patchJson('/pos/${po['id']}', body);
          if (ctx.mounted) {
            AppToast.success(ctx, 'PO ${po['poNo']} updated');
            Navigator.pop(ctx, true);
          }
        } on ApiException catch (e) {
          setState(() {
            busy = false;
            error = friendlyError(e.message);
          });
        }
      }

      return AppDialog(
        title: 'Edit PO ${po['poNo']}',
        icon: Icons.edit_outlined,
        width: 520,
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: DsLabeledField(
                label: 'Shipping mode',
                child: SearchableDropdownField<String>(
                  value: mode,
                  dialogTitle: 'Shipping mode',
                  decoration: dsInput(),
                  items: shipModeItems,
                  onChanged: (v) => setState(() => mode = v),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DsLabeledField(
                label: 'Delivery date (step 7)',
                child: InkWell(
                  onTap: () async {
                    final first = parseIsoDate(po['documentDate']) ?? DateTime(2020);
                    var initial = delivery ?? DateTime.now();
                    if (initial.isBefore(first)) initial = first;
                    final picked = await showDatePicker(
                        context: ctx,
                        initialDate: initial,
                        firstDate: first,
                        lastDate: DateTime.now().add(const Duration(days: 365 * 3)));
                    if (picked != null) setState(() => delivery = picked);
                  },
                  child: InputDecorator(
                      decoration: dsInput(icon: Icons.event_outlined),
                      child: Text(delivery == null ? 'Not set' : fmtDate(isoDate(delivery!)))),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: DsLabeledField(
                label: 'Shipment (Acknowledgment No.)',
                child: TextField(
                    controller: ack, decoration: dsInput(hint: '141-02-W051')),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DsLabeledField(
                label: 'S/I No.',
                child: TextField(
                    controller: ref, decoration: dsInput(hint: 'EX-26-W87')),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          DsLabeledField(
            label: 'Remark',
            child: TextField(
                controller: remark,
                maxLines: 3,
                maxLength: 1000,
                decoration: dsInput().copyWith(counterText: '')),
          ),
          const SizedBox(height: 14),
          if (admin) ...[
            const DsSectionLabel('Plan (section admin)'),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: DsLabeledField(
                  label: 'PO date (N1)',
                  child: InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                          context: ctx,
                          initialDate: docDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now());
                      if (picked != null) setState(() => docDate = picked);
                    },
                    child: InputDecorator(
                        decoration: dsInput(icon: Icons.event_outlined),
                        child: Text(fmtDate(isoDate(docDate)))),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const Spacer(),
            ]),
            const SizedBox(height: 8),
            const InfoStrip(
              icon: Icons.warning_amber_rounded,
              color: DsColors.amberFg,
              text:
                  'Changing the PO date re-plans every open step (step 7 stays on the Delivery date).',
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 10),
            InfoStrip(
                text: error!, icon: Icons.error_outline, color: DsColors.redFg),
          ],
        ]),
        actions: [
          DsOutlineButton(
              label: 'Cancel',
              height: 40,
              onPressed: busy ? null : () => Navigator.pop(ctx, false)),
          DsPrimaryButton(
              label: busy ? 'Saving…' : 'Save',
              icon: Icons.save_outlined,
              height: 40,
              onPressed: busy ? null : save),
        ],
      );
    }),
  );
  return ok == true;
}

/// Step 7 "Factory good received" is due on the PO's Delivery date, which
/// any editor can move at any time (also once the goods are in).
Future<bool> editDeliveryDate(BuildContext context, Map<String, dynamic> po) async {
  final first = parseIsoDate(po['documentDate']) ?? DateTime(2020);
  var initial = parseIsoDate(po['deliveryDate'] ?? po['etaDate']) ?? DateTime.now();
  if (initial.isBefore(first)) initial = first;
  final picked = await showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: first,
    lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    helpText: 'Delivery date of PO ${po['poNo']}',
  );
  if (picked == null || !context.mounted) return false;
  if (isoDate(picked) == po['deliveryDate']) return false;
  final api = AppScope.read(context).api;
  return await guard(
          context,
          () => api.patchJson('/pos/${po['id']}', {'deliveryDate': isoDate(picked)}),
          success: 'Delivery date set to ${fmtDate(isoDate(picked))}') !=
      null;
}

/// Round numbered badge for a step.
class _StepBadge extends StatelessWidget {
  const _StepBadge(
      {required this.no,
      required this.color,
      this.size = 30,
      this.filled = true});
  final int no;
  final Color color;
  final double size;
  final bool filled;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: .1),
        shape: BoxShape.circle,
        border: filled
            ? null
            : Border.all(color: color.withValues(alpha: .4), width: 1.4),
      ),
      child: Text('$no',
          style: TextStyle(
              color: filled ? Colors.white : color,
              fontWeight: FontWeight.w700,
              fontSize: size * .42)),
    );
  }
}
