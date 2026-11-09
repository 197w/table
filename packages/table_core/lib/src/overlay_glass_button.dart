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
/// Natywny przycisk jest cały czas (prośba użytkownika, 9.11.2026: „non stop ma być liquid glass”), także gdy
/// okno wjeżdża, zjeżdża, jest przeciągane albo podnosi się nad klawiaturę: po każdej klatce, w której jego miejsce
/// się ruszyło, dostaje nowe położenie. Szkło rysowane przez Fluttera ([GlassSurface]) jest tylko pod drugim
/// oknem (natywny leżałby nad nim) i gdy natywnego nie da się pokazać. Tylko na iOS 26 ([nativeLiquidGlass]).
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

  /// Ikona szkła rysowanego przez Fluttera (pod drugim oknem i dla czytnika ekranu).
  final AppIconData icon;
  final String label;
  final VoidCallback onTap;

  /// Średnica szkła. Pole dotyku co najmniej 48.
  final double size;

  @override
  State<OverlayGlassButton> createState() => _OverlayGlassButtonState();
}

class _OverlayGlassButtonState extends State<OverlayGlassButton> {
  final _glass = GlobalKey();
  late final int _id = TableGlass.register(_pressed);
  ModalRoute<Object?>? _route;

  /// Położenie, które dostał natywny przycisk.
  Rect? _sent;

  /// Wygląd natywnego przycisku (motyw), żeby zmiana motywu pokazała go od nowa.
  String? _style;

  /// Natywny przycisk widać (szkło Fluttera schowane).
  bool _native = false;

  /// Wysłano „pokaż” i nie wysłano „schowaj”.
  bool _requested = false;

  /// Natywnego nie da się pokazać (np. brak wtyczki): zostaje szkło Fluttera.
  bool _unavailable = false;

  /// Numer prośby o pokazanie; każde schowanie go zmienia, więc spóźniona odpowiedź nic nie pokaże.
  int _generation = 0;

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
    TableGlass.remove(_id);
    super.dispose();
  }

  /// Po każdej klatce sprawdza miejsce przycisku. Nie zamawia klatek, więc w spoczynku nic nie kosztuje.
  void _watchFrames() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _check();
      _watchFrames();
    });
  }

  /// Okno przykryte innym oknem albo stroną (ale nie zamykane: wtedy przycisk zjeżdża z nim).
  bool get _covered {
    final route = _route;
    return route != null && route.isActive && !route.isCurrent;
  }

  String get _currentStyle => '${AppColors.palette.brightness}-${AppColors.text.toARGB32()}';

  Rect? _measure() {
    final box = _glass.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  void _check() {
    if (_unavailable) return;
    final rect = _measure();
    if (rect == null || _covered) {
      _hideNative();
    } else if (!_requested || _style != _currentStyle) {
      _show(rect);
    } else if (rect != _sent) {
      _sent = rect;
      TableGlass.move(_id, rect);
    }
  }

  Future<void> _show(Rect rect) async {
    final generation = ++_generation;
    _requested = true;
    _style = _currentStyle;
    _sent = rect;
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
      _requested = false;
      setState(() => _unavailable = true);
      return;
    }
    if (!_native) setState(() => _native = true);
  }

  void _hideNative() {
    _generation++;
    if (_requested) {
      _requested = false;
      TableGlass.hide(_id);
    }
    if (_native) setState(() => _native = false);
  }

  /// Stuknięcie w natywny przycisk.
  void _pressed() {
    if (mounted) widget.onTap();
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
            child: Opacity(
              // Pod natywnym szkłem nic z Fluttera (prześwitywałoby).
              opacity: _native ? 0 : 1,
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
