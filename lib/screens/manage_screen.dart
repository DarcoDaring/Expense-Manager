import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../widgets/edit_dialogs.dart';

/// Manage the user's categories or payment modes.
class ManageScreen extends StatelessWidget {
  final bool categories;

  /// Shown as a bottom-bar tab: no back arrow, and the add button lives in the app bar.
  final bool embedded;
  const ManageScreen({super.key, required this.categories, this.embedded = false});

  Future<void> _confirmDelete(
      BuildContext context, String name, int used, Future<void> Function() delete) async {
    if (used > 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('“$name” is used by $used ${used == 1 ? 'expense' : 'expenses'}. '
              'Re-assign or delete those first.')));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Delete “$name”?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) await delete();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final title = categories ? 'Categories' : 'Payment modes';
    void add() => categories ? showCategoryDialog(context) : showPaymentModeDialog(context);

    final items = categories
        ? [
            for (final c in s.categories)
              (
                name: c.name,
                icon: iconAt(c.icon),
                color: Color(c.color),
                used: s.categoryUsage(c.id!),
                edit: () => showCategoryDialog(context, existing: c),
                delete: () => s.deleteCategory(c.id!),
              )
          ]
        : [
            for (final m in s.paymentModes)
              (
                name: m.name,
                icon: iconAt(m.icon),
                color: cs.primary,
                used: s.paymentModeUsage(m.id!),
                edit: () => showPaymentModeDialog(context, existing: m),
                delete: () => s.deletePaymentMode(m.id!),
              )
          ];

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        automaticallyImplyLeading: !embedded,
        actions: embedded
            ? [
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: IconButton.filledTonal(
                    tooltip: 'Add',
                    onPressed: add,
                    icon: const Icon(Icons.add_rounded),
                  ),
                ),
              ]
            : null,
      ),
      floatingActionButton: embedded
          ? null
          : FloatingActionButton.extended(
              onPressed: add,
              icon: const Icon(Icons.add_rounded),
              label: Text(categories ? 'New category' : 'New payment mode'),
            ),
      body: items.isEmpty
          ? Center(
              child: Text('Nothing here yet', style: TextStyle(color: cs.onSurfaceVariant)))
          : ListView(
              padding: EdgeInsets.fromLTRB(20, 4, 20, embedded ? 130 : 100),
              children: [
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (final it in items)
                        ListTile(
                          onTap: it.edit,
                          leading: CircleAvatar(
                            backgroundColor: it.color.withValues(alpha: .15),
                            child: Icon(it.icon, color: it.color, size: 22),
                          ),
                          title: Text(it.name,
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(
                              '${it.used} ${it.used == 1 ? 'expense' : 'expenses'}'),
                          trailing: IconButton(
                            icon: Icon(Icons.delete_outline_rounded, color: cs.error),
                            onPressed: () =>
                                _confirmDelete(context, it.name, it.used, it.delete),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
