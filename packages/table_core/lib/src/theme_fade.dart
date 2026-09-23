import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

/// Płynne przejście przy zmianie motywu. Przed zmianą robi zdjęcie ekranu,
/// kładzie je na nowym motywie i wygasza, więc stary wygląd przechodzi w nowy
/// zamiast przeskoczyć. Owijamy nim całą aplikację, nad MaterialApp.
class ThemeFade extends StatefulWidget {
  const ThemeFade({super.key, required this.child});

  final Widget child;

  /// Zmienia motyw z przejściem. [change] to zwykła zmiana ustawienia motywu.
  /// Bez [ThemeFade] nad [context] albo przy ograniczeniu animacji zmienia od razu.
  static Future<void> run(BuildContext context, VoidCallback change) async {
    final state = context.findAncestorStateOfType<_ThemeFadeState>();
    if (state == null || MediaQuery.disableAnimationsOf(context)) {
      change();
      return;
    }
    await state._capture(MediaQuery.devicePixelRatioOf(context));
    change();
    state._play();
  }

  @override
  State<ThemeFade> createState() => _ThemeFadeState();
}

class _ThemeFadeState extends State<ThemeFade> with SingleTickerProviderStateMixin {
  final _boundary = GlobalKey();
  late final _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );
  ui.Image? _snapshot;

  @override
  void initState() {
    super.initState();
    _fade.addStatusListener((status) {
      if (status == AnimationStatus.completed) _clear();
    });
  }

  @override
  void dispose() {
    _fade.dispose();
    _snapshot?.dispose();
    super.dispose();
  }

  Future<void> _capture(double pixelRatio) async {
    final boundary = _boundary.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null || !boundary.hasSize) return;
    try {
      final image = await boundary.toImage(pixelRatio: pixelRatio);
      if (!mounted) {
        image.dispose();
        return;
      }
      _snapshot?.dispose();
      setState(() => _snapshot = image);
    } catch (_) {
      // Bez zdjęcia motyw zmieni się bez przejścia.
    }
  }

  void _play() {
    if (_snapshot == null) return;
    _fade.forward(from: 0);
  }

  void _clear() {
    final old = _snapshot;
    setState(() => _snapshot = null);
    old?.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(key: _boundary, child: widget.child),
          if (snapshot != null)
            IgnorePointer(
              child: FadeTransition(
                opacity: ReverseAnimation(
                  CurvedAnimation(parent: _fade, curve: Curves.easeInOut),
                ),
                child: RawImage(image: snapshot, fit: BoxFit.fill),
              ),
            ),
        ],
      ),
    );
  }
}
