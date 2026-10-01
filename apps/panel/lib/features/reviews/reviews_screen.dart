import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/panel_widgets.dart';

enum _ReviewFilter {
  all('Wszystkie'),
  unanswered('Bez odpowiedzi'),
  verified('Zweryfikowane');

  const _ReviewFilter(this.label);
  final String label;
}

class ReviewsScreen extends ConsumerStatefulWidget {
  const ReviewsScreen({super.key});

  @override
  ConsumerState<ReviewsScreen> createState() => _ReviewsScreenState();
}

class _ReviewsScreenState extends ConsumerState<ReviewsScreen> {
  _ReviewFilter _filter = _ReviewFilter.all;

  @override
  Widget build(BuildContext context) {
    final restaurant = ref.watch(currentRestaurantProvider);
    if (restaurant == null) return const LoadingView();
    final async = ref.watch(reviewsProvider(restaurant.id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          subtitle:
              'Opinii nie da się ukryć ani usunąć. Możesz na nie publicznie odpowiedzieć.',
          below: Align(
            alignment: Alignment.centerLeft,
            child: SegmentedTabs<_ReviewFilter>(
              options: [for (final f in _ReviewFilter.values) (f, f.label)],
              selected: _filter,
              onChanged: (f) => setState(() => _filter = f),
            ),
          ),
        ),
        Expanded(
          child: async.when(
            skipLoadingOnReload: true,
            loading: () => const LoadingView(),
            error: (e, _) => ErrorView(
              error: e,
              onRetry: () => ref.invalidate(reviewsProvider(restaurant.id)),
            ),
            data: (all) {
              if (all.isEmpty) {
                return const MessageView(
                  icon: AppIcons.chatCircle,
                  title: 'Brak opinii',
                  message:
                      'Goście mogą ocenić lokal po wizycie. Opinie pojawią się tutaj.',
                );
              }
              final visible = all.where((r) {
                return switch (_filter) {
                  _ReviewFilter.all => true,
                  _ReviewFilter.unanswered => r.replyBody == null,
                  _ReviewFilter.verified => r.isVerified,
                };
              }).toList();
              return ListView(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
                children: [
                  _Summary(reviews: all),
                  const SizedBox(height: 16),
                  if (visible.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 40),
                      child: MessageView(
                        icon: AppIcons.checkCircle,
                        title: 'Nic w tym filtrze',
                        message: 'Zmień filtr, żeby zobaczyć pozostałe opinie.',
                      ),
                    ),
                  for (final r in visible)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _ReviewCard(
                        key: ValueKey(r.id),
                        review: r,
                        canReply: restaurant.canManage,
                        onSaved: () =>
                            ref.invalidate(reviewsProvider(restaurant.id)),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.reviews});

  final List<PanelReview> reviews;

  @override
  Widget build(BuildContext context) {
    final verified = reviews.where((r) => r.isVerified).toList();
    String avg(int Function(PanelReview) pick) {
      final v = averageOf(verified.map(pick));
      return v == null ? '–' : Fmt.rating(v);
    }

    final unanswered = reviews.where((r) => r.replyBody == null).length;
    return Row(
      children: [
        Expanded(
          child: StatTile(
            label: 'Kuchnia',
            value: avg((r) => r.food),
            icon: AppIcons.forkKnife,
            hint: 'liczy się do rankingu',
            accent: true,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: StatTile(label: 'Obsługa', value: avg((r) => r.service), icon: AppIcons.users),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: StatTile(label: 'Atmosfera', value: avg((r) => r.ambience), icon: AppIcons.armchair),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: StatTile(
            label: 'Zweryfikowane opinie',
            value: '${verified.length}',
            icon: AppIcons.checkCircle,
            hint: 'z ${reviews.length} wszystkich',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: StatTile(
            label: 'Bez odpowiedzi',
            value: '$unanswered',
            icon: AppIcons.chatCircle,
          ),
        ),
      ],
    );
  }
}

class _ReviewCard extends ConsumerStatefulWidget {
  const _ReviewCard({
    super.key,
    required this.review,
    required this.canReply,
    required this.onSaved,
  });

  final PanelReview review;
  final bool canReply;
  final VoidCallback onSaved;

  @override
  ConsumerState<_ReviewCard> createState() => _ReviewCardState();
}

class _ReviewCardState extends ConsumerState<_ReviewCard> {
  late final _reply = TextEditingController(text: widget.review.replyBody ?? '');
  bool _editing = false;
  bool _busy = false;

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _save(String body) async {
    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).replyToReview(widget.review.id, body);
      widget.onSaved();
      if (mounted) {
        setState(() => _editing = false);
        showMessage(context, body.trim().isEmpty ? 'Odpowiedź usunięta.' : 'Odpowiedź opublikowana.');
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.review;
    final text = Theme.of(context).textTheme;

    return PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(r.author, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(width: 10),
              Tag(
                r.verificationLabel.toUpperCase(),
                color: r.isVerified ? AppColors.accent : AppColors.textMuted,
              ),
              const Spacer(),
              Text(
                Fmt.capitalize(Fmt.dayShort(r.createdAt)),
                style: text.bodySmall?.copyWith(color: AppColors.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 18,
            runSpacing: 6,
            children: [
              _Score(label: 'Kuchnia', value: r.food),
              _Score(label: 'Obsługa', value: r.service),
              _Score(label: 'Atmosfera', value: r.ambience),
              if (r.pricePerPerson != null)
                Text(
                  'ok. ${r.pricePerPerson} zł na osobę',
                  style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
                ),
            ],
          ),
          if (r.body != null) ...[
            const SizedBox(height: 10),
            Text(r.body!, style: text.bodyLarge),
          ],
          const SizedBox(height: 14),
          if (_editing) ...[
            TextField(
              controller: _reply,
              autofocus: true,
              minLines: 2,
              maxLines: 6,
              maxLength: 1000,
              decoration: const InputDecoration(
                labelText: 'Odpowiedź lokalu',
                alignLabelWithHint: true,
                hintText: 'Podziękuj, wyjaśnij albo zaproś ponownie. Odpowiedź widzą wszyscy goście.',
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (r.replyBody != null)
                  TextButton(
                    onPressed: _busy ? null : () => _save(''),
                    style: TextButton.styleFrom(foregroundColor: AppColors.error),
                    child: const Text('Usuń odpowiedź'),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: _busy ? null : () => setState(() => _editing = false),
                  style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
                  child: const Text('Anuluj'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _busy || _reply.text.trim().isEmpty ? null : () => _save(_reply.text),
                  child: const Text('Opublikuj'),
                ),
              ],
            ),
          ] else if (r.replyBody != null)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surfaceRaised,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('Odpowiedź lokalu', style: text.labelLarge),
                      const SizedBox(width: 8),
                      if (r.replyAt != null)
                        Text(
                          Fmt.dayShort(r.replyAt!),
                          style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                        ),
                      const Spacer(),
                      if (widget.canReply)
                        TextButton(
                          onPressed: () => setState(() => _editing = true),
                          child: const Text('Edytuj'),
                        ),
                    ],
                  ),
                  Text(r.replyBody!, style: text.bodyMedium),
                ],
              ),
            )
          else if (widget.canReply)
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _editing = true),
                icon: const Glyph(AppIcons.chatText, size: 16),
                label: const Text('Odpowiedz'),
              ),
            ),
        ],
      ),
    );
  }
}

class _Score extends StatelessWidget {
  const _Score({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label ', style: text.bodyMedium?.copyWith(color: AppColors.textMuted)),
        for (var i = 1; i <= 5; i++)
          Glyph(
            i <= value ? AppIcons.starFill : AppIcons.star,
            size: 14,
            color: i <= value ? AppColors.accent : AppColors.textDisabled,
          ),
      ],
    );
  }
}
