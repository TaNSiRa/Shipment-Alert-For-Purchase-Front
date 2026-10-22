part of '../main.dart';

// Asks for a 24-hour time, starting from [current] ('HH:mm'); 'HH:mm' or null.
// Used rather than showTimePicker, whose keyboard mode cannot be confirmed
// with Enter — here Enter in either box is OK. Same dialog as RAP's OT entry.
Future<String?> askTime(BuildContext context, String current) =>
    showDialog<String>(
        context: context, builder: (_) => _TimeEntryDialog(initial: current));

class _TimeEntryDialog extends StatefulWidget {
  const _TimeEntryDialog({required this.initial});
  final String initial;

  @override
  State<_TimeEntryDialog> createState() => _TimeEntryDialogState();
}

class _TimeEntryDialogState extends State<_TimeEntryDialog> {
  late final TextEditingController _hour;
  late final TextEditingController _minute;
  final _hourFocus = FocusNode();
  final _minuteFocus = FocusNode();
  bool _invalid = false;

  @override
  void initState() {
    super.initState();
    final parts = widget.initial.split(':');
    final h = int.tryParse(parts.first) ?? 0;
    final m = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    _hour = TextEditingController(text: (h % 24).toString().padLeft(2, '0'));
    _minute = TextEditingController(text: (m % 60).toString().padLeft(2, '0'));
    _selectAll(_hour);
    _minuteFocus.addListener(() {
      if (_minuteFocus.hasFocus) _selectAll(_minute);
    });
    _hourFocus.addListener(() {
      if (_hourFocus.hasFocus) _selectAll(_hour);
    });
  }

  @override
  void dispose() {
    _hour.dispose();
    _minute.dispose();
    _hourFocus.dispose();
    _minuteFocus.dispose();
    super.dispose();
  }

  static void _selectAll(TextEditingController c) =>
      c.selection = TextSelection(baseOffset: 0, extentOffset: c.text.length);

  void _ok() {
    final h = int.tryParse(_hour.text.trim());
    final m = int.tryParse(_minute.text.trim());
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
      setState(() => _invalid = true);
      return;
    }
    Navigator.pop(context,
        '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}');
  }

  Widget _box(String label, TextEditingController controller, FocusNode focus,
          {bool autofocus = false}) =>
      Expanded(
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                focusNode: focus,
                autofocus: autofocus,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(2)
                ],
                style: const TextStyle(
                    fontSize: 44,
                    fontWeight: FontWeight.w400,
                    color: DsColors.heading),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: DsColors.chip,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide:
                          const BorderSide(color: DsColors.navy, width: 2)),
                ),
                onChanged: (v) {
                  if (_invalid) setState(() => _invalid = false);
                  // Two digits of hour typed: on to the minutes.
                  if (focus == _hourFocus && v.length == 2) {
                    _minuteFocus.requestFocus();
                  }
                },
                onSubmitted: (_) => _ok(),
              ),
              const SizedBox(height: 6),
              Text(label,
                  style: const TextStyle(fontSize: 12, color: DsColors.muted)),
            ]),
      );

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      // Numpad Enter too, wherever the focus is.
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): _ok,
        const SingleActivator(LogicalKeyboardKey.numpadEnter): _ok,
      },
      child: AlertDialog(
        title: const Text('Enter time',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
        content: SizedBox(
          width: 300,
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _box('Hour', _hour, _hourFocus, autofocus: true),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(10, 10, 10, 0),
                    child: Text(':',
                        style:
                            TextStyle(fontSize: 44, color: DsColors.heading)),
                  ),
                  _box('Minute', _minute, _minuteFocus),
                ]),
                if (_invalid)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('Enter a time from 00:00 to 23:59',
                        style: TextStyle(
                            fontSize: 12,
                            color: DsColors.redFg,
                            fontWeight: FontWeight.w600)),
                  ),
              ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(onPressed: _ok, child: const Text('OK')),
        ],
      ),
    );
  }
}
