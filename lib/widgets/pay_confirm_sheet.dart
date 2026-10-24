import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import 'account_picker.dart';

/// Account types an EMI may be paid from.
const kEmiAccountTypes = {AccountType.bank, AccountType.credit};

/// Asks which account / payment mode a due [r] is being paid from, starting
/// with its default. Returns the chosen payment mode id, or null if cancelled.
Future<int?> showPayConfirm(BuildContext context, Recurring r) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _PayConfirm(r: r),
  );
}

class _PayConfirm extends StatefulWidget {
  final Recurring r;
  const _PayConfirm({required this.r});

  @override
  State<_PayConfirm> createState() => _PayConfirmState();
}

class _PayConfirmState extends State<_PayConfirm> {
  int? _modeId;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>();
    final allowed = widget.r.isEmi ? kEmiAccountTypes : null;
    _modeId = AccountPicker.isAllowed(s, widget.r.paymentModeId, allowed)
        ? widget.r.paymentModeId
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final r = widget.r;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Confirm payment',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
              '${s.recurringTitle(r)} · ${s.money(r.amount)}'
              '${r.isEmi && r.totalCount > 0 ? ' · instalment ${r.paidCount + 1}/${r.totalCount}' : ''}',
              style: TextStyle(color: cs.onSurfaceVariant)),
          const SizedBox(height: 20),
          AccountPicker(
            modeId: _modeId,
            allowed: r.isEmi ? kEmiAccountTypes : null,
            onChanged: (id) => setState(() => _modeId = id),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _modeId == null ? null : () => Navigator.pop(context, _modeId),
            icon: const Icon(Icons.check_rounded),
            label: const Text('Confirm paid'),
          ),
        ],
      ),
    );
  }
}
