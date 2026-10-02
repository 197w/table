import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../data/models.dart';
import 'panel_widgets.dart';

/// Notatki przy kliencie albo pojeździe: pole na nową (Enter dodaje, Shift+Enter nowa linia)
/// i lista od najnowszej z autorem i datą. Widzą je tylko pracownicy lokalu.
class NotesView extends StatefulWidget {
  const NotesView({
    super.key,
    required this.notes,
    required this.onAdd,
    required this.onDelete,
    this.hint = 'Nowa notatka',
    this.scrollable = true,
  });

  final AsyncValue<List<Note>> notes;
  final Future<void> Function(String body) onAdd;
  final Future<void> Function(Note note) onDelete;
  final String hint;

  /// Lista przewija się sama (w wysokim miejscu). False: rośnie razem z treścią.
  final bool scrollable;

  @override
  State<NotesView> createState() => _NotesViewState();
}

class _NotesViewState extends State<NotesView> {
  final _body = TextEditingController();
  final _focus = FocusNode();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _focus.onKeyEvent = (node, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.enter &&
          !HardwareKeyboard.instance.isShiftPressed) {
        _add();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };
  }

  @override
  void dispose() {
    _body.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final body = _body.text.trim();
    if (body.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.onAdd(body);
      _body.clear();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(Note note) async {
    final ok = await confirm(context, title: 'Usunąć notatkę?', message: note.body, action: 'Usuń', destructive: true);
    if (!ok || !mounted) return;
    try {
      await widget.onDelete(note);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final field = TextField(
      controller: _body,
      focusNode: _focus,
      minLines: 1,
      maxLines: 4,
      maxLength: 1000,
      enabled: !_busy,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        hintText: widget.hint,
        counterText: '',
        isDense: true,
        suffixIcon: IconButton(
          tooltip: 'Dodaj notatkę',
          onPressed: _busy || _body.text.trim().isEmpty ? null : _add,
          icon: Glyph(
            AppIcons.send,
            size: 18,
            color: _body.text.trim().isEmpty ? AppColors.textMuted : AppColors.accent,
          ),
        ),
      ),
    );

    final list = widget.notes.when(
      skipLoadingOnReload: true,
      loading: () => const Padding(padding: EdgeInsets.all(24), child: LoadingView()),
      error: (e, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(errorText(e), style: text.bodyMedium?.copyWith(color: AppColors.error)),
      ),
      data: (notes) {
        if (notes.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text(
              'Brak notatek',
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
            ),
          );
        }
        final items = [for (final n in notes) _NoteTile(note: n, onDelete: () => _delete(n))];
        return widget.scrollable
            ? ListView.separated(
                padding: const EdgeInsets.only(top: 12),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, i) => items[i],
              )
            : Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, item) in items.indexed) ...[if (i > 0) const SizedBox(height: 8), item],
                  ],
                ),
              );
      },
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: widget.scrollable ? MainAxisSize.max : MainAxisSize.min,
      children: [
        field,
        if (widget.scrollable) Expanded(child: list) else list,
      ],
    );
  }
}

class _NoteTile extends StatefulWidget {
  const _NoteTile({required this.note, required this.onDelete});

  final Note note;
  final VoidCallback onDelete;

  @override
  State<_NoteTile> createState() => _NoteTileState();
}

class _NoteTileState extends State<_NoteTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final n = widget.note;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.ring),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(n.body, style: text.bodyMedium),
                  const SizedBox(height: 4),
                  Text(
                    '${n.author ?? 'Pracownik'} · ${Fmt.dayShort(n.createdAt)}, ${Fmt.time(n.createdAt)}',
                    style: text.bodySmall?.copyWith(
                      color: AppColors.textMuted,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            AnimatedOpacity(
              opacity: _hover ? 1 : 0,
              duration: const Duration(milliseconds: 120),
              child: IconButton(
                tooltip: 'Usuń notatkę',
                visualDensity: VisualDensity.compact,
                onPressed: widget.onDelete,
                icon: Glyph(AppIcons.trash, size: 16, color: AppColors.textMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
