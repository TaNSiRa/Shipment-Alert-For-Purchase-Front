part of '../main.dart';

/// Returns true when POs were imported.
Future<bool> showPoImportDialog(BuildContext context) async {
  final api = AppScope.read(context).api;
  final result = await showGlassDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _PoImportDialog(api: api),
  );
  return result == true;
}

class _PoImportDialog extends StatefulWidget {
  const _PoImportDialog({required this.api});
  final ApiClient api;
  @override
  State<_PoImportDialog> createState() => _PoImportDialogState();
}

class _PoImportDialogState extends State<_PoImportDialog> {
  PickedFile? file;
  Map<String, dynamic>? summary;
  List<Map<String, dynamic>> pos = [];
  final Set<String> chosen = {};
  final Set<String> expanded = {};
  bool busy = false;
  String? error;
  Map<String, dynamic>? done;

  Future<void> pick() async {
    final picked = await pickExcelFile();
    if (picked == null) return;
    setState(() {
      file = picked;
      busy = true;
      error = null;
      summary = null;
      pos = [];
      chosen.clear();
    });
    try {
      final result = await widget.api.postJson('/pos/import/preview',
          {'fileName': picked.name, 'data': picked.base64});
      final list = (result['pos'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      setState(() {
        summary = Map<String, dynamic>.from(result['summary'] as Map);
        pos = list;
        chosen.addAll(
            list.where((p) => p['status'] == 'NEW').map((p) => '${p['poNo']}'));
        busy = false;
      });
    } on ApiException catch (e) {
      setState(() {
        busy = false;
        error = friendlyError(e.message);
      });
    } catch (_) {
      setState(() {
        busy = false;
        error = 'Could not send the file to the server';
      });
    }
  }

  Future<void> commit() async {
    if (file == null || chosen.isEmpty) return;
    setState(() => busy = true);
    try {
      final result = await widget.api.postJson('/pos/import/commit', {
        'fileName': file!.name,
        'data': file!.base64,
        'poNos': chosen.toList(),
      });
      setState(() {
        busy = false;
        done = result;
      });
    } on ApiException catch (e) {
      setState(() {
        busy = false;
        error = friendlyError(e.message);
      });
    }
  }

  Future<void> template() async {
    try {
      final bytes = await widget.api.getBytes('/pos/import/template');
      saveBytes(bytes, 'po-import-template.xlsx');
    } catch (_) {
      if (mounted) AppToast.error(context, 'Could not download the template');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'Import POs from Excel',
      subtitle: 'นำเข้า PO จากไฟล์ Excel (SAP export) — no retyping',
      icon: Icons.upload_file,
      width: 1040,
      scrollable: false,
      body: done != null
          ? _done()
          : summary == null
              ? _start()
              : _preview(),
      actions: done != null
          ? [
              DsPrimaryButton(
                  label: 'Done',
                  icon: Icons.check,
                  height: 40,
                  onPressed: () => Navigator.pop(context, true))
            ]
          : [
              DsOutlineButton(
                  label: 'Close',
                  height: 40,
                  onPressed: busy ? null : () => Navigator.pop(context, false)),
              if (summary != null)
                DsOutlineButton(
                    label: 'Choose another file',
                    icon: Icons.folder_open,
                    height: 40,
                    onPressed: busy ? null : pick),
              if (summary != null)
                DsPrimaryButton(
                  label: busy ? 'Importing…' : _commitLabel(),
                  icon: Icons.cloud_upload_outlined,
                  height: 40,
                  onPressed: busy || chosen.isEmpty ? null : commit,
                ),
            ],
    );
  }

  // POs the user can tick: new ones, and ones already in the system that the
  // file changes (those start unticked — applying them overwrites the PO).
  bool _selectable(Map<String, dynamic> p) =>
      p['status'] == 'NEW' || p['status'] == 'CHANGED';

  String _commitLabel() {
    final updates = pos
        .where((p) => p['status'] == 'CHANGED' && chosen.contains('${p['poNo']}'))
        .length;
    final creates = chosen.length - updates;
    if (creates == 0 && updates == 0) return 'Import';
    return [
      if (creates > 0) 'Import ${plural(creates, 'PO')}',
      if (updates > 0) 'Update ${plural(updates, 'PO')}',
    ].join(' · ');
  }

  Widget _start() {
    return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: busy ? null : pick,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 38, horizontal: 20),
              decoration: BoxDecoration(
                color: DsColors.navySoft.withValues(alpha: .25),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: DsColors.navyBorder, width: 1.6),
              ),
              child: Column(children: [
                if (busy)
                  const SizedBox(
                      width: 34,
                      height: 34,
                      child: CircularProgressIndicator(strokeWidth: 3))
                else
                  const Icon(Icons.cloud_upload_outlined,
                      size: 44, color: DsColors.navy),
                const SizedBox(height: 12),
                Text(
                    busy
                        ? 'Reading ${file?.name ?? 'file'}…'
                        : 'Click to choose the Excel file (.xlsx)',
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: DsColors.heading)),
                const SizedBox(height: 6),
                const Text(
                    'Nothing is saved until you review the list and press Import.',
                    style: DsType.meta),
              ]),
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            InfoStrip(
                text: error!, icon: Icons.error_outline, color: DsColors.redFg),
          ],
          const SizedBox(height: 18),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: _tip(
                  Icons.table_view_outlined,
                  'Use the SAP export as it is',
                  'The "DATA BY SAP" list from SAP (Purchasing Document, Name of Supplier, Item, Document Date, Material, Short Text, Order Quantity…) works without changes. One row = one PO line; lines with the same PO No. become one PO.'),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _tip(Icons.rule_outlined, 'Checked before saving',
                  'Each PO is matched to the Supplier and Material Master to get its lead time and ETA. POs already in the system are compared with the file — changed columns are listed and you choose which POs to update. Future dates and deleted SAP lines are flagged.'),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _tip(Icons.edit_note_outlined, 'Not using SAP?',
                        'Fill in the template (PO No., supplier, PO date, material, qty…) and upload it the same way.'),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                          onPressed: template,
                          icon: const Icon(Icons.download, size: 18),
                          label: const Text('Download template')),
                    ),
                  ]),
            ),
          ]),
        ]);
  }

  Widget _tip(IconData icon, String title, String text) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: DsColors.subtle,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: DsColors.cardBorder),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 18, color: DsColors.navy),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: DsType.panelTitle)),
          ]),
          const SizedBox(height: 6),
          Text(text, style: DsType.meta),
        ]),
      );

  Widget _preview() {
    final s = summary!;
    final newPos = pos.where(_selectable).toList();
    final allChosen = newPos.isNotEmpty &&
        newPos.every((p) => chosen.contains('${p['poNo']}'));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const Icon(Icons.description_outlined, size: 18, color: DsColors.icon),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
              '${file?.name} · sheet "${s['sheetName']}" · ${plural(intFrom(s['lines']) ?? 0, 'line')}',
              style: DsType.meta,
              overflow: TextOverflow.ellipsis),
        ),
      ]),
      const SizedBox(height: 10),
      Wrap(spacing: 10, runSpacing: 10, children: [
        _stat('POs in file', s['pos'], DsColors.navy),
        _stat('Ready to import', s['ready'], DsColors.greenFg),
        _stat('With warnings', s['withWarnings'], DsColors.amberFg),
        _stat('Changed in file', s['changed'], DsColors.blueFg),
        _stat('Already in system', s['existing'], DsColors.muted),
        _stat('Errors', s['errors'], DsColors.redFg),
        _stat('New suppliers', s['newSuppliers'], DsColors.blueFg),
        _stat('Materials not in master', s['unmatchedMaterials'],
            DsColors.amberFg),
      ]),
      if ((s['orphanRows'] as List?)?.isNotEmpty == true) ...[
        const SizedBox(height: 10),
        InfoStrip(
          icon: Icons.warning_amber_rounded,
          color: DsColors.amberFg,
          text:
              '${(s['orphanRows'] as List).length} row(s) have no PO number and were ignored (rows ${(s['orphanRows'] as List).take(8).join(', ')}).',
        ),
      ],
      if (error != null) ...[
        const SizedBox(height: 10),
        InfoStrip(
            text: error!, icon: Icons.error_outline, color: DsColors.redFg),
      ],
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
            color: DsColors.subtle, borderRadius: BorderRadius.circular(9)),
        child: Row(children: [
          SizedBox(
            width: 40,
            child: Checkbox(
              value: allChosen,
              onChanged: newPos.isEmpty
                  ? null
                  : (v) => setState(() => v == true
                      ? chosen.addAll(newPos.map((p) => '${p['poNo']}'))
                      : chosen.clear()),
            ),
          ),
          for (final h in const [
            ('PO No.', 120.0),
            ('Status', 120.0),
            ('Supplier', null),
            ('PO date', 100.0),
            ('Lines', 50.0),
            ('Mode', 70.0),
            ('Lead time', 90.0),
            ('First due', 100.0),
            ('ETA', 100.0),
            ('', 40.0)
          ])
            h.$2 == null
                ? Expanded(
                    child: Text(h.$1.toUpperCase(), style: DsType.eyebrow))
                : SizedBox(
                    width: h.$2,
                    child: Text(h.$1.toUpperCase(), style: DsType.eyebrow)),
        ]),
      ),
      Flexible(
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: pos.length,
          itemBuilder: (_, i) => _poRow(pos[i]),
        ),
      ),
    ]);
  }

  Widget _stat(String label, dynamic value, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: .2)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('${value ?? 0}', style: DsType.stat(16, color: color)),
          const SizedBox(width: 7),
          Text(label,
              style: TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w600, color: color)),
        ]),
      );

  Widget _poRow(Map<String, dynamic> p) {
    final no = '${p['poNo']}';
    final status = '${p['status']}';
    final warnings = (p['warnings'] as List).cast<dynamic>();
    final errors = (p['errors'] as List).cast<dynamic>();
    final open = expanded.contains(no);
    final (fg, bg, label) = switch (status) {
      'NEW' => warnings.isEmpty
          ? (DsColors.greenFg, DsColors.greenBg, 'Ready')
          : (DsColors.amberFg, DsColors.amberBg, 'Ready · check'),
      'CHANGED' => (DsColors.blueFg, DsColors.blueBg, 'Changed · update?'),
      'EXISTS' => (DsColors.muted, DsColors.chip, 'Already added'),
      _ => (DsColors.redFg, DsColors.redBg, 'Error'),
    };
    return Container(
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: DsColors.lineSoft))),
      child: Column(children: [
        InkWell(
          onTap: () =>
              setState(() => open ? expanded.remove(no) : expanded.add(no)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(children: [
              SizedBox(
                width: 40,
                child: _selectable(p)
                    ? Checkbox(
                        value: chosen.contains(no),
                        onChanged: (v) => setState(() =>
                            v == true ? chosen.add(no) : chosen.remove(no)),
                      )
                    : null,
              ),
              SizedBox(
                  width: 120,
                  child: Text(no,
                      style: mono(size: 12.5, weight: FontWeight.w700))),
              SizedBox(
                  width: 120,
                  child: Align(
                      alignment: Alignment.centerLeft,
                      child: DsTag(label, color: fg, bg: bg))),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${p['supplierShort'] ?? p['supplierName'] ?? '-'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DsType.rowTitle),
                      Text(
                          '${p['supplierCode'] ?? ''}${p['supplierStatus'] == 'NEW' ? ' · new supplier' : ''}',
                          style: DsType.metaSm),
                    ]),
              ),
              SizedBox(
                  width: 100,
                  child: Text(fmtDate(p['documentDate']), style: DsType.meta)),
              SizedBox(
                  width: 50,
                  child: Text('${p['itemCount']}', style: mono(size: 12))),
              SizedBox(width: 70, child: ShipModeTag(mode: p['shipMode'])),
              SizedBox(
                width: 90,
                child: Text(
                    '${p['leadTimeDays']} d${p['leadTimeSource'] == 'MATERIAL' ? '' : ' *'}',
                    style: mono(
                        size: 12,
                        color: p['leadTimeSource'] == 'MATERIAL'
                            ? DsColors.heading
                            : DsColors.amberFg)),
              ),
              SizedBox(
                  width: 100,
                  child: Text(fmtDate(p['nextDueDate']), style: DsType.meta)),
              SizedBox(
                width: 100,
                child: Text(fmtDate(p['etaDate']),
                    style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: DsColors.navyDeep)),
              ),
              SizedBox(
                  width: 40,
                  child: Icon(open ? Icons.expand_less : Icons.expand_more,
                      size: 20, color: DsColors.icon)),
            ]),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.fromLTRB(48, 0, 12, 12),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final e in errors)
                    Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: InfoStrip(
                            text: '$e',
                            icon: Icons.error_outline,
                            color: DsColors.redFg)),
                  for (final w in warnings)
                    Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: InfoStrip(
                            text: '$w',
                            icon: Icons.warning_amber_rounded,
                            color: DsColors.amberFg)),
                  if (p['changes'] is Map) _changes(p['changes'] as Map),
                  if (p['leadTimeSource'] != 'MATERIAL')
                    const Padding(
                      padding: EdgeInsets.only(bottom: 6),
                      child: InfoStrip(
                          text:
                              '* Lead time comes from the supplier default or the section default because no line matched the Material Master.'),
                    ),
                  for (final it in (p['items'] as List).cast<Map>())
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(children: [
                        SizedBox(
                            width: 44,
                            child: Text('${it['itemNo'] ?? ''}',
                                style: DsType.metaSm)),
                        SizedBox(
                            width: 90,
                            child: Text('${it['materialCode'] ?? '-'}',
                                style: mono(size: 11.5))),
                        Expanded(
                            child: Text('${it['shortText'] ?? ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: DsType.meta)),
                        Expanded(
                            child: Text('${it['vendorMaterial'] ?? ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: DsType.metaSm)),
                        SizedBox(
                            width: 90,
                            child: Text(
                                '${fmtNum(it['orderQty'])} ${it['orderUnit'] ?? ''}',
                                style: DsType.meta)),
                        SizedBox(
                          width: 110,
                          child: it['match'] == 'NONE'
                              ? const DsTag('not in master',
                                  color: DsColors.amberFg, bg: DsColors.amberBg)
                              : Text(
                                  '${it['leadTimeDays']} d${it['match'] == 'CODE_ONLY' ? ' (other supplier)' : ''}',
                                  style: DsType.metaSm),
                        ),
                      ]),
                    ),
                ]),
          ),
      ]),
    );
  }

  // What the file would change on a PO already in the system: PO-level values
  // first, then each line (changed columns, or a line new in the file).
  Widget _changes(Map changes) {
    String v(dynamic x) => x == null || '$x'.isEmpty ? '-' : '$x';
    final po = (changes['po'] as List? ?? const []).cast<Map>();
    final lines = (changes['lines'] as List? ?? const [])
        .cast<Map>()
        .where((l) => l['kind'] != 'MISSING')
        .toList();
    if (po.isEmpty && lines.isEmpty) return const SizedBox.shrink();
    Widget row(String what, String detail) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
                width: 150,
                child: Text(what,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DsType.metaSm)),
            Expanded(child: Text(detail, style: DsType.meta)),
          ]),
        );
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: DsColors.blueBg.withValues(alpha: .5),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: DsColors.blueFg.withValues(alpha: .2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Different from the system (system → file)',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: DsColors.blueFg)),
        const SizedBox(height: 6),
        for (final c in po)
          row('${c['label']}', '${v(c['from'])} → ${v(c['to'])}'),
        for (final l in lines)
          row(
            'Line ${l['itemNo'] ?? '-'}${l['materialCode'] == null ? '' : ' · ${l['materialCode']}'}',
            l['kind'] == 'ADDED'
                ? 'New line — will be added'
                : (l['columns'] as List)
                    .cast<Map>()
                    .map((c) =>
                        '${c['header']}: ${v(c['from'])} → ${v(c['to'])}')
                    .join(' · '),
          ),
      ]),
    );
  }

  Widget _done() {
    final created = (done!['created'] as List).length;
    final updated = (done!['updated'] as List? ?? const []).length;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      const SizedBox(height: 10),
      Container(
        width: 70,
        height: 70,
        decoration: const BoxDecoration(
            color: DsColors.greenBg, shape: BoxShape.circle),
        child:
            const Icon(Icons.check_rounded, size: 40, color: DsColors.greenFg),
      ),
      const SizedBox(height: 14),
      Text(
          [
            if (created > 0 || updated == 0) '${plural(created, 'PO')} imported',
            if (updated > 0) '${plural(updated, 'PO')} updated',
          ].join(' · '),
          style: DsType.pageTitle),
      const SizedBox(height: 6),
      Text(
        [
          if ((intFrom(done!['skipped']) ?? 0) > 0)
            '${done!['skipped']} skipped',
          if ((intFrom(done!['suppliersAdded']) ?? 0) > 0)
            '${plural(intFrom(done!['suppliersAdded'])!, 'new supplier')} added to the master',
          'Step 1 (Issue PO) is done; each PO now waits for the supplier acknowledgement.',
        ].join(' · '),
        textAlign: TextAlign.center,
        style: DsType.meta,
      ),
      const SizedBox(height: 16),
    ]);
  }
}
