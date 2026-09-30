import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../data/providers.dart';

const _ratingWords = [
  '',
  'Słabo',
  'Przeciętnie',
  'Dobrze',
  'Bardzo dobrze',
  'Wybitnie',
];

class WriteReviewScreen extends ConsumerStatefulWidget {
  const WriteReviewScreen({
    super.key,
    required this.restaurantId,
    this.reservationId,
  });

  final String restaurantId;

  /// Z rezerwacją opinia jest zweryfikowana, bez niej nie.
  final String? reservationId;

  @override
  ConsumerState<WriteReviewScreen> createState() => _WriteReviewScreenState();
}

class _WriteReviewScreenState extends ConsumerState<WriteReviewScreen> {
  int _food = 0;
  int _service = 0;
  int _ambience = 0;
  final _body = TextEditingController();
  final _price = TextEditingController();
  bool _busy = false;

  bool get _complete => _food > 0 && _service > 0 && _ambience > 0;

  @override
  void dispose() {
    _body.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final priceText = _price.text.trim();
    final price = priceText.isEmpty ? null : int.tryParse(priceText);
    if (priceText.isNotEmpty && (price == null || price < 1 || price > 2000)) {
      showMessage(
        context,
        'Cena na osobę musi mieścić się między 1 a 2000 zł.',
      );
      return;
    }

    setState(() => _busy = true);
    try {
      await ref
          .read(repositoryProvider)
          .submitReview(
            restaurantId: widget.restaurantId,
            food: _food,
            service: _service,
            ambience: _ambience,
            body: _body.text,
            reservationId: widget.reservationId,
            pricePerPerson: price,
          );
      ref
        ..invalidate(reviewsProvider(widget.restaurantId))
        ..invalidate(restaurantProvider(widget.restaurantId))
        ..invalidate(myReviewedReservationsProvider)
        ..invalidate(searchResultsProvider);
      final reservationId = widget.reservationId;
      if (reservationId != null) {
        ref.invalidate(reservationDetailProvider(reservationId));
      }
      if (!mounted) return;
      showMessage(context, 'Dziękujemy za opinię.');
      context.pop();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final name = ref.watch(restaurantProvider(widget.restaurantId)).value?.name;
    final verified = widget.reservationId != null;

    return Scaffold(
      appBar: AppBar(title: Text(name ?? 'Opinia')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Text('Jak było?', style: text.headlineMedium),
          const SizedBox(height: 8),
          Text(
            verified
                ? 'Opinia zostanie oznaczona jako zweryfikowana wizyta i wpłynie na ranking kuchni.'
                : 'Bez rezerwacji w aplikacji opinia będzie niezweryfikowana. Będzie widoczna, '
                      'ale nie wpłynie na ranking ani na poziom cen. Weryfikacja paragonem pojawi się wkrótce.',
            style: text.bodyMedium?.copyWith(
              color: verified ? AppColors.accent : AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: Column(
                children: [
                  _RatingInput(
                    label: 'Kuchnia',
                    value: _food,
                    onChanged: (v) => setState(() => _food = v),
                  ),
                  const Divider(height: 1),
                  _RatingInput(
                    label: 'Obsługa',
                    value: _service,
                    onChanged: (v) => setState(() => _service = v),
                  ),
                  const Divider(height: 1),
                  _RatingInput(
                    label: 'Atmosfera',
                    value: _ambience,
                    onChanged: (v) => setState(() => _ambience = v),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _price,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4),
            ],
            style: const TextStyle(
              fontFeatures: [FontFeature.tabularFigures()],
            ),
            decoration: const InputDecoration(
              labelText: 'Średnia kwota na osobę (opcjonalnie)',
              suffixText: 'zł',
              helperText: 'Na tej podstawie ustalamy poziom cen lokalu.',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _body,
            maxLength: 2000,
            minLines: 4,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: 'Co warto wiedzieć o tym lokalu?',
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton(
          onPressed: !_complete || _busy ? null : _submit,
          child: Text(_complete ? 'Opublikuj opinię' : 'Oceń wszystkie trzy'),
        ),
      ),
    );
  }
}

/// Ocena w jednej osi. Gwiazdki dzielą szerokość karty po równo,
/// więc każda ma duże pole dotyku i żadna nie wychodzi poza ekran.
class _RatingInput extends StatelessWidget {
  const _RatingInput({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Text(
                value == 0
                    ? 'Dotknij gwiazdki'
                    : '$value/5 · ${_ratingWords[value]}',
                style: text.bodySmall?.copyWith(
                  color: value == 0
                      ? AppColors.textDisabled
                      : AppColors.textMuted,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              for (var i = 1; i <= 5; i++)
                Expanded(
                  child: _StarButton(
                    filled: i <= value,
                    selected: i == value,
                    semanticLabel: '$label: $i z 5',
                    onTap: () => onChanged(i),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StarButton extends StatelessWidget {
  const _StarButton({
    required this.filled,
    required this.selected,
    required this.semanticLabel,
    required this.onTap,
  });

  final bool filled;
  final bool selected;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      excludeSemantics: true,
      child: PressScale(
        onTap: onTap,
        child: SizedBox(
          height: 52,
          child: Center(
            child: Glyph(
              filled ? AppIcons.starFill : AppIcons.star,
              size: 36,
              color: filled ? AppColors.accent : AppColors.textDisabled,
            ),
          ),
        ),
      ),
    );
  }
}
