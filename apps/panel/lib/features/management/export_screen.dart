import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../data/providers.dart';
import '../../shared/panel_widgets.dart';
import 'export_csv.dart';

typedef ExportQuery = ({String restaurantId, DateTime month});

final exportMonthProvider = FutureProvider.autoDispose.family<MonthExport, ExportQuery>((ref, q) async {
  final json = await ref.watch(repositoryProvider).exportMonth(q.restaurantId, q.month);
  return MonthExport.fromJson(json);
});

/// Management → Eksport: pliki CSV dla księgowej za wybrany miesiąc (rachunki z VAT, zestawienie dzienne,
/// czas pracy z wynagrodzeniami, petty cash). Otwierają się w Excelu. Uprawnienie „Eksport”.
class ExportScreen extends ConsumerStatefulWidget {
  const ExportScreen({super.key});

  @override
  ConsumerState<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends ConsumerState<ExportScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  String get _suffix => '${_month.year}-${_month.month.toString().padLeft(2, '0')}';

  Future<void> _save(String name, String content) async {
    final location = await getSaveLocation(
      suggestedName: '$name-$_suffix.csv',
      acceptedTypeGroups: const [XTypeGroup(label: 'CSV', extensions: ['csv'])],
    );
    if (location == null) return;
    try {
      final path = location.path.toLowerCase().endsWith('.csv') ? location.path : '${location.path}.csv';
      await File(path).writeAsString(content, flush: true);
      if (mounted) showMessage(context, 'Zapisano: ${path.split(Platform.pathSeparator).last}.', tone: ToastTone.success);
    } catch (e) {
      if (mounted) showError(context, const AppFailure('Nie udało się zapisać pliku. Wybierz inny folder.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final restaurant = ref.watch(currentRestaurantProvider);
    if (restaurant == null) return const LoadingView();
    final query = (restaurantId: restaurant.id, month: _month);
    final async = ref.watch(exportMonthProvider(query));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          actions: [MonthSwitcher(month: _month, onChanged: (m) => setState(() => _month = m))],
        ),
        Expanded(
          child: async.when(
            skipLoadingOnReload: true,
            loading: () => const LoadingView(),
            error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(exportMonthProvider(query))),
            data: (e) {
              final hours = e.hours.fold(0, (s, h) => s + h.seconds);
              final payroll = e.hours.fold(0, (s, h) => s + (h.earningsGrosze ?? 0));
              final petty = e.petty.fold(0, (s, p) => s + (p.out ? -p.amountGrosze : p.amountGrosze));
              final days = {for (final o in e.orders) csvDate(o.closedAt)}.length;
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
                child: LayoutBuilder(
                  builder: (context, box) {
                    final width = (box.maxWidth - 16) / 2;
                    return Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        SizedBox(
                          width: width,
                          child: _ExportCard(
                            title: 'Sprzedaż: rachunki',
                            icon: AppIcons.receipt,
                            color: TileColors.green,
                            value: Fmt.price(e.revenueGrosze),
                            detail: '${e.orders.length} rachunków · stawki VAT, płatności, rabaty i napiwki',
                            onSave: e.orders.isEmpty ? null : () => _save('sprzedaz-rachunki', salesCsv(e)),
                          ),
                        ),
                        SizedBox(
                          width: width,
                          child: _ExportCard(
                            title: 'Sprzedaż: dzień po dniu',
                            icon: AppIcons.calendarDots,
                            color: TileColors.blue,
                            value: '$days dni',
                            detail: 'Zestawienie dzienne z VAT i formami płatności',
                            onSave: e.orders.isEmpty ? null : () => _save('sprzedaz-dzienna', dailyCsv(e)),
                          ),
                        ),
                        SizedBox(
                          width: width,
                          child: _ExportCard(
                            title: 'Czas pracy i wynagrodzenia',
                            icon: AppIcons.clockUser,
                            color: TileColors.violet,
                            value: '${(hours / 3600).toStringAsFixed(1).replaceAll('.', ',')} h',
                            detail: '${e.hours.length} pracowników · brutto ${Fmt.price(payroll)}',
                            onSave: e.hours.isEmpty ? null : () => _save('czas-pracy', hoursCsv(e)),
                          ),
                        ),
                        SizedBox(
                          width: width,
                          child: _ExportCard(
                            title: 'Petty cash',
                            icon: AppIcons.coins,
                            color: TileColors.amber,
                            value: '${petty < 0 ? '−' : '+'}${Fmt.price(petty.abs())}',
                            detail: '${e.petty.length} wpisów',
                            onSave: e.petty.isEmpty ? null : () => _save('petty-cash', pettyCsv(e)),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ExportCard extends StatelessWidget {
  const _ExportCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.value,
    required this.detail,
    required this.onSave,
  });

  final String title;
  final AppIconData icon;
  final Color color;
  final String value;
  final String detail;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            IconBadge(icon, color: color, size: 44),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: text.titleMedium),
                  const SizedBox(height: 2),
                  Text(value, style: text.headlineSmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                  const SizedBox(height: 2),
                  Text(detail, style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: onSave,
              icon: const Glyph(AppIcons.fileArrowDown, size: 18),
              label: const Text('Zapisz CSV'),
            ),
          ],
        ),
      ),
    );
  }
}
