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
    this.padding = const EdgeInsets.all(20),
  });

  final String? title;
  final Widget? trailing;
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

/// Liczba z opisem, na przykład „14 gości”.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.hint,
    this.accent = false,
  });

  final String label;
  final String value;
  final AppIconData? icon;
  final String? hint;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Glyph(icon!, size: 16, color: AppColors.textMuted),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: text.headlineMedium?.copyWith(
                color: accent ? AppColors.accent : AppColors.text,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            // Wiersz podpisu jest zawsze, żeby kafelki w rzędzie miały równą wysokość.
            Text(
              hint ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.bodySmall?.copyWith(color: AppColors.textMuted),
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
                    color: value == selected
                        ? AppColors.surface
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: value == selected
                        ? [BoxShadow(color: AppColors.ring, blurRadius: 0, spreadRadius: 1)]
                        : null,
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

/// Wybór godziny jako siatka godzin i minut. Czytelniejszy niż systemowa tarcza zegara.
Future<TimeOfDay?> pickTime(
  BuildContext context, {
  required TimeOfDay initial,
  String title = 'Wybierz godzinę',
  int minuteStep = 15,
}) {
  return showDialog<TimeOfDay>(
    context: context,
    builder: (_) => _TimeGridDialog(
      initial: initial,
      title: title,
      minuteStep: minuteStep,
    ),
  );
}

class _TimeGridDialog extends StatefulWidget {
  const _TimeGridDialog({
    required this.initial,
    required this.title,
    required this.minuteStep,
  });

  final TimeOfDay initial;
  final String title;
  final int minuteStep;

  @override
  State<_TimeGridDialog> createState() => _TimeGridDialogState();
}

class _TimeGridDialogState extends State<_TimeGridDialog> {
  late int _hour = widget.initial.hour;
  late int _minute = widget.initial.minute;

  String _two(int v) => v.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final minutes = <int>{
      for (var m = 0; m < 60; m += widget.minuteStep) m,
      widget.initial.minute,
    }.toList()
      ..sort();

    Widget cell(String label, bool selected, VoidCallback onTap) {
      return Material(
        color: selected ? AppColors.accentFill : AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Center(
            child: Text(
              label,
              style: text.titleSmall?.copyWith(
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? AppColors.onAccent : AppColors.text,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      );
    }

    Widget grid(List<Widget> children) => GridView.count(
      crossAxisCount: 6,
      shrinkWrap: true,
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      childAspectRatio: 1.6,
      physics: const NeverScrollableScrollPhysics(),
      children: children,
    );

    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text(widget.title)),
          Text(
            '${_two(_hour)}:${_two(_minute)}',
            style: text.headlineMedium?.copyWith(
              color: AppColors.accent,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Godzina', style: text.labelLarge?.copyWith(color: AppColors.textMuted)),
            const SizedBox(height: 8),
            grid([
              for (var h = 0; h < 24; h++)
                cell(_two(h), h == _hour, () => setState(() => _hour = h)),
            ]),
            const SizedBox(height: 16),
            Text('Minuty', style: text.labelLarge?.copyWith(color: AppColors.textMuted)),
            const SizedBox(height: 8),
            grid([
              for (final m in minutes)
                cell(_two(m), m == _minute, () => setState(() => _minute = m)),
            ]),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
          child: const Text('Anuluj'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, TimeOfDay(hour: _hour, minute: _minute)),
          child: const Text('Wybierz'),
        ),
      ],
    );
  }
}
