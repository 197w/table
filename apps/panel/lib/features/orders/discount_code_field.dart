import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../data/models.dart';
import '../../data/providers.dart';

/// Kod rabatowy przy zamykaniu rachunku. Podczas wpisywania pod polem pojawiają się kody lokalu, które działają
/// dziś (Management → Kody rabatowe). Kod przy rachunku zastępuje kod z rezerwacji; „Usuń” go zdejmuje.
class DiscountCodeField extends ConsumerStatefulWidget {
  const DiscountCodeField({super.key, required this.restaurantId, required this.orderId, required this.due});

  final String restaurantId;
  final String orderId;
  final OrderDue? due;

  @override
  ConsumerState<DiscountCodeField> createState() => _DiscountCodeFieldState();
}

class _DiscountCodeFieldState extends ConsumerState<DiscountCodeField> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _set(String? code) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(repositoryProvider)
          .setOrderDiscount(widget.orderId, code, memberId: ref.read(panelMemberProvider)?.dbMemberId);
      ref.invalidate(orderDueProvider(widget.orderId));
      _controller.clear();
      if (mounted) {
        showMessage(
          context,
          code == null ? 'Kod usunięty z rachunku.' : 'Kod ${code.toUpperCase()} dodany do rachunku.',
          tone: ToastTone.success,
        );
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _apply(String text) {
    final code = text.trim();
    if (code.isEmpty || _busy) return;
    _set(code);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final due = widget.due;
    final code = due?.code;

    if (code != null) {
      return Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
        decoration: BoxDecoration(
          color: AppColors.accentTint,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Glyph(AppIcons.sealPercent, size: 18, color: AppColors.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Kod ${due?.label ?? code}${due?.reservationCode != null ? ' zamiast kodu z rezerwacji' : ''}',
                style: text.bodyMedium,
              ),
            ),
            TextButton(
              onPressed: _busy ? null : () => _set(null),
              style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
              child: const Text('Usuń'),
            ),
          ],
        ),
      );
    }

    return RawAutocomplete<DiscountHint>(
      textEditingController: _controller,
      focusNode: _focus,
      displayStringForOption: (h) => h.code,
      optionsBuilder: (value) async {
        try {
          return await ref.read(repositoryProvider).discountSuggestions(widget.restaurantId, value.text);
        } catch (_) {
          return const <DiscountHint>[];
        }
      },
      onSelected: (h) => _apply(h.code),
      fieldViewBuilder: (context, controller, focus, _) => Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focus,
              enabled: !_busy,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9-]')),
                LengthLimitingTextInputFormatter(20),
                _UpperCase(),
              ],
              // Enter dodaje wpisany kod (podpowiedź wybiera się kliknięciem).
              onSubmitted: _apply,
              decoration: InputDecoration(
                labelText: 'Kod rabatowy',
                hintText: due?.reservationCode != null ? 'Zastąpi kod z rezerwacji' : 'Wpisz albo wybierz z listy',
                isDense: true,
                prefixIcon: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Glyph(AppIcons.sealPercent, size: 16, color: AppColors.textMuted),
                ),
                prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              ),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: _busy ? null : () => _apply(controller.text),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
            child: const Text('Dodaj'),
          ),
        ],
      ),
      optionsViewBuilder: (context, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Material(
            color: AppColors.surfaceRaised,
            elevation: 6,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260, maxWidth: 440),
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 6),
                shrinkWrap: true,
                children: [
                  for (final o in options)
                    InkWell(
                      onTap: () => onSelected(o),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                        child: Row(
                          children: [
                            Text(o.code, style: text.labelLarge),
                            const SizedBox(width: 10),
                            Text(o.valueText, style: text.labelLarge?.copyWith(color: AppColors.accent)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                [
                                  ?o.note,
                                  if (o.usesLeft != null) 'zostało ${o.usesLeft}',
                                ].join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                              ),
                            ),
                          ],
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
  }
}

/// Kody są wielkimi literami.
class _UpperCase extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) =>
      newValue.copyWith(text: newValue.text.toUpperCase());
}
