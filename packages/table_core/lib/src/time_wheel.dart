import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

import 'theme.dart';

/// Wybór godziny jak w iOS: przewijane kółka godzin i minut z podświetlonym pasem pośrodku.
/// Kółka się zapętlają, kręci się je myszą, palcem albo kółkiem myszy, a stuknięcie w liczbę ją wybiera.
/// [allowEndOfDay] dodaje godzinę 24 (24:00, koniec dnia, np. zamknięcie o północy); przy niej minuty to tylko 00.
/// Na telefonie wysuwa się od dołu, na komputerze to okno. Zwraca null po anulowaniu,
/// a 24:00 jako `TimeOfDay(hour: 24, minute: 0)`.
Future<TimeOfDay?> showTimeWheel(
  BuildContext context, {
  required TimeOfDay initial,
  int minuteStep = 5,
  bool allowEndOfDay = false,
  String? title,
}) {
  final phone = MediaQuery.sizeOf(context).width < 600;
  final picker = _TimeWheel(
    initial: initial,
    minuteStep: minuteStep,
    allowEndOfDay: allowEndOfDay,
    title: title,
  );
  if (phone) {
    return showModalBottomSheet<TimeOfDay>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SafeArea(top: false, child: picker),
    );
  }
  return showDialog<TimeOfDay>(
    context: context,
    builder: (_) => Dialog(child: SizedBox(width: 320, child: picker)),
  );
}

class _TimeWheel extends StatefulWidget {
  const _TimeWheel({
    required this.initial,
    required this.minuteStep,
    required this.allowEndOfDay,
    this.title,
  });

  final TimeOfDay initial;
  final int minuteStep;
  final bool allowEndOfDay;
  final String? title;

  @override
  State<_TimeWheel> createState() => _TimeWheelState();
}

class _TimeWheelState extends State<_TimeWheel> {
  static const _itemExtent = 40.0;

  late final List<int> _hours = [for (var h = 0; h < 24; h++) h, if (widget.allowEndOfDay) 24];
  late final List<int> _minutes = <int>{
    for (var m = 0; m < 60; m += widget.minuteStep) m,
    if (widget.initial.minute < 60) widget.initial.minute,
  }.toList()..sort();

  late int _hour = widget.initial.hour.clamp(0, widget.allowEndOfDay ? 24 : 23);
  late int _minute = _hour == 24 ? 0 : widget.initial.minute;

  late final _hourWheel = FixedExtentScrollController(initialItem: _hours.indexOf(_hour));
  late final _minuteWheel = FixedExtentScrollController(initialItem: _minutes.indexOf(_minute));

  @override
  void dispose() {
    _hourWheel.dispose();
    _minuteWheel.dispose();
    super.dispose();
  }

  String _two(int v) => v.toString().padLeft(2, '0');

  /// Przewija zapętlone kółko najkrótszą drogą do wartości o indeksie [target].
  void _scrollTo(FixedExtentScrollController controller, int length, int target) {
    final current = controller.selectedItem;
    var delta = (target - current) % length;
    if (delta > length / 2) delta -= length;
    controller.animateToItem(
      current + delta,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  /// O 24:00 minuty wracają do 00, jak niedostępna data w kalendarzu iOS.
  void _fixMinutes() {
    if (_hour == 24 && _minute != 0) {
      _scrollTo(_minuteWheel, _minutes.length, _minutes.indexOf(0));
    }
  }

  Widget _wheel({
    required FixedExtentScrollController controller,
    required List<int> values,
    required ValueChanged<int> onChanged,
    bool Function(int value)? disabled,
  }) {
    final text = Theme.of(context).textTheme;
    return SizedBox(
      width: 76,
      child: NotificationListener<ScrollEndNotification>(
        onNotification: (_) {
          _fixMinutes();
          return false;
        },
        child: ScrollConfiguration(
          // Na komputerze kółko da się też przeciągnąć myszą, jak palcem na telefonie.
          behavior: ScrollConfiguration.of(context).copyWith(
            dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse, PointerDeviceKind.trackpad},
            scrollbars: false,
          ),
          child: ListWheelScrollView.useDelegate(
            controller: controller,
            itemExtent: _itemExtent,
            diameterRatio: 1.25,
            perspective: 0.004,
            overAndUnderCenterOpacity: 0.35,
            physics: const FixedExtentScrollPhysics(),
            onSelectedItemChanged: (i) => onChanged(values[i % values.length]),
            childDelegate: ListWheelChildLoopingListDelegate(
              children: [
                for (final (i, v) in values.indexed)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _scrollTo(controller, values.length, i),
                    child: Center(
                      child: Text(
                        _two(v),
                        style: text.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: disabled?.call(v) == true ? AppColors.textDisabled : AppColors.text,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final minute = _hour == 24 ? 0 : _minute;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Jak w iOS: Anuluj po lewej, Gotowe po prawej, na środku wybrana godzina.
          Row(
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(foregroundColor: AppColors.textMuted, minimumSize: const Size(0, 44)),
                child: const Text('Anuluj'),
              ),
              Expanded(
                child: Column(
                  children: [
                    if (widget.title != null)
                      Text(widget.title!, style: text.labelMedium?.copyWith(color: AppColors.textMuted)),
                    Text(
                      '${_two(_hour)}:${_two(minute)}',
                      textAlign: TextAlign.center,
                      style: text.titleLarge?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, TimeOfDay(hour: _hour, minute: minute)),
                style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
                child: const Text('Gotowe', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: _itemExtent * 5,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Pas wybranej godziny pod środkowym wierszem.
                Container(
                  height: _itemExtent,
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceRaised,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _wheel(
                      controller: _hourWheel,
                      values: _hours,
                      onChanged: (v) => setState(() => _hour = v),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(':', style: text.headlineSmall?.copyWith(color: AppColors.textMuted)),
                    ),
                    _wheel(
                      controller: _minuteWheel,
                      values: _minutes,
                      onChanged: (v) => setState(() => _minute = v),
                      disabled: (v) => _hour == 24 && v != 0,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
