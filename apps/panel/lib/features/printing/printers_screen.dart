import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../app/panel_theme.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/panel_widgets.dart';
import '../../shared/side_panel.dart';
import 'devices_pages.dart';
import 'fiscal_printing.dart';
import 'label_printing.dart';
import 'label_render.dart';
import 'label_template.dart';
import 'printer_commands.dart';
import 'payment_terminal.dart';
import 'printer_transport.dart';

// Drukarki (pasek boczny pod „Ustawienia lokalu”, `/drukarki`, 6.11.2026, prośba użytkownika): drukarka etykiet
// tego komputera (np. Xprinter XP-410B) i edytor etykiety na pudełka i torby zamówień na wynos z wydrukiem
// testowym. Układ jak Pracownicy: po lewej zwijany panel, po prawej etykieta i właściwości elementu.

const _tabular = [FontFeature.tabularFigures()];

String _mm(double v) {
  final s = v.toStringAsFixed(1);
  return (s.endsWith('.0') ? s.substring(0, s.length - 2) : s).replaceAll('.', ',');
}

double? _parseMm(String text) => double.tryParse(text.trim().replaceAll(',', '.'));

/// Niezapisany wzór etykiety: przeżywa przejście do innej zakładki.
typedef _Draft = ({String restaurantId, LabelTemplate template});

class _DraftNotifier extends Notifier<_Draft?> {
  @override
  _Draft? build() => null;

  void set(_Draft? value) => state = value;
}

final _labelDraftProvider = NotifierProvider<_DraftNotifier, _Draft?>(_DraftNotifier.new);

/// Części „Drukarki”: etykiety (edytor), paragony (drukarka fiskalna), terminal płatniczy.
enum _Section { labels, fiscal, terminal }

class PrintersScreen extends ConsumerStatefulWidget {
  const PrintersScreen({super.key});

  @override
  ConsumerState<PrintersScreen> createState() => _PrintersScreenState();
}

class _PrintersScreenState extends ConsumerState<PrintersScreen> {
  bool _panelOpen = true;
  _Section _section = _Section.labels;
  String? _selectedId;
  bool _preview = false;
  bool _sampleDelivery = true;
  bool _saving = false;
  final _undo = <LabelTemplate>[];
  final _redo = <LabelTemplate>[];
  final _canvasFocus = FocusNode(debugLabel: 'etykieta');

  @override
  void dispose() {
    _canvasFocus.dispose();
    super.dispose();
  }

  LabelTemplate _current(String restaurantId, LabelTemplate base) {
    final draft = ref.read(_labelDraftProvider);
    return draft != null && draft.restaurantId == restaurantId ? draft.template : base;
  }

  /// Zmiana wzoru. [record] false w trakcie przeciągania (cofnięcie zapisuje się raz, na początku ruchu).
  void _apply(String restaurantId, LabelTemplate base, LabelTemplate next, {bool record = true}) {
    if (record) {
      _undo.add(_current(restaurantId, base));
      if (_undo.length > 60) _undo.removeAt(0);
      _redo.clear();
    }
    ref.read(_labelDraftProvider.notifier).set((restaurantId: restaurantId, template: next));
  }

  void _record(String restaurantId, LabelTemplate base) {
    _undo.add(_current(restaurantId, base));
    if (_undo.length > 60) _undo.removeAt(0);
    _redo.clear();
  }

  void _undoStep(String restaurantId, LabelTemplate base, {bool redo = false}) {
    final from = redo ? _redo : _undo;
    if (from.isEmpty) return;
    (redo ? _undo : _redo).add(_current(restaurantId, base));
    final next = from.removeLast();
    ref.read(_labelDraftProvider.notifier).set((restaurantId: restaurantId, template: next));
    if (_selectedId != null && !next.elements.any((e) => e.id == _selectedId)) _selectedId = null;
    setState(() {});
  }

  void _updateElement(String restaurantId, LabelTemplate base, LabelElement e, {bool record = true}) {
    final t = _current(restaurantId, base);
    _apply(restaurantId, base, t.copyWith(elements: [for (final x in t.elements) x.id == e.id ? e : x]), record: record);
  }

  void _add(String restaurantId, LabelTemplate base, LabelElementType type) {
    final t = _current(restaurantId, base);
    final w = t.widthMm.toDouble();
    final h = t.heightMm.toDouble();
    final id = newLabelElementId();
    final e = switch (type) {
      LabelElementType.text => LabelElement(
        id: id,
        type: type,
        x: roundMm(math.max(0, (w - 40) / 2)),
        y: roundMm(math.max(0, (h - 8) / 2)),
        w: math.min(40, w),
        h: 8,
        text: 'Tekst',
      ),
      LabelElementType.line => LabelElement(id: id, type: type, x: 3, y: roundMm(h / 2), w: w - 6, h: 0.4),
      LabelElementType.box => LabelElement(id: id, type: type, x: roundMm(w / 4), y: roundMm(h / 4), w: roundMm(w / 2), h: roundMm(h / 2)),
      LabelElementType.qr => LabelElement(
        id: id,
        type: type,
        x: roundMm(math.max(0, w - 21)),
        y: roundMm(math.max(0, h - 21)),
        w: math.min(18, w),
        h: math.min(18, h),
        text: '#{numer}',
      ),
      LabelElementType.logo => LabelElement(id: id, type: type, x: roundMm(math.max(0, w - 25)), y: 3, w: math.min(22, w), h: math.min(12, h)),
    };
    _apply(restaurantId, base, t.copyWith(elements: [...t.elements, e]));
    setState(() => _selectedId = id);
    _canvasFocus.requestFocus();
  }

  void _delete(String restaurantId, LabelTemplate base, String id) {
    final t = _current(restaurantId, base);
    _apply(restaurantId, base, t.copyWith(elements: [for (final e in t.elements) if (e.id != id) e]));
    setState(() => _selectedId = null);
  }

  void _duplicate(String restaurantId, LabelTemplate base, String id) {
    final t = _current(restaurantId, base);
    final source = t.elements.where((e) => e.id == id).firstOrNull;
    if (source == null) return;
    final copy = source.copyWith(
      id: newLabelElementId(),
      x: math.min(source.x + 2, math.max(0, t.widthMm - source.w)),
      y: math.min(source.y + 2, math.max(0, t.heightMm - source.h)),
    );
    _apply(restaurantId, base, t.copyWith(elements: [...t.elements, copy]));
    setState(() => _selectedId = copy.id);
  }

  Future<void> _save(String restaurantId, LabelTemplate template) async {
    setState(() => _saving = true);
    try {
      await ref.read(repositoryProvider).saveLabelTemplate(template.toRpc(restaurantId));
      ref.invalidate(labelTemplateProvider(restaurantId));
      await ref.read(labelTemplateProvider(restaurantId).future);
      ref.read(_labelDraftProvider.notifier).set(null);
      if (mounted) showMessage(context, 'Etykieta zapisana. Wszystkie komputery lokalu drukują ją od teraz.', tone: ToastTone.success);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _discard() {
    ref.read(_labelDraftProvider.notifier).set(null);
    _undo.clear();
    _redo.clear();
    setState(() => _selectedId = null);
  }

  KeyEventResult _onKey(String restaurantId, LabelTemplate base, KeyEvent event, bool editable) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final keys = HardwareKeyboard.instance;
    final ctrl = keys.isControlPressed || keys.isMetaPressed;
    final key = event.logicalKey;
    if (ctrl && key == LogicalKeyboardKey.keyZ && editable) {
      _undoStep(restaurantId, base, redo: keys.isShiftPressed);
      return KeyEventResult.handled;
    }
    if (ctrl && key == LogicalKeyboardKey.keyY && editable) {
      _undoStep(restaurantId, base, redo: true);
      return KeyEventResult.handled;
    }
    final id = _selectedId;
    if (id == null) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.escape) {
      setState(() => _selectedId = null);
      return KeyEventResult.handled;
    }
    if (!editable) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.delete || key == LogicalKeyboardKey.backspace) {
      _delete(restaurantId, base, id);
      return KeyEventResult.handled;
    }
    if (ctrl && key == LogicalKeyboardKey.keyD) {
      _duplicate(restaurantId, base, id);
      return KeyEventResult.handled;
    }
    final step = keys.isShiftPressed ? 5.0 : (keys.isAltPressed ? 0.1 : 0.5);
    final (dx, dy) = switch (key) {
      LogicalKeyboardKey.arrowLeft => (-step, 0.0),
      LogicalKeyboardKey.arrowRight => (step, 0.0),
      LogicalKeyboardKey.arrowUp => (0.0, -step),
      LogicalKeyboardKey.arrowDown => (0.0, step),
      _ => (0.0, 0.0),
    };
    if (dx == 0 && dy == 0) return KeyEventResult.ignored;
    final t = _current(restaurantId, base);
    final e = t.elements.where((x) => x.id == id).firstOrNull;
    if (e == null) return KeyEventResult.ignored;
    _updateElement(
      restaurantId,
      base,
      e.copyWith(
        x: (e.x + dx).clamp(0, math.max(0, t.widthMm - e.w)).toDouble(),
        y: (e.y + dy).clamp(0, math.max(0, t.heightMm - e.h)).toDouble(),
      ),
    );
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final restaurant = ref.watch(currentRestaurantProvider);
    if (restaurant == null) return const LoadingView();
    if (!restaurant.isPro) return const ProGate(feature: 'Drukarki i etykiety');
    final rid = restaurant.id;
    final editable = ref.watch(memberPermissionsProvider).contains('profile');
    final async = ref.watch(labelTemplateProvider(rid));
    final base = async.value;
    if (base == null) {
      return async.hasError
          ? ErrorView(error: async.error!, onRetry: () => ref.invalidate(labelTemplateProvider(rid)))
          : const LoadingView();
    }
    final draft = ref.watch(_labelDraftProvider);
    final template = draft != null && draft.restaurantId == rid ? draft.template : base;
    final dirty = template.signature != base.signature;
    final logoUrl = restaurant.logoUrl;
    final logo = logoUrl == null ? null : ref.watch(labelLogoProvider(logoUrl)).value;
    final values = sampleLabelValues(delivery: _sampleDelivery, restaurantName: restaurant.name);
    final menu = ref.watch(menuProvider(rid)).value ?? const <MenuSection>[];
    final selected = template.elements.where((e) => e.id == _selectedId).firstOrNull;

    final panel = SidePanel(
      header: SegmentedTabs<_Section>(
        options: const [(_Section.labels, 'Etykiety'), (_Section.fiscal, 'Paragony'), (_Section.terminal, 'Terminal')],
        selected: _section,
        expand: true,
        onChanged: (s) => setState(() => _section = s),
      ),
      children: switch (_section) {
        _Section.labels => [
          _PrinterSection(template: template, values: values, logoUrl: logoUrl),
          _RulesSection(
            template: template,
            menu: menu,
            editable: editable,
            onChanged: (t) => _apply(rid, base, t),
          ),
        ],
        _Section.fiscal => const [_DeviceSummary(fiscal: true)],
        _Section.terminal => const [_DeviceSummary(fiscal: false)],
      },
    );

    final text = Theme.of(context).textTheme;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 32, 12),
          child: SizedBox(
            height: 40,
            child: Row(
              children: [
                if (editable) ...[
                  for (final type in LabelElementType.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: TextButton.icon(
                        onPressed: _preview ? null : () => _add(rid, base, type),
                        icon: Glyph(type.icon, size: 16),
                        label: Text(type.label),
                      ),
                    ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Cofnij (Ctrl+Z)',
                    onPressed: _undo.isEmpty ? null : () => _undoStep(rid, base),
                    icon: const Glyph(AppIcons.undo, size: 18),
                  ),
                  IconButton(
                    tooltip: 'Ponów (Ctrl+Shift+Z)',
                    onPressed: _redo.isEmpty ? null : () => _undoStep(rid, base, redo: true),
                    icon: const Glyph(AppIcons.redo, size: 18),
                  ),
                ],
                const Spacer(),
                SegmentedTabs<bool>(
                  options: const [(true, 'Dostawa'), (false, 'Odbiór')],
                  selected: _sampleDelivery,
                  onChanged: (v) => setState(() => _sampleDelivery = v),
                ),
                const SizedBox(width: 8),
                SegmentedTabs<bool>(
                  options: const [(false, 'Edycja'), (true, 'Wydruk')],
                  selected: _preview,
                  onChanged: (v) => setState(() {
                    _preview = v;
                    if (v) _selectedId = null;
                  }),
                ),
                if (dirty && editable) ...[
                  const SizedBox(width: 12),
                  TextButton(onPressed: _saving ? null : _discard, child: const Text('Odrzuć zmiany')),
                  const SizedBox(width: 4),
                  FilledButton(
                    onPressed: _saving ? null : () => _save(rid, template),
                    child: Text(_saving ? 'Zapisywanie…' : 'Zapisz etykietę'),
                  ),
                ],
              ],
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 32, 24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Card(
                    margin: EdgeInsets.zero,
                    clipBehavior: Clip.antiAlias,
                    child: Focus(
                      focusNode: _canvasFocus,
                      onKeyEvent: (_, event) => _onKey(rid, base, event, editable && !_preview),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _preview
                                ? _RasterPreview(template: template, values: values, logo: logo)
                                : _LabelCanvas(
                                    template: template,
                                    values: values,
                                    logo: logo,
                                    selectedId: _selectedId,
                                    editable: editable,
                                    onSelect: (id) {
                                      _canvasFocus.requestFocus();
                                      setState(() => _selectedId = id);
                                    },
                                    onMoveStart: () => _record(rid, base),
                                    onMove: (e) => _updateElement(rid, base, e, record: false),
                                  ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                            child: Text(
                              _preview
                                  ? 'Tak wydrukuje drukarka: ${template.widthMm} × ${template.heightMm} mm, 203 dpi, '
                                        'czarne i białe punkty.'
                                  : '${template.widthMm} × ${template.heightMm} mm · przeciągnij element, żeby go '
                                        'przesunąć; strzałki o 0,5 mm (Shift o 5 mm), Delete usuwa, Ctrl+D duplikuje.',
                              textAlign: TextAlign.center,
                              style: text.bodySmall?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                SizedBox(
                  width: 320,
                  child: Card(
                    margin: EdgeInsets.zero,
                    child: selected == null
                        ? _TemplateInspector(
                            template: template,
                            editable: editable,
                            onChanged: (t) => _apply(rid, base, t),
                            onSelect: (id) => setState(() {
                              _preview = false;
                              _selectedId = id;
                            }),
                          )
                        : _ElementInspector(
                            key: ValueKey(selected.id),
                            element: selected,
                            template: template,
                            editable: editable,
                            onChanged: (e) => _updateElement(rid, base, e),
                            onDelete: () => _delete(rid, base, selected.id),
                            onDuplicate: () => _duplicate(rid, base, selected.id),
                            onClose: () => setState(() => _selectedId = null),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );

    return SidePanelLayout(
      open: _panelOpen,
      onToggle: () => setState(() => _panelOpen = !_panelOpen),
      panel: panel,
      content: TabContent(
        tab: _section.index,
        child: switch (_section) {
          _Section.labels => content,
          _Section.fiscal => const FiscalPage(),
          _Section.terminal => const TerminalPage(),
        },
      ),
    );
  }
}

/// Panel po lewej przy „Paragony” i „Terminal”: co jest ustawione na tym komputerze.
class _DeviceSummary extends ConsumerWidget {
  const _DeviceSummary({required this.fiscal});

  final bool fiscal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: AppColors.textMuted);
    final String title;
    final String body;
    if (fiscal) {
      final s = ref.watch(fiscalSettingsProvider);
      title = s.configured ? s.title : 'Nie ustawiona';
      body = s.configured
          ? (s.auto ? 'Kasa główna: drukuje paragony za wszystkie opłacone rachunki lokalu.' : 'Paragony drukuje się ręcznie z Historii zamówień.')
          : 'Wpisz adres drukarki fiskalnej Novitus w sieci lokalu.';
    } else {
      final s = ref.watch(terminalSettingsProvider);
      title = s.configured ? s.title : 'Nie ustawiony';
      body = s.configured
          ? 'Zamknięcie rachunku kartą wysyła kwotę na terminal.'
          : 'Wybierz operatora i wpisz dane z konta u operatora.';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _GroupTitle(fiscal ? 'Drukarka fiskalna' : 'Terminal płatniczy', subtitle: 'na tym komputerze', first: true),
        Text(title, style: text.bodyMedium),
        const SizedBox(height: 4),
        Text(body, style: muted),
      ],
    );
  }
}

/// Nagłówek grupy w panelu po lewej (z kreską nad sobą, poza pierwszą).
class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.title, {this.subtitle, this.first = false});

  final String title;
  final String? subtitle;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!first) ...[const SizedBox(height: 8), Divider(height: 1, color: AppColors.ring)],
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(title, style: text.labelLarge),
              if (subtitle != null) ...[
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Mały podpis nad kontrolką w panelu.
class _Caption extends StatelessWidget {
  const _Caption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: AppColors.textMuted)),
  );
}

/// Pole wyboru w wierszu panelu (bez liczby, w przeciwieństwie do filtrów).
class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.label, required this.value, required this.onChanged});

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        height: 32,
        child: Row(
          children: [
            PanelCheck(value: value, onChanged: onChanged == null ? null : (v) => onChanged!(v ?? false)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: onChanged == null ? AppColors.textDisabled : AppColors.text,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Przełącznik w wierszu panelu z opisem pod spodem.
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({required this.title, required this.value, required this.onChanged, this.description});

  final String title;
  final String? description;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.bodyMedium),
                if (description != null)
                  Text(description!, style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// Drukarka etykiet tego komputera: wybór z drukarek systemu albo adres w sieci, język, ciemność, przerwa,
/// obrót, wydruk testowy i automatyczne drukowanie.
class _PrinterSection extends ConsumerStatefulWidget {
  const _PrinterSection({required this.template, required this.values, required this.logoUrl});

  final LabelTemplate template;
  final Map<String, String> values;
  final String? logoUrl;

  @override
  ConsumerState<_PrinterSection> createState() => _PrinterSectionState();
}

class _PrinterSectionState extends ConsumerState<_PrinterSection> {
  static const _networkChoice = '\u0000sieć';
  final _host = TextEditingController();
  final _port = TextEditingController();
  bool _testing = false;
  bool _guessed = false;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(labelPrinterProvider);
    _host.text = settings.host;
    _port.text = '${settings.port}';
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  void _set(LabelPrinterSettings value) => ref.read(labelPrinterProvider.notifier).set(value);

  Future<void> _test() async {
    setState(() => _testing = true);
    try {
      await ref
          .read(labelPrintingProvider)
          .printTest(widget.template, widget.values, logoUrl: widget.logoUrl);
      if (mounted) {
        showMessage(
          context,
          'Etykieta testowa poszła do „${ref.read(labelPrinterProvider).title}”.',
          tone: ToastTone.success,
          icon: AppIcons.printer,
        );
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(labelPrinterProvider);
    final printers = ref.watch(systemPrintersProvider).value ?? const <String>[];
    // Pierwsze wejście bez wybranej drukarki: jedna drukarka etykiet w systemie wybiera się sama.
    if (!_guessed && !settings.configured && printers.isNotEmpty) {
      _guessed = true;
      final labelPrinters = [
        for (final p in printers)
          if (RegExp(r'xprinter|xp-\d|zebra|zdesigner|tsc|godex|label|etykiet', caseSensitive: false).hasMatch(p)) p,
      ];
      if (labelPrinters.length == 1) {
        final name = labelPrinters.single;
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _set(settings.copyWith(network: false, printer: name, language: PrinterLanguage.guess(name))),
        );
      }
    }
    final choice = settings.network ? _networkChoice : (printers.contains(settings.printer) ? settings.printer : null);
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _GroupTitle('Drukarka etykiet', subtitle: 'na tym komputerze', first: true),
        DropdownButtonFormField<String>(
          key: ValueKey('$choice${printers.length}'),
          initialValue: choice,
          isExpanded: true,
          icon: const Glyph(AppIcons.caretDown, size: 16),
          decoration: const InputDecoration(labelText: 'Drukarka', isDense: true),
          hint: Text(settings.printer.isNotEmpty ? '${settings.printer} (niedostępna)' : 'Wybierz drukarkę'),
          items: [
            for (final p in printers) DropdownMenuItem(value: p, child: Text(p, overflow: TextOverflow.ellipsis)),
            const DropdownMenuItem(value: _networkChoice, child: Text('Drukarka w sieci (adres IP)')),
          ],
          onChanged: (v) {
            if (v == null) return;
            if (v == _networkChoice) {
              _set(settings.copyWith(network: true));
            } else {
              _set(settings.copyWith(network: false, printer: v, language: PrinterLanguage.guess(v)));
            }
          },
        ),
        if (settings.network) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Focus(
                  canRequestFocus: false,
                  skipTraversal: true,
                  onFocusChange: (f) {
                    if (!f) _set(ref.read(labelPrinterProvider).copyWith(host: _host.text.trim()));
                  },
                  child: TextField(
                    controller: _host,
                    decoration: const InputDecoration(labelText: 'Adres IP', hintText: '192.168.1.50', isDense: true),
                    onSubmitted: (v) => _set(ref.read(labelPrinterProvider).copyWith(host: v.trim())),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 76,
                child: Focus(
                  canRequestFocus: false,
                  skipTraversal: true,
                  onFocusChange: (f) {
                    final port = int.tryParse(_port.text.trim());
                    if (!f && port != null) _set(ref.read(labelPrinterProvider).copyWith(port: port));
                  },
                  child: TextField(
                    controller: _port,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(5)],
                    decoration: const InputDecoration(labelText: 'Port', isDense: true),
                  ),
                ),
              ),
            ],
          ),
        ],
        if (!PrinterTransport.supportsSystem)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Na tablecie drukuje tylko drukarka w sieci (Wi-Fi albo kabel do routera).',
              style: text.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
          ),
        const SizedBox(height: 14),
        const _Caption('Język drukarki'),
        SegmentedTabs<PrinterLanguage>(
          options: [for (final l in PrinterLanguage.values) (l, l.label)],
          selected: settings.language,
          expand: true,
          onChanged: (l) => _set(settings.copyWith(language: l)),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(settings.language.brands, style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Expanded(child: _Caption('Ciemność druku')),
            Text('${settings.darkness}', style: text.labelMedium?.copyWith(fontFeatures: _tabular)),
          ],
        ),
        Slider(
          value: settings.darkness.toDouble(),
          min: 1,
          max: 15,
          divisions: 14,
          onChanged: (v) => _set(settings.copyWith(darkness: v.round())),
        ),
        const _Caption('Przerwa między etykietami'),
        SegmentedTabs<double>(
          options: const [(0, 'Brak'), (2, '2 mm'), (3, '3 mm')],
          selected: [0.0, 2.0, 3.0].contains(settings.gapMm) ? settings.gapMm : 2,
          expand: true,
          onChanged: (g) => _set(settings.copyWith(gapMm: g)),
        ),
        const SizedBox(height: 12),
        _SwitchRow(
          title: 'Obróć o 180°',
          description: 'Gdy etykieta wychodzi do góry nogami.',
          value: settings.rotate,
          onChanged: (v) => _set(settings.copyWith(rotate: v)),
        ),
        PanelAction(label: _testing ? 'Drukowanie…' : 'Wydruk testowy', onTap: _testing ? () {} : _test),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            'Drukuje etykietę z edytora (także niezapisaną) z przykładowym zamówieniem.',
            style: text.bodySmall?.copyWith(color: AppColors.textMuted),
          ),
        ),
        const _GroupTitle('Kiedy drukować', subtitle: 'na tym komputerze'),
        _SwitchRow(
          title: 'Sam po przyjęciu zamówienia',
          description: 'Dostawy i odbiór osobisty przyjęte w panelu albo w aplikacji pracownika. Ręcznie: '
              'przycisk drukarki na karcie zamówienia w Dostawach i Odbiorze.',
          value: settings.autoPrint,
          onChanged: settings.configured ? (v) => _set(settings.copyWith(autoPrint: v)) : null,
        ),
      ],
    );
  }
}

/// Zasady etykiety lokalu: na co drukujemy (każde danie albo zamówienie), rodzaje zamówień i działy menu.
class _RulesSection extends StatelessWidget {
  const _RulesSection({required this.template, required this.menu, required this.editable, required this.onChanged});

  final LabelTemplate template;
  final List<MenuSection> menu;
  final bool editable;
  final ValueChanged<LabelTemplate> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = template;
    final text = Theme.of(context).textTheme;
    void toggleKind(OrderKind k, bool on) =>
        onChanged(t.copyWith(kinds: on ? {...t.kinds, k} : ({...t.kinds}..remove(k))));
    void toggleSection(String id, bool on) =>
        onChanged(t.copyWith(sections: on ? [...t.sections, id] : [for (final s in t.sections) if (s != id) s]));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _GroupTitle('Etykieta', subtitle: 'wspólna dla lokalu'),
        const _Caption('Jedna etykieta na'),
        IgnorePointer(
          ignoring: !editable,
          child: SegmentedTabs<LabelPer>(
            options: [for (final p in LabelPer.values) (p, p.label)],
            selected: t.per,
            expand: true,
            onChanged: (p) => onChanged(t.copyWith(per: p)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 10),
          child: Text(
            t.per == LabelPer.item
                ? 'Każda sztuka dania dostaje swoją etykietę, np. 3 pizze = 3 etykiety (1/3, 2/3, 3/3).'
                : 'Jedna etykieta na torbę, z listą dań w polu „Wszystkie dania”.',
            style: text.bodySmall?.copyWith(color: AppColors.textMuted),
          ),
        ),
        const _Caption('Zamówienia'),
        _CheckRow(
          label: 'Dostawa',
          value: t.kinds.contains(OrderKind.delivery),
          onChanged: editable ? (v) => toggleKind(OrderKind.delivery, v) : null,
        ),
        _CheckRow(
          label: 'Odbiór osobisty',
          value: t.kinds.contains(OrderKind.pickup),
          onChanged: editable ? (v) => toggleKind(OrderKind.pickup, v) : null,
        ),
        if (t.per == LabelPer.item && menu.isNotEmpty) ...[
          const SizedBox(height: 10),
          const _Caption('Działy menu z etykietą'),
          for (final s in menu)
            _CheckRow(
              label: '${s.name} (${s.items.length})',
              value: t.sections.contains(s.id),
              onChanged: editable ? (v) => toggleSection(s.id, v) : null,
            ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              t.sections.isEmpty
                  ? 'Nic nie zaznaczone: etykietę dostaje każde danie, które robi kuchnia (bez napojów).'
                  : 'Etykiety tylko dla dań z zaznaczonych działów.',
              style: text.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
          ),
        ],
        if (!editable)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'Wygląd etykiety zmienia osoba z uprawnieniem do ustawień lokalu.',
              style: text.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
          ),
      ],
    );
  }
}

/// Etykieta w edytorze: białe tło jak papier, elementy z wartościami przykładowego zamówienia. Element przesuwa
/// się przeciąganiem, zaznaczony ma uchwyty do zmiany rozmiaru (co 0,5 mm, z Alt co 0,1 mm).
class _LabelCanvas extends StatefulWidget {
  const _LabelCanvas({
    required this.template,
    required this.values,
    required this.logo,
    required this.selectedId,
    required this.editable,
    required this.onSelect,
    required this.onMoveStart,
    required this.onMove,
  });

  final LabelTemplate template;
  final Map<String, String> values;
  final ui.Image? logo;
  final String? selectedId;
  final bool editable;
  final ValueChanged<String?> onSelect;
  final VoidCallback onMoveStart;
  final ValueChanged<LabelElement> onMove;

  @override
  State<_LabelCanvas> createState() => _LabelCanvasState();
}

/// Uchwyt zmiany rozmiaru: które krawędzie przesuwa (-1 lewa/górna, 1 prawa/dolna, 0 bez zmiany).
typedef _Handle = ({int h, int v});

class _LabelCanvasState extends State<_LabelCanvas> {
  LabelElement? _start;
  Offset _origin = Offset.zero;

  double _snap(double v) {
    if (HardwareKeyboard.instance.isAltPressed) return roundMm(v);
    return (v * 2).roundToDouble() / 2;
  }

  void _begin(LabelElement e, Offset global) {
    _start = e;
    _origin = global;
    widget.onSelect(e.id);
    widget.onMoveStart();
  }

  void _drag(Offset global, double scale, _Handle? handle) {
    final s = _start;
    if (s == null) return;
    final d = (global - _origin) / scale;
    final t = widget.template;
    final minSize = s.type == LabelElementType.line ? 0.2 : 1.0;
    if (handle == null) {
      widget.onMove(
        s.copyWith(
          x: _snap(s.x + d.dx).clamp(0, math.max(0, t.widthMm - s.w)).toDouble(),
          y: _snap(s.y + d.dy).clamp(0, math.max(0, t.heightMm - s.h)).toDouble(),
        ),
      );
      return;
    }
    var x = s.x;
    var y = s.y;
    var w = s.w;
    var h = s.h;
    if (handle.h == -1) {
      x = _snap(s.x + d.dx).clamp(0, s.x + s.w - minSize).toDouble();
      w = s.x + s.w - x;
    } else if (handle.h == 1) {
      w = _snap(s.w + d.dx).clamp(minSize, t.widthMm - s.x).toDouble();
    }
    if (handle.v == -1) {
      y = _snap(s.y + d.dy).clamp(0, s.y + s.h - minSize).toDouble();
      h = s.y + s.h - y;
    } else if (handle.v == 1) {
      h = _snap(s.h + d.dy).clamp(minSize, t.heightMm - s.y).toDouble();
    }
    widget.onMove(s.copyWith(x: x, y: y, w: w, h: h));
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.template;
    return LayoutBuilder(
      builder: (context, box) {
        const pad = 40.0;
        final scale = math.min(
          math.min((box.maxWidth - pad * 2) / t.widthMm, (box.maxHeight - pad * 2) / t.heightMm),
          9.0,
        ).clamp(1.0, 9.0);
        final size = Size(t.widthMm * scale, t.heightMm * scale);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => widget.onSelect(null),
          child: Center(
            child: SizedBox.fromSize(
              size: size,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 18, offset: Offset(0, 6))],
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: CustomPaint(
                          painter: _LabelPainter(template: t, values: widget.values, logo: widget.logo, scale: scale),
                        ),
                      ),
                    ),
                  ),
                  for (final e in t.elements) ..._element(e, scale),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _element(LabelElement e, double scale) {
    final selected = e.id == widget.selectedId;
    final rect = Rect.fromLTWH(e.x * scale, e.y * scale, e.w * scale, e.h * scale);
    // Cienką linię łatwo złapać: pole kliknięcia co najmniej 10 px.
    final hit = Rect.fromCenter(
      center: rect.center,
      width: math.max(rect.width, 10),
      height: math.max(rect.height, 10),
    );
    final widgets = <Widget>[
      Positioned.fromRect(
        rect: hit,
        child: MouseRegion(
          cursor: widget.editable ? SystemMouseCursors.move : SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => widget.onSelect(e.id),
            onPanStart: widget.editable ? (d) => _begin(e, d.globalPosition) : null,
            onPanUpdate: widget.editable ? (d) => _drag(d.globalPosition, scale, null) : null,
            onPanEnd: widget.editable ? (_) => _start = null : null,
            child: Center(
              child: Container(
                width: rect.width,
                height: rect.height,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: selected ? AppColors.accentFill : const Color(0x26000000),
                    width: selected ? 1.5 : 1,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ];
    if (selected && widget.editable) {
      const handles = <_Handle>[
        (h: -1, v: -1),
        (h: 0, v: -1),
        (h: 1, v: -1),
        (h: -1, v: 0),
        (h: 1, v: 0),
        (h: -1, v: 1),
        (h: 0, v: 1),
        (h: 1, v: 1),
      ];
      // Linia ma uchwyty tylko na końcach.
      final line = e.type == LabelElementType.line;
      final horizontal = e.w >= e.h;
      for (final handle in handles) {
        if (line && (horizontal ? handle.v != 0 || handle.h == 0 : handle.h != 0 || handle.v == 0)) continue;
        final at = Offset(
          rect.left + rect.width * (handle.h + 1) / 2,
          rect.top + rect.height * (handle.v + 1) / 2,
        );
        final cursor = switch (handle) {
          (h: 0, v: _) => SystemMouseCursors.resizeUpDown,
          (h: _, v: 0) => SystemMouseCursors.resizeLeftRight,
          (h: -1, v: -1) || (h: 1, v: 1) => SystemMouseCursors.resizeUpLeftDownRight,
          _ => SystemMouseCursors.resizeUpRightDownLeft,
        };
        widgets.add(
          Positioned(
            left: at.dx - 6,
            top: at.dy - 6,
            width: 12,
            height: 12,
            child: MouseRegion(
              cursor: cursor,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (d) => _begin(e, d.globalPosition),
                onPanUpdate: (d) => _drag(d.globalPosition, scale, handle),
                onPanEnd: (_) => _start = null,
                child: Center(
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: AppColors.accentFill, width: 1.5),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }
    }
    return widgets;
  }
}

class _LabelPainter extends CustomPainter {
  _LabelPainter({required this.template, required this.values, required this.logo, required this.scale});

  final LabelTemplate template;
  final Map<String, String> values;
  final ui.Image? logo;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) => paintLabel(canvas, template, values, scale: scale, logo: logo);

  @override
  bool shouldRepaint(_LabelPainter old) =>
      old.template != template || old.values != values || old.logo != logo || old.scale != scale;
}

/// Podgląd wydruku: etykieta zamieniona na punkty drukarki (to, co naprawdę pójdzie na papier).
class _RasterPreview extends StatefulWidget {
  const _RasterPreview({required this.template, required this.values, required this.logo});

  final LabelTemplate template;
  final Map<String, String> values;
  final ui.Image? logo;

  @override
  State<_RasterPreview> createState() => _RasterPreviewState();
}

class _RasterPreviewState extends State<_RasterPreview> {
  ui.Image? _image;
  int _version = 0;

  @override
  void initState() {
    super.initState();
    _render();
  }

  @override
  void didUpdateWidget(_RasterPreview old) {
    super.didUpdateWidget(old);
    if (old.template.signature != widget.template.signature || old.values != widget.values || old.logo != widget.logo) {
      _render();
    }
  }

  Future<void> _render() async {
    final version = ++_version;
    final raster = await rasterizeLabel(widget.template, widget.values, logo: widget.logo);
    final image = await labelRasterImage(raster);
    if (!mounted || version != _version) {
      image.dispose();
      return;
    }
    setState(() {
      _image?.dispose();
      _image = image;
    });
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) return const LoadingView();
    final t = widget.template;
    return LayoutBuilder(
      builder: (context, box) {
        const pad = 40.0;
        final scale = math.min(
          math.min((box.maxWidth - pad * 2) / t.widthMm, (box.maxHeight - pad * 2) / t.heightMm),
          9.0,
        ).clamp(1.0, 9.0);
        return Center(
          child: Container(
            width: t.widthMm * scale,
            height: t.heightMm * scale,
            decoration: const BoxDecoration(
              boxShadow: [BoxShadow(color: Color(0x40000000), blurRadius: 18, offset: Offset(0, 6))],
            ),
            child: RawImage(image: image, fit: BoxFit.fill, filterQuality: FilterQuality.none),
          ),
        );
      },
    );
  }
}

/// Liczba w milimetrach (albo punktach), zatwierdzana Enterem albo wyjściem z pola.
class _NumField extends StatefulWidget {
  const _NumField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.suffix = 'mm',
    this.min = 0,
    this.max = 500,
    this.enabled = true,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final String suffix;
  final double min;
  final double max;
  final bool enabled;

  @override
  State<_NumField> createState() => _NumFieldState();
}

class _NumFieldState extends State<_NumField> {
  late final _controller = TextEditingController(text: _mm(widget.value));
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(_NumField old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && old.value != widget.value) _controller.text = _mm(widget.value);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit() {
    final v = _parseMm(_controller.text);
    if (v == null) {
      _controller.text = _mm(widget.value);
      return;
    }
    final clamped = v.clamp(widget.min, widget.max).toDouble();
    _controller.text = _mm(clamped);
    if (clamped != widget.value) widget.onChanged(clamped);
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focus,
      enabled: widget.enabled,
      style: const TextStyle(fontFeatures: _tabular),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')), LengthLimitingTextInputFormatter(6)],
      decoration: InputDecoration(labelText: widget.label, suffixText: widget.suffix, isDense: true),
      onSubmitted: (_) => _commit(),
    );
  }
}

/// Bez zaznaczonego elementu: rozmiar etykiety (z gotowymi rozmiarami) i lista elementów.
class _TemplateInspector extends StatelessWidget {
  const _TemplateInspector({
    required this.template,
    required this.editable,
    required this.onChanged,
    required this.onSelect,
  });

  final LabelTemplate template;
  final bool editable;
  final ValueChanged<LabelTemplate> onChanged;
  final ValueChanged<String> onSelect;

  static const _presets = [(100, 50), (100, 100), (100, 150), (60, 40), (58, 40), (50, 30)];

  @override
  Widget build(BuildContext context) {
    final t = template;
    final text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Rozmiar etykiety', style: text.titleSmall),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _NumField(
                label: 'Szerokość',
                value: t.widthMm.toDouble(),
                min: LabelTemplate.minWidth.toDouble(),
                max: LabelTemplate.maxWidth.toDouble(),
                enabled: editable,
                onChanged: (v) => onChanged(t.copyWith(widthMm: v.round())),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _NumField(
                label: 'Wysokość',
                value: t.heightMm.toDouble(),
                min: LabelTemplate.minHeight.toDouble(),
                max: LabelTemplate.maxHeight.toDouble(),
                enabled: editable,
                onChanged: (v) => onChanged(t.copyWith(heightMm: v.round())),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final (w, h) in _presets)
              ChoiceChip(
                label: Text('$w × $h', style: const TextStyle(fontFeatures: _tabular)),
                selected: t.widthMm == w && t.heightMm == h,
                onSelected: editable ? (_) => onChanged(t.copyWith(widthMm: w, heightMm: h)) : null,
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Taki jak etykiety w drukarce. Elementy nie zmieniają rozmiaru razem z etykietą.',
            style: text.bodySmall?.copyWith(color: AppColors.textMuted),
          ),
        ),
        const SizedBox(height: 20),
        Text('Elementy', style: text.titleSmall),
        const SizedBox(height: 6),
        if (t.elements.isEmpty)
          Text('Pusta etykieta. Dodaj tekst, linię albo kod QR przyciskami nad etykietą.', style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
        for (final e in t.elements.reversed)
          InkWell(
            onTap: () => onSelect(e.id),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
              child: Row(
                children: [
                  Glyph(e.type.icon, size: 16, color: AppColors.textMuted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      e.type == LabelElementType.text || e.type == LabelElementType.qr
                          ? (e.text.trim().isEmpty ? e.type.label : e.text.replaceAll('\n', ' '))
                          : e.type.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Właściwości zaznaczonego elementu: treść z polami, czcionka, wyrównanie, położenie i rozmiar.
class _ElementInspector extends StatefulWidget {
  const _ElementInspector({
    super.key,
    required this.element,
    required this.template,
    required this.editable,
    required this.onChanged,
    required this.onDelete,
    required this.onDuplicate,
    required this.onClose,
  });

  final LabelElement element;
  final LabelTemplate template;
  final bool editable;
  final ValueChanged<LabelElement> onChanged;
  final VoidCallback onDelete;
  final VoidCallback onDuplicate;
  final VoidCallback onClose;

  @override
  State<_ElementInspector> createState() => _ElementInspectorState();
}

class _ElementInspectorState extends State<_ElementInspector> {
  late final _text = TextEditingController(text: widget.element.text);
  Timer? _debounce;

  @override
  void didUpdateWidget(_ElementInspector old) {
    super.didUpdateWidget(old);
    // Cofnięcie zmienia tekst z zewnątrz.
    if (widget.element.text != _text.text && _debounce?.isActive != true) _text.text = widget.element.text;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _text.dispose();
    super.dispose();
  }

  void _textChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () => widget.onChanged(widget.element.copyWith(text: value)));
  }

  void _insert(String key) {
    final token = '{$key}';
    final sel = _text.selection;
    final value = _text.text;
    final start = sel.isValid ? sel.start : value.length;
    final end = sel.isValid ? sel.end : value.length;
    final next = value.replaceRange(start, end, token);
    _text.value = TextEditingValue(text: next, selection: TextSelection.collapsed(offset: start + token.length));
    _debounce?.cancel();
    widget.onChanged(widget.element.copyWith(text: next));
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.element;
    final t = widget.template;
    final text = Theme.of(context).textTheme;
    final on = widget.editable;
    final hasText = e.type == LabelElementType.text || e.type == LabelElementType.qr;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Glyph(e.type.icon, size: 18, color: AppColors.textMuted),
            const SizedBox(width: 10),
            Expanded(child: Text(e.type.label, style: text.titleSmall)),
            if (on) ...[
              IconButton(tooltip: 'Duplikuj (Ctrl+D)', onPressed: widget.onDuplicate, icon: const Glyph(AppIcons.copy, size: 16)),
              DeleteButton(onPressed: widget.onDelete),
            ],
            IconButton(tooltip: 'Zamknij (Esc)', onPressed: widget.onClose, icon: const Glyph(AppIcons.close, size: 16)),
          ],
        ),
        const SizedBox(height: 12),
        if (hasText) ...[
          TextField(
            controller: _text,
            enabled: on,
            minLines: e.type == LabelElementType.text ? 2 : 1,
            maxLines: 5,
            decoration: InputDecoration(
              labelText: e.type == LabelElementType.qr ? 'Treść kodu' : 'Tekst',
              helperText: 'Pola w klamrach wstawi zamówienie, np. #{numer}.',
              helperMaxLines: 2,
            ),
            onChanged: _textChanged,
          ),
          const SizedBox(height: 10),
          Text('Wstaw pole', style: text.labelMedium?.copyWith(color: AppColors.textMuted)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final f in labelFields)
                if (t.per == LabelPer.item || (f.key != 'danie' && f.key != 'dodatki' && f.key != 'sztuka'))
                  ActionChip(
                    label: Text(f.label),
                    tooltip: '{${f.key}}',
                    onPressed: on ? () => _insert(f.key) : null,
                  ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        if (e.type == LabelElementType.text) ...[
          Row(
            children: [
              Expanded(
                child: _NumField(
                  label: 'Czcionka',
                  suffix: 'pt',
                  value: e.size,
                  min: 4,
                  max: 120,
                  enabled: on,
                  onChanged: (v) => widget.onChanged(e.copyWith(size: v)),
                ),
              ),
              const SizedBox(width: 8),
              _ToggleIcon(
                icon: AppIcons.textBold,
                tooltip: 'Pogrubienie',
                selected: e.bold,
                onTap: on ? () => widget.onChanged(e.copyWith(bold: !e.bold)) : null,
              ),
              for (final a in LabelAlign.values)
                _ToggleIcon(
                  icon: a.icon,
                  tooltip: a.label,
                  selected: e.align == a,
                  onTap: on ? () => widget.onChanged(e.copyWith(align: a)) : null,
                ),
            ],
          ),
          const SizedBox(height: 10),
          _SwitchRow(
            title: 'Biały napis na czarnym',
            value: e.invert,
            onChanged: on ? (v) => widget.onChanged(e.copyWith(invert: v)) : null,
          ),
          _SwitchRow(
            title: 'Zmniejsz, gdy się nie mieści',
            description: 'Długie nazwy dań i adresy zmieszczą się w polu.',
            value: e.fit,
            onChanged: on ? (v) => widget.onChanged(e.copyWith(fit: v)) : null,
          ),
        ],
        if (e.type == LabelElementType.box) ...[
          _NumField(
            label: 'Grubość obrysu',
            value: e.stroke,
            min: 0.1,
            max: 5,
            enabled: on && !e.fill,
            onChanged: (v) => widget.onChanged(e.copyWith(stroke: v)),
          ),
          const SizedBox(height: 8),
          _SwitchRow(
            title: 'Wypełniona na czarno',
            description: 'Pod białym napisem albo jako pasek.',
            value: e.fill,
            onChanged: on ? (v) => widget.onChanged(e.copyWith(fill: v)) : null,
          ),
        ],
        if (e.type == LabelElementType.logo)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Logo z „Dane lokalu”, w odcieniach szarości z punktów. Najlepiej wychodzi ciemne logo na przezroczystym tle.',
              style: text.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
          ),
        if (e.type == LabelElementType.line)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Linia pozioma: grubość to wysokość, pionowa: szerokość.',
              style: text.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
          ),
        Text('Położenie i rozmiar', style: text.labelMedium?.copyWith(color: AppColors.textMuted)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _NumField(
                label: 'Od lewej',
                value: e.x,
                max: t.widthMm.toDouble(),
                enabled: on,
                onChanged: (v) => widget.onChanged(e.copyWith(x: v)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _NumField(
                label: 'Od góry',
                value: e.y,
                max: t.heightMm.toDouble(),
                enabled: on,
                onChanged: (v) => widget.onChanged(e.copyWith(y: v)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _NumField(
                label: 'Szerokość',
                value: e.w,
                min: 0.2,
                max: t.widthMm.toDouble(),
                enabled: on,
                onChanged: (v) => widget.onChanged(e.copyWith(w: v)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _NumField(
                label: 'Wysokość',
                value: e.h,
                min: 0.2,
                max: t.heightMm.toDouble(),
                enabled: on,
                onChanged: (v) => widget.onChanged(e.copyWith(h: v)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Przycisk z ikoną, który zostaje wciśnięty (pogrubienie, wyrównanie).
class _ToggleIcon extends StatelessWidget {
  const _ToggleIcon({required this.icon, required this.tooltip, required this.selected, required this.onTap});

  final AppIconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 34,
          height: PanelTheme.controlHeight,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.accentTint : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Glyph(icon, size: 18, color: selected ? AppColors.accent : AppColors.textMuted),
        ),
      ),
    );
  }
}
