import 'package:material_ui/material_ui.dart';

/// Na tablecie ekran z treścią (lokal, rezerwacja, koszyk, ustawienia, logowanie) ma czytelną szerokość
/// i stoi na środku. Na telefonie bez zmian.
class TabletWidth extends StatelessWidget {
  const TabletWidth({super.key, required this.child, this.maxWidth = 820});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width <= maxWidth + 48) return child;
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      ),
    );
  }
}
