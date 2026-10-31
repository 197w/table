import 'package:material_ui/material_ui.dart';

import 'app_icons.dart';
import 'liquid_glass.dart';
import 'theme.dart';
import 'widgets.dart';

/// Opcja w [showOptionSheet]: ikona w kolorowym kafelku, nazwa, opis i strzałka.
class SheetOption<T> {
  const SheetOption({required this.value, required this.icon, required this.title, this.subtitle, this.color});

  final T value;
  final AppIconData icon;
  final String title;
  final String? subtitle;

  /// Kolor ikony i jej kafelka. Null: akcent.
  final Color? color;
}

/// Okno od dołu w stylu iOS (10.2026, wzór od użytkownika: wybór sposobu zamówienia): zaokrąglona karta
/// odsunięta od krawędzi ekranu, okrągłe „Zamknij” w lewym górnym rogu (na iOS 26 Liquid Glass), duży tytuł,
/// opis i opcje jako wiersze z ikoną i strzałką. Zwraca wartość wybranej opcji albo null po zamknięciu.
Future<T?> showOptionSheet<T>({
  required BuildContext context,
  required String title,
  required List<SheetOption<T>> options,
  String? message,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    elevation: 0,
    builder: (context) => _OptionSheet<T>(title: title, message: message, options: options),
  );
}

/// Komunikat w tym samym oknie od dołu: duża ikona, tytuł, opis i jeden przycisk (np. „Zmiana zakończona”).
Future<void> showMessageSheet({
  required BuildContext context,
  required String title,
  required String message,
  AppIconData? icon,
  Color? color,
  String button = 'Gotowe',
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    elevation: 0,
    builder: (context) => _OptionSheet<void>(
      title: title,
      message: message,
      options: const [],
      icon: icon,
      color: color,
      button: button,
    ),
  );
}

class _OptionSheet<T> extends StatelessWidget {
  const _OptionSheet({
    required this.title,
    required this.options,
    this.message,
    this.icon,
    this.color,
    this.button,
  });

  final String title;
  final String? message;
  final List<SheetOption<T>> options;

  /// Komunikat: duża ikona nad tytułem i przycisk na dole.
  final AppIconData? icon;
  final Color? color;
  final String? button;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final dark = AppColors.palette.brightness == Brightness.dark;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      child: Material(
        color: dark ? AppColors.surfaceRaised : AppColors.surface,
        borderRadius: BorderRadius.circular(36),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 20, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: GlassIconButton(
                  symbol: 'xmark',
                  label: 'Zamknij',
                  native: true,
                  onTap: () => Navigator.maybePop(context),
                  fallback: _CloseCircle(onTap: () => Navigator.maybePop(context)),
                ),
              ),
              const SizedBox(height: 18),
              if (icon case final i?) ...[
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Glyph(i.duotone, size: 48, color: color ?? AppColors.accent),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Semantics(
                  header: true,
                  child: Text(title, style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
                ),
              ),
              if (message case final m?) ...[
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text(m, style: text.bodyLarge?.copyWith(color: AppColors.textMuted)),
                ),
              ],
              const SizedBox(height: 22),
              for (final (i, o) in options.indexed) ...[
                if (i > 0) const SizedBox(height: 12),
                _OptionRow(option: o, onTap: () => Navigator.pop(context, o.value)),
              ],
              if (button case final b?)
                FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  onPressed: () => Navigator.pop(context),
                  child: Text(b),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Okrągłe „Zamknij” rysowane przez Fluttera (Android i iOS przed 26).
class _CloseCircle extends StatelessWidget {
  const _CloseCircle({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.palette.brightness == Brightness.dark;
    return Semantics(
      button: true,
      label: 'Zamknij',
      excludeSemantics: true,
      child: PressScale(
        onTap: onTap,
        child: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.surface,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.ringStrong),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF000000).withValues(alpha: dark ? 0.35 : 0.10),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Glyph(AppIcons.close, size: 22, color: AppColors.text),
        ),
      ),
    );
  }
}

class _OptionRow<T> extends StatelessWidget {
  const _OptionRow({required this.option, required this.onTap});

  final SheetOption<T> option;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final color = option.color ?? AppColors.accent;
    return Semantics(
      button: true,
      label: [option.title, ?option.subtitle].join('. '),
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: AppColors.ringStrong, width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 72),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Glyph(option.icon.duotone, size: 26, color: color),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(option.title, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                        if (option.subtitle case final s?)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(s, style: text.bodyMedium?.copyWith(color: AppColors.textMuted)),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Glyph(AppIcons.caretRight, size: 22, color: AppColors.text),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
