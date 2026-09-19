import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

/// Nagłówek strony panelu: tytuł, podtytuł i akcje po prawej.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.below,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  /// Dodatkowy rząd pod tytułem, na przykład zakładki albo filtry.
  final Widget? below;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: text.headlineMedium),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: text.bodyMedium?.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              for (var i = 0; i < actions.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                actions[i],
              ],
            ],
          ),
          if (below != null) ...[const SizedBox(height: 16), below!],
        ],
      ),
    );
  }
}

/// Karta z opcjonalnym tytułem i akcją w nagłówku.
class PanelCard extends StatelessWidget {
  const PanelCard({
    super.key,
    required this.child,
    this.title,
    this.trailing,
    this.icon,
    this.iconColor,
    this.padding = const EdgeInsets.all(20),
  });

  final String? title;
  final Widget? trailing;

  /// Ikona w kolorowej kostce przed tytułem.
  final AppIconData? icon;
  final Color? iconColor;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (title != null) ...[
              Row(
                children: [
                  if (icon != null) ...[
                    IconBadge(icon!, color: iconColor ?? AppColors.accentFill),
                    const SizedBox(width: 10),
                  ],
                  Expanded(child: Text(title!, style: text.titleMedium)),
                  ?trailing,
                ],
              ),
              const SizedBox(height: 16),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

/// Kolorowa kostka z ikoną, jak w kaflach liczb i nagłówkach kart.
class IconBadge extends StatelessWidget {
  const IconBadge(this.icon, {super.key, required this.color, this.size = 34});

  final AppIconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(size / 3),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.35),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Glyph(icon, size: size * 0.52, color: Colors.white),
    );
  }
}

/// Barwy kafli liczb. Każda miara ma swój kolor, ten sam co jej słupki na wykresie.
abstract final class TileColors {
  static const green = Color(0xFF2FB673);
  static const blue = Color(0xFF3B82F6);
  static const amber = Color(0xFFD99A15);
  static const violet = Color(0xFF7C5CFF);
  static const rose = Color(0xFFD9455F);
}

/// Liczba z opisem, na przykład „14 gości”. Z ikoną w kolorowej kostce
/// i zmianą względem poprzedniego okresu.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.hint,
    this.accent = false,
    this.color,
    this.change,
    this.moreIsBetter = true,
  });

  final String label;
  final String value;
  final AppIconData? icon;
  final String? hint;
  final bool accent;

  /// Kolor kostki z ikoną.
  final Color? color;

  /// Zmiana w procentach względem poprzedniego okresu. Null, gdy nie ma z czym porównać.
  final double? change;

  /// Czy wzrost jest dobrą wiadomością. Przy niestawiennictwach jest odwrotnie.
  final bool moreIsBetter;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final up = (change ?? 0) >= 0;
    final good = up == moreIsBetter;

    return Card(
      // Kafelek leży na karcie, więc jest o ton jaśniejszy od niej.
      color: AppColors.surfaceRaised,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  IconBadge(icon!, color: color ?? AppColors.accentFill),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: text.displaySmall?.copyWith(
                color: accent ? AppColors.accent : AppColors.text,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 4),
            // Wiersz podpisu jest zawsze, żeby kafelki w rzędzie miały równą wysokość.
            Row(
              children: [
                Expanded(
                  child: Text(
                    hint ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                  ),
                ),
                if (change != null) ...[
                  Glyph(
                    up ? AppIcons.caretUp : AppIcons.caretDown,
                    size: 12,
                    color: good ? AppColors.accent : AppColors.error,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${Fmt.rating(change!.abs())}%',
                    style: text.bodySmall?.copyWith(
                      color: good ? AppColors.accent : AppColors.error,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Wybór jednej opcji z kilku, jak zakładki w pigułce.
class SegmentedTabs<T> extends StatelessWidget {
  const SegmentedTabs({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final List<(T, String)> options;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (value, label) in options)
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => onChanged(value),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  curve: AppMotion.standard,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    // Ten sam kolor z inną przezroczystością, żeby przejście
                    // nie przechodziło przez szarość ani czerń.
                    color: AppColors.surface.withValues(
                      alpha: value == selected ? 1 : 0,
                    ),
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.accent.withValues(
                          alpha: value == selected ? 1 : 0,
                        ),
                        blurRadius: 0,
                        spreadRadius: 1,
                      ),
                      // Wybrana opcja unosi się nad pigułką.
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: value == selected ? 0.35 : 0,
                        ),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    label,
                    style: text.labelLarge?.copyWith(
                      color: value == selected
                          ? AppColors.text
                          : AppColors.textMuted,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Informacja zamiast funkcji dostępnej tylko w planie Pro.
class ProGate extends StatelessWidget {
  const ProGate({super.key, required this.feature});

  final String feature;

  @override
  Widget build(BuildContext context) {
    return MessageView(
      icon: AppIcons.lock,
      title: '$feature w planie Pro',
      message:
          'Ten lokal ma plan darmowy: goście rezerwują przez przycisk „Zadzwoń”. '
          'Plan Pro włącza rezerwacje w aplikacji, plan sali i automatyczny dobór stolików.',
    );
  }
}

/// Pasek informujący, że rola pracownika pozwala tylko na podgląd.
class ReadOnlyBanner extends StatelessWidget {
  const ReadOnlyBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(32, 0, 32, 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Glyph(AppIcons.lock, size: 16, color: AppColors.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Okno potwierdzenia. Zwraca true po wybraniu akcji.
Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SizedBox(width: 380, child: Text(message)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
          child: const Text('Anuluj'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          style: destructive
              ? TextButton.styleFrom(foregroundColor: AppColors.error)
              : null,
          child: Text(action),
        ),
      ],
    ),
  );
  return result == true;
}

/// Liczba całkowita z pola tekstowego albo null.
int? parseInt(String text) => int.tryParse(text.trim());

/// Kwota w złotych z pola tekstowego („12,50” albo „12.5”) w groszach.
int? parseGrosze(String text) {
  final normalized = text.trim().replaceAll(' ', '').replaceAll(',', '.');
  final value = double.tryParse(normalized);
  if (value == null || value < 0) return null;
  return (value * 100).round();
}

String groszeToText(int grosze) {
  final zl = grosze ~/ 100;
  final gr = grosze % 100;
  return gr == 0 ? '$zl' : '$zl,${gr.toString().padLeft(2, '0')}';
}

/// Wybór godziny: dwie wąskie kolumny, godziny i minuty. Zwraca null po anulowaniu.
Future<TimeOfDay?> pickTime(
  BuildContext context, {
  required TimeOfDay initial,
  int minuteStep = 15,
}) {
  return showDialog<TimeOfDay>(
    context: context,
    builder: (_) => _TimeDialog(initial: initial, minuteStep: minuteStep),
  );
}

class _TimeDialog extends StatefulWidget {
  const _TimeDialog({required this.initial, required this.minuteStep});

  final TimeOfDay initial;
  final int minuteStep;

  @override
  State<_TimeDialog> createState() => _TimeDialogState();
}

class _TimeDialogState extends State<_TimeDialog> {
  static const _itemHeight = 34.0;

  late int _hour = widget.initial.hour;
  late int _minute = widget.initial.minute;
  late final List<int> _minutes = <int>{
    for (var m = 0; m < 60; m += widget.minuteStep) m,
    widget.initial.minute,
  }.toList()..sort();

  // Wybrana wartość od razu w środku listy.
  late final _hours = ScrollController(initialScrollOffset: math.max(0, (_hour - 2) * _itemHeight));
  late final _mins = ScrollController(
    initialScrollOffset: math.max(0, (_minutes.indexOf(_minute) - 2) * _itemHeight),
  );

  @override
  void dispose() {
    _hours.dispose();
    _mins.dispose();
    super.dispose();
  }

  String _two(int v) => v.toString().padLeft(2, '0');

  Widget _column(ScrollController controller, List<int> values, int selected, ValueChanged<int> onTap) {
    final text = Theme.of(context).textTheme;
    return SizedBox(
      width: 64,
      height: _itemHeight * 5,
      child: ListView.builder(
        controller: controller,
        itemExtent: _itemHeight,
        itemCount: values.length,
        itemBuilder: (context, i) {
          final v = values[i];
          final isSelected = v == selected;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Material(
              color: isSelected ? AppColors.accentFill : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => onTap(v),
                child: Center(
                  child: Text(
                    _two(v),
                    style: text.bodyLarge?.copyWith(
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                      color: isSelected ? AppColors.onAccent : AppColors.text,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Dialog(
      child: SizedBox(
        width: 216,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${_two(_hour)}:${_two(_minute)}',
                style: text.headlineMedium?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _column(_hours, [for (var h = 0; h < 24; h++) h], _hour, (v) => setState(() => _hour = v)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(':', style: text.titleMedium?.copyWith(color: AppColors.textMuted)),
                  ),
                  _column(_mins, _minutes, _minute, (v) => setState(() => _minute = v)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
                    child: const Text('Anuluj'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, TimeOfDay(hour: _hour, minute: _minute)),
                    child: const Text('OK'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
