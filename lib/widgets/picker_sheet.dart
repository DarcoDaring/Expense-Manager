import 'package:flutter/material.dart';

import 'app_icon.dart';

/// One choice in [showPickerSheet]. [icon] is an index into the app's icon set.
class PickerItem {
  final int id;
  final String name;
  final int icon;
  final String? subtitle;

  /// Recolours plain icons (brand badges keep their own colours).
  final Color? color;
  const PickerItem(this.id, this.name, this.icon, {this.subtitle, this.color});
}

/// Bottom sheet with a grid/list toggle, an edit (manage) button and close.
/// Resolves to the chosen id, or null if dismissed. [onEdit] runs after the
/// sheet closes when the pencil is tapped.
Future<int?> showPickerSheet(
  BuildContext context, {
  required String title,
  required List<PickerItem> items,
  required int? selectedId,
  required VoidCallback onEdit,
}) async {
  var edit = false;
  final picked = await showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _PickerSheet(
      title: title,
      items: items,
      selectedId: selectedId,
      onEdit: () => edit = true,
    ),
  );
  if (edit && context.mounted) onEdit();
  return picked;
}

class _PickerSheet extends StatefulWidget {
  final String title;
  final List<PickerItem> items;
  final int? selectedId;
  final VoidCallback onEdit;
  const _PickerSheet(
      {required this.title, required this.items, required this.selectedId, required this.onEdit});

  @override
  State<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<_PickerSheet> {
  bool _grid = true;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(widget.title,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              ),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Row(
                  children: [
                    _toggle(Icons.grid_view_rounded, _grid, () => setState(() => _grid = true)),
                    _toggle(Icons.view_list_rounded, !_grid, () => setState(() => _grid = false)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'Edit',
                onPressed: () {
                  widget.onEdit();
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.edit_rounded),
              ),
              const SizedBox(width: 4),
              IconButton.filledTonal(
                tooltip: 'Close',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Flexible(
            child: widget.items.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Text('Nothing here yet. Tap the pencil to add some.',
                          style: TextStyle(color: cs.onSurfaceVariant)),
                    ),
                  )
                : _grid
                    ? GridView.count(
                        shrinkWrap: true,
                        crossAxisCount: 4,
                        mainAxisSpacing: 8,
                        childAspectRatio: .72,
                        children: [for (final it in widget.items) _gridCell(cs, it)],
                      )
                    : ListView(
                        shrinkWrap: true,
                        children: [for (final it in widget.items) _listRow(cs, it)],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _toggle(IconData icon, bool on, VoidCallback tap) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: tap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 42,
        height: 36,
        decoration: BoxDecoration(
          color: on ? cs.surfaceContainerHighest : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Icon(icon, size: 20, color: on ? cs.onSurface : cs.onSurfaceVariant),
      ),
    );
  }

  Widget _gridCell(ColorScheme cs, PickerItem it) {
    final selected = it.id == widget.selectedId;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.pop(context, it.id),
      child: Column(
        children: [
          Container(
            width: 66,
            height: 66,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? cs.onSurface.withValues(alpha: .14) : Colors.transparent,
              border: selected ? Border.all(color: cs.onSurface.withValues(alpha: .6), width: 2) : null,
            ),
            child: AppIcon(it.icon, size: 36, color: it.color),
          ),
          const SizedBox(height: 6),
          Text(it.name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
          if (it.subtitle != null)
            Text(it.subtitle!,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _listRow(ColorScheme cs, PickerItem it) {
    final selected = it.id == widget.selectedId;
    return ListTile(
      onTap: () => Navigator.pop(context, it.id),
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: IconTile(it.icon, size: 44, color: it.color),
      title: Text(it.name,
          style: TextStyle(fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
      subtitle: it.subtitle == null ? null : Text(it.subtitle!),
      trailing: selected ? Icon(Icons.check_circle_rounded, color: cs.primary) : null,
    );
  }
}
