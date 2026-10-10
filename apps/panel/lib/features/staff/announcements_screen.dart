import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/panel_widgets.dart';

enum _Filter { all, sent, scheduled }

/// Pracownicy → Informacje dla pracowników. Osoba z uprawnieniem „Informacje dla pracowników” (zwykle kierownik,
/// ALL i właściciel) pisze informacje, wybiera odbiorców (wszyscy, pracujący tego dnia, stanowiska albo osoby)
/// i może zaplanować wysłanie na dowolny dzień; widzi, ile osób przeczytało. Pozostali pracownicy tylko czytają
/// informacje wysłane do siebie (tu i w Table for employees).
class AnnouncementsScreen extends ConsumerStatefulWidget {
  const AnnouncementsScreen({super.key});

  @override
  ConsumerState<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends ConsumerState<AnnouncementsScreen> {
  _Filter _filter = _Filter.all;

  Future<void> _edit(String restaurantId, [Announcement? existing]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _AnnouncementDialog(restaurantId: restaurantId, existing: existing),
    );
    if (saved == true) ref.invalidate(announcementsProvider);
  }

  Future<void> _delete(Announcement a) async {
    final ok = await confirm(
      context,
      title: 'Usunąć informację?',
      message: '„${a.title}” zniknie u wszystkich pracowników.',
      action: 'Usuń',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(repositoryProvider).deleteAnnouncement(a.id, memberId: ref.read(panelMemberProvider)?.dbMemberId);
      ref.invalidate(announcementsProvider);
      if (mounted) showMessage(context, 'Informacja usunięta.', tone: ToastTone.success);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _markRead(Announcement a, String memberId) async {
    try {
      await ref.read(repositoryProvider).readAnnouncement(a.id, memberId);
      ref.invalidate(announcementsProvider);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final restaurant = ref.watch(currentRestaurantProvider);
    if (restaurant == null) return const LoadingView();
    final member = ref.watch(panelMemberProvider);
    final memberId = member?.dbMemberId;
    final canEdit = ref.watch(memberPermissionsProvider).contains('announcements');
    final query = (restaurantId: restaurant.id, memberId: memberId);
    final async = ref.watch(announcementsProvider(query));
    final positions = {
      for (final p in ref.watch(positionsProvider(restaurant.id)).value ?? const <StaffPosition>[]) p.id: p.name,
    };
    final members = {
      for (final m in ref.watch(staffProvider(restaurant.id)).value ?? const <StaffMember>[]) m.id: m.name,
    };
    final now = DateTime.now();
    final all = async.value ?? const <Announcement>[];
    final scheduled = all.where((a) => !a.isPublished(now)).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          actions: [
            if (canEdit)
              FilledButton.icon(
                onPressed: () => _edit(restaurant.id),
                icon: const Glyph(AppIcons.plus, size: 18),
                label: const Text('Nowa informacja'),
              ),
          ],
          below: canEdit
              ? Align(
                  alignment: Alignment.centerLeft,
                  child: SegmentedTabs<_Filter>(
                    options: [
                      (_Filter.all, 'Wszystkie (${all.length})'),
                      (_Filter.sent, 'Wysłane (${all.length - scheduled})'),
                      (_Filter.scheduled, 'Zaplanowane ($scheduled)'),
                    ],
                    selected: _filter,
                    onChanged: (f) => setState(() => _filter = f),
                  ),
                )
              : null,
        ),
        Expanded(
          child: async.when(
            skipLoadingOnReload: true,
            loading: () => const LoadingView(),
            error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(announcementsProvider(query))),
            data: (list) {
              // Kto nie pisze informacji, widzi tylko wysłane już do siebie.
              final visible = [
                for (final a in list)
                  if (canEdit
                      ? switch (_filter) {
                          _Filter.all => true,
                          _Filter.sent => a.isPublished(now),
                          _Filter.scheduled => !a.isPublished(now),
                        }
                      : a.forMe && a.isPublished(now))
                    a,
              ];
              if (visible.isEmpty) {
                return MessageView(
                  icon: AppIcons.megaphone.duotone,
                  title: canEdit && _filter == _Filter.scheduled ? 'Nic nie czeka na wysłanie' : 'Brak informacji',
                  message: canEdit
                      ? 'Napisz informację dla całego zespołu, wybranych stanowisk albo osób. '
                            'Pracownicy zobaczą ją tutaj i w aplikacji Table for employees.'
                      : 'Tu pojawią się informacje od kierownika.',
                  actionLabel: canEdit && _filter != _Filter.scheduled ? 'Nowa informacja' : null,
                  onAction: canEdit ? () => _edit(restaurant.id) : null,
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
                itemCount: visible.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, i) {
                  final a = visible[i];
                  return Align(
                    alignment: Alignment.topLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 920),
                      child: _AnnouncementCard(
                        announcement: a,
                        recipients: recipientsLabel(a, positions, members),
                        canEdit: canEdit,
                        onEdit: () => _edit(restaurant.id, a),
                        onDelete: () => _delete(a),
                        onRead: memberId != null && a.forMe && !a.read && a.isPublished(now)
                            ? () => _markRead(a, memberId)
                            : null,
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Do kogo idzie informacja, w jednym krótkim napisie.
String recipientsLabel(Announcement a, Map<String, String> positions, Map<String, String> members) {
  String names(List<String> ids, Map<String, String> byId) {
    final list = [for (final id in ids) byId[id] ?? 'usunięte'];
    if (list.length <= 3) return list.join(', ');
    return '${list.take(3).join(', ')} i ${list.length - 3} innych';
  }

  return switch (a.audience) {
    AnnouncementAudience.all => 'Wszyscy',
    AnnouncementAudience.working => 'Pracujący ${Fmt.dayShort(a.publishAt)}',
    AnnouncementAudience.positions => names(a.positionIds, positions),
    AnnouncementAudience.members => names(a.memberIds, members),
  };
}

class _AnnouncementCard extends StatelessWidget {
  const _AnnouncementCard({
    required this.announcement,
    required this.recipients,
    required this.canEdit,
    required this.onEdit,
    required this.onDelete,
    required this.onRead,
  });

  final Announcement announcement;
  final String recipients;
  final bool canEdit;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  /// Zalogowany pracownik oznacza informację jako przeczytaną. Null: już przeczytana albo nie do niego.
  final VoidCallback? onRead;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final a = announcement;
    final published = a.isPublished();
    final unread = onRead != null;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: unread ? AppColors.accent.withValues(alpha: 0.6) : AppColors.ring),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconBadge(AppIcons.megaphone, color: published ? TileColors.violet : TileColors.amber, size: 40),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(a.title, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                        if (unread) StatusChip(label: 'Nowa', icon: AppIcons.bell, color: AppColors.accent),
                        if (!published)
                          StatusChip(
                            label: 'Zaplanowana: ${dayTimeLabel(a.publishAt)}',
                            icon: AppIcons.clock,
                            color: TileColors.amber,
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [?a.authorName, '${Fmt.dayShort(a.publishAt)}, ${Fmt.time(a.publishAt)}'].join(' · '),
                      style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              if (canEdit) ...[
                IconButton(
                  tooltip: 'Zmień',
                  onPressed: onEdit,
                  icon: Glyph(AppIcons.pencil, size: 18, color: AppColors.textMuted),
                ),
                IconButton(
                  tooltip: 'Usuń',
                  onPressed: onDelete,
                  icon: Glyph(AppIcons.trash, size: 18, color: AppColors.textMuted),
                ),
              ],
            ],
          ),
          if (a.body.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: SelectableText(a.body.trim(), style: text.bodyLarge?.copyWith(height: 1.45)),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Glyph(AppIcons.users, size: 16, color: AppColors.textMuted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  [
                    'Do: $recipients',
                    if (canEdit && published) 'Przeczytało ${a.reads} z ${a.recipients}',
                    if (canEdit && !published) 'dostanie ${a.recipients} ${a.recipients == 1 ? 'osoba' : 'osób'}',
                  ].join(' · '),
                  style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                ),
              ),
              if (onRead != null)
                TextButton.icon(
                  onPressed: onRead,
                  icon: const Glyph(AppIcons.check, size: 16),
                  label: const Text('Przeczytane'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Nowa informacja albo zmiana: tytuł, treść, odbiorcy i kiedy wysłać.
class _AnnouncementDialog extends ConsumerStatefulWidget {
  const _AnnouncementDialog({required this.restaurantId, this.existing});

  final String restaurantId;
  final Announcement? existing;

  @override
  ConsumerState<_AnnouncementDialog> createState() => _AnnouncementDialogState();
}

class _AnnouncementDialogState extends ConsumerState<_AnnouncementDialog> {
  late final _title = TextEditingController(text: widget.existing?.title ?? '');
  late final _body = TextEditingController(text: widget.existing?.body ?? '');
  late AnnouncementAudience _audience = widget.existing?.audience ?? AnnouncementAudience.all;
  late final Set<String> _positions = {...?widget.existing?.positionIds};
  late final Set<String> _members = {...?widget.existing?.memberIds};

  /// Null: wysłać od razu. Wysłanej już informacji nie da się przenieść w czasie.
  late DateTime? _publishAt = widget.existing == null || widget.existing!.isPublished()
      ? null
      : widget.existing!.publishAt.toLocal();
  bool _busy = false;

  bool get _published => widget.existing?.isPublished() ?? false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _pickDay() async {
    final now = DateTime.now();
    final current = _publishAt ?? DateTime(now.year, now.month, now.day + 1, 9);
    final day = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (day != null) setState(() => _publishAt = DateTime(day.year, day.month, day.day, current.hour, current.minute));
  }

  Future<void> _pickTime() async {
    final now = DateTime.now();
    final current = _publishAt ?? DateTime(now.year, now.month, now.day + 1, 9);
    final time = await pickTime(
      context,
      initial: TimeOfDay(hour: current.hour, minute: current.minute),
      minuteStep: 5,
      title: 'Godzina wysłania',
    );
    if (time != null) {
      setState(() => _publishAt = DateTime(current.year, current.month, current.day, time.hour, time.minute));
    }
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    String? problem;
    if (title.isEmpty) {
      problem = 'Wpisz tytuł informacji.';
    } else if (_audience == AnnouncementAudience.positions && _positions.isEmpty) {
      problem = 'Wybierz co najmniej jedno stanowisko.';
    } else if (_audience == AnnouncementAudience.members && _members.isEmpty) {
      problem = 'Wybierz co najmniej jedną osobę.';
    } else if (_publishAt != null && !_publishAt!.isAfter(DateTime.now())) {
      problem = 'Ta godzina już minęła. Wybierz późniejszą albo „Teraz”.';
    }
    if (problem != null) {
      showMessage(context, problem, tone: ToastTone.warning);
      return;
    }
    setState(() => _busy = true);
    try {
      final existing = widget.existing;
      // Zaplanowana zmieniona na „Teraz”: wysyła się od razu (przy zmianie null zostawiłoby starą datę).
      final publishAt =
          _publishAt ??
          (existing != null && !existing.isPublished() ? DateTime.now().subtract(const Duration(seconds: 5)) : null);
      await ref
          .read(repositoryProvider)
          .saveAnnouncement(
            widget.restaurantId,
            id: existing?.id,
            title: title,
            body: _body.text.trim(),
            audience: _audience,
            positionIds: _positions.toList(),
            memberIds: _members.toList(),
            publishAt: publishAt,
            memberId: ref.read(panelMemberProvider)?.dbMemberId,
          );
      if (!mounted) return;
      showMessage(
        context,
        _publishAt == null
            ? (existing == null ? 'Informacja wysłana.' : 'Informacja zapisana.')
            : 'Informacja wyśle się ${dayTimeLabel(_publishAt!)}.',
        tone: ToastTone.success,
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final positions = ref.watch(positionsProvider(widget.restaurantId)).value ?? const <StaffPosition>[];
    final members = [
      for (final m in ref.watch(staffProvider(widget.restaurantId)).value ?? const <StaffMember>[])
        if (m.active || _members.contains(m.id)) m,
    ]..sort((a, b) => a.name.compareTo(b.name));
    final publishAt = _publishAt;

    Widget chips<T>(List<T> items, String Function(T) id, String Function(T) label, Set<String> selected) => Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final item in items)
          FilterChip(
            label: Text(label(item)),
            selected: selected.contains(id(item)),
            onSelected: (on) => setState(() => on ? selected.add(id(item)) : selected.remove(id(item))),
          ),
      ],
    );

    return AlertDialog(
      title: Text(widget.existing == null ? 'Nowa informacja dla pracowników' : 'Informacja dla pracowników'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _title,
                autofocus: widget.existing == null,
                maxLength: 120,
                decoration: const InputDecoration(
                  labelText: 'Tytuł',
                  hintText: 'Na przykład Zmiana godzin w sobotę',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _body,
                minLines: 4,
                maxLines: 10,
                maxLength: 4000,
                decoration: const InputDecoration(labelText: 'Treść', alignLabelWithHint: true, counterText: ''),
              ),
              const SizedBox(height: 18),
              Text('Do kogo', style: text.titleSmall),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: SegmentedTabs<AnnouncementAudience>(
                  options: [for (final a in AnnouncementAudience.values) (a, a.label)],
                  selected: _audience,
                  onChanged: (a) => setState(() => _audience = a),
                ),
              ),
              const SizedBox(height: 10),
              switch (_audience) {
                AnnouncementAudience.all => Text(
                  'Wszyscy aktywni pracownicy lokalu.',
                  style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                ),
                AnnouncementAudience.working => Text(
                  'Osoby, które w dniu wysłania mają przyjęte godziny w grafiku albo są na zmianie.',
                  style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                ),
                AnnouncementAudience.positions =>
                  positions.isEmpty
                      ? const LinearProgressIndicator()
                      : chips(positions, (p) => p.id, (p) => p.name, _positions),
                AnnouncementAudience.members =>
                  members.isEmpty
                      ? const LinearProgressIndicator()
                      : chips(members, (m) => m.id, (m) => m.name, _members),
              },
              if (!_published) ...[
                const SizedBox(height: 18),
                Text('Kiedy wysłać', style: text.titleSmall),
                const SizedBox(height: 8),
                Row(
                  children: [
                    SegmentedTabs<bool>(
                      options: const [(false, 'Teraz'), (true, 'Zaplanuj')],
                      selected: publishAt != null,
                      onChanged: (later) => setState(() {
                        final now = DateTime.now();
                        _publishAt = later ? DateTime(now.year, now.month, now.day + 1, 9) : null;
                      }),
                    ),
                    if (publishAt != null) ...[
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: _pickDay,
                        icon: const Glyph(AppIcons.calendar, size: 16),
                        label: Text(Fmt.capitalize(Fmt.dayShort(publishAt))),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: _pickTime,
                        icon: const Glyph(AppIcons.clock, size: 16),
                        label: Text(Fmt.time(publishAt)),
                      ),
                    ],
                  ],
                ),
                if (publishAt != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Pracownicy zobaczą ją ${dayTimeLabel(publishAt)}. Do tego czasu widzisz ją tylko Ty '
                    'i inne osoby, które piszą informacje.',
                    style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
          child: const Text('Anuluj'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(
            publishAt != null
                ? 'Zaplanuj'
                : widget.existing == null
                ? 'Wyślij'
                : 'Zapisz',
          ),
        ),
      ],
    );
  }
}
