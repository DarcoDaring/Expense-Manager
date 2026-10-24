import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';

/// Bottom-bar tab: free-form notes, pinned ones first.
class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  String _query = '';

  void _open(BuildContext context, [Note? note]) => Navigator.push(
      context, MaterialPageRoute(builder: (_) => NoteEditScreen(existing: note)));

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final q = _query.trim().toLowerCase();
    final notes = s.notes
        .where((n) =>
            q.isEmpty || n.title.toLowerCase().contains(q) || n.body.toLowerCase().contains(q))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notes'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: IconButton.filledTonal(
              tooltip: 'New note',
              onPressed: () => _open(context),
              icon: const Icon(Icons.add_rounded),
            ),
          ),
        ],
      ),
      body: s.notes.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 100),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.sticky_note_2_rounded, size: 64, color: cs.outline),
                    const SizedBox(height: 12),
                    const Text('No notes yet',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Text('Keep loan details, account numbers, reminders or anything else here.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: cs.onSurfaceVariant)),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(minimumSize: const Size(200, 52)),
                      onPressed: () => _open(context),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('New note'),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 130),
              children: [
                TextField(
                  onChanged: (v) => setState(() => _query = v),
                  decoration: const InputDecoration(
                    hintText: 'Search notes',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                ),
                const SizedBox(height: 14),
                if (notes.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 40),
                    child: Center(
                        child: Text('No matching notes',
                            style: TextStyle(color: cs.onSurfaceVariant))),
                  ),
                for (final n in notes) ...[
                  _tile(context, n),
                  const SizedBox(height: 10),
                ],
              ],
            ),
    );
  }

  Widget _tile(BuildContext context, Note n) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _open(context, n),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(n.title.isEmpty ? 'Untitled' : n.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700)),
                  ),
                  if (n.pinned)
                    Icon(Icons.push_pin_rounded, size: 18, color: cs.primary),
                ],
              ),
              if (n.body.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(n.body,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: cs.onSurfaceVariant, height: 1.35)),
              ],
              const SizedBox(height: 10),
              Text(DateFormat('d MMM y · h:mm a').format(n.updated),
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Write or edit a note. It is saved automatically when you leave the page;
/// a note left completely empty is not kept.
class NoteEditScreen extends StatefulWidget {
  final Note? existing;
  const NoteEditScreen({super.key, this.existing});

  @override
  State<NoteEditScreen> createState() => _NoteEditScreenState();
}

class _NoteEditScreenState extends State<NoteEditScreen> {
  late final _title = TextEditingController(text: widget.existing?.title ?? '');
  late final _body = TextEditingController(text: widget.existing?.body ?? '');
  late bool _pinned = widget.existing?.pinned ?? false;
  bool _deleted = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_deleted) return;
    final s = context.read<AppState>();
    final old = widget.existing;
    final title = _title.text.trim();
    final body = _body.text.trim();
    if (title.isEmpty && body.isEmpty) {
      if (old != null) await s.deleteNote(old.id!);
      return;
    }
    final unchanged =
        old != null && old.title == title && old.body == body && old.pinned == _pinned;
    if (unchanged) return;
    await s.saveNote(Note(
        id: old?.id, title: title, body: body, pinned: _pinned, updated: DateTime.now()));
  }

  Future<void> _delete() async {
    final old = widget.existing;
    final ok = old == null
        ? true
        : await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Delete this note?'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel')),
                TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Delete')),
              ],
            ),
          );
    if (ok != true || !mounted) return;
    _deleted = true;
    final nav = Navigator.of(context);
    if (old != null) await context.read<AppState>().deleteNote(old.id!);
    nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _save();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.existing == null ? 'New note' : 'Edit note'),
          actions: [
            IconButton(
              tooltip: _pinned ? 'Unpin' : 'Pin to top',
              onPressed: () => setState(() => _pinned = !_pinned),
              icon: Icon(_pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                  color: _pinned ? cs.primary : null),
            ),
            IconButton(
              tooltip: 'Delete',
              onPressed: _delete,
              icon: Icon(Icons.delete_outline_rounded, color: cs.error),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            children: [
              TextField(
                controller: _title,
                autofocus: widget.existing == null,
                maxLength: 80,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                decoration: const InputDecoration(hintText: 'Title', counterText: ''),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: TextField(
                  controller: _body,
                  expands: true,
                  maxLines: null,
                  minLines: null,
                  textAlignVertical: TextAlignVertical.top,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(hintText: 'Write your note…'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
