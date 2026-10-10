import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import 'data.dart';
import 'ui.dart';

/// Kiedy przyszła informacja: „dziś, 14:05”, „wczoraj, 9:00” albo „pt, 3 paź, 9:00”.
String announcementWhen(DateTime at, [DateTime? now]) {
  final n = now ?? DateTime.now();
  final days = DateTime(n.year, n.month, n.day).difference(DateTime(at.year, at.month, at.day)).inDays;
  final day = switch (days) {
    0 => 'dziś',
    1 => 'wczoraj',
    _ => Fmt.dayShort(at),
  };
  return '$day, ${hm(at)}';
}

/// Karta na „Zeskanuj”: ile nowych informacji od kierownika i najnowsza z nich.
class AnnouncementsCard extends StatelessWidget {
  const AnnouncementsCard({super.key, required this.announcements, required this.onTap});

  final List<StaffAnnouncement> announcements;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final unread = announcements.where((a) => !a.read).toList();
    final latest = unread.firstOrNull ?? announcements.first;
    final title = unread.isEmpty
        ? 'Informacje od kierownika'
        : unread.length == 1
        ? 'Nowa informacja od kierownika'
        : 'Nowe informacje od kierownika: ${unread.length}';

    return Card(
      margin: EdgeInsets.zero,
      shape: unread.isEmpty
          ? null
          : RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
              side: BorderSide(color: AppColors.accent.withValues(alpha: 0.6)),
            ),
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        button: true,
        label: '$title. ${latest.title}',
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 72),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  IconTile(AppIcons.megaphone, active: unread.isNotEmpty),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: text.titleMedium),
                        const SizedBox(height: 2),
                        Text(
                          latest.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Glyph(AppIcons.caretRight, size: 18, color: AppColors.textMuted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Informacje od kierownika z ostatnich 60 dni, najnowsze pierwsze. Nowe są wyróżnione; otwarcie oznacza
/// informację jako przeczytaną (kierownik widzi w panelu, ile osób ją przeczytało).
class AnnouncementsScreen extends ConsumerWidget {
  const AnnouncementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(announcementsProvider);
    final jobs = ref.watch(jobsProvider).value ?? const <Job>[];

    return Scaffold(
      appBar: AppBar(title: const Text('Informacje')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(announcementsProvider),
        child: async.when(
          skipLoadingOnReload: true,
          loading: () => const CardsSkeleton(count: 3, tile: false),
          error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(announcementsProvider)),
          data: (list) => list.isEmpty
              ? ListView(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 40),
                      child: MessageView(
                        icon: AppIcons.megaphone.duotone,
                        title: 'Brak informacji',
                        message: 'Tu pojawią się informacje od kierownika lokalu.',
                      ),
                    ),
                  ],
                )
              : ContentWidth(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, i) => _AnnouncementTile(
                      announcement: list[i],
                      showRestaurant: jobs.length > 1,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => AnnouncementDetail(announcement: list[i], showRestaurant: jobs.length > 1),
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

class _AnnouncementTile extends StatelessWidget {
  const _AnnouncementTile({required this.announcement, required this.showRestaurant, required this.onTap});

  final StaffAnnouncement announcement;
  final bool showRestaurant;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final a = announcement;
    final meta = [announcementWhen(a.publishAt), ?a.authorName, if (showRestaurant) a.restaurantName].join(' · ');

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        button: true,
        label: '${a.read ? '' : 'Nowa. '}${a.title}. $meta',
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        a.title,
                        style: text.titleMedium?.copyWith(fontWeight: a.read ? null : FontWeight.w600),
                      ),
                    ),
                    if (!a.read) ...[
                      const SizedBox(width: 8),
                      StatusChip(label: 'Nowa', icon: AppIcons.bell, color: AppColors.accent),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(meta, style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
                if (a.body.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    a.body.trim(),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Cała informacja. Otwarcie nieprzeczytanej oznacza ją jako przeczytaną.
class AnnouncementDetail extends ConsumerStatefulWidget {
  const AnnouncementDetail({super.key, required this.announcement, this.showRestaurant = false});

  final StaffAnnouncement announcement;
  final bool showRestaurant;

  @override
  ConsumerState<AnnouncementDetail> createState() => _AnnouncementDetailState();
}

class _AnnouncementDetailState extends ConsumerState<AnnouncementDetail> {
  @override
  void initState() {
    super.initState();
    if (!widget.announcement.read) _markRead();
  }

  Future<void> _markRead() async {
    try {
      await ref.read(staffRepositoryProvider).readAnnouncement(widget.announcement);
      ref.invalidate(announcementsProvider);
    } catch (_) {
      // Bez sieci informacja zostanie nowa; oznaczy się przy następnym otwarciu.
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final a = widget.announcement;
    return Scaffold(
      appBar: AppBar(title: const Text('Informacja')),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Semantics(header: true, child: Text(a.title, style: text.headlineSmall)),
            const SizedBox(height: 6),
            Text(
              [announcementWhen(a.publishAt), ?a.authorName, if (widget.showRestaurant) a.restaurantName].join(' · '),
              style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
            ),
            if (a.body.trim().isNotEmpty) ...[
              const SizedBox(height: 18),
              SelectableText(a.body.trim(), style: text.bodyLarge?.copyWith(height: 1.5)),
            ],
          ],
        ),
      ),
    );
  }
}
