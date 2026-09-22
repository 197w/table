import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

/// Naciśnięcie lekko zmniejsza element, więc panel od razu odpowiada na kliknięcie.
/// Nasłuchuje wskaźnika obok własnych gestów dziecka, więc nie przejmuje kliknięć.
class PanelPress extends StatefulWidget {
  const PanelPress({super.key, required this.child, this.scale = 0.96});

  final Widget child;
  final double scale;

  @override
  State<PanelPress> createState() => _PanelPressState();
}

class _PanelPressState extends State<PanelPress> {
  bool _pressed = false;

  void _set(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    // Przy włączonym ograniczeniu ruchu zostaje sam kolor, bez skalowania.
    final still = MediaQuery.disableAnimationsOf(context);
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _pressed && !still ? widget.scale : 1,
        duration: const Duration(milliseconds: 140),
        curve: AppMotion.easeOut,
        child: widget.child,
      ),
    );
  }
}

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(32, 28, 32, below == null ? 20 : 16),
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
                    PanelPress(child: actions[i]),
                  ],
                ],
              ),
              if (below != null) ...[const SizedBox(height: 16), below!],
            ],
          ),
        ),
        // Cienka linia oddziela nagłówek z filtrami od treści strony.
        // W jasnym motywie sam pierścień ginie na białym tle.
        Divider(
          height: 1,
          thickness: 1,
          color: AppColors.palette.brightness == Brightness.dark
              ? AppColors.ring
              : AppColors.ringStrong,
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

/// Pigułka z tekstem, na przykład „Na żywo”. Z kropką, gdy coś się dzieje samo.
class PanelPill extends StatelessWidget {
  const PanelPill(this.label, {super.key, this.icon, this.dotColor});

  final String label;
  final AppIconData? icon;
  final Color? dotColor;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.ring),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dotColor != null) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
          ],
          if (icon != null) ...[
            Glyph(icon!, size: 14, color: AppColors.textMuted),
            const SizedBox(width: 6),
          ],
          Text(label, style: text.labelLarge?.copyWith(color: AppColors.textMuted)),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null) ...[
            Padding(
              padding: EdgeInsets.fromLTRB(padding.left, 16, padding.right, 16),
              child: Row(
                children: [
                  if (icon != null) ...[
                    IconBadge(icon!, color: iconColor ?? AppColors.accentFill),
                    const SizedBox(width: 10),
                  ],
                  Expanded(child: Text(title!, style: text.titleMedium)),
                  ?trailing,
                ],
              ),
            ),
            // Linia oddziela nagłówek karty od jej treści, na całą szerokość.
            Divider(height: 1, thickness: 1, color: AppColors.ring),
          ],
          Padding(
            padding: title == null
                ? padding
                : EdgeInsets.fromLTRB(padding.left, 18, padding.right, padding.bottom),
            child: child,
          ),
        ],
      ),
    );
  }
}

/// Przycisk z samą ikoną do akcji w nagłówku, na przykład „Nowa rezerwacja”.
/// W ciemnym motywie jest biały z białą poświatą: ikona główna w kolorze marki,
/// pozostałe szare. W jasnym motywie główny jest miętowy, a reszta obrysowana.
class GlowButton extends StatelessWidget {
  const GlowButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.primary = false,
    this.iconSize = 18,
  });

  final AppIconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  /// Najważniejsza akcja na ekranie.
  final bool primary;
  final double iconSize;

  /// Szara ikona na białym przycisku w ciemnym motywie.
  static const _grey = Color(0xFF7A7A7A);

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.palette.brightness == Brightness.dark;
    const radius = BorderRadius.all(Radius.circular(12));

    final Color background;
    final Color iconColor;
    final List<BoxShadow> glow;
    BorderSide side = BorderSide.none;
    if (dark) {
      background = Colors.white;
      // Na białym tle jasna mięta ginie, więc marka występuje w ciemniejszym odcieniu.
      iconColor = primary ? AppPalette.light.accent : _grey;
      glow = [
        BoxShadow(color: Colors.white.withValues(alpha: 0.28), blurRadius: 16),
      ];
    } else if (primary) {
      background = AppColors.accentFill;
      iconColor = AppColors.onAccent;
      glow = [
        BoxShadow(
          color: AppColors.accentFill.withValues(alpha: 0.45),
          blurRadius: 12,
          offset: const Offset(0, 3),
        ),
      ];
    } else {
      background = AppColors.background;
      iconColor = AppColors.textMuted;
      side = BorderSide(color: AppColors.ringStrong);
      glow = [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.08),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ];
    }

    return Tooltip(
      message: tooltip,
      child: DecoratedBox(
        decoration: BoxDecoration(borderRadius: radius, boxShadow: glow),
        child: Material(
          color: background,
          shape: RoundedRectangleBorder(borderRadius: radius, side: side),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: SizedBox(
              width: 44,
              height: 40,
              child: Center(child: Glyph(icon, size: iconSize, color: iconColor)),
            ),
          ),
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
    final flat = change == null || change!.abs() < 0.05;
    final up = (change ?? 0) >= 0;
    final good = up == moreIsBetter;
    final changeColor = flat
        ? AppColors.textMuted
        : (good ? AppColors.accent : AppColors.error);

    return Card(
      // Kafelek leży na karcie, więc jest o ton jaśniejszy od niej
      // i ma mniejszy promień, żeby narożniki nie były współśrodkowe.
      color: AppColors.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.ringStrong),
      ),
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
                  if (!flat) ...[
                    Glyph(
                      up ? AppIcons.caretUp : AppIcons.caretDown,
                      size: 12,
                      color: changeColor,
                    ),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    flat ? 'bez zmian' : '${Fmt.rating(change!.abs())}%',
                    style: text.bodySmall?.copyWith(
                      color: changeColor,
                      fontWeight: flat ? null : FontWeight.w600,
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
                child: PanelPress(
                  scale: 0.96,
                  child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  curve: AppMotion.easeOut,
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
