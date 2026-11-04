import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
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

/// Nagłówek nad treścią zakładki: rząd zakładek albo filtrów i przyciski po prawej, w jednym rzędzie.
/// Bez tytułu, opisu i linii pod spodem: nazwę zakładki widać w menu bocznym. [actionsInRow] false zostawia przyciski
/// w osobnym rzędzie nad zakładkami (np. dużo przycisków w Edycji sali).
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    this.actions = const [],
    this.below,
    this.actionsInRow = true,
  });

  final List<Widget> actions;

  /// Dodatkowy rząd, na przykład zakładki albo filtry.
  final Widget? below;
  final bool actionsInRow;

  @override
  Widget build(BuildContext context) {
    final inRow = actionsInRow && below != null && actions.isNotEmpty;
    final top = actions.isNotEmpty && !inRow;
    final row = inRow
        ? Row(
            children: [
              Expanded(child: below!),
              for (final a in actions) ...[const SizedBox(width: 8), PanelPress(child: a)],
            ],
          )
        : below;
    if (!top && row == null) return const SizedBox(height: 20);
    // Bez linii pod spodem (31.10.2026, prośba użytkownika): treść zaczyna się zaraz pod zakładkami.
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 18, 32, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (top)
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Spacer(),
                for (var i = 0; i < actions.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  PanelPress(child: actions[i]),
                ],
              ],
            ),
          if (row != null) ...[if (top) const SizedBox(height: 16), row],
        ],
      ),
    );
  }
}

/// Treść zakładki wewnątrz ekranu (np. Zespół, Grafik, Czas pracy). Przy zmianie zakładki stara treść
/// gaśnie, a nowa pojawia się lekko z dołu, tak jak przy przejściu między zakładkami w menu bocznym.
class TabContent extends StatelessWidget {
  const TabContent({super.key, required this.tab, required this.child});

  /// Wybrana zakładka. Animacja rusza tylko przy jej zmianie, nie przy odświeżeniu danych.
  final Object tab;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: PanelMotion.tab,
      reverseDuration: PanelMotion.tabOut,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: PanelMotion.tabTransition,
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.expand,
        children: [...previous, ?current],
      ),
      child: KeyedSubtree(key: ValueKey(tab), child: child),
    );
  }
}

/// Ruch przy zmianie zakładki: krótkie wygaszenie i wjazd o kilka pikseli z dołu.
/// Nowa treść ma tło strony, więc zakrywa starą zamiast na nią nachodzić.
abstract final class PanelMotion {
  static const tab = Duration(milliseconds: 220);
  static const tabOut = Duration(milliseconds: 140);

  static Widget tabTransition(Widget child, Animation<double> animation) {
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.012), end: Offset.zero).animate(animation),
        child: ColoredBox(color: AppColors.background, child: child),
      ),
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
      height: 40,
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

/// Przycisk z samą ikoną do akcji w nagłówku, na przykład „Nowa rezerwacja”. Sama ikona, bez tła,
/// obwódki i poświaty (1.11.2026, prośba użytkownika), jak ikony w menu bocznym: główna akcja
/// w kolorze akcentu, pozostałe szare, a najechana myszą jaśnieje.
class GlowButton extends StatefulWidget {
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

  @override
  State<GlowButton> createState() => _GlowButtonState();
}

class _GlowButtonState extends State<GlowButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final color = !enabled
        ? AppColors.textDisabled
        : widget.primary
        ? AppColors.accent
        : (_hovered ? AppColors.text : AppColors.textMuted);
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: PanelPress(
            scale: 0.9,
            child: SizedBox(
              width: 40,
              height: 40,
              child: Center(
                child: TweenAnimationBuilder<Color?>(
                  tween: ColorTween(end: color),
                  duration: const Duration(milliseconds: 180),
                  builder: (context, c, _) => Glyph(
                    widget.primary ? widget.icon.duotone : widget.icon,
                    size: widget.iconSize + 4,
                    color: c,
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

/// Kosz do usuwania: zawsze czerwony (1.11.2026, prośba użytkownika), najechany wyraźniejszy, wyłączony bladoczerwony
/// (4.11.2026: szary wyłączony kosz w Podsumowaniu dnia, przy jedynym terminalu, wyglądał na nieczerwony).
/// Bez tła, jak inne przyciski z ikoną (podświetlenie przy kliknięciu wyłącza motyw).
class DeleteButton extends StatelessWidget {
  const DeleteButton({super.key, required this.onPressed, this.tooltip = 'Usuń', this.size = 16, this.compact = false});

  final VoidCallback? onPressed;
  final String tooltip;
  final double size;
  final bool compact;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    visualDensity: compact ? VisualDensity.compact : null,
    style: ButtonStyle(
      foregroundColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.disabled)
            ? AppColors.error.withValues(alpha: 0.4)
            : (s.contains(WidgetState.hovered) || s.contains(WidgetState.pressed)
                  ? Color.lerp(AppColors.error, AppColors.text, 0.25)
                  : AppColors.error),
      ),
    ),
    onPressed: onPressed,
    icon: Glyph(AppIcons.trash, size: size),
  );
}

/// Ikona w kolorze miary, jak w kaflach liczb i nagłówkach kart. Sama ikona, bez kolorowej kostki
/// i cienia (1.11.2026, prośba użytkownika: ikony bez tła).
class IconBadge extends StatelessWidget {
  const IconBadge(this.icon, {super.key, required this.color, this.size = 34});

  final AppIconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Glyph(icon.duotone, size: size * 0.7, color: color);
}

/// Barwy kafli liczb. Każda miara ma swój kolor, ten sam co jej słupki na wykresie.
abstract final class TileColors {
  static const green = Color(0xFF2FB673);
  static const blue = Color(0xFF3B82F6);
  static const amber = Color(0xFFD99A15);
  static const violet = Color(0xFF7C5CFF);
  static const rose = Color(0xFFD9455F);
}

/// Liczba z opisem, na przykład „14 gości”. Z kolorową ikoną i zmianą względem poprzedniego okresu.
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

  /// Kolor ikony.
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
                  const SizedBox(width: 8),
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

/// Wybór jednej opcji z kilku, jak zakładki w pigułce. Podświetlenie przesuwa się do wybranej opcji.
class SegmentedTabs<T> extends StatelessWidget {
  const SegmentedTabs({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.expand = false,
    this.icons,
  });

  final List<(T, String)> options;
  final T selected;
  final ValueChanged<T> onChanged;

  /// Na całą dostępną szerokość (np. nad osią czasu w Logach, w panelu Pracowników): każda opcja dostaje
  /// swoją szerokość i równą część zapasu, a napisy mają mniejszy margines, żeby zmieściły się trzy.
  final bool expand;

  /// Ikony przed napisami, w kolejności opcji (jak „People” i „Roles” w UniFi).
  final List<AppIconData>? icons;

  @override
  Widget build(BuildContext context) {
    return _SlidingSegments(
      selectedIndex: options.indexWhere((o) => o.$1 == selected),
      expand: expand,
      children: [
        for (final (i, (value, label)) in options.indexed)
          _TextSegment(
            label: label,
            icon: icons?.elementAtOrNull(i),
            selected: value == selected,
            padding: expand ? 6 : 14,
            onTap: () => onChanged(value),
          ),
      ],
    );
  }
}

/// Zakładki jako same ikony, bez pigułki i podświetlenia z obwódką (1.11.2026, prośba użytkownika), jak grupy
/// w górnym pasku: wybrana jest w kolorze akcentu i rozsuwa się, pokazując nazwę obok ikony. Pozostałe mają
/// nazwę w podpowiedzi po najechaniu myszą.
class IconTabs<T> extends StatelessWidget {
  const IconTabs({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.tooltips,
  });

  final List<(T, AppIconData, String)> options;
  final T selected;
  final ValueChanged<T> onChanged;

  /// Podpowiedzi po najechaniu zamiast samych nazw, w kolejności opcji (np. ze skrótem klawiszowym).
  final List<String>? tooltips;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, (value, icon, label)) in options.indexed)
          _IconSegment(
            icon: icon,
            label: label,
            tooltip: tooltips?.elementAtOrNull(i),
            selected: value == selected,
            onTap: () => onChanged(value),
          ),
      ],
    );
  }
}

/// Czas ruchu podświetlenia i zmian w opcjach.
const _segmentDuration = Duration(milliseconds: 340);

/// Pigułka z opcjami. Jedno podświetlenie przesuwa się między opcjami i dopasowuje szerokość,
/// zamiast gasnąć w jednej opcji i zapalać się w drugiej.
class _SlidingSegments extends StatefulWidget {
  const _SlidingSegments({required this.selectedIndex, required this.children, this.expand = false});

  /// -1: nic nie jest wybrane.
  final int selectedIndex;
  final List<Widget> children;
  final bool expand;

  @override
  State<_SlidingSegments> createState() => _SlidingSegmentsState();
}

class _SlidingSegmentsState extends State<_SlidingSegments> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: _segmentDuration, value: 1);
  late final _progress = CurvedAnimation(parent: _controller, curve: AppMotion.easeOut);

  @override
  void didUpdateWidget(_SlidingSegments old) {
    super.didUpdateWidget(old);
    if (old.selectedIndex == widget.selectedIndex) return;
    // Przy włączonym ograniczeniu ruchu podświetlenie przeskakuje od razu.
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _progress.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.palette.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(12),
      ),
      child: _IndicatorRow(
        selected: widget.selectedIndex,
        expand: widget.expand,
        progress: _progress,
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF26262B) : AppColors.surface,
          borderRadius: BorderRadius.circular(9),
          boxShadow: [
            // Cienki pierścień w kolorze akcentu i cień: wybrana opcja unosi się nad pigułką.
            BoxShadow(color: AppColors.accent, spreadRadius: 1),
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? 0.35 : 0.12),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        children: widget.children,
      ),
    );
  }
}

/// Rząd opcji, pod którymi rysuje się podświetlenie wybranej. Podświetlenie idzie od miejsca,
/// w którym było w chwili zmiany, do bieżącego miejsca wybranej opcji, więc nadąża też za opcjami,
/// które w tym czasie zmieniają szerokość (np. rozsuwająca się nazwa w IconTabs).
class _IndicatorRow extends MultiChildRenderObjectWidget {
  const _IndicatorRow({
    required this.selected,
    required this.expand,
    required this.progress,
    required this.decoration,
    required super.children,
  });

  final int selected;
  final bool expand;
  final Animation<double> progress;
  final BoxDecoration decoration;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderIndicatorRow(selected, expand, progress, decoration, createLocalImageConfiguration(context));

  @override
  void updateRenderObject(BuildContext context, _RenderIndicatorRow renderObject) {
    renderObject
      ..selected = selected
      ..expand = expand
      ..progress = progress
      ..decoration = decoration
      ..configuration = createLocalImageConfiguration(context);
  }
}

class _IndicatorParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderIndicatorRow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _IndicatorParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _IndicatorParentData> {
  _RenderIndicatorRow(this._selected, this._expand, this._progress, this._decoration, this._configuration);

  /// Opcje po równo na całą szerokość.
  bool _expand;
  set expand(bool value) {
    if (value == _expand) return;
    _expand = value;
    markNeedsLayout();
  }

  int _selected;
  set selected(int value) {
    if (value == _selected) return;
    // Nowa droga zaczyna się tam, gdzie podświetlenie jest teraz, także w połowie poprzedniego ruchu.
    _from = _painted;
    _selected = value;
    markNeedsPaint();
  }

  Animation<double> _progress;
  set progress(Animation<double> value) {
    if (value == _progress) return;
    if (attached) {
      _progress.removeListener(markNeedsPaint);
      value.addListener(markNeedsPaint);
    }
    _progress = value;
    markNeedsPaint();
  }

  BoxDecoration _decoration;
  set decoration(BoxDecoration value) {
    if (value == _decoration) return;
    _decoration = value;
    _painter?.dispose();
    _painter = null;
    markNeedsPaint();
  }

  ImageConfiguration _configuration;
  set configuration(ImageConfiguration value) {
    if (value == _configuration) return;
    _configuration = value;
    markNeedsPaint();
  }

  BoxPainter? _painter;

  /// Miejsce podświetlenia w chwili zmiany wyboru i ostatnio narysowane.
  Rect? _from;
  Rect? _painted;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _IndicatorParentData) child.parentData = _IndicatorParentData();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _progress.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _progress.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void dispose() {
    _painter?.dispose();
    super.dispose();
  }

  Iterable<RenderBox> get _children sync* {
    var child = firstChild;
    while (child != null) {
      yield child;
      child = childAfter(child);
    }
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      _children.fold(0, (sum, c) => sum + c.getMinIntrinsicWidth(height));

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _children.fold(0, (sum, c) => sum + c.getMaxIntrinsicWidth(height));

  @override
  double computeMinIntrinsicHeight(double width) =>
      _children.fold(0, (m, c) => math.max(m, c.getMinIntrinsicHeight(double.infinity)));

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _children.fold(0, (m, c) => math.max(m, c.getMaxIntrinsicHeight(double.infinity)));

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      defaultComputeDistanceToHighestActualBaseline(baseline);

  /// Ograniczenia każdej opcji: swoja szerokość, a przy [_expand] swoja szerokość i równa część wolnego miejsca
  /// (gdy miejsca brakuje, wszystkie po równo).
  List<BoxConstraints> _childConstraints(BoxConstraints constraints) {
    final loose = BoxConstraints(maxHeight: constraints.maxHeight);
    if (!_expand || !constraints.hasBoundedWidth || childCount == 0) {
      return List.filled(childCount, loose);
    }
    final own = [for (final c in _children) c.getMaxIntrinsicWidth(constraints.maxHeight)];
    final extra = (constraints.maxWidth - own.fold(0.0, (a, b) => a + b)) / childCount;
    return [
      for (final w in own)
        BoxConstraints.tightFor(width: extra >= 0 ? w + extra : constraints.maxWidth / childCount)
            .copyWith(maxHeight: constraints.maxHeight),
    ];
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final each = _childConstraints(constraints);
    var width = 0.0;
    var height = 0.0;
    for (final (i, c) in _children.indexed) {
      final s = c.getDryLayout(each[i]);
      width += s.width;
      height = math.max(height, s.height);
    }
    return constraints.constrain(Size(width, height));
  }

  @override
  void performLayout() {
    final each = _childConstraints(constraints);
    var height = 0.0;
    for (final (i, c) in _children.indexed) {
      c.layout(each[i], parentUsesSize: true);
      height = math.max(height, c.size.height);
    }
    var x = 0.0;
    for (final c in _children) {
      (c.parentData! as _IndicatorParentData).offset = Offset(x, (height - c.size.height) / 2);
      x += c.size.width;
    }
    size = constraints.constrain(Size(x, height));
  }

  Rect? _rectOf(int index) {
    if (index < 0) return null;
    var i = 0;
    for (final c in _children) {
      if (i++ == index) return (c.parentData! as _IndicatorParentData).offset & c.size;
    }
    return null;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final target = _rectOf(_selected);
    if (target != null) {
      final t = _progress.value;
      final from = _from;
      final rect = from == null || t >= 1 ? target : Rect.lerp(from, target, t)!;
      if (t >= 1) _from = null;
      _painted = rect;
      _painter ??= _decoration.createBoxPainter(markNeedsPaint);
      _painter!.paint(context.canvas, offset + rect.topLeft, _configuration.copyWith(size: rect.size));
    } else {
      _painted = null;
    }
    defaultPaint(context, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

/// Kolor napisu albo ikony opcji: wybrana jasna, najechana myszą jaśniejsza niż pozostałe.
Color _segmentColor({required bool selected, required bool hovered, Color? selectedColor}) => selected
    ? (selectedColor ?? AppColors.text)
    : hovered
    ? Color.lerp(AppColors.textMuted, AppColors.text, 0.6)!
    : AppColors.textMuted;

/// Opcja z napisem (i ewentualnie ikoną przed nim).
class _TextSegment extends StatefulWidget {
  const _TextSegment({
    required this.label,
    required this.selected,
    required this.onTap,
    this.padding = 14,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final AppIconData? icon;

  /// Margines napisu z lewej i prawej.
  final double padding;

  @override
  State<_TextSegment> createState() => _TextSegmentState();
}

class _TextSegmentState extends State<_TextSegment> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      selected: widget.selected,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: PanelPress(
            scale: 0.95,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: widget.padding, vertical: 7),
              child: TweenAnimationBuilder<Color?>(
                tween: ColorTween(end: _segmentColor(selected: widget.selected, hovered: _hovered)),
                duration: const Duration(milliseconds: 200),
                curve: AppMotion.easeOut,
                builder: (context, color, _) {
                  final label = Text(
                    widget.label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelLarge?.copyWith(color: color),
                  );
                  if (widget.icon == null) return label;
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Glyph(widget.icon!, size: 16, color: color),
                      const SizedBox(width: 7),
                      Flexible(child: label),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Opcja z ikoną. Wybrana rozsuwa się: nazwa wysuwa się zza ikony.
class _IconSegment extends StatefulWidget {
  const _IconSegment({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.tooltip,
  });

  final AppIconData icon;
  final String label;
  final String? tooltip;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_IconSegment> createState() => _IconSegmentState();
}

class _IconSegmentState extends State<_IconSegment> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final selected = widget.selected;
    final tab = Semantics(
      button: true,
      selected: selected,
      label: widget.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: PanelPress(
            scale: 0.92,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TweenAnimationBuilder<Color?>(
                    tween: ColorTween(
                      end: _segmentColor(selected: selected, hovered: _hovered, selectedColor: AppColors.accent),
                    ),
                    duration: const Duration(milliseconds: 200),
                    curve: AppMotion.easeOut,
                    builder: (context, color, _) => AnimatedScale(
                      // Wybrana ikona lekko rośnie, najechana myszą odrobinę.
                      scale: selected ? 1.1 : (_hovered ? 1.05 : 1),
                      duration: _segmentDuration,
                      curve: Curves.easeOutBack,
                      child: Glyph(selected ? widget.icon.duotone : widget.icon, size: 18, color: color),
                    ),
                  ),
                  // Nazwa wysuwa się zza ikony: szerokość rośnie, tekst pojawia się i przesuwa w prawo.
                  ClipRect(
                    child: AnimatedAlign(
                      alignment: Alignment.centerLeft,
                      widthFactor: selected ? 1 : 0,
                      duration: _segmentDuration,
                      curve: AppMotion.easeOut,
                      child: AnimatedOpacity(
                        opacity: selected ? 1 : 0,
                        duration: selected ? _segmentDuration : const Duration(milliseconds: 120),
                        curve: AppMotion.easeOut,
                        child: AnimatedSlide(
                          offset: selected ? Offset.zero : const Offset(-0.3, 0),
                          duration: _segmentDuration,
                          curve: AppMotion.easeOut,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Text(
                              widget.label,
                              maxLines: 1,
                              softWrap: false,
                              style: text.labelLarge?.copyWith(color: AppColors.accent, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return selected ? tab : Tooltip(message: widget.tooltip ?? widget.label, child: tab);
  }
}

/// Grupa ustawień jak w UniFi: tytuł (i opis) nad kartą, a w karcie wiersze ([SettingsRow]) oddzielone
/// cienką linią. [footer], na przykład „Zapisz”, stoi po prawej pod ostatnim wierszem.
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.title,
    required this.children,
    this.description,
    this.footer,
  });

  final String title;
  final String? description;
  final List<Widget> children;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget line() => Divider(height: 1, thickness: 1, color: AppColors.ring);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: text.titleMedium),
              if (description != null) ...[
                const SizedBox(height: 2),
                Text(description!, style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
              ],
            ],
          ),
        ),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, child) in children.indexed) ...[if (i > 0) line(), child],
              if (footer != null) ...[
                line(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Align(alignment: Alignment.centerRight, child: footer),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Wiersz ustawień: nazwa i opis po lewej, przełącznik, pole albo wybór po prawej ([trailing]).
/// [below] to treść pod wierszem na całą szerokość, na przykład podpowiedzi do kliknięcia.
class SettingsRow extends StatelessWidget {
  const SettingsRow({super.key, required this.title, this.description, this.trailing, this.below, this.muted = false});

  final String title;
  final String? description;
  final Widget? trailing;
  final Widget? below;

  /// Szary napis, na przykład „Brak platform”.
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            // Wiersze z przełącznikiem i z polem mają tę samą wysokość.
            constraints: const BoxConstraints(minHeight: 40),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: text.bodyMedium?.copyWith(
                          color: muted ? AppColors.textMuted : AppColors.text,
                          fontWeight: muted ? null : FontWeight.w500,
                        ),
                      ),
                      if (description != null) ...[
                        const SizedBox(height: 2),
                        Text(description!, style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 24), trailing!],
              ],
            ),
          ),
          if (below != null) ...[const SizedBox(height: 12), below!],
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

/// Podpowiedź po prawej stronie elementu, na wysokości jego środka (ikony w bocznym pasku).
/// Gdy z prawej brakuje miejsca, staje po lewej.
Offset tooltipOnRight(TooltipPositionContext c) {
  const gap = 8.0;
  const edge = 8.0;
  var x = c.target.dx + c.targetSize.width / 2 + gap;
  if (x + c.tooltipSize.width > c.overlaySize.width - edge) {
    x = c.target.dx - c.targetSize.width / 2 - gap - c.tooltipSize.width;
  }
  final maxY = c.overlaySize.height - c.tooltipSize.height - edge;
  final y = (c.target.dy - c.tooltipSize.height / 2).clamp(edge, maxY < edge ? edge : maxY);
  return Offset(x, y);
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

/// Wybór godziny kółkami jak w iOS (`showTimeWheel`). [allowEndOfDay] pozwala wybrać 24:00,
/// np. zamknięcie o północy albo koniec zmiany. Zwraca null po anulowaniu.
Future<TimeOfDay?> pickTime(
  BuildContext context, {
  required TimeOfDay initial,
  int minuteStep = 15,
  bool allowEndOfDay = false,
  String? title,
}) {
  return showTimeWheel(
    context,
    initial: initial,
    minuteStep: minuteStep,
    allowEndOfDay: allowEndOfDay,
    title: title,
  );
}

/// Przełącznik okresu w jednej pigułce: strzałka, napis i strzałka, np. „‹ 5–11 paź ›”.
/// Stuknięcie w napis wraca do bieżącego okresu ([onReset], null gdy już jest bieżący).
class StepSwitcher extends StatelessWidget {
  const StepSwitcher({
    super.key,
    required this.label,
    required this.onPrevious,
    required this.onNext,
    required this.previousTooltip,
    required this.nextTooltip,
    this.onReset,
    this.resetTooltip,
    this.labelWidth,
    this.extras = const [],
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final String previousTooltip;
  final String nextTooltip;
  final VoidCallback? onReset;
  final String? resetTooltip;

  /// Stała szerokość napisu, żeby strzałki nie skakały przy zmianie okresu.
  final double? labelWidth;

  /// Dodatkowe przyciski w tej samej pigułce za kreską, np. kalendarz: ikona, podpowiedź, akcja.
  final List<(AppIconData, String, VoidCallback?)> extras;

  /// Na całą dostępną szerokość: napis zajmuje miejsce między strzałkami ([labelWidth] się nie liczy).
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget caption = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        label,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: text.titleSmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
      ),
    );
    if (labelWidth != null && !expand) caption = SizedBox(width: labelWidth, child: caption);
    if (onReset != null) {
      caption = Tooltip(
        message: resetTooltip ?? '',
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onReset, child: caption),
        ),
      );
    }
    if (expand) caption = Expanded(child: caption);
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.ring),
      ),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: [
          _StepArrow(icon: AppIcons.caretLeft, tooltip: previousTooltip, onTap: onPrevious),
          caption,
          _StepArrow(icon: AppIcons.caretRight, tooltip: nextTooltip, onTap: onNext),
          for (final (icon, tooltip, onTap) in extras) ...[
            Container(width: 1, height: 20, margin: const EdgeInsets.symmetric(horizontal: 4), color: AppColors.ring),
            _StepArrow(icon: icon, tooltip: tooltip, onTap: onTap),
          ],
        ],
      ),
    );
  }
}

class _StepArrow extends StatelessWidget {
  const _StepArrow({required this.icon, required this.tooltip, required this.onTap});

  final AppIconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        type: MaterialType.transparency,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 32,
            height: 32,
            child: Center(
              child: Glyph(icon, size: 16, color: onTap == null ? AppColors.textDisabled : AppColors.text),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tydzień jako „5–11 paź”, a przez przełom miesiąca „28 wrz – 4 paź”. Inny rok dostaje rok na końcu.
String weekLabel(DateTime start, DateTime end) {
  final month = DateFormat('MMM', 'pl_PL');
  final year = end.year == DateTime.now().year ? '' : ' ${end.year}';
  if (start.month == end.month && start.year == end.year) {
    return '${start.day}–${end.day} ${month.format(end)}$year';
  }
  return '${start.day} ${month.format(start)} – ${end.day} ${month.format(end)}$year';
}

/// Wybór miesiąca w pigułce, np. „‹ Październik 2026 ›”. Dalej niż bieżący miesiąc się nie da.
class MonthSwitcher extends StatelessWidget {
  const MonthSwitcher({super.key, required this.month, required this.onChanged});

  /// Pierwszy dzień wybranego miesiąca.
  final DateTime month;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isCurrent = month.year == now.year && month.month == now.month;
    return StepSwitcher(
      label: Fmt.monthYear(month),
      labelWidth: 150,
      previousTooltip: 'Poprzedni miesiąc',
      nextTooltip: 'Następny miesiąc',
      onPrevious: () => onChanged(DateTime(month.year, month.month - 1)),
      onNext: isCurrent ? null : () => onChanged(DateTime(month.year, month.month + 1)),
      resetTooltip: 'Wróć do bieżącego miesiąca',
      onReset: isCurrent ? null : () => onChanged(DateTime(now.year, now.month)),
    );
  }
}
