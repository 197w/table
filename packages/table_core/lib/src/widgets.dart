import 'package:material_ui/material_ui.dart';

import 'app_icons.dart';
import 'failure.dart';
import 'formatters.dart';
import 'theme.dart';

/// Wiadomość błędu gotowa do pokazania użytkownikowi.
String errorText(Object error) => error is AppFailure
    ? error.message
    : 'Coś poszło nie tak. Spróbuj ponownie.';

/// Delikatne zmniejszenie przy naciśnięciu: 0.96, 150 ms, ease-out.
class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _pressed = false;

  void _set(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: widget.onTap == null ? null : (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      child: AnimatedScale(
        scale: _pressed && !reduceMotion ? 0.96 : 1,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox.square(
        dimension: 28,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: AppColors.accent,
        ),
      ),
    );
  }
}

class MessageView extends StatelessWidget {
  const MessageView({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final AppIconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Glyph(icon.duotone, size: 44, color: AppColors.textMuted),
            const SizedBox(height: 16),
            Text(title, style: text.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              message,
              style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              SizedBox(
                width: 240,
                child: OutlinedButton(
                  onPressed: onAction,
                  child: Text(actionLabel!),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return MessageView(
      icon: AppIcons.wifiOff,
      title: 'Nie udało się wczytać',
      message: errorText(error),
      actionLabel: 'Spróbuj ponownie',
      onAction: onRetry,
    );
  }
}

/// Ocena kuchni. Pokazuje się tylko przy zweryfikowanych opiniach.
class FoodScore extends StatelessWidget {
  const FoodScore({
    super.key,
    required this.score,
    required this.verifiedCount,
  });

  final double? score;
  final int verifiedCount;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    if (score == null || verifiedCount == 0) {
      return Text(
        'Brak ocen',
        style: text.labelLarge?.copyWith(
          color: AppColors.textMuted,
          fontWeight: FontWeight.w500,
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          Fmt.rating(score!),
          style: text.labelLarge?.copyWith(
            color: AppColors.text,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(width: 6),
        Text(
          Fmt.reviews(verifiedCount),
          style: text.labelMedium?.copyWith(color: AppColors.textMuted),
        ),
      ],
    );
  }
}

class Tag extends StatelessWidget {
  const Tag(this.label, {super.key, this.color});

  final String label;

  /// Domyślnie przygaszony tekst bieżącego motywu.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: const BorderRadius.all(Radius.circular(6)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: AppTheme.fontFamily,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
          color: color ?? AppColors.textMuted,
        ),
      ),
    );
  }
}

/// Cienki obrys na zdjęciu, żeby jasne logo nie zlewało się z tłem.
/// Czysta biel albo czerń przy 10%, nigdy kolor z palety.
class ImageOutline extends StatelessWidget {
  const ImageOutline({super.key, required this.child, required this.radius});

  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.palette.brightness == Brightness.dark;
    return Container(
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: (dark ? Colors.white : Colors.black).withValues(alpha: 0.1),
        ),
      ),
      child: child,
    );
  }
}

/// Zastępczy obrazek lokalu w stylu pikselowego logo.
class RestaurantMark extends StatelessWidget {
  const RestaurantMark({
    super.key,
    required this.name,
    this.size = 56,
    this.radius,
  });

  final String name;
  final double size;

  /// Domyślnie jedna czwarta rozmiaru. W rogu karty podaj promień karty minus jej odstęp.
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final letter = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(radius ?? size * 0.25),
      ),
      child: Text(
        letter,
        style: TextStyle(
          fontFamily: AppTheme.fontFamily,
          fontSize: size * 0.42,
          fontWeight: FontWeight.w600,
          color: AppColors.accent,
        ),
      ),
    );
  }
}

/// Mały przycisk ze strzałką, jak w wierszach list na referencji.
class ArrowBadge extends StatelessWidget {
  const ArrowBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.ring),
      ),
      child: Glyph(AppIcons.arrowUpRight, size: 16, color: AppColors.textMuted),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleLarge),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------
// Rozwijana lista w kształcie pigułki
// ---------------------------------------------------------------

class DropdownOption<T> {
  const DropdownOption({
    required this.value,
    required this.label,
    this.trailing,
  });

  final T value;
  final String label;

  /// Krótka informacja po prawej, na przykład liczba lokali.
  final String? trailing;
}

/// Pigułka filtra otwierająca listę tuż pod sobą.
/// Lista rośnie od strony pigułki: 180 ms z mocnym ease-out przy otwarciu,
/// 120 ms przy zamknięciu. Przy ograniczonym ruchu pojawia się od razu.
class DropdownPill<T> extends StatefulWidget {
  const DropdownPill({
    super.key,
    required this.icon,
    required this.title,
    required this.label,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.tapHeight = 40,
  });

  final AppIconData icon;

  /// Wysokość pola dotyku. Pigułka zostaje 40 px, a pole rośnie (na telefonie 48 dp, wymóg Androida).
  final double tapHeight;

  /// Nazwa filtra, na przykład „Miasto”. Nagłówek listy i etykieta dla czytnika ekranu.
  final String title;

  /// Tekst na pigułce, czyli bieżący wybór.
  final String label;
  final List<DropdownOption<T>> options;
  final T selected;
  final ValueChanged<T> onSelected;

  @override
  State<DropdownPill<T>> createState() => _DropdownPillState<T>();
}

class _DropdownPillState<T> extends State<DropdownPill<T>>
    with SingleTickerProviderStateMixin {
  final _link = LayerLink();
  final _portal = OverlayPortalController();

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
    reverseDuration: const Duration(milliseconds: 120),
  );

  // Przy zamykaniu ease-in na malejącej wartości daje szybki start zmiany.
  late final Animation<double> _progress = CurvedAnimation(
    parent: _controller,
    curve: AppMotion.easeOut,
    reverseCurve: Curves.easeIn,
  );
  late final Animation<double> _scale = Tween<double>(
    begin: 0.96,
    end: 1,
  ).animate(_progress);

  bool _alignRight = false;

  bool get _isOpen => _portal.isShowing;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _open() {
    final box = context.findRenderObject()! as RenderBox;
    final center = box.localToGlobal(box.size.center(Offset.zero)).dx;
    setState(() {
      _alignRight = center > MediaQuery.sizeOf(context).width / 2;
      _portal.show();
    });
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  Future<void> _close() async {
    if (!_isOpen) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 0;
    } else {
      await _controller.reverse();
    }
    if (mounted && _controller.isDismissed && _isOpen) {
      setState(_portal.hide);
    }
  }

  void _select(T value) {
    _close();
    if (value != widget.selected) widget.onSelected(value);
  }

  @override
  Widget build(BuildContext context) {
    final origin = _alignRight ? Alignment.topRight : Alignment.topLeft;

    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (context) => Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _close,
              ),
            ),
            CompositedTransformFollower(
              link: _link,
              showWhenUnlinked: false,
              targetAnchor: _alignRight
                  ? Alignment.bottomRight
                  : Alignment.bottomLeft,
              followerAnchor: origin,
              offset: const Offset(0, 8),
              child: FadeTransition(
                opacity: _progress,
                child: ScaleTransition(
                  scale: _scale,
                  alignment: origin,
                  child: _DropdownPanel<T>(
                    title: widget.title,
                    options: widget.options,
                    selected: widget.selected,
                    onSelected: _select,
                  ),
                ),
              ),
            ),
          ],
        ),
        child: Semantics(
          button: true,
          expanded: _isOpen,
          label: '${widget.title}: ${widget.label}',
          excludeSemantics: true,
          child: PressScale(
            onTap: _isOpen ? _close : _open,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              height: 40,
              margin: EdgeInsets.symmetric(vertical: (widget.tapHeight - 40).clamp(0, 24) / 2),
              // Po stronie ikony odstęp o 2 px mniejszy, żeby pigułka wyglądała na wyśrodkowaną.
              padding: const EdgeInsets.only(left: 12, right: 10),
              decoration: BoxDecoration(
                color: _isOpen ? AppColors.surfaceRaised : AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _isOpen ? AppColors.ringStrong : AppColors.ring,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Glyph(widget.icon, size: 17, color: AppColors.textMuted),
                  const SizedBox(width: 7),
                  Text(
                    widget.label,
                    style: TextStyle(
                      fontFamily: AppTheme.fontFamily,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: _isOpen ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    curve: AppMotion.easeOut,
                    child: Glyph(
                      AppIcons.caretDown,
                      size: 18,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DropdownPanel<T> extends StatelessWidget {
  const _DropdownPanel({
    required this.title,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final String title;
  final List<DropdownOption<T>> options;
  final T selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Container(
        width: 248,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.5,
        ),
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised,
          // Promień 16 = promień pozycji (10) + odstęp panelu (6).
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.ringStrong),
          boxShadow: const [
            BoxShadow(
              color: Color(0x8C000000),
              blurRadius: 32,
              offset: Offset(0, 16),
            ),
          ],
        ),
        child: ListView(
          padding: const EdgeInsets.all(6),
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
              child: Text(
                title.toUpperCase(),
                style: TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                  color: AppColors.textMuted,
                ),
              ),
            ),
            for (final option in options)
              _DropdownItem(
                label: option.label,
                trailing: option.trailing,
                selected: option.value == selected,
                onTap: () => onSelected(option.value),
              ),
          ],
        ),
      ),
    );
  }
}

class _DropdownItem extends StatelessWidget {
  const _DropdownItem({
    required this.label,
    required this.selected,
    required this.onTap,
    this.trailing,
  });

  final String label;
  final String? trailing;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        highlightColor: const Color(0x14FFFFFF),
        splashColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontFamily: AppTheme.fontFamily,
                      fontSize: 15,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      color: AppColors.text,
                    ),
                  ),
                ),
                if (trailing != null) ...[
                  Text(
                    trailing!,
                    style: TextStyle(
                      fontFamily: AppTheme.fontFamily,
                      fontSize: 13,
                      color: AppColors.textMuted,
                      fontFeatures: [const FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                SizedBox(
                  width: 20,
                  child: selected
                      ? Glyph(AppIcons.check, size: 18, color: AppColors.accent)
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Logo lokalu z internetu, a bez logo znak z inicjałami.
class RestaurantLogo extends StatelessWidget {
  const RestaurantLogo({
    super.key,
    required this.name,
    required this.logoUrl,
    this.size = 56,
    this.radius,
  });

  final String name;
  final String? logoUrl;
  final double size;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final url = logoUrl;
    final fallback = RestaurantMark(name: name, size: size, radius: radius);
    if (url == null) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius ?? size / 4),
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}
