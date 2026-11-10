import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import 'panel_widgets.dart';

// Układ list jak „People” w UniFi (Pracownicy, Grafik, Logi): po lewej zwijany panel z zakładkami albo tytułem,
// wyszukiwaniem, przyciskami i grupami filtrów z liczbami, po prawej tabela.

const _tabular = [FontFeature.tabularFigures()];

/// Szerokość panelu po lewej i zwiniętego paska.
const sidePanelWidth = 288.0;
const sidePanelCollapsedWidth = 20.0;

/// Panel po lewej (albo wąski pasek, gdy zwinięty), obok niego okno dodawania albo zmiany (gdy otwarte), po prawej
/// treść. Przycisk zwijania stoi na kresce między panelem a resztą, jak w UniFi.
class SidePanelLayout extends StatelessWidget {
  const SidePanelLayout({
    super.key,
    required this.open,
    required this.onToggle,
    required this.panel,
    required this.content,
    this.sheet,
  });

  final bool open;
  final VoidCallback onToggle;
  final Widget panel;
  final Widget content;
  final Widget? sheet;

  @override
  Widget build(BuildContext context) {
    // Panel zwija się i rozwija płynnie: szerokość maleje do wąskiego paska, treść panelu odjeżdża w lewo
    // i gaśnie, a przycisk jedzie razem z kreską.
    return TweenAnimationBuilder<double>(
      tween: Tween(end: open ? 1 : 0),
      duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 280),
      curve: Curves.easeInOutCubic,
      builder: (context, t, _) {
        final width = sidePanelCollapsedWidth + (sidePanelWidth - sidePanelCollapsedWidth) * t;
        return Stack(
          children: [
            Positioned.fill(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: width,
                    decoration: BoxDecoration(border: Border(right: BorderSide(color: AppColors.ring))),
                    child: t == 0
                        ? null
                        : ClipRect(
                            child: OverflowBox(
                              alignment: Alignment.centerRight,
                              minWidth: sidePanelWidth,
                              maxWidth: sidePanelWidth,
                              child: Opacity(opacity: t, child: panel),
                            ),
                          ),
                  ),
                  // Okno dodawania wysuwa się zza panelu.
                  AnimatedSwitcher(
                    duration: PanelMotion.tab,
                    transitionBuilder: (child, animation) => SizeTransition(
                      axis: Axis.horizontal,
                      alignment: Alignment.centerLeft,
                      sizeFactor: CurvedAnimation(parent: animation, curve: AppMotion.easeOut),
                      child: child,
                    ),
                    child: sheet ?? const SizedBox.shrink(key: ValueKey('bez okna')),
                  ),
                  Expanded(child: content),
                ],
              ),
            ),
            Positioned(
              left: width - 10,
              top: 18,
              child: _EdgeButton(open: open, onTap: onToggle),
            ),
          ],
        );
      },
    );
  }
}

/// Uchwyt na kresce panelu: wąski prostokąt z zaokrąglonymi rogami (1.11.2026, prośba użytkownika; wcześniej
/// kółko), zwija panel albo go rozwija. Bez podświetlenia tła: najechana strzałka jaśnieje.
class _EdgeButton extends StatefulWidget {
  const _EdgeButton({required this.open, required this.onTap});

  final bool open;
  final VoidCallback onTap;

  @override
  State<_EdgeButton> createState() => _EdgeButtonState();
}

class _EdgeButtonState extends State<_EdgeButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.open ? 'Zwiń panel' : 'Pokaż panel',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 20,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _hover ? AppColors.textMuted : AppColors.ringStrong),
            ),
            child: Center(
              child: Glyph(
                widget.open ? AppIcons.caretLeft : AppIcons.caretRight,
                size: 13,
                color: _hover ? AppColors.text : AppColors.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Panel po lewej: zakładki albo tytuł, wyszukiwanie (bez niego w Statystykach), przyciski (np. wybór lokalu,
/// „Dodaj pracownika”, dzień) i przewijane filtry.
class SidePanel extends StatelessWidget {
  const SidePanel({
    super.key,
    required this.header,
    this.search,
    this.searchHint = '',
    this.onSearch,
    this.actions = const [],
    this.children = const [],
  });

  final Widget header;

  /// Bez pola wyszukiwania, gdy null.
  final TextEditingController? search;
  final String searchHint;
  final VoidCallback? onSearch;
  final List<Widget> actions;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: sidePanelWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: SizedBox(height: 40, child: header),
          ),
          if (search != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: TextField(
                controller: search,
                onChanged: (_) => onSearch?.call(),
                decoration: InputDecoration(
                  hintText: searchHint,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                  prefixIcon: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Glyph(AppIcons.search, size: 16, color: AppColors.textMuted),
                  ),
                  prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
              ),
            ),
          for (final a in actions)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: a,
            ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

/// Tytuł panelu, gdy nie ma zakładek do wyboru (Grafik albo tylko jedna część Pracowników).
class PanelTitle extends StatelessWidget {
  const PanelTitle({super.key, required this.icon, required this.title});

  final AppIconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Glyph(icon, size: 18, color: AppColors.textMuted),
        const SizedBox(width: 10),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}

/// Przycisk z obrysem w kolorze akcentu w panelu („Dodaj pracownika”, „Dodaj pojazd”), podświetlony, gdy jego okno
/// jest otwarte.
class PanelAction extends StatelessWidget {
  const PanelAction({super.key, required this.label, required this.onTap, this.active = false});

  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.accent,
        backgroundColor: active ? AppColors.accentTint : null,
        side: BorderSide(color: AppColors.accent.withValues(alpha: 0.7)),
        minimumSize: const Size.fromHeight(40),
      ),
      child: Text(label),
    );
  }
}

/// Mała odznaka w wierszu tabeli, np. „ALL”, „Ty” albo „Nieużywany”.
class RowBadge extends StatelessWidget {
  const RowBadge(this.label, {super.key, this.accent = false});

  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: accent ? AppColors.accentTint : AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: accent ? AppColors.accent : AppColors.textMuted,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

/// Pole wyboru w grupie filtrów: napis, liczba, zaznaczenie i kropka koloru (np. „Na zmianie”).
typedef FilterOption = ({String label, int count, bool checked, ValueChanged<bool> onChanged, Color? dot});

/// Grupa filtrów w panelu po lewej: nagłówek ze strzałką (zwija grupę) i pola wyboru z liczbą.
class FilterSection extends StatelessWidget {
  const FilterSection({
    super.key,
    required this.title,
    required this.open,
    required this.onToggle,
    required this.options,
    this.first = false,
  });

  final String title;
  final bool open;
  final VoidCallback onToggle;
  final List<FilterOption> options;

  /// Pierwsza grupa nie ma kreski nad sobą.
  final bool first;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!first) Divider(height: 1, color: AppColors.ring),
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                Expanded(child: Text(title, style: text.labelLarge)),
                Glyph(open ? AppIcons.caretUp : AppIcons.caretDown, size: 14, color: AppColors.textMuted),
              ],
            ),
          ),
        ),
        if (open) ...[for (final o in options) _FilterRow(option: o), const SizedBox(height: 8)],
      ],
    );
  }
}

/// Jedno pole wyboru filtra. Bez niczego w tej grupie przygaszone i nieklikalne (chyba że zaznaczone).
class _FilterRow extends StatelessWidget {
  const _FilterRow({required this.option});

  final FilterOption option;

  @override
  Widget build(BuildContext context) {
    final o = option;
    final enabled = o.count > 0 || o.checked;
    return InkWell(
      onTap: enabled ? () => o.onChanged(!o.checked) : null,
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        height: 32,
        child: Row(
          children: [
            PanelCheck(value: o.checked, onChanged: enabled ? (v) => o.onChanged(v ?? false) : null),
            const SizedBox(width: 10),
            if (o.dot != null) ...[
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: enabled ? o.dot : AppColors.textDisabled, shape: BoxShape.circle),
              ),
              const SizedBox(width: 7),
            ],
            Expanded(
              child: Text(
                '${o.label} (${o.count})',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: enabled ? AppColors.text : AppColors.textDisabled,
                  fontFeatures: _tabular,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Małe pole wyboru (filtry, uprawnienia, wiersze tabeli), bez poświaty. Przy [tristate] null znaczy
/// „część zaznaczona”.
class PanelCheck extends StatelessWidget {
  const PanelCheck({super.key, required this.value, required this.onChanged, this.tristate = false});

  final bool? value;
  final ValueChanged<bool?>? onChanged;
  final bool tristate;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    return SizedBox(
      width: 18,
      height: 18,
      child: Checkbox(
        value: value,
        tristate: tristate,
        onChanged: onChanged,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        // Bez okrągłej poświaty po najechaniu i kliknięciu (prośba użytkownika).
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        splashRadius: 0,
        activeColor: AppColors.accentFill,
        checkColor: AppColors.onAccent,
        side: WidgetStateBorderSide.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? BorderSide.none
              : BorderSide(color: enabled ? AppColors.ringStrong : AppColors.ring, width: 1.5),
        ),
      ),
    );
  }
}

/// Nagłówek kolumny tabeli: z [width] stała szerokość, bez niej część wolnego miejsca według [flex].
Widget tableHead(BuildContext context, String label, int flex, {TextAlign align = TextAlign.left, double? width}) {
  final child = Text(
    label,
    textAlign: align,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: Theme.of(context).textTheme.labelMedium?.copyWith(color: AppColors.text, fontWeight: FontWeight.w600),
  );
  return width == null ? Expanded(flex: flex, child: child) : SizedBox(width: width, child: child);
}

// Okno dodawania albo zmiany obok panelu, jak „Add New Person” w UniFi (Pracownicy, od 10.11.2026 też nowe wydarzenie
// w Kalendarzu): ramka z tytułem i „Zamknij”, pola z małym napisem nad nimi, karty wyboru po dwie i przyciski na dole.

/// Szerokość okna obok panelu.
const sideSheetWidth = 368.0;

/// Ramka okna obok panelu: tytuł z „Zamknij”, przewijana treść i przycisk na dole.
class SideSheetFrame extends StatelessWidget {
  const SideSheetFrame({super.key, required this.title, required this.onClose, required this.children, this.footer});

  final String title;
  final VoidCallback onClose;
  final List<Widget> children;

  /// Przyciski na dole (np. „Usuń” i „Zapisz”). Null: bez paska na dole.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(right: BorderSide(color: AppColors.ring)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 10, 4),
            child: SizedBox(
              height: 40,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Zamknij',
                    onPressed: onClose,
                    icon: const Glyph(AppIcons.close, size: 18),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              children: children,
            ),
          ),
          if (footer case final footer?) ...[
            Divider(height: 1, color: AppColors.ring),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
              child: footer,
            ),
          ],
        ],
      ),
    );
  }
}

/// Pole w oknie: mały napis nad nim, jak w UniFi.
class SheetField extends StatelessWidget {
  const SheetField({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: AppColors.textMuted)),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

/// Nagłówek części okna, np. „Stanowisko” albo „Dodatkowe stanowiska (opcjonalnie)”.
class SheetHeading extends StatelessWidget {
  const SheetHeading(this.title, {super.key, this.optional = false, this.trailing});

  final String title;
  final bool optional;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        Text(title, style: text.titleSmall),
        if (optional) ...[
          const SizedBox(width: 6),
          Text('(opcjonalnie)', style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
        ],
        const Spacer(),
        if (trailing != null)
          Text(trailing!, style: text.bodySmall?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular)),
      ],
    );
  }
}

InputDecoration sheetInput({String? hint, String? suffix}) => InputDecoration(
  isDense: true,
  hintText: hint,
  suffixText: suffix,
  counterText: '',
  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
);

/// Karty po dwie w rzędzie (stanowiska w oknie pracownika, jak role w UniFi).
class CardGrid extends StatelessWidget {
  const CardGrid({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final width = (box.maxWidth - 10) / 2;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [for (final c in children) SizedBox(width: width, height: 60, child: c)],
        );
      },
    );
  }
}

/// Karta wyboru: ikona i nazwa (bez opisu, prośba użytkownika). Wybrana ma obrys i tło w kolorze akcentu.
class ChoiceCard extends StatelessWidget {
  const ChoiceCard({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.selected = false,
  });

  final AppIconData icon;
  final String title;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Material(
      color: selected ? AppColors.accentTint : AppColors.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: selected ? AppColors.accent : Colors.transparent, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Glyph(selected ? icon.duotone : icon, size: 20, color: AppColors.accent),
              const SizedBox(width: 10),
              // Dłuższa nazwa (np. „Nowe stanowisko”, „Kierownik zmiany”) mieści się w dwóch liniach.
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelLarge?.copyWith(height: 1.2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
