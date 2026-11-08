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

/// Okno od dołu w stylu iOS (10.2026, wzór od użytkownika: wybór sposobu zamówienia z aplikacji McDonald's):
/// karta na całą szerokość telefonu aż do dołu ekranu, zaokrąglona u góry (1.11.2026, prośba użytkownika; wcześniej
/// odsunięta od krawędzi), okrągłe „Zamknij” w lewym górnym rogu (na iOS 26 szkło Liquid Glass), duży tytuł i opis.
/// Treść kończy się nad paskiem systemu, a tło karty sięga pod niego. Tak wyglądają wszystkie okna w Table i Table for employees (od 31.10.2026): pytania
/// ([showConfirmSheet]), wybór ([showOptionSheet]), komunikaty ([showMessageSheet]), wpisanie tekstu
/// ([showTextSheet]) i większe okna z własną treścią ([showTableSheet]).
class TableSheet extends StatelessWidget {
  const TableSheet({
    super.key,
    required this.child,
    this.title,
    this.message,
    this.icon,
    this.iconColor,
    this.scrollable = true,
    this.avoidKeyboard = true,
  });

  /// Treść pod tytułem.
  final Widget child;
  final String? title;
  final String? message;

  /// Duża ikona nad tytułem (komunikaty).
  final AppIconData? icon;
  final Color? iconColor;

  /// Tytuł i treść przewijają się razem. False: treść sama się przewija (np. lista) i ma własne odstępy.
  final bool scrollable;

  /// Karta podnosi się nad klawiaturę. False: treść robi to sama.
  final bool avoidKeyboard;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final dark = AppColors.palette.brightness == Brightness.dark;
    final head = <Widget>[
      if (icon case final i?) ...[
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Glyph(i.duotone, size: 48, color: iconColor ?? AppColors.accent),
          ),
        ),
        const SizedBox(height: 12),
      ],
      if (title case final t?)
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Semantics(
            header: true,
            child: Text(t, style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
          ),
        ),
      if (message case final m?) ...[
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(m, style: text.bodyLarge?.copyWith(color: AppColors.textMuted)),
        ),
      ],
      if (title != null || message != null) const SizedBox(height: 22),
    ];
    final Widget body = scrollable
        ? SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 20, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [...head, child],
            ),
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (head.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 20, 0),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: head),
                ),
              Flexible(child: child),
            ],
          );
    return Padding(
      padding: EdgeInsets.only(bottom: avoidKeyboard ? MediaQuery.viewInsetsOf(context).bottom : 0),
      child: Material(
        color: dark ? AppColors.surfaceRaised : AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(36)),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          // Pasek systemu na dole (przy otwartej klawiaturze zero, bo wtedy karta stoi nad nią).
          padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
          // Ramka już odsunęła treść od paska systemu, więc treść nie dolicza go drugi raz (viewPadding).
          child: MediaQuery.removeViewPadding(
            context: context,
            removeBottom: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 18),
                  child: Align(alignment: Alignment.centerLeft, child: _SheetClose()),
                ),
                Flexible(child: body),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Okno od dołu z własną treścią (np. filtry, koszyk, zamknięcie rachunku) w ramce [TableSheet]: „Zamknij” u góry,
/// a treść z [builder] sama ma odstępy, przewijanie i miejsce na klawiaturę.
Future<T?> showTableSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isDismissible = true,
  bool enableDrag = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    backgroundColor: Colors.transparent,
    elevation: 0,
    builder: (context) => TableSheet(scrollable: false, avoidKeyboard: false, child: builder(context)),
  );
}

Future<T?> _sheet<T>(BuildContext context, WidgetBuilder builder) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  elevation: 0,
  builder: builder,
);

/// Wybór jednej z opcji: wiersze z ikoną i strzałką. Zwraca wartość wybranej opcji albo null po zamknięciu.
Future<T?> showOptionSheet<T>({
  required BuildContext context,
  required String title,
  required List<SheetOption<T>> options,
  String? message,
}) {
  return _sheet<T>(
    context,
    (context) => TableSheet(
      title: title,
      message: message,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, o) in options.indexed) ...[
            if (i > 0) const SizedBox(height: 12),
            _OptionRow(option: o, onTap: () => Navigator.pop(context, o.value)),
          ],
        ],
      ),
    ),
  );
}

/// Pytanie przed działaniem (np. „Odwołać rezerwację?”): jedna opcja z ikoną, zamknięcie to „nie”.
/// True: potwierdzone.
Future<bool> showConfirmSheet({
  required BuildContext context,
  required String title,
  required String action,
  required AppIconData icon,
  String? message,
  String? actionHint,
  Color? color,
}) async {
  final ok = await showOptionSheet<bool>(
    context: context,
    title: title,
    message: message,
    options: [SheetOption(value: true, icon: icon, title: action, subtitle: actionHint, color: color)],
  );
  return ok ?? false;
}

/// Komunikat: duża ikona, tytuł, opis i jeden przycisk (np. „Zmiana zakończona”).
Future<void> showMessageSheet({
  required BuildContext context,
  required String title,
  required String message,
  AppIconData? icon,
  Color? color,
  String button = 'Gotowe',
}) {
  return _sheet<void>(
    context,
    (context) => TableSheet(
      title: title,
      message: message,
      icon: icon,
      iconColor: color,
      child: FilledButton(
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        onPressed: () => Navigator.pop(context),
        child: Text(button),
      ),
    ),
  );
}

/// Wpisanie krótkiego tekstu (np. uwaga na tydzień). Zwraca tekst po „Zapisz” albo null po zamknięciu.
Future<String?> showTextSheet({
  required BuildContext context,
  required String title,
  required String label,
  String? message,
  String initial = '',
  String? hint,
  int maxLength = 300,
  String action = 'Zapisz',
}) {
  return _sheet<String>(
    context,
    (_) => _TextSheet(
      title: title,
      message: message,
      label: label,
      initial: initial,
      hint: hint,
      maxLength: maxLength,
      action: action,
    ),
  );
}

class _TextSheet extends StatefulWidget {
  const _TextSheet({
    required this.title,
    required this.label,
    required this.initial,
    required this.maxLength,
    required this.action,
    this.message,
    this.hint,
  });

  final String title;
  final String? message;
  final String label;
  final String initial;
  final String? hint;
  final int maxLength;
  final String action;

  @override
  State<_TextSheet> createState() => _TextSheetState();
}

class _TextSheetState extends State<_TextSheet> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TableSheet(
    title: widget.title,
    message: widget.message,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          autofocus: true,
          maxLength: widget.maxLength,
          maxLines: 3,
          minLines: 1,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: widget.label, hintText: widget.hint),
        ),
        const SizedBox(height: 12),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: Text(widget.action),
        ),
      ],
    ),
  );
}

/// „Zamknij” w oknie od dołu. Na iOS 26 i nowszym natywny Liquid Glass (8.11.2026, prośba użytkownika), ale tylko
/// gdy okno już wjechało i nic go nie przykrywa. W czasie wjazdu, wyjazdu i pod drugim oknem (np. kółka godzin nad
/// „Zgłoś godziny”) szkło rysowane przez Fluttera: natywny widok w takim miejscu psuł na iPhonie rysowanie treści
/// okna (puste kółka godzin, 1.11.2026). Poza iOS 26 [_CloseCircle].
class _SheetClose extends StatefulWidget {
  const _SheetClose();

  @override
  State<_SheetClose> createState() => _SheetCloseState();
}

class _SheetCloseState extends State<_SheetClose> {
  Animation<double>? _animation;
  bool _settled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animation = ModalRoute.of(context)?.animation;
    if (animation != _animation) {
      _animation?.removeStatusListener(_onStatus);
      _animation = animation?..addStatusListener(_onStatus);
      _settled = (animation?.status ?? AnimationStatus.completed) == AnimationStatus.completed;
    }
  }

  void _onStatus(AnimationStatus status) {
    final settled = status == AnimationStatus.completed;
    if (settled != _settled && mounted) setState(() => _settled = settled);
  }

  @override
  void dispose() {
    _animation?.removeStatusListener(_onStatus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final native = _settled && (ModalRoute.of(context)?.isCurrent ?? true);
    void close() => Navigator.maybePop(context);
    return GlassIconButton(
      symbol: 'xmark',
      icon: native ? null : AppIcons.close,
      native: native,
      label: 'Zamknij',
      onTap: close,
      fallback: _CloseCircle(onTap: close),
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
