import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_panel/app/app.dart';
import 'package:table_panel/app/idle_logout.dart';
import 'package:table_panel/data/models.dart';
import 'package:table_panel/data/providers.dart';

class _Member extends PanelMemberNotifier {
  @override
  ActingMember? build() => null;
}

const _anna = ActingMember(memberId: 'm1', name: 'Anna Kowalska', permissions: {'kitchen'});

void main() {
  Future<ProviderContainer> pump(WidgetTester tester, String path) async {
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [panelMemberProvider.overrideWith(_Member.new)],
        child: MaterialApp(
          navigatorKey: key,
          builder: (context, child) => IdleLogout(location: () => path, navigators: [key], child: child!),
          home: const Text('panel'),
        ),
      ),
    );
    return ProviderScope.containerOf(tester.element(find.text('panel')));
  }

  Future<void> wait(WidgetTester tester, int seconds) async {
    for (var i = 0; i < seconds; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
  }

  testWidgets('pracownik wylogowuje się po 30 s bez ruchu', (tester) async {
    final container = await pump(tester, PanelRoutes.reservations);
    container.read(panelMemberProvider.notifier).signIn(_anna);
    await wait(tester, kIdleLogoutSeconds - 1);
    expect(container.read(panelMemberProvider)?.name, 'Anna Kowalska');
    expect(container.read(idleSecondsProvider), kIdleLogoutSeconds - 1);
    await wait(tester, 2);
    expect(container.read(panelMemberProvider), isNull);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('pełny dostęp właściciela nie wylogowuje się sam', (tester) async {
    final container = await pump(tester, PanelRoutes.reservations);
    container.read(panelMemberProvider.notifier).signIn(ActingMember.account());
    await wait(tester, kIdleLogoutSeconds * 3);
    expect(container.read(panelMemberProvider)?.isAccount, isTrue);
    // Bez odliczania w górnym pasku.
    expect(container.read(idleSecondsProvider), 0);
  });

  testWidgets('po właścicielu pracownik znowu wylogowuje się po 30 s', (tester) async {
    final container = await pump(tester, PanelRoutes.orders);
    container.read(panelMemberProvider.notifier).signIn(ActingMember.account());
    await wait(tester, kIdleLogoutSeconds + 5);
    container.read(panelMemberProvider.notifier).signIn(_anna);
    await wait(tester, kIdleLogoutSeconds + 1);
    expect(container.read(panelMemberProvider), isNull);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('w Kuchni pracownik zostaje', (tester) async {
    final container = await pump(tester, PanelRoutes.kitchen);
    container.read(panelMemberProvider.notifier).signIn(_anna);
    await wait(tester, kIdleLogoutSeconds + 5);
    expect(container.read(panelMemberProvider)?.name, 'Anna Kowalska');
  });
}
