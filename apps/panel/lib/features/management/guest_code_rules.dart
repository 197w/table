import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/panel_widgets.dart';

const _tabular = [FontFeature.tabularFigures()];

/// Kody rabatowe → „Automatyczne kody dla gości”: po zrealizowanej rezerwacji i po zweryfikowanej opinii gość
/// dostaje osobisty kod do tego lokalu (aplikacja Table, „Moje” → „Kody”). Kod aktywuje przy stoliku na 15 minut,
/// kelner wpisuje go przy rachunku jak zwykły kod.
class GuestCodeRules extends ConsumerWidget {
  const GuestCodeRules({super.key, required this.restaurantId, required this.canEdit});

  final String restaurantId;
  final bool canEdit;

  Future<void> _save(BuildContext context, WidgetRef ref, GuestCodeRule rule) async {
    try {
      await ref
          .read(repositoryProvider)
          .saveGuestCodeRule(restaurantId, rule, memberId: ref.read(panelMemberProvider)?.dbMemberId);
      ref.invalidate(guestCodeRulesProvider(restaurantId));
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, GuestCodeRule rule) async {
    final changed = await showDialog<GuestCodeRule>(
      context: context,
      builder: (_) => _RuleDialog(rule: rule),
    );
    if (changed != null && context.mounted) await _save(context, ref, changed);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final rules = ref.watch(guestCodeRulesProvider(restaurantId)).value ?? const <GuestCodeRule>[];
    if (rules.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Automatyczne kody dla gości', style: text.titleMedium),
        const SizedBox(height: 2),
        Text(
          'Gość widzi kod w aplikacji Table w „Moje” → „Kody”. Aktywuje go przy stoliku na 15 minut i pokazuje '
          'kelnerowi, który wpisuje go przy rachunku. Kodów nie da się przekazać innym osobom.',
          style: text.bodySmall?.copyWith(color: AppColors.textMuted),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (i, rule) in rules.indexed) ...[
              if (i > 0) const SizedBox(width: 16),
              Expanded(
                child: PanelCard(
                  title: rule.title,
                  icon: rule.event == 'review' ? AppIcons.chatCircle : AppIcons.calendarCheck,
                  iconColor: rule.event == 'review' ? TileColors.amber : TileColors.violet,
                  trailing: Switch(
                    value: rule.active,
                    onChanged: canEdit ? (v) => _save(context, ref, rule.copyWith(active: v)) : null,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(rule.description, style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            rule.valueText,
                            style: text.headlineSmall?.copyWith(
                              color: rule.active ? AppColors.accent : AppColors.textMuted,
                              fontWeight: FontWeight.w600,
                              fontFeatures: _tabular,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 3),
                              child: Text(
                                [
                                  if (rule.minGrosze != null) 'od ${discountMoney(rule.minGrosze!)}',
                                  'ważny ${rule.validDays} dni',
                                ].join(' · '),
                                style: text.bodyMedium?.copyWith(fontFeatures: _tabular),
                              ),
                            ),
                          ),
                          if (canEdit)
                            TextButton.icon(
                              onPressed: () => _edit(context, ref, rule),
                              icon: const Glyph(AppIcons.pencil, size: 15),
                              label: const Text('Zmień'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Wydane: ${rule.issued} · wykorzystane: ${rule.used}',
                        style: text.bodySmall?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _RuleDialog extends StatefulWidget {
  const _RuleDialog({required this.rule});

  final GuestCodeRule rule;

  @override
  State<_RuleDialog> createState() => _RuleDialogState();
}

class _RuleDialogState extends State<_RuleDialog> {
  late bool _percent = widget.rule.percent;
  late final _value = TextEditingController(
    text: widget.rule.percent ? '${widget.rule.value}' : groszeToText(widget.rule.value),
  );
  late final _min = TextEditingController(
    text: widget.rule.minGrosze == null ? '' : groszeToText(widget.rule.minGrosze!),
  );
  late final _days = TextEditingController(text: '${widget.rule.validDays}');

  @override
  void dispose() {
    _value.dispose();
    _min.dispose();
    _days.dispose();
    super.dispose();
  }

  void _save() {
    final value = _percent ? int.tryParse(_value.text.trim()) : parseGrosze(_value.text);
    final min = _min.text.trim().isEmpty ? null : parseGrosze(_min.text);
    final days = int.tryParse(_days.text.trim());
    String? problem;
    if (value == null || value <= 0 || (_percent && value > 100)) {
      problem = _percent ? 'Wpisz procent od 1 do 100.' : 'Wpisz kwotę rabatu, na przykład 20.';
    } else if (_min.text.trim().isNotEmpty && (min == null || min <= 0)) {
      problem = 'Wpisz minimalną kwotę rachunku, na przykład 100.';
    } else if (min != null && !_percent && min < value) {
      problem = 'Minimalna kwota rachunku nie może być mniejsza niż rabat.';
    } else if (days == null || days < 1 || days > 365) {
      problem = 'Ważność kodu to od 1 do 365 dni.';
    }
    if (problem != null) {
      showMessage(context, problem, tone: ToastTone.warning);
      return;
    }
    Navigator.pop(
      context,
      widget.rule.copyWith(percent: _percent, value: value, validDays: days, minGrosze: () => min, active: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.rule.title),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
                    autofocus: true,
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
            TextField(
              controller: _min,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))],
              textAlign: TextAlign.right,
              style: const TextStyle(fontFeatures: _tabular),
              decoration: const InputDecoration(
                labelText: 'Minimalna kwota rachunku',
                hintText: 'Puste: od każdej kwoty',
                suffixText: 'zł',
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _days,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textAlign: TextAlign.right,
              style: const TextStyle(fontFeatures: _tabular),
              decoration: const InputDecoration(labelText: 'Ważny przez', suffixText: 'dni'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
          child: const Text('Anuluj'),
        ),
        FilledButton(onPressed: _save, child: const Text('Zapisz i włącz')),
      ],
    );
  }
}
