import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/panel_widgets.dart';
import '../fleet/fleet_screen.dart' show UpperCaseFormatter;

const _tabular = [FontFeature.tabularFigures()];

String _date(DateTime d) => '${d.day}.${d.month.toString().padLeft(2, '0')}.${d.year}';

String _validity(DiscountCode c) => switch ((c.validFrom, c.validUntil)) {
  (null, null) => 'bez terminu',
  (final from?, null) => 'od ${_date(from)}',
  (null, final until?) => 'do ${_date(until)}',
  (final from?, final until?) => '${_date(from)} – ${_date(until)}',
};

/// Management → Kody rabatowe: kierownik tworzy kod, gość wpisuje go przy rezerwacji w aplikacji Table,
/// a rabat odejmuje się od rachunku stolika przy zamknięciu. Uprawnienie „Kody rabatowe”.
class DiscountsScreen extends ConsumerWidget {
  const DiscountsScreen({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref, String restaurantId, [DiscountCode? code]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _CodeDialog(restaurantId: restaurantId, code: code),
    );
    if (saved == true) ref.invalidate(discountCodesProvider(restaurantId));
  }

  Future<void> _toggle(BuildContext context, WidgetRef ref, String restaurantId, DiscountCode c, bool active) async {
    try {
      await ref.read(repositoryProvider).saveDiscountCode(
        restaurantId,
        id: c.id,
        code: c.code,
        percent: c.percent,
        value: c.value,
        validFrom: c.validFrom,
        validUntil: c.validUntil,
        maxUses: c.maxUses,
        active: active,
        note: c.note,
      );
      ref.invalidate(discountCodesProvider(restaurantId));
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, String restaurantId, DiscountCode c) async {
    final ok = await confirm(
      context,
      title: 'Usunąć kod ${c.code}?',
      message: 'Rezerwacje z tym kodem zachowają rabat.',
      action: 'Usuń',
      destructive: true,
    );
    if (!ok) return;
    try {
      await ref.read(repositoryProvider).deleteDiscountCode(c.id);
      ref.invalidate(discountCodesProvider(restaurantId));
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final restaurant = ref.watch(currentRestaurantProvider);
    if (restaurant == null) return const LoadingView();
    final text = Theme.of(context).textTheme;
    final canEdit = ref.watch(memberPermissionsProvider).contains('discounts');
    final async = ref.watch(discountCodesProvider(restaurant.id));
    final header = text.labelMedium?.copyWith(color: AppColors.textMuted);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          actions: [
            if (canEdit)
              FilledButton.icon(
                onPressed: () => _edit(context, ref, restaurant.id),
                icon: const Glyph(AppIcons.plus, size: 18),
                label: const Text('Nowy kod'),
              ),
          ],
        ),
        Expanded(
          child: async.when(
            skipLoadingOnReload: true,
            loading: () => const LoadingView(),
            error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(discountCodesProvider(restaurant.id))),
            data: (codes) => codes.isEmpty
                ? MessageView(
                    icon: AppIcons.sealPercent,
                    title: 'Brak kodów rabatowych',
                    message: 'Gość wpisuje kod przy rezerwacji w aplikacji Table, a rabat odejmuje się od rachunku.',
                    actionLabel: canEdit ? 'Nowy kod' : null,
                    onAction: canEdit ? () => _edit(context, ref, restaurant.id) : null,
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
                    child: Card(
                      margin: EdgeInsets.zero,
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                            child: Row(
                              children: [
                                Expanded(flex: 3, child: Text('Kod', style: header)),
                                Expanded(flex: 2, child: Text('Rabat', style: header)),
                                Expanded(flex: 3, child: Text('Ważność', style: header)),
                                Expanded(flex: 2, child: Text('Użycia', style: header)),
                                const SizedBox(width: 160),
                              ],
                            ),
                          ),
                          for (final c in codes) ...[
                            Divider(height: 1, color: AppColors.ring),
                            Opacity(
                              opacity: c.expired ? 0.55 : 1,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(20, 10, 12, 10),
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          SelectableText(
                                            c.code,
                                            style: text.titleSmall?.copyWith(letterSpacing: 1.2, fontFeatures: _tabular),
                                          ),
                                          if (c.note != null)
                                            Text(c.note!, style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(c.valueText, style: text.titleSmall?.copyWith(color: AppColors.accent)),
                                    ),
                                    Expanded(flex: 3, child: Text(_validity(c), style: text.bodyMedium)),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        c.maxUses == null ? '${c.uses}' : '${c.uses}/${c.maxUses}',
                                        style: text.bodyMedium?.copyWith(fontFeatures: _tabular),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 160,
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.end,
                                        children: [
                                          Tooltip(
                                            message: c.active ? 'Wyłącz kod' : 'Włącz kod',
                                            child: Switch(
                                              value: c.active,
                                              onChanged: canEdit ? (v) => _toggle(context, ref, restaurant.id, c, v) : null,
                                            ),
                                          ),
                                          IconButton(
                                            tooltip: 'Zmień',
                                            onPressed: canEdit ? () => _edit(context, ref, restaurant.id, c) : null,
                                            icon: const Glyph(AppIcons.pencil, size: 16),
                                          ),
                                          IconButton(
                                            tooltip: 'Usuń',
                                            onPressed: canEdit ? () => _delete(context, ref, restaurant.id, c) : null,
                                            icon: Glyph(AppIcons.trash, size: 16, color: AppColors.error),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

/// Nowy albo zmieniany kod: kod, rabat procentowy albo kwotowy, ważność, limit użyć i notatka.
class _CodeDialog extends ConsumerStatefulWidget {
  const _CodeDialog({required this.restaurantId, this.code});

  final String restaurantId;
  final DiscountCode? code;

  @override
  ConsumerState<_CodeDialog> createState() => _CodeDialogState();
}

class _CodeDialogState extends ConsumerState<_CodeDialog> {
  late final _code = TextEditingController(text: widget.code?.code ?? '');
  late final _value = TextEditingController(
    text: widget.code == null ? '' : (widget.code!.percent ? '${widget.code!.value}' : groszeToText(widget.code!.value)),
  );
  late final _limit = TextEditingController(text: widget.code?.maxUses?.toString() ?? '');
  late final _note = TextEditingController(text: widget.code?.note ?? '');
  late bool _percent = widget.code?.percent ?? true;
  late DateTime? _from = widget.code?.validFrom;
  late DateTime? _until = widget.code?.validUntil;
  late bool _active = widget.code?.active ?? true;
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    _value.dispose();
    _limit.dispose();
    _note.dispose();
    super.dispose();
  }

  void _generate() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    setState(() => _code.text = List.generate(8, (_) => chars[random.nextInt(chars.length)]).join());
  }

  Future<DateTime?> _pick(DateTime? initial) => showDatePicker(
    context: context,
    initialDate: initial ?? DateTime.now(),
    firstDate: DateTime.now().subtract(const Duration(days: 365)),
    lastDate: DateTime.now().add(const Duration(days: 730)),
  );

  Future<void> _save() async {
    final code = _code.text.trim().toUpperCase();
    final value = _percent ? int.tryParse(_value.text.trim()) : parseGrosze(_value.text);
    final limit = _limit.text.trim().isEmpty ? null : int.tryParse(_limit.text.trim());
    String? problem;
    if (!RegExp(r'^[A-Z0-9-]{3,20}$').hasMatch(code)) {
      problem = 'Kod ma od 3 do 20 znaków: litery bez polskich znaków, cyfry i myślnik.';
    } else if (value == null || value <= 0 || (_percent && value > 100)) {
      problem = _percent ? 'Wpisz procent od 1 do 100.' : 'Wpisz kwotę rabatu, na przykład 20.';
    } else if (_limit.text.trim().isNotEmpty && (limit == null || limit < 1)) {
      problem = 'Limit użyć to liczba od 1.';
    }
    if (problem != null) {
      showMessage(context, problem, tone: ToastTone.warning);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).saveDiscountCode(
        widget.restaurantId,
        id: widget.code?.id,
        code: code,
        percent: _percent,
        value: value!,
        validFrom: _from,
        validUntil: _until,
        maxUses: limit,
        active: _active,
        note: _note.text,
        memberId: ref.read(panelMemberProvider)?.dbMemberId,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AlertDialog(
      title: Text(widget.code == null ? 'Nowy kod rabatowy' : 'Kod rabatowy'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _code,
                    autofocus: widget.code == null,
                    maxLength: 20,
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9-]')), UpperCaseFormatter()],
                    style: const TextStyle(letterSpacing: 1.2, fontFeatures: _tabular),
                    decoration: const InputDecoration(labelText: 'Kod', hintText: 'Na przykład JESIEN10', counterText: ''),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(onPressed: _generate, child: const Text('Losuj')),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                SegmentedTabs<bool>(
                  options: const [(true, 'Procent'), (false, 'Kwota')],
                  selected: _percent,
                  onChanged: (v) => setState(() {
                    _percent = v;
                    _value.clear();
                  }),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _value,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(_percent ? r'[0-9]' : r'[0-9,.]'))],
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontFeatures: _tabular),
                    decoration: InputDecoration(labelText: 'Rabat', suffixText: _percent ? '%' : 'zł', isDense: true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final d = await _pick(_from);
                      if (d != null) setState(() => _from = d);
                    },
                    icon: const Glyph(AppIcons.calendar, size: 16),
                    label: Text(_from == null ? 'Ważny od: od razu' : 'Od ${_date(_from!)}'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final d = await _pick(_until);
                      if (d != null) setState(() => _until = d);
                    },
                    icon: const Glyph(AppIcons.calendar, size: 16),
                    label: Text(_until == null ? 'Do: bez terminu' : 'Do ${_date(_until!)}'),
                  ),
                ),
              ],
            ),
            if (_from != null || _until != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(() {
                    _from = null;
                    _until = null;
                  }),
                  child: const Text('Bez terminu'),
                ),
              ),
            const SizedBox(height: 10),
            TextField(
              controller: _limit,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Limit użyć', hintText: 'Puste: bez limitu'),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _note,
              maxLength: 200,
              decoration: const InputDecoration(labelText: 'Notatka', hintText: 'Na przykład dla stałych gości', counterText: ''),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: Text('Kod działa', style: text.titleSmall)),
                Switch(value: _active, onChanged: (v) => setState(() => _active = v)),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
          child: const Text('Anuluj'),
        ),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('Zapisz')),
      ],
    );
  }
}
