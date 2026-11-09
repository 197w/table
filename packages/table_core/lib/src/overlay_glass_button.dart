import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_glass/table_glass.dart';

import 'app_icons.dart';
import 'liquid_glass.dart';
import 'theme.dart';
import 'widgets.dart';

/// Okrągły przycisk Liquid Glass (iOS 26) jako prawdziwy przycisk UIKit nad widokiem Fluttera
/// (`package:table_glass`), a nie widok platformy w drzewie Fluttera. Do miejsc, gdzie widok platformy psuł
/// ekran: „Zamknij” w oknie od dołu (9.11.2026: natywny widok platformy w oknie blokował na iPhonie całe okno,
/// trzy próby; prośba użytkownika: „żeby działały okna i był tam przycisk zamknięcia w liquid glass”).
///
/// Natywny przycisk stoi tylko wtedy, gdy jego miejsce się nie rusza: okno wjechało, nic go nie przykrywa
/// (trasa jest na wierzchu) i od ostatniej zmiany położenia minęła chwila. W ruchu (wjazd i zjazd okna,
/// przeciąganie, klawiatura) natywny się chowa, a w tym samym miejscu jest szkło rysowane przez Fluttera
/// ([GlassSurface]); przy pokazaniu natywnego przechodzą jedno w drugie. Tylko na iOS 26 ([nativeLiquidGlass]).
class OverlayGlassButton extends StatefulWidget {
  const OverlayGlassButton({
    super.key,
    required this.symbol,
    required this.icon,
    required this.label,
    required this.onTap,
    this.size = 44,
  });

  /// Symbol SF natywnego przycisku.
  final String symbol;

  /// Ikona szkła rysowanego przez Fluttera (w ruchu i dla czytnika ekranu).
  final AppIconData icon;
  final String label;
  final VoidCallback onTap;

  /// Średnica szkła. Pole dotyku co najmniej 48.
  final double size;

  @override
  State<OverlayGlassButton> createState() => _OverlayGlassButtonState();
}

class _OverlayGlassButtonState extends State<OverlayGlassButton> {
  /// Ile położenie musi stać, zanim pojawi się natywny przycisk.
  static const _settleDelay = Duration(milliseconds: 120);

  final _glass = GlobalKey();
  late final int _id = TableGlass.register(_pressed);
  ModalRoute<Object?>? _route;

  /// Położenie szkła w poprzedniej klatce.
  Rect? _rect;

  /// Wygląd natywnego przycisku (motyw), żeby zmiana motywu pokazała go od nowa.
  String? _style;

  /// Natywny przycisk widać (szkło Fluttera schowane).
  bool _native = false;

  /// Wysłano „pokaż” i nie wysłano „schowaj”.
  bool _requested = false;

  /// Numer prośby o pokazanie; każde schowanie go zmienia, więc spóźniona odpowiedź nic nie pokaże.
  int _generation = 0;
  Timer? _settle;

  @override
  void initState() {
    super.initState();
    _watchFrames();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  @override
  void dispose() {
    _settle?.cancel();
    TableGlass.remove(_id);
    super.dispose();
  }

  /// Po każdej klatce sprawdza, czy miejsce przycisku się ruszyło. Nie zamawia klatek, więc w spoczynku nic nie
  /// kosztuje.
  void _watchFrames() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _check();
      _watchFrames();
    });
  }

  bool get _routeSettled {
    final route = _route;
    if (route == null) return true;
    return route.isCurrent && route.isActive && route.animation?.status == AnimationStatus.completed;
  }

  String get _currentStyle => '${AppColors.palette.brightness}-${AppColors.text.toARGB32()}';

  Rect? _measure() {
    final box = _glass.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  void _check() {
    final rect = _measure();
    final moved = rect != _rect;
    _rect = rect;
    if (moved || rect == null || !_routeSettled || (_requested && _style != _currentStyle)) {
      _hideNative();
      _settle?.cancel();
      _settle = Timer(_settleDelay, _trySettle);
    } else if (!_requested && _settle == null) {
      _settle = Timer(_settleDelay, _trySettle);
    }
  }

  Future<void> _trySettle() async {
    _settle = null;
    if (!mounted || _requested) return;
    final rect = _measure();
    if (rect == null || rect != _rect || !_routeSettled) return;
    final generation = ++_generation;
    final style = _currentStyle;
    _requested = true;
    _style = style;
    final ok = await TableGlass.show(
      _id,
      rect: rect,
      symbol: widget.symbol,
      symbolSize: widget.size * 0.43,
      dark: AppColors.palette.brightness == Brightness.dark,
      color: AppColors.text,
    );
    if (!mounted || generation != _generation) return;
    if (!ok) {
      // Bez natywnego przycisku zostaje szkło Fluttera, bez kolejnych prób.
      _requested = false;
      return;
    }
    setState(() => _native = true);
  }

  void _hideNative() {
    _generation++;
    if (_requested) {
      _requested = false;
      TableGlass.hide(_id);
    }
    if (_native) setState(() => _native = false);
  }

  /// Stuknięcie w natywny przycisk (natywny już się schował).
  void _pressed() {
    if (!mounted) return;
    _generation++;
    _requested = false;
    if (_native) setState(() => _native = false);
    widget.onTap();
    // Jeśli okno zostaje (np. nie da się go zamknąć), natywny wraca po chwili.
    _settle?.cancel();
    _settle = Timer(const Duration(milliseconds: 300), _trySettle);
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final tap = size < 48 ? 48.0 : size;
    return Semantics(
      button: true,
      label: widget.label,
      excludeSemantics: true,
      // Natywny przycisk jest ukryty przed czytnikiem ekranu; czyta i stuka ten.
      onTap: widget.onTap,
      child: SizedBox(
        width: tap,
        height: tap,
        child: Center(
          child: SizedBox(
            key: _glass,
            width: size,
            height: size,
            child: AnimatedOpacity(
              // Natywne szkło pojawia się w 0,15 s, a szkło Fluttera w tym czasie znika. W drugą stronę od razu:
              // natywny chowa się w tej samej chwili.
              opacity: _native ? 0 : 1,
              duration: _native ? const Duration(milliseconds: 150) : Duration.zero,
              child: PressScale(
                onTap: widget.onTap,
                child: GlassSurface(
                  circle: true,
                  child: Center(child: Glyph(widget.icon, size: size * 0.45, color: AppColors.text)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
