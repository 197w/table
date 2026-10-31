import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:table_core/table_core.dart';

import 'data.dart';
import 'ui.dart';

const _tabular = [FontFeature.tabularFigures()];

double? _num(Object? v) => v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);

/// Mniejsza jednostka do reszty: ml dla litrów, g dla kilogramów.
String _portion(String unit) => switch (unit) {
  'l' => 'ml',
  'kg' => 'g',
  'szt' => 'szt.',
  _ => unit,
};

String _unitLabel(String unit) => unit == 'szt' ? 'szt.' : unit;

double _portionFactor(String unit) => unit == 'l' || unit == 'kg' ? 1000 : 1;

/// Pojemnik do ważenia lokalu (mały, średni, duży).
class InvContainer {
  const InvContainer({required this.id, required this.name, required this.tareG});

  final String id;
  final String name;
  final double tareG;

  factory InvContainer.fromJson(Map<String, dynamic> j) =>
      InvContainer(id: j['id'] as String, name: j['name'] as String, tareG: _num(j['tare_g']) ?? 0);
}

/// Składnik w spisie na telefonie: opakowanie, lokalizacja, stan „powinno być” i to, co już wpisano.
class InvItem {
  const InvItem({
    required this.id,
    required this.name,
    required this.unit,
    required this.capacity,
    this.location,
    this.packName,
    this.containerId,
    this.expected,
    this.counted = false,
    this.packages,
    this.loose,
    this.gross,
    this.lineContainerId,
  });

  final String id;
  final String name;
  final String unit;
  final double capacity;
  final String? location;
  final String? packName;

  /// Zwykły pojemnik do ważenia.
  final String? containerId;

  /// Stan „powinno być” w jednostce składnika. Null: jeszcze nie liczono.
  final double? expected;

  /// Już wpisany w tej inwentaryzacji.
  final bool counted;
  final double? packages;
  final double? loose;
  final double? gross;
  final String? lineContainerId;

  bool get weighed => unit == 'g' || unit == 'kg';

  String get package => [?packName, '${inventoryNumber(capacity)} ${_unitLabel(unit)}'].join(' ');

  factory InvItem.fromJson(Map<String, dynamic> j) {
    final line = j['line'] as Map<String, dynamic>?;
    return InvItem(
      id: j['id'] as String,
      name: j['name'] as String,
      unit: j['unit'] as String? ?? 'szt',
      capacity: _num(j['capacity']) ?? 1,
      location: (j['location'] as String?)?.trim().isEmpty ?? true ? null : (j['location'] as String).trim(),
      packName: j['pack_name'] as String?,
      containerId: j['container_id'] as String?,
      expected: _num(j['expected']),
      counted: line != null,
      packages: _num(line?['packages']) ?? (line != null && line['loose'] == null ? _num(line['quantity']) : null),
      loose: _num(line?['loose']),
      gross: _num(line?['gross']),
      lineContainerId: line?['container_id'] as String?,
    );
  }
}

class StaffInventory {
  const StaffInventory({required this.countId, required this.containers, required this.items});

  /// Trwająca inwentaryzacja lokalu. Null: żadna nie trwa.
  final String? countId;
  final List<InvContainer> containers;
  final List<InvItem> items;

  factory StaffInventory.fromJson(Map<String, dynamic> j) => StaffInventory(
    countId: j['count_id'] as String?,
    containers: [
      for (final c in j['containers'] as List? ?? const []) InvContainer.fromJson(c as Map<String, dynamic>),
    ],
    items: [for (final i in j['items'] as List? ?? const []) InvItem.fromJson(i as Map<String, dynamic>)],
  );
}

Future<T> _guard<T>(Future<T> Function() action) async {
  try {
    return await action();
  } on PostgrestException catch (e) {
    if (e.code == 'P0001' && e.message.isNotEmpty) throw AppFailure(e.message);
    throw const AppFailure('Nie udało się. Spróbuj ponownie.');
  } on AppFailure {
    rethrow;
  } catch (_) {
    throw const AppFailure('Brak połączenia z serwerem. Sprawdź internet.');
  }
}

SupabaseClient get _db => Supabase.instance.client;

final staffInventoryProvider = FutureProvider.autoDispose.family<StaffInventory, String>((ref, memberId) {
  return _guard(() async {
    final json = await _db.rpc<Map<String, dynamic>>('staff_inventory', params: {'p_member_id': memberId});
    return StaffInventory.fromJson(json);
  });
});

/// Inwentaryzacja w telefonie (uprawnienie „Wpisywanie ilości składników”): ten sam spis co w panelu, zapisuje się
/// od razu, więc można liczyć w kilka osób naraz. Składniki pogrupowane po lokalizacji, pełne opakowania i reszta,
/// pojemnik do ważenia odejmuje się sam, a różnica od stanu „powinno być” liczy się w trakcie pisania.
class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key, required this.job});

  final Job job;

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  final _search = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _reload() => ref.invalidate(staffInventoryProvider(widget.job.memberId));

  Future<void> _start() async {
    setState(() => _busy = true);
    try {
      await _guard(
        () => _db.rpc<String>(
          'panel_inventory_start',
          params: {'p_restaurant_id': widget.job.restaurantId, 'p_member_id': widget.job.memberId},
        ),
      );
      _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finish(StaffInventory inv) async {
    final missing = inv.items.where((i) => !i.counted).length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Zakończyć inwentaryzację?'),
        content: Text(
          missing == 0
              ? 'Wpisane ilości staną się aktualnym stanem składników.'
              : 'Bez ilości: ${missing == 1 ? 'jeden składnik' : '$missing składników'}. Zostaną pominięte.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Wróć')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Zakończ'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await _guard(
        () => _db.rpc<void>(
          'panel_inventory_finish',
          params: {'p_count_id': inv.countId, 'p_member_id': widget.job.memberId},
        ),
      );
      if (!mounted) return;
      showMessage(context, 'Inwentaryzacja zapisana.', tone: ToastTone.success);
      Navigator.pop(context);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _save(StaffInventory inv, InvItem item, double? packages, double? loose, String? containerId) async {
    try {
      await _guard(
        () => _db.rpc<void>(
          'panel_inventory_set',
          params: {
            'p_count_id': inv.countId,
            'p_item_id': item.id,
            'p_quantity': packages,
            'p_loose': loose,
            'p_container_id': loose == null ? null : containerId,
            'p_member_id': widget.job.memberId,
          },
        ),
      );
      return true;
    } catch (e) {
      if (mounted) showError(context, e);
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final async = ref.watch(staffInventoryProvider(widget.job.memberId));
    final inv = async.value;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inwentaryzacja'),
        actions: [IconButton(tooltip: 'Odśwież', onPressed: _reload, icon: const Glyph(AppIcons.refresh, size: 20))],
      ),
      body: async.when(
        skipLoadingOnReload: true,
        loading: () => const CardsSkeleton(count: 4),
        error: (e, _) => ErrorView(error: e, onRetry: _reload),
        data: (inv) {
          if (inv.items.isEmpty) {
            return MessageView(
              icon: AppIcons.package.duotone,
              title: 'Brak składników',
              message: 'Składniki dodaje kierownik w panelu: Management → Inwentaryzacja.',
            );
          }
          if (inv.countId == null) {
            return MessageView(
              icon: AppIcons.clipboardText.duotone,
              title: 'Żadna inwentaryzacja nie trwa',
              message:
                  'Zacznij spis w ${widget.job.restaurantName}. Ilości zapisują się od razu, więc możecie liczyć '
                  'w kilka osób, także w panelu na komputerze.',
              actionLabel: 'Zacznij inwentaryzację',
              onAction: _busy ? null : _start,
            );
          }
          final query = _search.text.trim().toLowerCase();
          final visible = [
            for (final i in inv.items)
              if (query.isEmpty ||
                  i.name.toLowerCase().contains(query) ||
                  (i.location ?? '').toLowerCase().contains(query))
                i,
          ];
          final groups = <String?, List<InvItem>>{};
          for (final i in visible) {
            groups.putIfAbsent(i.location, () => []).add(i);
          }
          final keys = groups.keys.whereType<String>().toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
          final done = inv.items.where((i) => i.counted).length;
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ContentWidth(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  Text('Wpisano $done z ${inv.items.length}', style: text.titleSmall?.copyWith(fontFeatures: _tabular)),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: done / inv.items.length,
                      minHeight: 6,
                      color: AppColors.accent,
                      backgroundColor: AppColors.surfaceRaised,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Szukaj składnika albo miejsca',
                      prefixIcon: const Padding(padding: EdgeInsets.all(12), child: Glyph(AppIcons.search, size: 18)),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Wyczyść',
                              onPressed: () => setState(_search.clear),
                              icon: const Glyph(AppIcons.close, size: 18),
                            ),
                    ),
                  ),
                  for (final key in [...keys, if (groups.containsKey(null)) null]) ...[
                    SectionHeader(key ?? (keys.isEmpty ? 'Składniki' : 'Bez lokalizacji'), top: 20),
                    for (final item in groups[key]!)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _ItemCard(
                          key: ValueKey(item.id),
                          item: item,
                          containers: inv.containers,
                          onSave: (p, l, c) async {
                            final ok = await _save(inv, item, p, l, c);
                            if (ok) _reload();
                            return ok;
                          },
                        ),
                      ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: inv?.countId == null
          ? null
          : BottomActionBar(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                onPressed: _busy ? null : () => _finish(inv!),
                icon: const Glyph(AppIcons.check, size: 20),
                label: const Text('Zakończ inwentaryzację'),
              ),
            ),
    );
  }
}

/// Składnik: pełne opakowania, reszta, pojemnik i wynik na żywo. „Zapisz” pojawia się po zmianie.
class _ItemCard extends StatefulWidget {
  const _ItemCard({super.key, required this.item, required this.containers, required this.onSave});

  final InvItem item;
  final List<InvContainer> containers;
  final Future<bool> Function(double? packages, double? loose, String? containerId) onSave;

  @override
  State<_ItemCard> createState() => _ItemCardState();
}

class _ItemCardState extends State<_ItemCard> {
  late final _packages = TextEditingController(text: _fmt(widget.item.packages));
  late final _loose = TextEditingController(
    text: _fmt(widget.item.lineContainerId != null ? widget.item.gross : widget.item.loose),
  );
  late String? _containerId = widget.item.counted
      ? widget.item.lineContainerId
      : (widget.item.weighed ? widget.item.containerId : null);
  bool _dirty = false;
  bool _saving = false;
  bool _saved = false;

  static String _fmt(double? v) => v == null ? '' : inventoryNumber(v);

  @override
  void dispose() {
    _packages.dispose();
    _loose.dispose();
    super.dispose();
  }

  InvContainer? get _box => widget.containers.where((c) => c.id == _containerId).firstOrNull;

  double? get _p => _packages.text.trim().isEmpty ? null : parseInventoryNumber(_packages.text);
  double? get _l => _loose.text.trim().isEmpty ? null : parseInventoryNumber(_loose.text);

  double? get _total {
    final p = _p, l = _l;
    if (p == null && l == null) return null;
    final net = l == null ? 0.0 : (l - (_box?.tareG ?? 0)).clamp(0, double.infinity).toDouble();
    return (p ?? 0) * widget.item.capacity + net / _portionFactor(widget.item.unit);
  }

  void _changed() => setState(() {
    _dirty = true;
    _saved = false;
  });

  Future<void> _save() async {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    final ok = await widget.onSave(_p, _l, _box?.id);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (ok) {
        _dirty = false;
        _saved = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final item = widget.item;
    final unit = _unitLabel(item.unit);
    final total = _total;
    final diff = total == null || item.expected == null ? null : total - item.expected!;
    final diffColor = diff == null || diff.abs() < 0.0005
        ? AppColors.textMuted
        : (diff > 0 ? AppColors.accent : AppColors.error);
    final box = _box;
    final number = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(item.name, style: text.titleMedium)),
                if (item.counted && !_dirty || _saved)
                  StatusChip(label: 'Wpisano', icon: AppIcons.check, color: AppColors.accent),
              ],
            ),
            Text(item.package, style: text.bodyMedium?.copyWith(color: AppColors.textMuted)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _packages,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: number,
                    textInputAction: TextInputAction.next,
                    onChanged: (_) => _changed(),
                    style: const TextStyle(fontFeatures: _tabular),
                    decoration: InputDecoration(labelText: 'Pełne', suffixText: packWord(item.packName, _p)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _loose,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: number,
                    textInputAction: TextInputAction.done,
                    onChanged: (_) => _changed(),
                    onSubmitted: (_) => _save(),
                    style: const TextStyle(fontFeatures: _tabular),
                    decoration: InputDecoration(
                      labelText: box == null ? 'Reszta' : 'Z pojemnikiem',
                      suffixText: box == null ? _portion(item.unit) : 'g',
                    ),
                  ),
                ),
              ],
            ),
            if (item.weighed && widget.containers.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Bez pojemnika'),
                    selected: box == null,
                    onSelected: (_) => setState(() {
                      _containerId = null;
                      _dirty = true;
                    }),
                  ),
                  for (final c in widget.containers)
                    ChoiceChip(
                      label: Text('${c.name} −${inventoryGrouped(c.tareG)} g'),
                      selected: box?.id == c.id,
                      onSelected: (_) => setState(() {
                        _containerId = c.id;
                        _dirty = true;
                      }),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            Text(
              [
                total == null ? 'Razem: —' : 'Razem ${inventoryNumber(total)} $unit',
                if (item.expected != null) 'powinno być ${inventoryNumber(item.expected!)} $unit',
              ].join(' · '),
              style: text.bodyMedium?.copyWith(fontFeatures: _tabular),
            ),
            if (diff != null)
              Text(
                diff.abs() < 0.0005
                    ? 'Zgadza się'
                    : 'Różnica ${diff > 0 ? '+' : '−'}${inventoryNumber(diff.abs())} $unit',
                style: text.titleSmall?.copyWith(color: diffColor, fontFeatures: _tabular),
              ),
            if (_dirty) ...[
              const SizedBox(height: 10),
              FilledButton.tonal(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Zapisywanie…' : 'Zapisz'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
