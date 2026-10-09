import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

/// Kolory stanów spoza palety Table. W obu motywach tekst ma kontrast co najmniej 4,5:1.
abstract final class StaffColors {
  static bool get _dark => AppColors.palette.brightness == Brightness.dark;

  /// W drodze, w kursie, wolne w grafiku: niebieski.
  static Color get info => _dark ? const Color(0xFF60A5FA) : const Color(0xFF1D4ED8);

  /// Propozycja przełożonego: fioletowy.
  static Color get proposal => _dark ? const Color(0xFFA78BFA) : const Color(0xFF6D28D9);

  /// Czeka na decyzję, gotówka do pobrania, uwaga gościa, niewysłane pozycje: pomarańczowy.
  static Color get pending => AppColors.warning;
}

/// Najszersza treść na tablecie: listy nie rozciągają się na cały ekran.
const kContentWidth = 720.0;

/// Treść ekranu wyśrodkowana i nie szersza niż [kContentWidth].
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: kContentWidth),
      child: child,
    ),
  );
}

/// Nagłówek sekcji listy, jak w aplikacji dla gości („W trakcie”, „Zakończone”).
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing, this.top = 24});

  final String title;
  final Widget? trailing;
  final double top;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(4, top, 4, 10),
      child: Row(
        children: [
          Expanded(
            child: Semantics(header: true, child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Kafelek z ikoną duotone na spokojnym tle: rodzaj kursu, lokal, ustawienie.
class IconTile extends StatelessWidget {
  const IconTile(this.icon, {super.key, this.color, this.size = 52, this.active = true});

  final AppIconData icon;

  /// Kolor ikony. Domyślnie akcent, a przy nieaktywnym kafelku przygaszony.
  final Color? color;
  final double size;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final fg = color ?? (active ? AppColors.accent : AppColors.textMuted);
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? fg.withValues(alpha: 0.12) : AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(size * 0.27),
        ),
        child: Glyph(icon.duotone, size: size * 0.46, color: fg),
      ),
    );
  }
}

/// Liczba z podpisem: godziny zmiany, kursy, gotówka.
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value, this.caption, this.icon, this.color});

  final String label;
  final String value;
  final String? caption;
  final AppIconData? icon;

  /// Kolor liczby (np. gotówka do rozliczenia). Domyślnie zwykły tekst.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      label: [label, value, ?caption].join(', '),
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(color: AppColors.surfaceRaised, borderRadius: BorderRadius.circular(14)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[Glyph(icon!, size: 14, color: AppColors.textMuted), const SizedBox(width: 6)],
                Expanded(
                  child: Text(label, style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: text.titleLarge?.copyWith(color: color, fontFeatures: const [FontFeature.tabularFigures()]),
            ),
            if (caption != null)
              Text(
                caption!,
                style: text.bodySmall?.copyWith(
                  color: AppColors.textMuted,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Szary prostokąt w miejscu tekstu, zanim dane dojdą.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, required this.width, required this.height, this.radius = 6});

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(color: AppColors.surfaceRaised, borderRadius: BorderRadius.circular(radius)),
  );
}

/// Szkielet listy kart (bez animacji, czytnik ekranu go pomija).
class CardsSkeleton extends StatelessWidget {
  const CardsSkeleton({super.key, this.count = 3, this.tile = true, this.top = 16});

  final int count;

  /// Kafelek z ikoną po lewej, jak w docelowych wierszach.
  final bool tile;
  final double top;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: ContentWidth(
        child: ListView(
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(16, top, 16, 0),
          children: [
            for (var i = 0; i < count; i++)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: AppColors.ring),
                ),
                child: Row(
                  children: [
                    if (tile) ...[const SkeletonBox(width: 52, height: 52, radius: 14), const SizedBox(width: 12)],
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBox(width: 160, height: 14),
                        SizedBox(height: 8),
                        SkeletonBox(width: 110, height: 12),
                        SizedBox(height: 8),
                        SkeletonBox(width: 70, height: 18),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Dolny pasek ekranu z głównym działaniem, nad dolnym menu aplikacji.
class BottomActionBar extends StatelessWidget {
  const BottomActionBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      // Nad dolnym menu aplikacji odstęp systemu jest już zdjęty, na osobnym ekranie dochodzi pasek Androida.
      padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + MediaQuery.paddingOf(context).bottom),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.ring)),
      ),
      // Wysokość paska to wysokość przycisku (heightFactor), szerokość jak treść ekranu.
      child: Align(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kContentWidth),
          child: child,
        ),
      ),
    );
  }
}

String _two(int n) => n.toString().padLeft(2, '0');

/// Godzina jako „19:05”.
String hm(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

/// Czas trwania jako „7:45”.
String hoursText(Duration d) => '${d.inMinutes ~/ 60}:${_two(d.inMinutes % 60)}';

/// Czas trwania dla czytnika ekranu: „7 godzin 45 minut”.
String hoursSpoken(Duration d) {
  final h = d.inMinutes ~/ 60;
  final m = d.inMinutes % 60;
  String unit(int n, String one, String few, String many) =>
      n == 1 ? one : (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 12 || n % 100 > 14) ? few : many);
  return [
    if (h > 0) '$h ${unit(h, 'godzina', 'godziny', 'godzin')}',
    if (m > 0 || h == 0) '$m ${unit(m, 'minuta', 'minuty', 'minut')}',
  ].join(' ');
}
