import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../app/app.dart';
import '../../data/providers.dart';

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
      appBar: AppBar(leading: glassLeading(context), title: Text(title)),
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
