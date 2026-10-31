import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../app/app.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

const _tabular = [FontFeature.tabularFigures()];

/// „Moje” → Kody: osobiste kody rabatowe od lokali (za wizytę albo opinię). Kod widać dopiero po „Aktywuj”
/// i działa 15 minut: gość pokazuje go kelnerowi przy rachunku. Każda aktywacja daje nowy kod, więc nie da się
/// go przekazać dalej.
class MyCodesList extends ConsumerWidget {
  const MyCodesList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myCodesProvider);
    return async.when(
      skipLoadingOnReload: true,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(myCodesProvider)),
      data: (codes) {
        final now = DateTime.now();
        final ready = [
          for (final c in codes)
            if (c.statusAt(now) != GuestCodeStatus.used && c.statusAt(now) != GuestCodeStatus.expired) c,
        ];
        final past = [
          for (final c in codes)
            if (!ready.contains(c)) c,
        ];
        if (codes.isEmpty) {
          return MessageView(
            icon: AppIcons.sealPercent.duotone,
            title: 'Nie masz jeszcze kodów',
            message: 'Lokale dają kody rabatowe za wizytę z rezerwacją w aplikacji albo za opinię. Pojawią się tutaj.',
            actionLabel: 'Odkrywaj lokale',
            onAction: () => context.go(AppRoutes.discover),
          );
        }
        return RefreshIndicator(
          color: AppColors.accent,
          backgroundColor: AppColors.surface,
          onRefresh: () async {
            ref.invalidate(myCodesProvider);
            await ref.read(myCodesProvider.future);
          },
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 24 + MediaQuery.paddingOf(context).bottom),
                children: [
                  for (final c in ready) ...[_CodeCard(code: c), const SizedBox(height: 12)],
                  if (past.isNotEmpty) ...[
                    const SectionTitle('Wykorzystane i wygasłe'),
                    for (final c in past) ...[_CodeCard(code: c), const SizedBox(height: 10)],
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CodeCard extends ConsumerStatefulWidget {
  const _CodeCard({required this.code});

  final GuestCode code;

  @override
  ConsumerState<_CodeCard> createState() => _CodeCardState();
}

class _CodeCardState extends ConsumerState<_CodeCard> {
  Timer? _tick;
  bool _busy = false;

  /// Kod po aktywacji (zanim lista pobierze się od nowa).
  ({String code, DateTime until})? _activated;

  @override
  void initState() {
    super.initState();
    _syncTimer();
  }

  @override
  void didUpdateWidget(covariant _CodeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTimer();
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  DateTime? get _until => _activated?.until ?? widget.code.activeUntil;
  String? get _codeText => _activated?.code ?? widget.code.code;

  /// Odliczanie co sekundę tylko przy aktywnym kodzie.
  void _syncTimer() {
    final until = _until;
    final active = until != null && until.isAfter(DateTime.now());
    if (active && _tick == null) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {});
        if (!(_until?.isAfter(DateTime.now()) ?? false)) {
          _tick?.cancel();
          _tick = null;
          _activated = null;
          ref.invalidate(myCodesProvider);
        }
      });
    } else if (!active) {
      _tick?.cancel();
      _tick = null;
    }
  }

  Future<void> _activate() async {
    final ok = await showConfirmSheet(
      context: context,
      title: 'Aktywować kod?',
      message: 'Kod będzie ważny 15 minut. Aktywuj go przy stoliku w ${widget.code.restaurantName}, '
          'zanim poprosisz o rachunek, i pokaż kelnerowi.',
      icon: AppIcons.sealPercent,
      action: 'Aktywuj kod',
      actionHint: 'Ważny 15 minut od teraz',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final result = await ref.read(repositoryProvider).activateCode(widget.code.id);
      if (!mounted) return;
      setState(() => _activated = result);
      _syncTimer();
      ref.invalidate(myCodesProvider);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = widget.code;
    final now = DateTime.now();
    final until = _until;
    final active = until != null && until.isAfter(now) && c.usedAt == null;
    final status = active ? GuestCodeStatus.active : c.statusAt(now);
    final dimmed = status == GuestCodeStatus.used || status == GuestCodeStatus.expired;
    final left = active ? until.difference(now) : Duration.zero;
    String two(int n) => n.toString().padLeft(2, '0');

    return Card(
      margin: EdgeInsets.zero,
      shape: active
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
              side: BorderSide(color: AppColors.accent, width: 1.5),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ImageOutline(
                  radius: 10,
                  child: RestaurantLogo(name: c.restaurantName, logoUrl: c.restaurantLogo, size: 44, radius: 10),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.restaurantName, style: text.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        [c.sourceLabel, ?c.conditions].join(' · '),
                        style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  c.valueText,
                  style: text.headlineSmall?.copyWith(
                    color: dimmed ? AppColors.textMuted : AppColors.accent,
                    fontWeight: FontWeight.w600,
                    fontFeatures: _tabular,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (active) ...[
              Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(color: AppColors.accentTint, borderRadius: BorderRadius.circular(14)),
                child: Column(
                  children: [
                    Semantics(
                      label: 'Kod rabatowy ${_codeText!.split('').join(' ')}',
                      excludeSemantics: true,
                      child: Text(
                        _codeText!,
                        style: text.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          letterSpacing: 3,
                          fontFeatures: _tabular,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Ważny jeszcze ${left.inMinutes}:${two(left.inSeconds % 60)} · pokaż kelnerowi przy rachunku',
                      textAlign: TextAlign.center,
                      style: text.bodySmall?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
                    ),
                  ],
                ),
              ),
            ] else if (status == GuestCodeStatus.available)
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: _busy ? null : _activate,
                icon: const Glyph(AppIcons.lockOpen, size: 18),
                label: Text('Aktywuj · ważny do ${Fmt.dayShort(c.expiresAt)}'),
              )
            else
              Text(
                status == GuestCodeStatus.used
                    ? 'Wykorzystany${c.usedAt == null ? '' : ' ${Fmt.dayShort(c.usedAt!)}'}'
                    : 'Wygasł ${Fmt.dayShort(c.expiresAt)}',
                style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
              ),
          ],
        ),
      ),
    );
  }
}

/// Konto → Kody: osobiste kody rabatowe od lokali (wcześniej zakładka w „Moje”).
class CodesScreen extends StatelessWidget {
  const CodesScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(leading: glassLeading(context), title: const Text('Kody')),
    body: const MyCodesList(),
  );
}
