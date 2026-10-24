import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../screens/accounts_screen.dart';
import '../state/app_state.dart';
import 'picker_sheet.dart';

/// Choose where money comes from using the same sheet as categories: first the
/// account and then, when the account has several payment modes, the mode.
/// Resolves to a payment mode id, or null if the user backed out.
Future<int?> pickAccountMode(
  BuildContext context, {
  required int? modeId,
  String title = 'Select Account',
  Set<AccountType>? allowed,
}) async {
  final s = context.read<AppState>();
  void manage() => Navigator.push(
      context, MaterialPageRoute(builder: (_) => const AccountsScreen()));

  // Modes that belong to no account (older data) are offered directly, with
  // a negative id so they cannot clash with an account id.
  final unlinked =
      allowed == null ? s.paymentModes.where((m) => m.accountId == null).toList() : <PaymentMode>[];
  final current = modeId == null ? null : s.accountOfMode(modeId);

  final items = <PickerItem>[
    for (final a in s.accounts)
      if (s.modesOf(a.id!).isNotEmpty && (allowed?.contains(a.type) ?? true))
        PickerItem(a.id!, a.name, s.modesOf(a.id!).first.icon, subtitle: a.type.label),
    for (final m in unlinked) PickerItem(-m.id!, m.name, m.icon),
  ];

  final pickedId = await showPickerSheet(
    context,
    title: title,
    selectedId: current?.id ?? (modeId == null ? null : -modeId),
    items: items,
    onEdit: manage,
  );
  if (pickedId == null) return null;
  if (pickedId < 0) return -pickedId;

  final modes = s.modesOf(pickedId);
  if (modes.length == 1) return modes.first.id;
  if (!context.mounted) return null;

  // Staying inside the same account keeps the mode that was already chosen.
  return showPickerSheet(
    context,
    title: 'Pay using',
    selectedId: modes.any((m) => m.id == modeId) ? modeId : null,
    items: [for (final m in modes) PickerItem(m.id!, m.name, m.icon)],
    onEdit: manage,
  );
}
