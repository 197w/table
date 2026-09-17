import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../app/app.dart';
import '../../data/providers.dart';

/// Grupa wierszy ustawień w jednej karcie, z opcjonalnym nagłówkiem i przypisem.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({
    super.key,
    required this.children,
    this.title,
    this.footer,
  });

  final String? title;
  final String? footer;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
            child: Text(
              title!.toUpperCase(),
              style: text.labelSmall?.copyWith(
                color: AppColors.textMuted,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 62),
                children[i],
              ],
            ],
          ),
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 8, 6, 0),
            child: Text(
              footer!,
              style: text.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
          ),
      ],
    );
  }
}

class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.icon, this.destructive = false});

  final AppIconData icon;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: destructive
            ? AppColors.error.withValues(alpha: 0.12)
            : AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Glyph(
        icon,
        size: 16,
        color: destructive ? AppColors.error : AppColors.accent,
      ),
    );
  }
}

/// Wiersz prowadzący do podstrony albo wykonujący akcję.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.icon,
    required this.title,
    this.value,
    this.onTap,
    this.destructive = false,
    this.showChevron = true,
    this.locked = false,
  });

  final AppIconData icon;
  final String title;

  /// Kłódka przy sekcjach wymagających logowania.
  final bool locked;

  /// Bieżąca wartość po prawej, na przykład wybrany motyw.
  final String? value;
  final VoidCallback? onTap;
  final bool destructive;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      splashColor: Colors.transparent,
      highlightColor: AppColors.ring,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Row(
          children: [
            _IconBadge(icon: icon, destructive: destructive),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: destructive ? AppColors.error : AppColors.text,
                ),
              ),
            ),
            if (value != null) ...[
              Flexible(
                child: Text(
                  value!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
                ),
              ),
              const SizedBox(width: 4),
            ],
            if (locked) ...[
              Glyph(
                AppIcons.lock,
                size: 14,
                color: AppColors.textDisabled,
                semanticLabel: 'Wymaga logowania',
              ),
              const SizedBox(width: 2),
            ],
            if (onTap != null && showChevron)
              Glyph(
                AppIcons.caretRight,
                size: 18,
                color: AppColors.textDisabled,
              ),
          ],
        ),
      ),
    );
  }
}

/// Wiersz jednokrotnego wyboru z ptaszkiem przy zaznaczonej opcji.
class SettingsChoiceRow extends StatelessWidget {
  const SettingsChoiceRow({
    super.key,
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.icon,
  });

  final String title;
  final String? subtitle;
  final AppIconData? icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        splashColor: Colors.transparent,
        highlightColor: AppColors.ring,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            children: [
              if (icon != null) ...[
                _IconBadge(icon: icon!),
                const SizedBox(width: 12),
              ] else
                const SizedBox(width: 48),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: text.bodyLarge?.copyWith(
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: text.bodySmall?.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(
                width: 24,
                child: selected
                    ? Glyph(AppIcons.check, size: 18, color: AppColors.accent)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Wiersz z przełącznikiem.
class SettingsSwitchRow extends StatelessWidget {
  const SettingsSwitchRow({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final AppIconData icon;
  final String title;
  final String? subtitle;
  final bool value;

  /// Null wyłącza przełącznik, na przykład podczas zapisu.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return MergeSemantics(
      child: InkWell(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        splashColor: Colors.transparent,
        highlightColor: AppColors.ring,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          child: Row(
            children: [
              _IconBadge(icon: icon),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: text.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: text.bodySmall?.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Switch(
                value: value,
                onChanged: onChanged,
                activeTrackColor: AppColors.accentFill,
                activeThumbColor: AppColors.onAccent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Strona dostępna tylko po zalogowaniu. Bez konta pokazuje prośbę o logowanie
/// i po zalogowaniu wraca w to samo miejsce.
class SignedInOnly extends ConsumerWidget {
  const SignedInOnly({
    super.key,
    required this.title,
    required this.next,
    required this.body,
    this.bottom,
  });

  final String title;
  final String next;
  final Widget body;
  final Widget? bottom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loggedIn = ref.watch(userIdProvider) != null;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: loggedIn
          ? body
          : MessageView(
              icon: AppIcons.lock,
              title: 'Zaloguj się',
              message: 'Ta część ustawień dotyczy twojego konta.',
              actionLabel: 'Zaloguj się',
              onAction: () =>
                  context.push(AppRoutes.withNext(AppRoutes.login, next)),
            ),
      bottomNavigationBar: loggedIn ? bottom : null,
    );
  }
}
