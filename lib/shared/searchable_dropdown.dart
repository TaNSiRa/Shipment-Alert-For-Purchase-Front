part of '../main.dart';

class SearchableDropdownItem<T> {
  const SearchableDropdownItem({required this.value, required this.label, this.subtitle, this.detail});

  final T? value;
  final String label;
  final String? subtitle;
  // Optional extra row rendered under the subtitle in the picker (e.g. a
  // person's skill badges). Not shown in the collapsed field.
  final Widget? detail;
}

class SearchableDropdownField<T> extends StatelessWidget {
  const SearchableDropdownField({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    required this.decoration,
    this.dialogTitle,
    this.searchHint = 'Search',
    this.enabled = true,
    this.dense = false,
  });

  final T? value;
  final List<SearchableDropdownItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final InputDecoration decoration;
  final String? dialogTitle;
  final String searchHint;
  final bool enabled;

  /// Filter-bar size: smaller text and icon, so it sits at the height of the
  /// chips and buttons around it.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final selected = _selectedItem;
    final iconSize = dense ? 17.0 : 24.0;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: enabled ? () => _openPicker(context) : null,
        child: InputDecorator(
          isEmpty: selected == null,
          decoration: decoration.copyWith(
            enabled: enabled,
            suffixIcon: Icon(enabled ? Icons.search : Icons.arrow_drop_down, size: iconSize),
            suffixIconConstraints:
                dense ? const BoxConstraints(minWidth: 30, minHeight: 20) : decoration.suffixIconConstraints,
          ),
          child: Text(
            selected?.label ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: dense ? 12.5 : null,
                color: enabled ? (dense ? DsColors.heading : const Color(0xff0f172a)) : DsColors.faint2),
          ),
        ),
      ),
    );
  }

  SearchableDropdownItem<T>? get _selectedItem {
    for (final item in items) {
      if (item.value == value) return item;
    }
    return null;
  }

  Future<void> _openPicker(BuildContext context) async {
    final result = await showGlassDialog<_SearchableDropdownResult<T>>(
      context: context,
      builder: (_) => _SearchableDropdownDialog<T>(
        title: dialogTitle ?? decoration.labelText ?? 'Select',
        searchHint: searchHint,
        value: value,
        items: items,
      ),
    );
    if (result != null) onChanged?.call(result.value);
  }
}

class _SearchableDropdownResult<T> {
  const _SearchableDropdownResult(this.value);

  final T? value;
}

class _SearchableDropdownDialog<T> extends StatefulWidget {
  const _SearchableDropdownDialog({
    required this.title,
    required this.searchHint,
    required this.value,
    required this.items,
  });

  final String title;
  final String searchHint;
  final T? value;
  final List<SearchableDropdownItem<T>> items;

  @override
  State<_SearchableDropdownDialog<T>> createState() => _SearchableDropdownDialogState<T>();
}

class _SearchableDropdownDialogState<T> extends State<_SearchableDropdownDialog<T>> {
  final search = TextEditingController();

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = search.text.trim().toLowerCase();
    final filtered = widget.items.where((item) {
      if (query.isEmpty) return true;
      return item.label.toLowerCase().contains(query) || (item.subtitle ?? '').toLowerCase().contains(query);
    }).toList();

    return AlertDialog(
      backgroundColor: DsColors.popupSurface,
      surfaceTintColor: DsColors.popupSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      titlePadding: const EdgeInsets.fromLTRB(22, 20, 14, 0),
      contentPadding: const EdgeInsets.fromLTRB(22, 12, 22, 10),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      title: Row(children: [
        Expanded(
          child: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close), tooltip: 'Close'),
      ]),
      content: SizedBox(
        width: 430,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: search,
            autofocus: true,
            decoration: InputDecoration(labelText: widget.searchHint, prefixIcon: const Icon(Icons.search)),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: filtered.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 28),
                    child: Center(child: Text('No matching option')),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = filtered[index];
                      final selected = item.value == widget.value;
                      return ListTile(
                        dense: true,
                        selected: selected,
                        selectedTileColor: const Color(0xffe0f2f1),
                        leading: Icon(
                          selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                          color: selected ? DsColors.navy : DsColors.faint2,
                        ),
                        title: Text(item.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: item.subtitle == null && item.detail == null
                            ? null
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (item.subtitle != null)
                                    Text(item.subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis),
                                  if (item.detail != null) ...[
                                    const SizedBox(height: 4),
                                    item.detail!,
                                  ],
                                ],
                              ),
                        onTap: () => Navigator.pop(context, _SearchableDropdownResult<T>(item.value)),
                      );
                    },
                  ),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      ],
    );
  }
}
