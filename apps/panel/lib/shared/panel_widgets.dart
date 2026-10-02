import 'dart:math' as math;

import 'package:flutter/rendering.dart';
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

/// Pasek nad treścią zakładki: rząd zakładek albo filtrów i przyciski po prawej, w jednym rzędzie.
/// Bez tytułu i opisu: nazwę zakładki widać w menu bocznym. [actionsInRow] false zostawia przyciski
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(32, 18, 32, below == null ? 18 : 16),
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
        ),
        // Cienka linia oddziela nagłówek z filtrami od treści strony.
        // W jasnym motywie sam pierścień ginie na białym tle.
        Divider(
          height: 1,
          thickness: 1,
          color: AppColors.palette.brightness == Brightness.dark
              ? AppColors.ring
              : AppColors.ringStrong,
        ),
        const SizedBox(height: 20),
      ],
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
      height: 36,
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

/// Przycisk z samą ikoną do akcji w nagłówku, na przykład „Nowa rezerwacja”.
/// W ciemnym motywie jest biały z białą poświatą: ikona główna w kolorze marki,
/// pozostałe szare. W jasnym motywie główny jest miętowy, a reszta obrysowana.
class GlowButton extends StatelessWidget {
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

  /// Szara ikona na białym przycisku w ciemnym motywie.
  static const _grey = Color(0xFF7A7A7A);

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.palette.brightness == Brightness.dark;
    const radius = BorderRadius.all(Radius.circular(12));

    final Color background;
    final Color iconColor;
    final List<BoxShadow> glow;
    BorderSide side = BorderSide.none;
    if (dark) {
      background = Colors.white;
      // Na białym tle jasna mięta ginie, więc marka występuje w ciemniejszym odcieniu.
      iconColor = primary ? AppPalette.light.accent : _grey;
      glow = [
        BoxShadow(color: Colors.white.withValues(alpha: 0.16), blurRadius: 14),
      ];
    } else if (primary) {
      background = AppColors.accentFill;
      iconColor = AppColors.onAccent;
      glow = [
        BoxShadow(
          color: AppColors.accentFill.withValues(alpha: 0.45),
          blurRadius: 12,
          offset: const Offset(0, 3),
        ),
      ];
    } else {
      background = AppColors.background;
      iconColor = AppColors.textMuted;
      side = BorderSide(color: AppColors.ringStrong);
      glow = [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.08),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ];
    }

    return Tooltip(
      message: tooltip,
      child: DecoratedBox(
        decoration: BoxDecoration(borderRadius: radius, boxShadow: glow),
        child: Material(
          color: background,
          shape: RoundedRectangleBorder(borderRadius: radius, side: side),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: SizedBox(
              width: 44,
              height: 40,
              child: Center(child: Glyph(icon, size: iconSize, color: iconColor)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Kolorowa kostka z ikoną, jak w kaflach liczb i nagłówkach kart.
class IconBadge extends StatelessWidget {
  const IconBadge(this.icon, {super.key, required this.color, this.size = 34});

  final AppIconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(size / 3),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.35),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Glyph(icon.duotone, size: size * 0.52, color: Colors.white),
    );
  }
}

/// Barwy kafli liczb. Każda miara ma swój kolor, ten sam co jej słupki na wykresie.
abstract final class TileColors {
  static const green = Color(0xFF2FB673);
  static const blue = Color(0xFF3B82F6);
  static const amber = Color(0xFFD99A15);
  static const violet = Color(0xFF7C5CFF);
  static const rose = Color(0xFFD9455F);
}

/// Liczba z opisem, na przykład „14 gości”. Z ikoną w kolorowej kostce
/// i zmianą względem poprzedniego okresu.
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

  /// Kolor kostki z ikoną.
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
                  const SizedBox(width: 10),
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
  });

  final List<(T, String)> options;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return _SlidingSegments(
      selectedIndex: options.indexWhere((o) => o.$1 == selected),
      children: [
        for (final (value, label) in options)
          _TextSegment(
            label: label,
            selected: value == selected,
            onTap: () => onChanged(value),
          ),
      ],
    );
  }
}

/// Zakładki jako same ikony. Wybrana rozsuwa się i pokazuje nazwę obok ikony, a podświetlenie
/// płynie do niej od poprzedniej. Pozostałe mają nazwę w podpowiedzi po najechaniu myszą.
class IconTabs<T> extends StatelessWidget {
  const IconTabs({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final List<(T, AppIconData, String)> options;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return _SlidingSegments(
      selectedIndex: options.indexWhere((o) => o.$1 == selected),
      children: [
        for (final (value, icon, label) in options)
          _IconSegment(
            icon: icon,
            label: label,
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
  const _SlidingSegments({required this.selectedIndex, required this.children});

  /// -1: nic nie jest wybrane.
  final int selectedIndex;
  final List<Widget> children;

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
    required this.progress,
    required this.decoration,
    required super.children,
  });

  final int selected;
  final Animation<double> progress;
  final BoxDecoration decoration;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderIndicatorRow(selected, progress, decoration, createLocalImageConfiguration(context));

  @override
  void updateRenderObject(BuildContext context, _RenderIndicatorRow renderObject) {
    renderObject
      ..selected = selected
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
  _RenderIndicatorRow(this._selected, this._progress, this._decoration, this._configuration);

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

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final loose = BoxConstraints(maxHeight: constraints.maxHeight);
    var width = 0.0;
    var height = 0.0;
    for (final c in _children) {
      final s = c.getDryLayout(loose);
      width += s.width;
      height = math.max(height, s.height);
    }
    return constraints.constrain(Size(width, height));
  }

  @override
  void performLayout() {
    final loose = BoxConstraints(maxHeight: constraints.maxHeight);
    var height = 0.0;
    for (final c in _children) {
      c.layout(loose, parentUsesSize: true);
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

/// Opcja z samym napisem.
class _TextSegment extends StatefulWidget {
  const _TextSegment({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

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
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              child: TweenAnimationBuilder<Color?>(
                tween: ColorTween(end: _segmentColor(selected: widget.selected, hovered: _hovered)),
                duration: const Duration(milliseconds: 200),
                curve: AppMotion.easeOut,
                builder: (context, color, _) => Text(
                  widget.label,
                  style: text.labelLarge?.copyWith(color: color),
                ),
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
  });

  final AppIconData icon;
  final String label;
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
                              style: text.labelLarge?.copyWith(color: AppColors.text),
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
    return selected ? tab : Tooltip(message: widget.label, child: tab);
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

/// Wybór miesiąca: strzałki i nazwa, np. „Październik 2026”. Dalej niż bieżący miesiąc się nie da.
class MonthSwitcher extends StatelessWidget {
  const MonthSwitcher({super.key, required this.month, required this.onChanged});

  /// Pierwszy dzień wybranego miesiąca.
  final DateTime month;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isCurrent = month.year == now.year && month.month == now.month;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlowButton(
          icon: AppIcons.caretLeft,
          tooltip: 'Poprzedni miesiąc',
          onPressed: () => onChanged(DateTime(month.year, month.month - 1)),
        ),
        SizedBox(
          width: 164,
          child: Text(
            Fmt.monthYear(month),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        GlowButton(
          icon: AppIcons.caretRight,
          tooltip: 'Następny miesiąc',
          onPressed: isCurrent ? null : () => onChanged(DateTime(month.year, month.month + 1)),
        ),
      ],
    );
  }
}
