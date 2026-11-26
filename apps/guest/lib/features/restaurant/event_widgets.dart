import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../data/models.dart';

// Wydarzenia lokali dla gości (26.11.2026, prośba użytkownika: „wydarzenia nie są za bardzo widoczne i krzykliwe,
// zmień to”). Wcześniej blady wiersz z cienką kreską w kolorze pod ocenami. Teraz: duża karta w kolorze wydarzenia
// zaraz pod szybkimi akcjami na stronie lokalu, znaczek na zdjęciu lokalu i na kartach w Odkrywaj.

const _tabular = [FontFeature.tabularFigures()];

/// Kolor wydarzenia z panelu (gotowy albo własny RGB); nieznany: kolor aplikacji.
Color eventColor(RestaurantEvent e) => calendarColorFromDb(e.color) ?? AppColors.accentFill;

/// Napis na wypełnieniu w kolorze wydarzenia: biały na ciemnym, prawie czarny na jasnym.
Color onEventColor(Color fill) =>
    ThemeData.estimateBrightnessForColor(fill) == Brightness.dark ? Colors.white : const Color(0xFF121212);

/// Kolor napisu na wypełnieniu [on] (pigułka, przycisk): ciemny odcień wydarzenia na jasnym, jasny na ciemnym.
Color _ink(Color fill, Color on) =>
    on.computeLuminance() > 0.5 ? Color.lerp(fill, Colors.black, 0.35)! : Color.lerp(fill, Colors.white, 0.2)!;

/// Opis wydarzenia dla czytnika ekranu.
String eventSemantics(RestaurantEvent e, DateTime now, [List<String> perks = const []]) => [
  'Wydarzenie: ${e.title}',
  if (e.activeAt(now)) 'trwa teraz',
  restaurantEventWhen(e, now),
  ...perks,
  ?e.description,
].join(', ');

/// Duża karta wydarzenia na stronie lokalu: tło w kolorze wydarzenia, „TRWA TERAZ” albo kiedy, nazwa, godziny,
/// opis, zniżki i specjalne menu jako znaczki, „Zobacz menu”.
class EventCard extends StatelessWidget {
  const EventCard({super.key, required this.event, this.perks = const [], this.onMenu, this.featured = false});

  final RestaurantEvent event;

  /// Np. „−20% · Pizze”, „Specjalne menu · Zimowe dania”.
  final List<String> perks;

  /// „Zobacz menu”. Null: bez przycisku.
  final VoidCallback? onMenu;

  /// Pierwsze (najbliższe) wydarzenie: większa nazwa.
  final bool featured;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final now = DateTime.now();
    final e = event;
    final fill = eventColor(e);
    final on = onEventColor(fill);
    final active = e.activeAt(now);
    final dark = Color.lerp(fill, Colors.black, 0.3)!;
    return Semantics(
      container: true,
      label: eventSemantics(e, now, perks),
      excludeSemantics: onMenu == null,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [fill, dark]),
          boxShadow: [
            BoxShadow(color: fill.withValues(alpha: 0.45), blurRadius: 26, spreadRadius: -10, offset: const Offset(0, 12)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Stack(
            children: [
              // Konfetti w tle jako ozdoba.
              Positioned(
                right: -22,
                top: -18,
                child: ExcludeSemantics(
                  child: Opacity(opacity: 0.2, child: Glyph(AppIcons.confetti.duotone, size: 132, color: on)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _WhenPill(label: eventBadgeWhen(e, now).toUpperCase(), live: active, fill: fill, on: on),
                    const SizedBox(height: 10),
                    Text(
                      e.title,
                      style: (featured ? text.headlineSmall : text.titleLarge)?.copyWith(
                        color: on,
                        fontWeight: FontWeight.w600,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Glyph(AppIcons.calendar, size: 15, color: on.withValues(alpha: 0.85)),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            restaurantEventWhen(e, now),
                            style: text.bodyMedium?.copyWith(
                              color: on.withValues(alpha: 0.9),
                              fontWeight: FontWeight.w500,
                              fontFeatures: _tabular,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (e.description != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        e.description!,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodyMedium?.copyWith(color: on.withValues(alpha: 0.92), height: 1.4),
                      ),
                    ],
                    if (perks.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [for (final p in perks) _Perk(label: p, fill: fill, on: on)],
                      ),
                    ],
                    if (onMenu != null) ...[
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: on,
                          foregroundColor: _ink(fill, on),
                          minimumSize: const Size.fromHeight(46),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: onMenu,
                        icon: Glyph(AppIcons.forkKnife, size: 18, color: _ink(fill, on)),
                        label: const Text('Zobacz menu'),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// „TRWA TERAZ” z pulsującą kropką albo kiedy („DZIŚ 18:00”), na odwróconych kolorach karty.
class _WhenPill extends StatelessWidget {
  const _WhenPill({required this.label, required this.live, required this.fill, required this.on});

  final String label;
  final bool live;
  final Color fill;
  final Color on;

  @override
  Widget build(BuildContext context) {
    final fg = _ink(fill, on);
    return Container(
      padding: const EdgeInsets.fromLTRB(9, 5, 11, 5),
      decoration: BoxDecoration(color: on, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (live) ...[const _LiveDot(color: Color(0xFFE5484D)), const SizedBox(width: 6)] else ...[
            Glyph(AppIcons.confetti, size: 13, color: fg),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              fontFamily: AppTheme.fontFamily,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
              color: fg,
              fontFeatures: _tabular,
            ),
          ),
        ],
      ),
    );
  }
}

/// Zniżka albo specjalne menu: półprzezroczysta pigułka na karcie.
class _Perk extends StatelessWidget {
  const _Perk({required this.label, required this.fill, required this.on});

  final String label;
  final Color fill;
  final Color on;

  @override
  Widget build(BuildContext context) {
    final discount = label.startsWith('−');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: on.withValues(alpha: discount ? 0.22 : 0.14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: on.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Glyph(discount ? AppIcons.sealPercent : AppIcons.bookOpen, size: 14, color: on),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: on,
                fontFeatures: _tabular,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pulsująca kropka „na żywo”; przy „Ogranicz ruch” stoi.
class _LiveDot extends StatefulWidget {
  const _LiveDot({required this.color});

  final Color color;

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot> with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _pulse.stop();
      _pulse.value = 1;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1).animate(_pulse),
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}

/// Znaczek wydarzenia na zdjęciu lokalu (Odkrywaj, strona lokalu): kolor wydarzenia, konfetti, kiedy i nazwa.
class EventBadge extends StatelessWidget {
  const EventBadge({super.key, required this.event, this.onTap, this.maxWidth = 280});

  final RestaurantEvent event;
  final VoidCallback? onTap;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final fill = eventColor(event);
    final on = onEventColor(fill);
    final active = event.activeAt(now);
    final badge = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Container(
        padding: const EdgeInsets.fromLTRB(9, 6, 12, 6),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
          boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 10, offset: Offset(0, 3))],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (active) ...[_LiveDot(color: on), const SizedBox(width: 6)] else ...[
              Glyph(AppIcons.confetti, size: 14, color: on),
              const SizedBox(width: 5),
            ],
            Flexible(
              child: Text(
                '${eventBadgeWhen(event, now)} · ${event.title}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: on,
                  fontFeatures: _tabular,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (onTap == null) return badge;
    return Semantics(
      button: true,
      label: eventSemantics(event, now),
      excludeSemantics: true,
      child: GestureDetector(onTap: onTap, child: badge),
    );
  }
}

/// Wydarzenie w zwartym wierszu lokalu (Odkrywaj, widok listy): linia w kolorze wydarzenia.
class EventLine extends StatelessWidget {
  const EventLine({super.key, required this.event});

  final RestaurantEvent event;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final fill = eventColor(event);
    // Kolor wydarzenia bywa jasny: napis w kolorze czytelnym na tle karty.
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = dark ? Color.lerp(fill, Colors.white, 0.25)! : Color.lerp(fill, Colors.black, 0.25)!;
    return Row(
      children: [
        Glyph(AppIcons.confetti, size: 13, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            '${eventBadgeWhen(event, now)} · ${event.title}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
              fontFeatures: _tabular,
            ),
          ),
        ),
      ],
    );
  }
}
