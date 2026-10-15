part of '../main.dart';

/// Opens a PO. [scope] is passed when the caller sits above the AppScope
/// (the shell itself); pages can leave it out.
Future<void> showPoDetail(BuildContext context, int id,
    {AppScope? scope}) async {
  final s = scope ?? context.getInheritedWidgetOfExactType<AppScope>();
  await showGlassDialog<void>(
      context: context, builder: (_) => _PoDetailHost(id: id, scope: s));
}

/// Re-provides the AppScope inside the dialog route (dialogs live above the
/// page tree, outside the InheritedWidget).
class _PoDetailHost extends StatelessWidget {
  const _PoDetailHost({required this.id, required this.scope});
  final int id;
  final AppScope? scope;
  @override
  Widget build(BuildContext context) {
    final scope = this.scope;
    if (scope == null) return PoDetailDialog(id: id);
    return AppScope(
      api: scope.api,
      me: scope.me,
      section: scope.section,
      refreshTick: scope.refreshTick,
      navigate: scope.navigate,
      openPo: scope.openPo,
      onMeChanged: scope.onMeChanged,
      child: PoDetailDialog(id: id),
    );
  }
}

class PoDetailDialog extends StatefulWidget {
  const PoDetailDialog({super.key, required this.id});
  final int id;
  @override
  State<PoDetailDialog> createState() => _PoDetailDialogState();
}

class _PoDetailDialogState extends State<PoDetailDialog> {
  Map<String, dynamic>? po;
  String? error;
  int tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(load()));
  }

  Future<void> load() async {
    final scope = AppScope.maybeOf(context);
    if (scope == null) return;
    try {
      await WorkflowCache.steps(context);
      final result = await scope.api.getJson('/pos/${widget.id}');
      if (!mounted) return;
      setState(() {
        po = Map<String, dynamic>.from(result['data'] as Map);
        error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => error = friendlyError(e.message));
    }
  }

  Future<void> _after(Future<bool> action) async {
    if (await action) await load();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxWidth: 1080,
            maxHeight: size.height - 48,
            minHeight: min(560, size.height - 48)),
        child: po == null
            ? SizedBox(
                height: 420,
                child: error == null
                    ? const Center(child: CircularProgressIndicator())
                    : Center(
                        child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: ErrorPanel(message: error!, onRetry: load))),
              )
            : _content(po!),
      ),
    );
  }

  Widget _content(Map<String, dynamic> po) {
    final scope = AppScope.of(context);
    final status = '${po['status']}';
    final active = status == 'ACTIVE';
    final cancelled = status == 'CANCELLED';
    final items = (po['items'] as List).cast<Map>();
    final history = (po['history'] as List).cast<Map>();
    final step = intFrom(po['currentStep']) ?? 2;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // ---- header
      Container(
        padding: const EdgeInsets.fromLTRB(24, 20, 14, 16),
        decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: DsColors.line))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
                color: DsColors.navySoft,
                borderRadius: BorderRadius.circular(14)),
            child: Icon(po['shipMode'] == null ? Icons.inventory_2_outlined : shipModeIcon(po['shipMode']), color: DsColors.navyDeep),
          ),
          const SizedBox(width: 14),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SelectableText('PO ${po['poNo']}',
                        style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                            color: DsColors.heading)),
                    DueChip(po: po),
                    if (po['source'] == 'EXCEL') const DsTag('From Excel'),
                    if ('${po['shipmentRef'] ?? ''}'.isNotEmpty)
                      DsTag('S/I ${po['shipmentRef']}',
                          color: DsColors.tealFg, bg: DsColors.tealBg),
                  ]),
              const SizedBox(height: 4),
              Text(
                  '${po['supplierName'] ?? '-'}  ·  ${po['supplierCode'] ?? ''}',
                  style: DsType.meta),
              if (cancelled) ...[
                const SizedBox(height: 6),
                InfoStrip(
                  icon: Icons.block,
                  color: DsColors.redFg,
                  text:
                      'Cancelled ${fmtDateTime(po['cancelledAt'])} — ${po['cancelReason'] ?? ''}',
                ),
              ],
            ]),
          ),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            const Text('EXPECTED AT FACTORY', style: DsType.eyebrow),
            const SizedBox(height: 2),
            Text(fmtDate(po['etaDate']),
                style: DsType.stat(20, color: DsColors.navyDeep)),
            Text(
                'Lead time ${po['leadTimeDays'] ?? '-'} days (${_leadSource(po['leadTimeSource'])})',
                style: DsType.metaSm),
          ]),
          const SizedBox(width: 6),
          IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
              tooltip: 'Close'),
        ]),
      ),
      // ---- tabs + actions
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
        child: Row(children: [
          DsSegmented(
            selected: tab,
            length: 3,
            itemBuilder: (context, i, t) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Text(
                  [
                    'Progress',
                    'Items (${items.length})',
                    'History (${history.length})'
                  ][i],
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Color.lerp(DsColors.muted, DsColors.navyDeep, t))),
            ),
            onSelect: (i) => setState(() => tab = i),
          ),
          const Spacer(),
          if (scope.canEdit && !cancelled) ...[
            DsOutlineButton(
                label: 'Edit',
                icon: Icons.edit_outlined,
                height: 36,
                onPressed: () => _after(editPoDialog(context, po))),
            const SizedBox(width: 8),
          ],
          if (scope.canEdit && !cancelled && step > 2) ...[
            DsOutlineButton(
                label: 'Undo last step',
                icon: Icons.undo,
                height: 36,
                onPressed: () => _after(undoLastStep(context, po))),
            const SizedBox(width: 8),
          ],
          if (scope.canEdit && active)
            DsOutlineButton(
              label: 'Cancel PO',
              icon: Icons.block,
              height: 36,
              foreground: DsColors.redFg,
              borderColor: DsColors.redBg,
              onPressed: () => _after(cancelPoDialog(context, po)),
            ),
          if (scope.isSectionAdmin && cancelled)
            DsPrimaryButton(
                label: 'Reopen',
                icon: Icons.restore,
                height: 36,
                onPressed: () => _after(reopenPo(context, po))),
          if (scope.isSectionAdmin) ...[
            const SizedBox(width: 4),
            DsIconButton(
              icon: Icons.delete_outline,
              tooltip: 'Delete permanently',
              color: DsColors.redFg,
              onTap: () async {
                if (await deletePo(context, po) && mounted) {
                  Navigator.pop(context);
                }
              },
            ),
          ],
        ]),
      ),
      Flexible(
        child: switch (tab) {
          0 => _progress(po, scope),
          1 => _items(items),
          _ => _history(history),
        },
      ),
    ]);
  }

  String _leadSource(dynamic s) => switch ('$s') {
        'MATERIAL' => 'from material master',
        'SUPPLIER' => 'supplier default',
        'MANUAL' => 'set by hand',
        _ => 'section default',
      };

  Widget _progress(Map<String, dynamic> po, AppScope scope) {
    final steps = (po['steps'] as List).cast<Map>();
    final wide = MediaQuery.of(context).size.width > 980;
    final timeline = ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 12, 20),
      children: [
        for (var i = 0; i < steps.length; i++)
          _TimelineRow(
            step: Map<String, dynamic>.from(steps[i]),
            last: i == steps.length - 1,
            canAct: scope.canEdit && po['status'] == 'ACTIVE',
            onDone: () => _after(showAdvanceDialog(context, [po])),
          ),
      ],
    );
    final info =
        ListView(padding: const EdgeInsets.fromLTRB(8, 8, 20, 20), children: [
      DsCard(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const DsCardTitle('Details', icon: Icons.info_outline),
          const SizedBox(height: 10),
          _kv('PO date (N1)', fmtDate(po['documentDate'])),
          _kv('Supplier',
              '${po['supplierShort'] ?? po['supplierName'] ?? '-'}'),
          _kv('Shipping mode', shipModeLabel(po['shipMode'])),
          _kv('Lines', '${po['itemCount']}'),
          _kv(
              'Value',
              po['totalValue'] == null
                  ? '-'
                  : '${fmtMoney(po['totalValue'])} ${po['currency'] ?? ''}'),
          _kv('Doc type / plant',
              '${po['docType'] ?? '-'} / ${po['plant'] ?? '-'}'),
          _kv('Shipment / S/I ref.', '${po['shipmentRef'] ?? '-'}'),
          _kv('Added by',
              '${po['createdByName'] ?? '-'} · ${fmtDateTime(po['createdAt'])}'),
          if (po['updatedAt'] != null)
            _kv('Last update',
                '${po['updatedByName'] ?? '-'} · ${fmtDateTime(po['updatedAt'])}'),
          if ('${po['remark'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: 8),
            InfoStrip(
                text: '${po['remark']}',
                icon: Icons.sticky_note_2_outlined,
                color: DsColors.amberFg),
          ],
        ]),
      ),
    ]);
    if (!wide) return timeline;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(flex: 3, child: timeline),
      Expanded(flex: 2, child: info),
    ]);
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 130, child: Text(k, style: DsType.meta)),
          Expanded(
              child: SelectableText(v,
                  style: const TextStyle(
                      fontSize: 12.5,
                      color: DsColors.heading,
                      fontWeight: FontWeight.w500))),
        ]),
      );

  Widget _items(List<Map> items) {
    Widget cell(String t, double? w,
        {bool bold = false, TextAlign align = TextAlign.left}) {
      final text = Text(t,
          textAlign: align,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: 12,
              color: DsColors.text,
              fontWeight: bold ? FontWeight.w600 : FontWeight.w400));
      return w == null
          ? Expanded(child: text)
          : SizedBox(width: w, child: text);
    }

    return ListView(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
                color: DsColors.subtle, borderRadius: BorderRadius.circular(9)),
            child: Row(children: [
              for (final h in const [
                ('Item', 50.0),
                ('Material', 96.0),
                ('SAP short text', null),
                ('Vendor material', null),
                ('Type', 80.0),
                ('Qty', 90.0),
                ('Price', 110.0),
                ('', 30.0),
                ('Lead time', 74.0)
              ])
                h.$2 == null
                    ? Expanded(
                        child: Text(h.$1.toUpperCase(), style: DsType.eyebrow))
                    : SizedBox(
                        width: h.$2,
                        child: Text(h.$1.toUpperCase(), style: DsType.eyebrow)),
            ]),
          ),
          for (final i in items)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: DsColors.lineSoft))),
              child: Row(children: [
                cell('${i['itemNo'] ?? '-'}', 50),
                SizedBox(
                    width: 96,
                    child: Text('${i['materialCode'] ?? '-'}',
                        style: mono(size: 11.5, weight: FontWeight.w600))),
                cell('${i['shortText'] ?? '-'}', null, bold: true),
                cell('${i['vendorMaterial'] ?? '-'}', null),
                cell('${i['materialType'] ?? '-'}', 80),
                cell('${fmtNum(i['orderQty'])} ${i['orderUnit'] ?? ''}', 90),
                cell(
                    i['netPrice'] == null
                        ? '-'
                        : '${fmtMoney(i['netPrice'])} ${i['currency'] ?? ''}',
                    110),
                SizedBox(
                  width: 30,
                  child: i['raw'] == null
                      ? null
                      : IconButton(
                          padding: EdgeInsets.zero,
                          tooltip: 'All columns from the SAP file',
                          icon: const Icon(Icons.table_rows_outlined,
                              size: 16, color: DsColors.iconSoft),
                          onPressed: () =>
                              _showRaw(Map<String, dynamic>.from(i)),
                        ),
                ),
                SizedBox(
                  width: 74,
                  child: i['deleted'] == true
                      ? const Tooltip(
                          message: 'Marked deleted in SAP — not counted',
                          child: DsTag('deleted',
                              color: DsColors.redFg, bg: DsColors.redBg))
                      : i['leadTimeDays'] == null
                          ? const Tooltip(
                              message: 'Not in the material master',
                              child: DsTag('n/a',
                                  color: DsColors.amberFg,
                                  bg: DsColors.amberBg))
                          : Text('${i['leadTimeDays']} d',
                              style: mono(size: 12, weight: FontWeight.w600)),
                ),
              ]),
            ),
        ]);
  }

  void _showRaw(Map<String, dynamic> item) {
    final raw = Map<String, dynamic>.from(item['raw'] as Map);
    unawaited(showGlassDialog<void>(
      context: context,
      builder: (ctx) => AppDialog(
        title:
            'SAP line ${item['itemNo'] ?? ''} · ${item['materialCode'] ?? ''}',
        subtitle:
            'Every column of this row in the uploaded Excel (row ${item['sourceRow'] ?? '-'})',
        icon: Icons.table_rows_outlined,
        width: 560,
        body: Column(children: [
          for (final e in raw.entries)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 7),
              decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: DsColors.lineSoft))),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 220, child: Text(e.key, style: DsType.meta)),
                Expanded(
                    child:
                        SelectableText('${e.value}', style: DsType.rowTitle)),
              ]),
            ),
        ]),
        actions: [
          DsOutlineButton(
              label: 'Close', height: 38, onPressed: () => Navigator.pop(ctx))
        ],
      ),
    ));
  }

  Widget _history(List<Map> history) {
    if (history.isEmpty) {
      return const DsEmptyState(icon: Icons.history, message: 'No history yet');
    }
    return ListView(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
        children: [
          for (final h in history)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                      color: _historyColor('${h['action']}')
                          .withValues(alpha: .12),
                      shape: BoxShape.circle),
                  child: Icon(_historyIcon('${h['action']}'),
                      size: 16, color: _historyColor('${h['action']}')),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_historyTitle(Map<String, dynamic>.from(h)),
                            style: DsType.rowTitle),
                        const SizedBox(height: 2),
                        Text(
                            '${h['actorName'] ?? 'System'} · ${fmtDateTime(h['createdAt'])}',
                            style: DsType.metaSm),
                        if (_historyDetail(Map<String, dynamic>.from(h))
                            .isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                                _historyDetail(Map<String, dynamic>.from(h)),
                                style: DsType.meta),
                          ),
                      ]),
                ),
              ]),
            ),
        ]);
  }

  IconData _historyIcon(String a) => switch (a) {
        'CREATED' => Icons.add_circle_outline,
        'STEP_DONE' => Icons.check_circle_outline,
        'STEP_UNDONE' => Icons.undo,
        'CANCELLED' => Icons.block,
        'REOPENED' => Icons.restore,
        _ => Icons.edit_outlined,
      };

  Color _historyColor(String a) => switch (a) {
        'STEP_DONE' => DsColors.greenFg,
        'STEP_UNDONE' => DsColors.amberFg,
        'CANCELLED' => DsColors.redFg,
        'CREATED' => DsColors.navy,
        _ => DsColors.blueFg,
      };

  String _historyTitle(Map<String, dynamic> h) {
    final d = (h['detail'] as Map?) ?? const {};
    return switch ('${h['action']}') {
      'CREATED' =>
        'PO added${d['source'] == 'EXCEL' ? ' from Excel' : ' by hand'} (${d['items'] ?? 0} lines)',
      'STEP_DONE' => 'Step ${h['stepNo']} done · ${d['stepName'] ?? ''}',
      'STEP_UNDONE' => 'Step ${h['stepNo']} undone · ${d['stepName'] ?? ''}',
      'CANCELLED' => 'PO cancelled',
      'REOPENED' => 'PO reopened',
      'EDITED' => 'PO edited',
      _ => '${h['action']}',
    };
  }

  String _historyDetail(Map<String, dynamic> h) {
    final d = (h['detail'] as Map?) ?? const {};
    switch ('${h['action']}') {
      case 'STEP_DONE':
        final late = intFrom(d['lateDays']) ?? 0;
        return [
          'Actual ${fmtDate(d['actualDate'])}',
          if (d['dueDate'] != null)
            'due ${fmtDate(d['dueDate'])}${late > 0 ? ' ($late d late)' : ' (on time)'}',
          if ('${d['referenceNo'] ?? ''}'.isNotEmpty) 'ref ${d['referenceNo']}',
          if ('${d['remark'] ?? ''}'.isNotEmpty) '"${d['remark']}"',
        ].join(' · ');
      case 'CANCELLED':
        return '${d['reason'] ?? ''}';
      case 'CREATED':
        return 'PO date ${fmtDate(d['documentDate'])} · lead time ${d['leadTimeDays'] ?? '-'} days';
      case 'EDITED':
        return d.entries.map((e) {
          final v = e.value;
          return v is Map
              ? '${e.key}: ${v['from'] ?? '-'} → ${v['to'] ?? '-'}'
              : '${e.key}';
        }).join(' · ');
      default:
        return '';
    }
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow(
      {required this.step,
      required this.last,
      required this.canAct,
      required this.onDone});
  final Map<String, dynamic> step;
  final bool last;
  final bool canAct;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final state = '${step['state']}';
    final done = state == 'done';
    final current = state == 'current';
    final late = intFrom(step['lateDays']) ?? 0;
    final color = done
        ? (late > 0 ? DsColors.amberFg : DsColors.greenFg)
        : current
            ? (late > 0 ? DsColors.redFg : DsColors.navy)
            : DsColors.faint2;
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 40,
          child: Column(children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: done
                    ? color
                    : current
                        ? color.withValues(alpha: .12)
                        : DsColors.chip,
                shape: BoxShape.circle,
                border: current ? Border.all(color: color, width: 2) : null,
                boxShadow: current
                    ? [
                        BoxShadow(
                            color: color.withValues(alpha: .3), blurRadius: 10)
                      ]
                    : null,
              ),
              child: done
                  ? const Icon(Icons.check, size: 17, color: Colors.white)
                  : Icon(stepIcon(step['icon']), size: 16, color: color),
            ),
            if (!last)
              Expanded(
                child: Container(
                  width: 2,
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  color: done ? color.withValues(alpha: .5) : DsColors.line,
                ),
              ),
          ]),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
              decoration: BoxDecoration(
                color: current
                    ? DsColors.navySoft.withValues(alpha: .45)
                    : done
                        ? DsColors.subtleAlt
                        : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: current ? DsColors.navyBorder : DsColors.lineSoft),
              ),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Text('${step['stepNo']}.',
                              style: mono(
                                  size: 12,
                                  weight: FontWeight.w700,
                                  color: color)),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text('${step['name']}',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: done || current
                                        ? DsColors.heading
                                        : DsColors.muted)),
                          ),
                          if ('${step['milestone'] ?? ''}'.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            DsTag('${step['milestone']}'),
                          ],
                          if (step['isArrival'] == true) ...[
                            const SizedBox(width: 6),
                            const DsTag('ETA',
                                color: DsColors.tealFg, bg: DsColors.tealBg),
                          ],
                        ]),
                        const SizedBox(height: 4),
                        Wrap(spacing: 14, runSpacing: 2, children: [
                          if (done)
                            Text('Done ${fmtDate(step['actualDate'])}',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: color)),
                          Text(
                              '${done ? 'Was due' : 'Due'} ${fmtDate(step['dueDate'])}',
                              style: DsType.meta),
                          if (step['plannedDate'] != null &&
                              step['plannedDate'] != step['dueDate'])
                            Text('Plan ${fmtDate(step['plannedDate'])}',
                                style: DsType.metaSm),
                          if (late > 0)
                            Text(done ? '$late d late' : '$late d overdue',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: done
                                        ? DsColors.amberFg
                                        : DsColors.redFg)),
                        ]),
                        if (done &&
                            (step['doneByName'] != null ||
                                '${step['referenceNo'] ?? ''}'.isNotEmpty ||
                                '${step['remark'] ?? ''}'.isNotEmpty))
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              [
                                if (step['doneByName'] != null)
                                  'by ${step['doneByName']}',
                                if ('${step['referenceNo'] ?? ''}'.isNotEmpty)
                                  '${step['referenceLabel'] ?? 'Ref'} ${step['referenceNo']}',
                                if ('${step['remark'] ?? ''}'.isNotEmpty)
                                  '"${step['remark']}"',
                              ].join('  ·  '),
                              style: DsType.metaSm,
                            ),
                          ),
                      ]),
                ),
                if (current && canAct)
                  DsPrimaryButton(
                      label: 'Mark done',
                      icon: Icons.check,
                      height: 34,
                      onPressed: onDone),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}
