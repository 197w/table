import 'package:material_ui/material_ui.dart';

import 'app_icons.dart';
import 'theme.dart';
import 'widgets.dart' show errorText;

/// Rodzaj powiadomienia: kolor i ikona.
enum ToastTone { info, success, warning, error }

/// Powiadomienie w stylu Table: karta z ikoną, treścią, paskiem czasu i opcjonalnym przyciskiem.
/// Na komputerze pojawia się w prawym dolnym rogu, na telefonie u góry ekranu.
void showMessage(
  BuildContext context,
  String message, {
  ToastTone tone = ToastTone.info,
  String? title,
  AppIconData? icon,
  String? actionLabel,
  VoidCallback? onAction,
  Duration? duration,
}) {
  Toasts.instance.show(
    message,
    tone: tone,
    title: title,
    icon: icon,
    actionLabel: actionLabel,
    onAction: onAction,
    duration: duration,
  );
}

/// Błąd jako czerwone powiadomienie, z polskim komunikatem z [errorText].
void showError(BuildContext context, Object error) =>
    showMessage(context, errorText(error), tone: ToastTone.error);

class _Toast {
  _Toast({
    required this.id,
    required this.message,
    required this.tone,
    required this.duration,
    this.title,
    this.icon,
    this.actionLabel,
    this.onAction,
  });

  final int id;
  final String message;
  final String? title;
  final ToastTone tone;
  final AppIconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Duration duration;

  /// Powiadomienie znika (animacja wyjścia), potem wypada z listy.
  final leaving = ValueNotifier(false);

  /// To samo powiadomienie pokazane jeszcze raz: czas liczy się od nowa.
  final repeats = ValueNotifier(0);
}

/// Lista powiadomień całej aplikacji. Pokazuje je [ToastHost].
class Toasts extends ChangeNotifier {
  Toasts._();

  static final instance = Toasts._();

  /// Najwyżej tyle powiadomień naraz. Najstarsze znika, gdy przychodzi nowe.
  static const maxVisible = 3;

  final List<_Toast> _items = [];
  int _nextId = 0;

  List<_Toast> get _visible => [for (final t in _items) if (!t.leaving.value) t];

  void show(
    String message, {
    ToastTone tone = ToastTone.info,
    String? title,
    AppIconData? icon,
    String? actionLabel,
    VoidCallback? onAction,
    Duration? duration,
  }) {
    // Ten sam komunikat drugi raz nie dubluje karty, tylko odświeża jej czas.
    for (final t in _visible) {
      if (t.message == message && t.title == title && t.tone == tone) {
        t.repeats.value++;
        return;
      }
    }
    final visible = _visible;
    if (visible.length >= maxVisible) visible.first.leaving.value = true;
    // Czas czytania rośnie z długością tekstu. Błędy wiszą dłużej.
    final reading = 2600 + (message.length + (title?.length ?? 0)) * 45;
    _items.add(
      _Toast(
        id: _nextId++,
        message: message,
        title: title,
        tone: tone,
        icon: icon,
        actionLabel: actionLabel,
        onAction: onAction,
        duration: duration ??
            Duration(milliseconds: reading.clamp(3500, 9000) + (tone == ToastTone.error ? 1500 : 0)),
      ),
    );
    notifyListeners();
  }

  /// Zamyka wszystkie powiadomienia.
  void clear() {
    for (final t in _items) {
      t.leaving.value = true;
    }
  }

  void _remove(int id) {
    _items.removeWhere((t) => t.id == id);
    notifyListeners();
  }
}

/// Warstwa z powiadomieniami nad całą aplikacją. Wstaw raz: `MaterialApp(builder: (context, child) =>
/// ToastHost(child: child!))`. Szeroki ekran (komputer): prawy dolny róg, najnowsze na dole.
/// Wąski (telefon): góra ekranu, najnowsze na górze.
class ToastHost extends StatefulWidget {
  const ToastHost({super.key, required this.child});

  final Widget child;

  @override
  State<ToastHost> createState() => _ToastHostState();
}

class _ToastHostState extends State<ToastHost> {
  @override
  void initState() {
    super.initState();
    Toasts.instance.addListener(_changed);
  }

  @override
  void dispose() {
    Toasts.instance.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 700;
    final items = Toasts.instance._items;
    final cards = [
      for (final t in wide ? items : items.reversed)
        _ToastView(key: ValueKey(t.id), toast: t, wide: wide, onGone: () => Toasts.instance._remove(t.id)),
    ];
    return Stack(
      children: [
        widget.child,
        if (cards.isNotEmpty)
          Positioned(
            left: wide ? null : 0,
            right: 0,
            top: wide ? null : 0,
            bottom: wide ? 0 : null,
            child: SafeArea(
              top: !wide,
              bottom: wide,
              child: Padding(
                padding: wide ? const EdgeInsets.fromLTRB(0, 0, 20, 12) : const EdgeInsets.fromLTRB(12, 6, 12, 0),
                child: Material(
                  type: MaterialType.transparency,
                  child: Align(
                    alignment: wide ? Alignment.bottomRight : Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: wide ? 400 : 520),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: cards,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ToastView extends StatefulWidget {
  const _ToastView({super.key, required this.toast, required this.wide, required this.onGone});

  final _Toast toast;
  final bool wide;
  final VoidCallback onGone;

  @override
  State<_ToastView> createState() => _ToastViewState();
}

class _ToastViewState extends State<_ToastView> with TickerProviderStateMixin {
  late final _presence = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    reverseDuration: const Duration(milliseconds: 240),
  );
  late final _countdown = AnimationController(vsync: this, duration: widget.toast.duration);
  late final _curve = CurvedAnimation(parent: _presence, curve: AppMotion.easeOut, reverseCurve: Curves.easeInCubic);
  bool _hovered = false;
  bool _swiped = false;

  @override
  void initState() {
    super.initState();
    widget.toast.leaving.addListener(_leave);
    widget.toast.repeats.addListener(_restart);
    _countdown.addStatusListener((status) {
      if (status == AnimationStatus.completed) widget.toast.leaving.value = true;
    });
    // Powiadomienie, które znikało, gdy warstwa się przebudowała (np. zmiana motywu): tylko je usuwamy.
    if (widget.toast.leaving.value) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onGone();
      });
      return;
    }
    _presence.forward();
    _countdown.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Przy ograniczeniu ruchu karta pojawia się i znika bez przesuwania.
    if (MediaQuery.disableAnimationsOf(context)) {
      _presence.duration = Duration.zero;
      _presence.reverseDuration = Duration.zero;
    }
  }

  @override
  void dispose() {
    widget.toast.leaving.removeListener(_leave);
    widget.toast.repeats.removeListener(_restart);
    _curve.dispose();
    _countdown.dispose();
    _presence.dispose();
    super.dispose();
  }

  void _restart() {
    _countdown.forward(from: 0);
    if (_hovered) _countdown.stop();
  }

  Future<void> _leave() async {
    if (!widget.toast.leaving.value || _swiped) return;
    _countdown.stop();
    await _presence.reverse();
    if (mounted) widget.onGone();
  }

  void _dismiss() => widget.toast.leaving.value = true;

  void _hover(bool value) {
    setState(() => _hovered = value);
    // Najechanie myszą wstrzymuje odliczanie, żeby dało się spokojnie przeczytać.
    if (value) {
      _countdown.stop();
    } else if (!widget.toast.leaving.value) {
      _countdown.forward();
    }
  }

  (Color, AppIconData) get _look => switch (widget.toast.tone) {
    ToastTone.success => (AppColors.accent, AppIcons.checkCircle),
    ToastTone.warning => (AppColors.warning, AppIcons.warning),
    ToastTone.error => (AppColors.error, AppIcons.warning),
    ToastTone.info => (AppColors.accent, AppIcons.info),
  };

  @override
  Widget build(BuildContext context) {
    final t = widget.toast;
    final wide = widget.wide;
    final (color, defaultIcon) = _look;
    final text = Theme.of(context).textTheme;
    final dark = AppColors.palette.brightness == Brightness.dark;

    final card = MouseRegion(
      onEnter: (_) => _hover(true),
      onExit: (_) => _hover(false),
      child: AnimatedScale(
        scale: _hovered ? 1.01 : 1,
        duration: const Duration(milliseconds: 180),
        curve: AppMotion.easeOut,
        child: Container(
          decoration: BoxDecoration(
            color: dark ? AppColors.surfaceRaised : AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: dark ? AppColors.ringStrong : AppColors.ring),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? 0.45 : 0.12),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: Stack(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(12, 12, t.actionLabel == null ? 8 : 4, 14),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: Alignment.center,
                        child: Glyph((t.icon ?? defaultIcon).duotone, size: 19, color: color),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (t.title != null)
                              Text(t.title!, style: text.titleSmall?.copyWith(color: AppColors.text)),
                            Text(
                              t.message,
                              style: text.bodyMedium?.copyWith(
                                color: t.title == null ? AppColors.text : AppColors.textMuted,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (t.actionLabel != null) ...[
                        const SizedBox(width: 6),
                        TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.accent,
                            minimumSize: const Size(0, 36),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                          onPressed: () {
                            t.onAction?.call();
                            _dismiss();
                          },
                          child: Text(t.actionLabel!),
                        ),
                      ],
                      if (wide)
                        _CloseButton(onTap: _dismiss)
                      else
                        const SizedBox(width: 4),
                    ],
                  ),
                ),
                // Pasek czasu: kurczy się do zera, wtedy powiadomienie znika.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: AnimatedBuilder(
                    animation: _countdown,
                    builder: (context, _) => Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: 1 - _countdown.value,
                        child: Container(height: 2.5, color: color.withValues(alpha: _hovered ? 0.35 : 0.8)),
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

    return SizeTransition(
      sizeFactor: _curve,
      alignment: wide ? Alignment.bottomCenter : Alignment.topCenter,
      child: FadeTransition(
        opacity: _curve,
        child: SlideTransition(
          position: Tween(
            begin: wide ? const Offset(0.25, 0) : const Offset(0, -0.6),
            end: Offset.zero,
          ).animate(_curve),
          child: ScaleTransition(
            scale: Tween(begin: 0.94, end: 1.0).animate(_curve),
            child: Padding(
              padding: EdgeInsets.only(top: wide ? 10 : 0, bottom: wide ? 0 : 8),
              child: Semantics(
                liveRegion: true,
                child: Dismissible(
                  key: ValueKey('toast-${t.id}'),
                  direction: wide ? DismissDirection.startToEnd : DismissDirection.up,
                  onDismissed: (_) {
                    _swiped = true;
                    t.leaving.value = true;
                    widget.onGone();
                  },
                  child: GestureDetector(
                    // Na telefonie stuknięcie zamyka powiadomienie.
                    onTap: wide ? null : _dismiss,
                    child: card,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CloseButton extends StatefulWidget {
  const _CloseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_CloseButton> createState() => _CloseButtonState();
}

class _CloseButtonState extends State<_CloseButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Zamknij powiadomienie',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 30,
            height: 30,
            margin: const EdgeInsets.only(left: 2),
            decoration: BoxDecoration(
              color: _hovered ? AppColors.ring : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Glyph(AppIcons.close, size: 14, color: _hovered ? AppColors.text : AppColors.textMuted),
          ),
        ),
      ),
    );
  }
}
