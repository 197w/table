import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:table_core/table_core.dart';

import 'data.dart';
import 'ui.dart';

const _tabular = [FontFeature.tabularFigures()];

typedef _Query = ({String restaurantId, String memberId, int daysAgo});

final _activityProvider = FutureProvider.autoDispose.family<List<ActivityEvent>, _Query>((ref, q) async {
  final now = DateTime.now();
  final day = DateTime(now.year, now.month, now.day - q.daysAgo);
  try {
    final rows = await Supabase.instance.client.rpc<List<dynamic>>(
      'panel_activity',
      params: {
        'p_restaurant_id': q.restaurantId,
        'p_from': day.toUtc().toIso8601String(),
        'p_to': day.add(const Duration(days: 1)).toUtc().toIso8601String(),
        'p_member_id': q.memberId,
      },
    );
    return [for (final r in rows) ActivityEvent.fromJson(r as Map<String, dynamic>)].reversed.toList();
  } on PostgrestException catch (e) {
    if (e.code == 'P0001' && e.message.isNotEmpty) throw AppFailure(e.message);
    throw const AppFailure('Nie udało się pobrać zdarzeń. Spróbuj ponownie.');
  } catch (e) {
    if (e is AppFailure) rethrow;
    throw const AppFailure('Brak połączenia z serwerem. Sprawdź internet.');
  }
});

Color _groupColor(ActivityGroup g) => switch (g) {
  ActivityGroup.staff => StaffColors.info,
  ActivityGroup.bills => AppColors.accent,
  ActivityGroup.kitchen => StaffColors.pending,
  ActivityGroup.takeaway => StaffColors.proposal,
  ActivityGroup.reservations => AppColors.accent,
  ActivityGroup.stock => AppColors.error,
};

String _groupLabel(ActivityGroup g) => switch (g) {
  ActivityGroup.staff => 'Zmiany',
  ActivityGroup.bills => 'Rachunki',
  ActivityGroup.kitchen => 'Kuchnia',
  ActivityGroup.takeaway => 'Na wynos',
  ActivityGroup.reservations => 'Rezerwacje',
  ActivityGroup.stock => 'Magazyn',
};

/// Logi w telefonie (uprawnienie „Logi i Time Machine”): zdarzenia lokalu z dziś albo wczoraj, najnowsze u góry,
/// z filtrem grup. Dziś odświeża się co minutę. Time Machine z salą jest w panelu (Management → Logi).
class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({super.key, required this.job});

  final Job job;

  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  int _daysAgo = 0;
  ActivityGroup? _group;
  Timer? _timer;

  _Query get _query => (restaurantId: widget.job.restaurantId, memberId: widget.job.memberId, daysAgo: _daysAgo);

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted && _daysAgo == 0) ref.invalidate(_activityProvider(_query));
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final async = ref.watch(_activityProvider(_query));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Logi'),
        actions: [
          IconButton(
            tooltip: 'Odśwież',
            onPressed: () => ref.invalidate(_activityProvider(_query)),
            icon: const Glyph(AppIcons.refresh, size: 20),
          ),
        ],
      ),
      body: ContentWidth(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final (days, label) in const [(0, 'Dziś'), (1, 'Wczoraj')]) ...[
                      ChoiceChip(
                        label: Text(label),
                        selected: _daysAgo == days,
                        onSelected: (_) => setState(() => _daysAgo = days),
                      ),
                      const SizedBox(width: 8),
                    ],
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('Wszystko'),
                      selected: _group == null,
                      onSelected: (_) => setState(() => _group = null),
                    ),
                    for (final g in ActivityGroup.values) ...[
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: Text(_groupLabel(g)),
                        selected: _group == g,
                        onSelected: (_) => setState(() => _group = _group == g ? null : g),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Expanded(
              child: async.when(
                skipLoadingOnReload: true,
                loading: () => const CardsSkeleton(count: 6, tile: false),
                error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(_activityProvider(_query))),
                data: (events) {
                  final visible = [
                    for (final e in events)
                      if (_group == null || e.group == _group) e,
                  ];
                  return RefreshIndicator(
                    onRefresh: () async => ref.invalidate(_activityProvider(_query)),
                    child: visible.isEmpty
                        ? ListView(
                            children: [
                              const SizedBox(height: 80),
                              MessageView(
                                icon: AppIcons.clockCounterClockwise.duotone,
                                title: 'Brak zdarzeń',
                                message: _daysAgo == 0
                                    ? 'Dziś jeszcze nic się nie działo.'
                                    : 'Wczoraj nic nie zapisano.',
                              ),
                            ],
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                            itemCount: visible.length,
                            separatorBuilder: (_, _) => Divider(height: 1, color: AppColors.ring),
                            itemBuilder: (context, i) {
                              final e = visible[i];
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(
                                      width: 48,
                                      child: Text(
                                        hm(e.at),
                                        style: text.titleSmall?.copyWith(
                                          color: AppColors.textMuted,
                                          fontFeatures: _tabular,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      width: 10,
                                      height: 10,
                                      margin: const EdgeInsets.only(top: 5, right: 10),
                                      decoration: BoxDecoration(color: _groupColor(e.group), shape: BoxShape.circle),
                                    ),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(e.title, style: text.titleSmall),
                                          if (e.detail case final d?)
                                            Text(d, style: text.bodyMedium?.copyWith(color: AppColors.textMuted)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
