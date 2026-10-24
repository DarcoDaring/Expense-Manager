import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/lock_service.dart';
import 'pin_pad.dart';

/// Asks the user to prove it is them before something private is shown: their
/// fingerprint or face when app lock uses it, otherwise the app PIN, and with
/// no app lock the phone's own screen lock. Resolves to whether they passed.
Future<bool> confirmIdentity(
  BuildContext context, {
  String reason = 'Confirm it is you to show your balances',
}) async {
  final lock = context.read<LockService>();
  if (lock.enabled) {
    if (lock.biometricEnabled && await lock.confirmWithBiometric(reason)) return true;
    if (!context.mounted) return false;
    return await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          showDragHandle: true,
          builder: (_) => _PinSheet(lock: lock, reason: reason),
        ) ??
        false;
  }
  final device = await lock.confirmWithDevice(reason);
  // Null means this phone has no screen lock to check against.
  return device ?? true;
}

class _PinSheet extends StatefulWidget {
  final LockService lock;
  final String reason;
  const _PinSheet({required this.lock, required this.reason});

  @override
  State<_PinSheet> createState() => _PinSheetState();
}

class _PinSheetState extends State<_PinSheet> {
  int _fails = 0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_rounded, size: 36, color: cs.primary),
          const SizedBox(height: 12),
          const Text('Enter your PIN',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(widget.reason, style: TextStyle(color: cs.onSurfaceVariant)),
          const SizedBox(height: 22),
          PinPad(
            onSubmit: (pin) async {
              final nav = Navigator.of(context);
              if (await widget.lock.verifyPin(pin)) {
                nav.pop(true);
                return null;
              }
              // Too many wrong tries closes the sheet.
              if (++_fails >= 5) {
                nav.pop(false);
                return null;
              }
              return 'Wrong PIN';
            },
            bottomLeft: widget.lock.biometricEnabled
                ? IconButton(
                    iconSize: 34,
                    color: cs.primary,
                    tooltip: 'Use biometrics',
                    onPressed: () async {
                      final nav = Navigator.of(context);
                      if (await widget.lock.confirmWithBiometric(widget.reason)) {
                        nav.pop(true);
                      }
                    },
                    icon: const Icon(Icons.fingerprint_rounded),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}
