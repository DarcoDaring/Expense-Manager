import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import 'app_icon.dart';

const _accountIcons = {
  AccountType.cash: Icons.payments_rounded,
  AccountType.bank: Icons.account_balance_rounded,
  AccountType.wallet: Icons.account_balance_wallet_rounded,
  AccountType.credit: Icons.credit_card_rounded,
};

/// Pick what an expense is paid from: an account, then (when the account has
/// several) one of its linked payment modes. Reports the payment mode id.
class AccountPicker extends StatelessWidget {
  final int? modeId;
  final ValueChanged<int> onChanged;
  final String? error;

  /// Limits the choice to these account types (and hides unlinked modes).
  final Set<AccountType>? allowed;
  final String label;
  const AccountPicker({
    super.key,
    required this.modeId,
    required this.onChanged,
    this.error,
    this.allowed,
    this.label = 'Account',
  });

  /// Whether [modeId] belongs to an account this picker would offer.
  static bool isAllowed(AppState s, int? modeId, Set<AccountType>? allowed) {
    if (modeId == null) return false;
    if (allowed == null) return s.paymentModes.any((m) => m.id == modeId);
    final a = s.accountOfMode(modeId);
    return a != null && allowed.contains(a.type);
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 10, left: 4),
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      );

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final selected = s.paymentModes.where((m) => m.id == modeId).firstOrNull;
    // Modes without an account (older data) stay selectable.
    final unlinked =
        allowed == null ? s.paymentModes.where((m) => m.accountId == null).toList() : <PaymentMode>[];
    final current = selected?.accountId == null
        ? null
        : s.accounts.where((a) => a.id == selected!.accountId).firstOrNull;
    final siblings = current == null ? <PaymentMode>[] : s.modesOf(current.id!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final a in s.accounts)
              if (s.modesOf(a.id!).isNotEmpty && (allowed?.contains(a.type) ?? true))
                ChoiceChip(
                  avatar: Icon(_accountIcons[a.type], size: 18),
                  label: Text(a.name),
                  selected: current?.id == a.id,
                  onSelected: (_) {
                    // Keep the current mode when staying inside the same account.
                    if (current?.id != a.id) onChanged(s.modesOf(a.id!).first.id!);
                  },
                ),
            for (final m in unlinked)
              ChoiceChip(
                avatar: AppIcon(m.icon, size: 18),
                label: Text(m.name),
                selected: modeId == m.id,
                onSelected: (_) => onChanged(m.id!),
              ),
          ],
        ),
        if (siblings.length > 1) ...[
          const SizedBox(height: 16),
          _label('Pay using'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in siblings)
                ChoiceChip(
                  avatar: AppIcon(m.icon, size: 18),
                  label: Text(m.name),
                  selected: modeId == m.id,
                  onSelected: (_) => onChanged(m.id!),
                ),
            ],
          ),
        ],
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 4),
            child: Text(error!, style: TextStyle(color: cs.error)),
          ),
      ],
    );
  }
}
