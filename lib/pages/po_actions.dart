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
            if (ctx.mounted) {
              AppToast.success(
                  ctx,
                  result['completed'] == true
                      ? 'PO ${pos.first['poNo']} is complete 🎉'
                      : 'PO ${pos.first['poNo']}: ${step['shortName']} done');
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
                        hint: stepNo == 4 ? 'e.g. EX-26-W87' : null,
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
            label: busy ? 'Saving…' : 'Mark done',
            icon: Icons.check,
            height: 40,
            onPressed: busy ? null : submit,
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
  final ok = await confirmAction(
    context,
    title: 'Undo the last step?',
    message:
        'Step $last${step == null ? '' : ' · ${step['name']}'} of PO ${po['poNo']} goes back to "not done", '
        'and the due dates after it are worked out again.',
    confirmLabel: 'Undo step',
    icon: Icons.undo,
  );
  if (!ok || !context.mounted) return false;
  final api = AppScope.read(context).api;
  final result = await guard(
      context, () => api.postJson('/pos/${po['id']}/undo', {}),
      success: 'Step $last reopened');
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
/// lead time (which re-plan the PO) for section admins only.
Future<bool> editPoDialog(BuildContext context, Map<String, dynamic> po) async {
  final scope = AppScope.read(context);
  final remark = TextEditingController(text: '${po['remark'] ?? ''}');
  final ref = TextEditingController(text: '${po['shipmentRef'] ?? ''}');
  final lead = TextEditingController(text: '${po['leadTimeDays'] ?? ''}');
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
        };
        if (admin) {
          final days = int.tryParse(lead.text.trim());
          if (days == null || days < 1 || days > 365) {
            return setState(() => error = 'Lead time must be 1–365 days');
          }
          if (isoDate(docDate) != po['documentDate']) {
            body['documentDate'] = isoDate(docDate);
          }
          if (days != intFrom(po['leadTimeDays'])) body['leadTimeDays'] = days;
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
                label: 'Shipment / S/I ref.',
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
              Expanded(
                child: DsLabeledField(
                  label: 'Lead time (days)',
                  child: TextField(
                    controller: lead,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: dsInput(icon: Icons.timelapse),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            const InfoStrip(
              icon: Icons.warning_amber_rounded,
              color: DsColors.amberFg,
              text:
                  'Changing the PO date or lead time re-plans every open step and the ETA.',
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
