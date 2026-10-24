import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import 'app_icon.dart';

/// Add or edit a category. Returns its id, or null if cancelled.
Future<int?> showCategoryDialog(BuildContext context,
    {Category? existing, bool income = false}) {
  return showDialog<int>(
    context: context,
    builder: (_) => _EditDialog(
      title: existing == null
          ? (income ? 'New income category' : 'New category')
          : 'Edit category',
      initialName: existing?.name ?? '',
      initialIcon: existing?.icon ?? 15,
      initialColor: existing?.color ?? kPalette.first.toARGB32(),
      withColor: true,
      onSave: (name, icon, color) => context
          .read<AppState>()
          .saveCategory(Category(
              id: existing?.id,
              name: name,
              icon: icon,
              color: color,
              kind: existing?.kind ?? (income ? 1 : 0))),
    ),
  );
}

/// Add or edit a payment mode. Returns its id, or null if cancelled.
Future<int?> showPaymentModeDialog(BuildContext context, {PaymentMode? existing}) {
  return showDialog<int>(
    context: context,
    builder: (_) => _EditDialog(
      title: existing == null ? 'New payment mode' : 'Edit payment mode',
      initialName: existing?.name ?? '',
      initialIcon: existing?.icon ?? 16,
      initialColor: 0,
      withColor: false,
      onSave: (name, icon, _) => context
          .read<AppState>()
          .savePaymentMode(PaymentMode(
          id: existing?.id, name: name, icon: icon, accountId: existing?.accountId)),
    ),
  );
}

class _EditDialog extends StatefulWidget {
  final String title;
  final String initialName;
  final int initialIcon;
  final int initialColor;
  final bool withColor;
  final Future<int?> Function(String name, int icon, int color) onSave;

  const _EditDialog({
    required this.title,
    required this.initialName,
    required this.initialIcon,
    required this.initialColor,
    required this.withColor,
    required this.onSave,
  });

  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  late final _name = TextEditingController(text: widget.initialName);
  late int _icon = widget.initialIcon;
  late int _color = widget.initialColor;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Name is required');
      return;
    }
    final id = await widget.onSave(name, _icon, _color);
    if (!mounted) return;
    if (id == null) {
      setState(() => _error = 'That name already exists');
    } else {
      Navigator.pop(context, id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = widget.withColor ? Color(_color) : cs.primary;
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              maxLength: 24,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: 'Name', errorText: _error),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 8),
            IconField(
              index: _icon,
              color: widget.withColor ? accent : null,
              onPick: (i) => setState(() {
                _icon = i;
                // A category takes the icon's own colour; it can still be changed below.
                if (widget.withColor) _color = iconSpec(i).color.toARGB32();
              }),
            ),
            if (widget.withColor) ...[
              const SizedBox(height: 16),
              const Text('Colour', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final c in kPalette)
                    GestureDetector(
                      onTap: () => setState(() => _color = c.toARGB32()),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                        child: _color == c.toARGB32()
                            ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
                            : null,
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(88, 44)),
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
