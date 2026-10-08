import 'package:material_ui/material_ui.dart';

/// Kolory osób przy stoliku (podział rachunku), po kolei.
const _personColors = [
  Color(0xFF3B82F6),
  Color(0xFFD946EF),
  Color(0xFFF59E0B),
  Color(0xFF10B981),
  Color(0xFFEF4444),
  Color(0xFF8B5CF6),
];

Color personColor(int guest) => _personColors[(guest - 1) % _personColors.length];

/// Kółko z numerem osoby przy pozycji rachunku.
class PersonBadge extends StatelessWidget {
  const PersonBadge(this.guest, {super.key, this.size = 20});

  final int guest;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: personColor(guest), shape: BoxShape.circle),
      child: Text(
        '$guest',
        style: TextStyle(
          fontSize: size * 0.55,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
