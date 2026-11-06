import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/panel_widgets.dart';
import 'fiscal_printing.dart';
import 'payment_terminal.dart';

// Zakładki „Paragony” i „Terminal” w „Drukarki”: drukarka fiskalna (Novitus XML) i terminal płatniczy
// (Viva.com, Adyen) na tym komputerze, okno płatności kartą na terminalu i stan paragonu w Historii zamówień.

const _tabular = [FontFeature.tabularFigures()];

/// Pole tekstowe w wierszu ustawień, zapisywane Enterem albo wyjściem z pola.
class _SettingField extends StatefulWidget {
  const _SettingField({
    required this.value,
    required this.onCommit,
    this.hint = '',
    this.width = 240,
    this.obscure = false,
    this.digits = false,
  });

  final String value;
  final ValueChanged<String> onCommit;
  final String hint;
  final double width;
  final bool obscure;
  final bool digits;

  @override
  State<_SettingField> createState() => _SettingFieldState();
}

class _SettingFieldState extends State<_SettingField> {
  late final _controller = TextEditingController(text: widget.value);
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(_SettingField old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && old.value != widget.value) _controller.text = widget.value;
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit() {
    final v = _controller.text.trim();
    if (v != widget.value) widget.onCommit(v);
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: widget.width,
    child: TextField(
      controller: _controller,
      focusNode: _focus,
      obscureText: widget.obscure,
      keyboardType: widget.digits ? TextInputType.number : null,
      inputFormatters: widget.digits ? [FilteringTextInputFormatter.digitsOnly] : null,
      style: const TextStyle(fontFeatures: _tabular),
      decoration: InputDecoration(hintText: widget.hint, isDense: true),
      onSubmitted: (_) => _commit(),
    ),
  );
}

/// Szeroka kolumna ustawień na środku, jak „Ustawienia lokalu”.
class _Page extends StatelessWidget {
  const _Page({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(24, 16, 32, 32),
    children: [
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        ),
      ),
    ],
  );
}

class _Note extends StatelessWidget {
  const _Note(this.lines);

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 7, right: 10),
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(color: AppColors.textMuted, shape: BoxShape.circle),
                    ),
                  ),
                  Expanded(child: Text(l, style: text.bodyMedium?.copyWith(color: AppColors.textMuted))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// „Paragony”: drukarka fiskalna albo kasoterminal na tym komputerze.
class FiscalPage extends ConsumerStatefulWidget {
  const FiscalPage({super.key});

  @override
  ConsumerState<FiscalPage> createState() => _FiscalPageState();
}

class _FiscalPageState extends ConsumerState<FiscalPage> {
  bool _busy = false;
  String? _status;

  void _set(FiscalSettings s) => ref.read(fiscalSettingsProvider.notifier).set(s);

  Future<void> _check() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final s = await ref.read(fiscalPrintingProvider).check();
      final rates = [
        for (final e in s.rates.entries) '${e.key}: ${e.value == null ? 'zw.' : '${e.value!.toStringAsFixed(0)}%'}',
      ];
      setState(() {
        _status = [
          s.online ? 'Drukarka odpowiada' : 'Drukarka jest w menu albo offline',
          s.fiscal ? 'tryb fiskalny' : 'tryb szkoleniowy (paragony nie liczą się do sprzedaży)',
          if (!s.paperOk) 'brak papieru',
          'stawki PTU: ${rates.isEmpty ? 'brak' : rates.join(', ')}',
        ].join(' · ');
      });
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _test() async {
    setState(() => _busy = true);
    try {
      await ref.read(fiscalPrintingProvider).printTest(ref.read(currentRestaurantProvider)?.name ?? '');
      if (mounted) showMessage(context, 'Wydruk niefiskalny poszedł do drukarki.', tone: ToastTone.success);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(fiscalSettingsProvider);
    final text = Theme.of(context).textTheme;
    return _Page(
      children: [
        SettingsSection(
          title: 'Drukarka fiskalna albo kasoterminal',
          description: 'Na tym komputerze. Paragon dostaje to, co nabito w zamówieniu: pozycje ze stawkami VAT z menu, '
              'rabat, formy płatności i NIP firmy.',
          footer: Wrap(
            spacing: 8,
            children: [
              OutlinedButton(onPressed: _busy || !s.configured ? null : _test, child: const Text('Wydruk niefiskalny')),
              FilledButton(onPressed: _busy || !s.configured ? null : _check, child: const Text('Sprawdź połączenie')),
            ],
          ),
          children: [
            SettingsRow(
              title: 'Protokół',
              description: FiscalProtocol.novitusXml.devices,
              trailing: Text(FiscalProtocol.novitusXml.label, style: text.bodyMedium),
            ),
            SettingsRow(
              title: 'Adres IP drukarki',
              description: 'Drukarka w sieci lokalu (kabel albo Wi-Fi). Adres jest w menu drukarki, w ustawieniach sieci.',
              trailing: _SettingField(value: s.host, hint: '192.168.1.60', width: 200, onCommit: (v) => _set(s.copyWith(host: v))),
            ),
            SettingsRow(
              title: 'Port',
              description: 'Domyślnie 6001 dla protokołu XML Novitus.',
              trailing: _SettingField(
                value: '${s.port}',
                width: 100,
                digits: true,
                onCommit: (v) => _set(s.copyWith(port: int.tryParse(v) ?? 6001)),
              ),
            ),
            SettingsRow(
              title: 'Stawka VAT dostawy',
              description: 'Opłata za dostawę na paragonie. Stawkę potwierdza księgowość lokalu.',
              trailing: SegmentedTabs<int>(
                options: const [(8, '8%'), (23, '23%'), (5, '5%')],
                selected: s.deliveryVat,
                onChanged: (v) => _set(s.copyWith(deliveryVat: v)),
              ),
            ),
            SettingsRow(
              title: 'Kasa główna: paragony za wszystkie rachunki',
              description: 'Ten komputer sam drukuje paragon za każdy opłacony rachunek lokalu zamknięty od włączenia: '
                  'w panelu, u kelnera w telefonie i przy wydaniu zamówienia na wynos. Włącz tylko na jednym komputerze.',
              trailing: Switch(value: s.auto, onChanged: s.configured ? (v) => _set(s.copyWith(auto: v)) : null),
            ),
            if (_status != null) SettingsRow(title: 'Stan drukarki', description: _status),
          ],
        ),
        const SizedBox(height: 24),
        const SettingsSection(
          title: 'Jak to działa',
          children: [
            _Note([
              'Każdy rachunek dostaje najwyżej jeden paragon: przed wydrukiem rezerwuje się w bazie, więc dwa komputery '
                  'go nie zdublują. Wydrukowany paragon ma numer z drukarki w Historii zamówień.',
              'Bez kasy głównej paragon drukuje się ręcznie: Historia zamówień → rachunek → „Wydrukuj paragon”.',
              'Stawki VAT drukarki (A, B, C…) panel odczytuje sam i dopasowuje do stawek z menu.',
              'Testy rób na drukarce przed fiskalizacją albo w trybie szkoleniowym. Paragon z drukarki fiskalnej '
                  'trafia do urzędu skarbowego. „Wydruk niefiskalny” nie rejestruje sprzedaży.',
              'Posnet i Elzab nie mają publicznej dokumentacji protokołu. Dodamy je, gdy lokal dostanie ją od producenta.',
            ]),
          ],
        ),
      ],
    );
  }
}

/// „Terminal”: terminal płatniczy na tym komputerze.
class TerminalPage extends ConsumerStatefulWidget {
  const TerminalPage({super.key});

  @override
  ConsumerState<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends ConsumerState<TerminalPage> {
  bool _busy = false;
  String? _status;

  void _set(TerminalSettings s) {
    ref.read(terminalSettingsProvider.notifier).set(s);
    setState(() => _status = null);
  }

  Future<void> _check() async {
    final client = ref.read(terminalClientProvider);
    if (client == null) return;
    setState(() => _busy = true);
    try {
      final status = await client.check();
      setState(() => _status = status);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _testPayment() async {
    final client = ref.read(terminalClientProvider);
    if (client == null) return;
    final result = await showTerminalPayment(context, client, grosze: 100, reference: 'Table: płatność próbna');
    if (result != null && mounted) showMessage(context, 'Płatność próbna: ${result.message}', tone: ToastTone.success);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(terminalSettingsProvider);
    final provider = s.provider;
    return _Page(
      children: [
        SettingsSection(
          title: 'Terminal płatniczy',
          description: 'Na tym komputerze. Przy zamknięciu rachunku kartą panel wysyła kwotę na terminal i zapisuje '
              'płatność dopiero, gdy terminal ją przyjmie.',
          footer: Wrap(
            spacing: 8,
            children: [
              if (s.test)
                OutlinedButton(
                  onPressed: _busy || !s.configured ? null : _testPayment,
                  child: const Text('Płatność próbna 1,00 zł'),
                ),
              FilledButton(onPressed: _busy || !s.configured ? null : _check, child: const Text('Sprawdź połączenie')),
            ],
          ),
          children: [
            SettingsRow(
              title: 'Operator',
              description: provider?.devices ?? 'Terminale z publicznym API. Inni operatorzy po umowie partnerskiej.',
              trailing: SegmentedTabs<TerminalProvider?>(
                options: [(null, 'Brak'), for (final p in TerminalProvider.values) (p, p.label)],
                selected: provider,
                onChanged: (p) => _set(p == null ? s.copyWith(clearProvider: true) : s.copyWith(provider: p)),
              ),
            ),
            if (provider != null)
              SettingsRow(
                title: provider == TerminalProvider.viva ? 'Konto demo' : 'Konto testowe',
                description: s.test
                    ? 'Płatności bez prawdziwych pieniędzy. Wyłącz, gdy lokal przejdzie na konto produkcyjne.'
                    : 'Konto produkcyjne: terminal pobiera prawdziwe pieniądze.',
                trailing: Switch(value: s.test, onChanged: (v) => _set(s.copyWith(test: v))),
              ),
            if (provider == TerminalProvider.viva) ...[
              SettingsRow(
                title: 'Client ID',
                description: 'Konto Viva → Settings → API Access → POS APIs.',
                trailing: _SettingField(value: s.vivaClientId, width: 300, onCommit: (v) => _set(s.copyWith(vivaClientId: v))),
              ),
              SettingsRow(
                title: 'Client Secret',
                trailing: _SettingField(
                  value: s.vivaClientSecret,
                  width: 300,
                  obscure: true,
                  onCommit: (v) => _set(s.copyWith(vivaClientSecret: v)),
                ),
              ),
              SettingsRow(
                title: 'Terminal ID',
                description: 'W aplikacji Viva.com Terminal: More → About → Source Terminal ID.',
                trailing: _SettingField(value: s.vivaTerminalId, width: 200, onCommit: (v) => _set(s.copyWith(vivaTerminalId: v))),
              ),
            ],
            if (provider == TerminalProvider.adyen) ...[
              SettingsRow(
                title: 'Klucz API',
                description: 'Customer Area → Developers → API credentials, z rolą „Cloud Device API”.',
                trailing: _SettingField(
                  value: s.adyenApiKey,
                  width: 300,
                  obscure: true,
                  onCommit: (v) => _set(s.copyWith(adyenApiKey: v)),
                ),
              ),
              SettingsRow(
                title: 'Konto (merchant account)',
                trailing: _SettingField(value: s.adyenMerchant, width: 300, onCommit: (v) => _set(s.copyWith(adyenMerchant: v))),
              ),
              SettingsRow(
                title: 'Terminal (POIID)',
                description: 'Model i numer seryjny, np. V400m-123456789 (Devices → Device list).',
                trailing: _SettingField(value: s.adyenPoiid, width: 220, onCommit: (v) => _set(s.copyWith(adyenPoiid: v))),
              ),
            ],
            if (provider != null)
              SettingsRow(
                title: 'Nazwa kasy',
                description: 'Ten komputer w systemie operatora (każdy komputer z terminalem inna, np. TABLE-1, TABLE-2).',
                trailing: _SettingField(value: s.cashRegisterId, width: 200, onCommit: (v) => _set(s.copyWith(cashRegisterId: v))),
              ),
            if (_status != null) SettingsRow(title: 'Połączenie', description: _status),
          ],
        ),
        const SizedBox(height: 24),
        const SettingsSection(
          title: 'Jak to działa',
          children: [
            _Note([
              'Zamknięcie rachunku kartą (całość albo wybrane pozycje) otwiera okno płatności: terminal pokazuje kwotę '
                  'z napiwkiem, a panel czeka na wynik. „Przerwij” działa, dopóki gość nie przyłożył karty.',
              'Przy podziale „Równo” na osoby kartę przyjmuje się na terminalu ręcznie, jak dotąd.',
              'Klucze operatora zostają tylko na tym komputerze. Wpisuje je lokal ze swojego konta u operatora.',
              'Polscy operatorzy (eService, Polcard, Elavon, PeP, PayTel) nie mają publicznej dokumentacji; ich terminale '
                  'dodamy po umowie partnerskiej.',
            ]),
          ],
        ),
      ],
    );
  }
}

/// Okno płatności na terminalu: kwota, napis z terminala, „Przerwij”. Zwraca wynik udanej płatności, null: brak.
Future<TerminalResult?> showTerminalPayment(
  BuildContext context,
  TerminalClient client, {
  required int grosze,
  required String reference,
}) {
  return showDialog<TerminalResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _TerminalDialog(client: client, grosze: grosze, reference: reference),
  );
}

class _TerminalDialog extends StatefulWidget {
  const _TerminalDialog({required this.client, required this.grosze, required this.reference});

  final TerminalClient client;
  final int grosze;
  final String reference;

  @override
  State<_TerminalDialog> createState() => _TerminalDialogState();
}

class _TerminalDialogState extends State<_TerminalDialog> {
  String _status = 'Łączę z terminalem…';
  String? _error;
  bool _running = false;
  TerminalCancel _cancel = TerminalCancel();

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    _cancel = TerminalCancel();
    setState(() {
      _running = true;
      _error = null;
      _status = 'Łączę z terminalem…';
    });
    try {
      final r = await widget.client.pay(
        widget.grosze,
        reference: widget.reference,
        onStatus: (s) {
          if (mounted) setState(() => _status = s);
        },
        cancel: _cancel,
      );
      if (!mounted) return;
      if (r.success) {
        Navigator.pop(context, r);
        return;
      }
      setState(() => _error = r.message);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AlertDialog(
      title: const Text('Płatność kartą'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Text(Fmt.price(widget.grosze), style: text.displaySmall?.copyWith(fontFeatures: _tabular)),
            const SizedBox(height: 16),
            if (_error == null) ...[
              const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5)),
              const SizedBox(height: 14),
              Text(_status, textAlign: TextAlign.center, style: text.bodyMedium),
            ] else ...[
              Glyph(AppIcons.warning, size: 28, color: AppColors.error),
              const SizedBox(height: 10),
              Text(_error!, textAlign: TextAlign.center, style: text.bodyMedium?.copyWith(color: AppColors.error)),
            ],
          ],
        ),
      ),
      actions: [
        if (_running)
          TextButton(
            onPressed: _cancel.requested ? null : _cancel.cancel,
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Przerwij'),
          )
        else ...[
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Zamknij')),
          FilledButton(onPressed: _start, child: const Text('Spróbuj ponownie')),
        ],
      ],
    );
  }
}

/// Stan paragonu fiskalnego w szczegółach rachunku (Historia zamówień): numer z drukarki albo „Wydrukuj paragon”.
class FiscalReceiptRow extends ConsumerStatefulWidget {
  const FiscalReceiptRow({super.key, required this.order});

  final PanelOrder order;

  @override
  ConsumerState<FiscalReceiptRow> createState() => _FiscalReceiptRowState();
}

class _FiscalReceiptRowState extends ConsumerState<FiscalReceiptRow> {
  bool _busy = false;

  Future<void> _print({bool force = false}) async {
    if (force) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Wydrukować paragon jeszcze raz?'),
          content: const SizedBox(
            width: 420,
            child: Text(
              'Wydruk tego rachunku został przerwany. Sprawdź na drukarce, czy paragon nie wyszedł: drugi paragon '
              'za ten sam rachunek zawyży sprzedaż.',
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Wróć')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Drukuj')),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _busy = true);
    try {
      final printed = await ref.read(fiscalPrintingProvider).printOrder(widget.order.id, force: force);
      if (!mounted) return;
      showMessage(
        context,
        printed ? 'Paragon wydrukowany.' : 'Ten rachunek ma już paragon.',
        tone: printed ? ToastTone.success : ToastTone.info,
        icon: AppIcons.receipt,
      );
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    if (!order.isPaid) return const SizedBox.shrink();
    final restaurant = ref.watch(currentRestaurantProvider);
    if (restaurant == null) return const SizedBox.shrink();
    final day = DateTime((order.closedAt ?? order.openedAt).year, (order.closedAt ?? order.openedAt).month,
        (order.closedAt ?? order.openedAt).day);
    final receipts = ref.watch(fiscalReceiptsProvider((restaurantId: restaurant.id, day: day))).value;
    final configured = ref.watch(fiscalSettingsProvider).configured;
    final entry = receipts?[order.id];
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular);
    final Widget content;
    if (entry != null && entry.$1 != null) {
      content = Text(
        'Paragon fiskalny${entry.$2 == null || entry.$2!.isEmpty ? '' : ' nr ${entry.$2}'} · ${Fmt.time(entry.$1!)}',
        style: muted,
      );
    } else if (entry != null) {
      content = Row(
        children: [
          Expanded(child: Text('Wydruk paragonu w toku albo przerwany', style: muted)),
          if (configured)
            TextButton(onPressed: _busy ? null : () => _print(force: true), child: const Text('Drukuj ponownie')),
        ],
      );
    } else if (configured) {
      content = Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _busy ? null : _print,
          icon: const Glyph(AppIcons.receipt, size: 16),
          label: Text(_busy ? 'Drukowanie…' : 'Wydrukuj paragon'),
        ),
      );
    } else {
      return const SizedBox.shrink();
    }
    return Padding(padding: const EdgeInsets.only(top: 6), child: content);
  }
}
