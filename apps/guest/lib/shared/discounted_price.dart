import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../data/models.dart';

/// Cena dania w menu jako tekst: „od 32,00 zł” przy wariantach o różnych cenach, a gdy trwa wydarzenie ze zniżką na
/// dział dania (0092), cena po zniżce („−20% 25,60 zł”).
String menuPriceText(MenuItem item, [DateTime? at]) {
  final pct = item.discountAt(at);
  final price = item.priceAfterDiscount(item.priceGrosze, at);
  final text = item.priceVaries ? 'od ${Fmt.price(price)}' : Fmt.price(price);
  return pct > 0 ? '−$pct% $text' : text;
}

/// Cena dania na liście: bez zniżki zwykły napis, ze zniżką dawna cena przekreślona obok ceny po zniżce.
class DiscountedPrice extends StatelessWidget {
  const DiscountedPrice({super.key, required this.item, required this.style});

  final MenuItem item;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final pct = item.discountAt();
    final now = item.priceAfterDiscount(item.priceGrosze);
    final shown = item.priceVaries ? 'od ${Fmt.price(now)}' : Fmt.price(now);
    if (pct <= 0) return Text(shown, style: style);
    final was = item.priceVaries ? 'od ${Fmt.price(item.priceGrosze)}' : Fmt.price(item.priceGrosze);
    final muted = style?.copyWith(
      color: AppColors.textMuted,
      fontWeight: FontWeight.w400,
      decoration: TextDecoration.lineThrough,
      decorationColor: AppColors.textMuted,
    );
    return Semantics(
      label: '$shown, zniżka $pct procent, wcześniej $was',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(shown, style: style),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  '−$pct%',
                  style: style?.copyWith(fontSize: (style?.fontSize ?? 14) * 0.75, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 6),
              Text(was, style: muted?.copyWith(fontSize: (style?.fontSize ?? 14) * 0.8)),
            ],
          ),
        ],
      ),
    );
  }
}
