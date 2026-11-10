import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'app_icons.dart';
import 'theme.dart';

/// Gotowe kolory wydarzeń w Kalendarzu (0080), w tej kolejności w wyborze.
const calendarPresetColors = <String, Color>{
  'green': Color(0xFF2FB673),
  'blue': Color(0xFF3B82F6),
  'violet': Color(0xFF7C5CFF),
  'amber': Color(0xFFD99A15),
  'rose': Color(0xFFE5484D),
  'teal': Color(0xFF14A3A8),
  'gray': Color(0xFF8A8F98),
};

/// Kolor wydarzenia z bazy: nazwa gotowego koloru albo własny „#RRGGBB” (0085, 10.11.2026). Null: nieznany.
Color? calendarColorFromDb(String? value) {
  if (value == null) return null;
  if (calendarPresetColors[value] case final preset?) return preset;
  final hex = RegExp(r'^#([0-9A-Fa-f]{6})$').firstMatch(value);
  if (hex == null) return null;
  return Color(0xFF000000 | int.parse(hex.group(1)!, radix: 16));
}

/// „#2FB673”: własny kolor do zapisania w bazie.
String calendarColorHex(Color color) =>
    '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// Wybór koloru wydarzenia: gotowe kółka i ostatnie „Własny kolor” (tęczowe, a po wyborze w wybranym kolorze),
/// które otwiera wybór RGB przez [onCustom] (okno w panelu, okno od dołu w telefonie).
class CalendarColorSwatches extends StatelessWidget {
  const CalendarColorSwatches({
    super.key,
    required this.value,
    required this.onChanged,
    required this.onCustom,
    this.enabled = true,
    this.size = 28,
  });

  /// Wartość z bazy: nazwa gotowego koloru albo „#RRGGBB”.
  final String value;
  final ValueChanged<String> onChanged;

  /// Wybór RGB zaczynający od podanego koloru. Null: anulowany.
  final Future<Color?> Function(Color initial) onCustom;
  final bool enabled;
  final double size;

  @override
  Widget build(BuildContext context) {
    final custom = !calendarPresetColors.containsKey(value);
    final current = calendarColorFromDb(value) ?? calendarPresetColors['green']!;
    Widget swatch({required Widget child, required bool selected, required String label, VoidCallback? onTap}) =>
        Semantics(
          button: true,
          selected: selected,
          label: label,
          excludeSemantics: true,
          child: InkWell(
            onTap: enabled ? onTap : null,
            customBorder: const CircleBorder(),
            child: Container(
              width: size + 8,
              height: size + 8,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: selected ? Border.all(color: AppColors.text, width: 2) : null,
              ),
              child: SizedBox(width: size, height: size, child: child),
            ),
          ),
        );
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final MapEntry(key: name, value: color) in calendarPresetColors.entries)
          swatch(
            label: 'Kolor $name',
            selected: value == name,
            onTap: () => onChanged(name),
            child: DecoratedBox(decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          ),
        swatch(
          label: 'Własny kolor RGB',
          selected: custom,
          onTap: () async {
            final picked = await onCustom(current);
            if (picked != null) onChanged(calendarColorHex(picked));
          },
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: custom ? current : null,
              gradient: custom
                  ? null
                  : const SweepGradient(
                      colors: [
                        Color(0xFFFF3B30),
                        Color(0xFFFFCC00),
                        Color(0xFF34C759),
                        Color(0xFF00C7BE),
                        Color(0xFF007AFF),
                        Color(0xFFAF52DE),
                        Color(0xFFFF3B30),
                      ],
                    ),
            ),
            child: Center(child: Glyph(AppIcons.plus, size: size * 0.5, color: const Color(0xFFFFFFFF))),
          ),
        ),
      ],
    );
  }
}

/// Wybór koloru RGB (10.11.2026, prośba użytkownika): podgląd, pole „#RRGGBB” i suwaki czerwonego, zielonego
/// i niebieskiego od 0 do 255.
class RgbColorPicker extends StatefulWidget {
  const RgbColorPicker({super.key, required this.initial, required this.onChanged});

  final Color initial;
  final ValueChanged<Color> onChanged;

  @override
  State<RgbColorPicker> createState() => _RgbColorPickerState();
}

class _RgbColorPickerState extends State<RgbColorPicker> {
  late int _r = (widget.initial.toARGB32() >> 16) & 0xFF;
  late int _g = (widget.initial.toARGB32() >> 8) & 0xFF;
  late int _b = widget.initial.toARGB32() & 0xFF;
  late final _hex = TextEditingController(text: calendarColorHex(widget.initial).substring(1));

  Color get _color => Color.fromARGB(255, _r, _g, _b);

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _set({int? r, int? g, int? b, bool fromHex = false}) {
    setState(() {
      _r = r ?? _r;
      _g = g ?? _g;
      _b = b ?? _b;
    });
    if (!fromHex) _hex.text = calendarColorHex(_color).substring(1);
    widget.onChanged(_color);
  }

  void _hexChanged(String value) {
    if (value.length != 6) return;
    final v = int.tryParse(value, radix: 16);
    if (v == null) return;
    _set(r: (v >> 16) & 0xFF, g: (v >> 8) & 0xFF, b: v & 0xFF, fromHex: true);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget channel(String label, int value, Color tint, void Function(int) onChanged) => Row(
      children: [
        SizedBox(width: 18, child: Text(label, style: text.labelLarge)),
        Expanded(
          child: Slider(
            value: value.toDouble(),
            max: 255,
            divisions: 255,
            activeColor: tint,
            inactiveColor: tint.withValues(alpha: 0.2),
            label: '$value',
            onChanged: (v) => onChanged(v.round()),
          ),
        ),
        SizedBox(
          width: 34,
          child: Text(
            '$value',
            textAlign: TextAlign.end,
            style: text.bodyMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ),
      ],
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _color,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.ringStrong),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: TextField(
                controller: _hex,
                maxLength: 6,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[0-9A-Fa-f]'))],
                style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
                decoration: const InputDecoration(prefixText: '#', labelText: 'Kolor', counterText: ''),
                onChanged: _hexChanged,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        channel('R', _r, const Color(0xFFE5484D), (v) => _set(r: v)),
        channel('G', _g, const Color(0xFF2FB673), (v) => _set(g: v)),
        channel('B', _b, const Color(0xFF3B82F6), (v) => _set(b: v)),
      ],
    );
  }
}
