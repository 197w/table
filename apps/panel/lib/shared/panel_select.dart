import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';


/// Wspólny styl rozwijanych menu panelu (16.11.2026, prośba użytkownika, według zrzutu z UniFi): ciemny panel
/// z zaokrąglonymi rogami i cienką linią, wiersze 40 px, najechany wiersz jaśniejszy, a wybrany ma haczyk
/// z lewej i pogrubiony napis.
MenuStyle panelMenuStyle({AppPalette? palette, double? width, double maxHeight = 320}) {
  final p = palette ?? AppColors.palette;
  final dark = p.brightness == Brightness.dark;
  return MenuStyle(
    backgroundColor: WidgetStatePropertyAll(dark ? p.surfaceRaised : p.surface),
    surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
    elevation: const WidgetStatePropertyAll(12),
    shadowColor: WidgetStatePropertyAll(Colors.black.withValues(alpha: dark ? 0.6 : 0.2)),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: p.ringStrong),
      ),
    ),
    padding: const WidgetStatePropertyAll(EdgeInsets.all(6)),
    minimumSize: WidgetStatePropertyAll(Size(width ?? 0, 0)),
    maximumSize: WidgetStatePropertyAll(Size(width ?? double.infinity, maxHeight)),
  );
}

/// Styl jednego wiersza menu: [selected] pogrubia napis, najechany albo wybrany klawiszem dostaje jaśniejsze tło.
ButtonStyle panelMenuItemStyle(BuildContext context, {bool selected = false}) {
  final text = Theme.of(context).textTheme;
  return ButtonStyle(
    minimumSize: const WidgetStatePropertyAll(Size(0, 40)),
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 10)),
    alignment: Alignment.centerLeft,
    foregroundColor: WidgetStatePropertyAll(AppColors.text),
    iconColor: WidgetStatePropertyAll(AppColors.text),
    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    backgroundColor: WidgetStateProperty.resolveWith(
      (s) => s.contains(WidgetState.hovered) || s.contains(WidgetState.focused)
          ? AppColors.text.withValues(alpha: 0.08)
          : Colors.transparent,
    ),
    shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
    textStyle: WidgetStatePropertyAll(
      text.bodyLarge?.copyWith(fontWeight: selected ? FontWeight.w600 : FontWeight.w400),
    ),
    mouseCursor: const WidgetStatePropertyAll(SystemMouseCursors.click),
  );
}

/// Haczyk przed wybranym wierszem menu. Pozostałe wiersze mają puste miejsce o tej samej szerokości, żeby napisy
/// stały równo.
Widget panelMenuCheck({required bool selected}) =>
    SizedBox(width: 18, child: selected ? const Glyph(AppIcons.check, size: 16) : null);

/// Pole wyboru jednej opcji z listy rozwijanej, w stylu menu z UniFi: pole z ramką w kolorze akcentu, gdy lista jest
/// otwarta, a pod nim ciemny panel z opcjami, haczykiem przy wybranej i pogrubionym napisem.
///
/// Zastępuje `DropdownButtonFormField` (od 16.11.2026 w całym panelu) i przyjmuje te same pozycje
/// (`DropdownMenuItem`), więc zmiana w miejscu użycia to sama nazwa. Jak tamto pole pamięta wybór sama i nie
/// reaguje na zmianę [initialValue]; inna wartość początkowa wymaga nowego klucza.
class PanelSelect<T> extends StatefulWidget {
  const PanelSelect({
    super.key,
    required this.items,
    required this.onChanged,
    this.initialValue,
    this.decoration = const InputDecoration(),
    this.hint,
    this.menuMaxHeight = 320,
  });

  final List<DropdownMenuItem<T>> items;

  /// Null: pole wyłączone.
  final ValueChanged<T?>? onChanged;
  final T? initialValue;

  /// Etykieta, podpowiedź pod polem itd., jak w zwykłym polu.
  final InputDecoration decoration;

  /// Napis, gdy nic nie jest wybrane (i nie ma pozycji z wartością null).
  final Widget? hint;
  final double menuMaxHeight;

  @override
  State<PanelSelect<T>> createState() => _PanelSelectState<T>();
}

class _PanelSelectState<T> extends State<PanelSelect<T>> {
  final _menu = MenuController();
  late T? _value = widget.initialValue;
  bool _open = false;

  DropdownMenuItem<T>? get _selected {
    for (final item in widget.items) {
      if (item.value == _value) return item;
    }
    return null;
  }

  void _toggle() {
    if (widget.onChanged == null || widget.items.isEmpty) return;
    if (_menu.isOpen) {
      _menu.close();
      return;
    }
    _menu.open();
  }

  void _pick(T? value) {
    setState(() => _value = value);
    widget.onChanged?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final enabled = widget.onChanged != null && widget.items.isNotEmpty;
    final selected = _selected;
    final style = text.bodyLarge?.copyWith(color: enabled ? AppColors.text : AppColors.textDisabled);

    final field = Semantics(
      button: true,
      enabled: enabled,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggle,
          child: InputDecorator(
            isFocused: _open,
            isEmpty: selected == null && widget.hint == null,
            expands: false,
            baseStyle: style,
            decoration: widget.decoration.copyWith(enabled: enabled),
            child: Row(
              children: [
                Expanded(
                  child: DefaultTextStyle.merge(
                    style: style,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    child: selected?.child ?? widget.hint ?? const SizedBox.shrink(),
                  ),
                ),
                const SizedBox(width: 8),
                Glyph(
                  _open ? AppIcons.caretUp : AppIcons.caretDown,
                  size: 16,
                  color: enabled ? AppColors.textMuted : AppColors.textDisabled,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // Lista ma szerokość pola: pole zajmuje całą dostępną szerokość.
    return LayoutBuilder(
      builder: (context, box) => MenuAnchor(
        controller: _menu,
        onOpen: () => setState(() => _open = true),
        onClose: () => setState(() => _open = false),
        alignmentOffset: const Offset(0, 6),
        // Bez tego panel zostaje przy szerokości najdłuższej opcji zamiast szerokości pola.
        crossAxisUnconstrained: false,
        style: panelMenuStyle(
          width: box.maxWidth.isFinite ? box.maxWidth : null,
          maxHeight: widget.menuMaxHeight,
        ),
        menuChildren: [
          for (final item in widget.items)
            MenuItemButton(
              onPressed: item.enabled ? () => _pick(item.value) : null,
              leadingIcon: panelMenuCheck(selected: item.value == _value),
              style: panelMenuItemStyle(context, selected: item.value == _value),
              child: item.child,
            ),
        ],
        child: field,
      ),
    );
  }
}
