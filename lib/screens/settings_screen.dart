import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/lock_service.dart';
import '../state/app_state.dart';
import 'manage_screen.dart';
import 'pin_setup_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  void _toast(BuildContext c, String m) =>
      ScaffoldMessenger.of(c)..clearSnackBars()..showSnackBar(SnackBar(content: Text(m)));

  Future<void> _toggleLock(BuildContext context, bool on) async {
    final lock = context.read<LockService>();
    if (on) {
      final ok = await Navigator.push<bool>(
          context, MaterialPageRoute(builder: (_) => const PinSetupScreen()));
      if (ok == true && context.mounted) {
        _toast(context, 'App lock enabled');
        // Offer biometrics right away if the device has them.
        await lock.refreshBiometricAvailability();
        if (lock.biometricAvailable && context.mounted) {
          final yes = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              icon: const Icon(Icons.fingerprint_rounded, size: 36),
              title: const Text('Use biometrics too?'),
              content: const Text('Unlock with your fingerprint or face instead of typing the PIN. '
                  'The PIN always works as a fallback.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Not now')),
                TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Enable')),
              ],
            ),
          );
          if (yes == true) await lock.enableBiometric();
        }
      }
    } else {
      final pin = await _askPin(context, 'Enter PIN to turn off app lock');
      if (pin == null) return;
      if (await lock.verifyPin(pin)) {
        await lock.disableLock();
        if (context.mounted) _toast(context, 'App lock disabled');
      } else if (context.mounted) {
        _toast(context, 'Wrong PIN');
      }
    }
  }

  Future<void> _toggleBio(BuildContext context, bool on) async {
    final lock = context.read<LockService>();
    if (!on) return lock.disableBiometric();
    final ok = await lock.enableBiometric();
    if (!ok && context.mounted) {
      _toast(context, lock.biometricAvailable
          ? 'Biometric check failed'
          : 'No fingerprint or face enrolled on this device');
    }
  }

  Future<String?> _askPin(BuildContext context, String title) {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: LockService.pinLength,
          decoration: const InputDecoration(labelText: 'PIN'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('OK')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lock = context.watch<LockService>();
    final s = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 130),
        children: [
          _section('Organise'),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              _nav(context, Icons.category_rounded, 'Categories',
                  '${s.categories.length} created', const ManageScreen(categories: true)),
              _nav(context, Icons.account_balance_wallet_rounded, 'Payment modes',
                  '${s.paymentModes.length} created', const ManageScreen(categories: false)),
            ]),
          ),
          _section('Security'),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              SwitchListTile(
                secondary: Icon(Icons.lock_rounded, color: cs.primary),
                title: const Text('App lock'),
                subtitle: const Text('Ask for a PIN when opening the app'),
                value: lock.enabled,
                onChanged: (v) => _toggleLock(context, v),
              ),
              if (lock.enabled) ...[
                SwitchListTile(
                  secondary: Icon(Icons.fingerprint_rounded, color: cs.primary),
                  title: const Text('Biometric unlock'),
                  subtitle: Text(lock.biometricAvailable
                      ? 'Fingerprint or face'
                      : 'Not available on this device'),
                  value: lock.biometricEnabled,
                  onChanged: lock.biometricAvailable || lock.biometricEnabled
                      ? (v) => _toggleBio(context, v)
                      : null,
                ),
                ListTile(
                  leading: Icon(Icons.pin_rounded, color: cs.primary),
                  title: const Text('Change PIN'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () async {
                    final ok = await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const PinSetupScreen(change: true)));
                    if (ok == true && context.mounted) _toast(context, 'PIN changed');
                  },
                ),
              ],
            ]),
          ),
          _section('Appearance'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Theme', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  SegmentedButton<ThemeMode>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: ThemeMode.system, label: Text('System')),
                      ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                      ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                    ],
                    selected: {s.themeMode},
                    onSelectionChanged: (v) => s.setThemeMode(v.first),
                  ),
                  const SizedBox(height: 18),
                  const Text('Currency symbol', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final c in const ['₹', '\$', '€', '£', '¥', 'AED ', 'SAR '])
                        ChoiceChip(
                          label: Text(c.trim()),
                          selected: s.currency == c,
                          onSelected: (_) => s.setCurrency(c),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 22, 0, 10),
        child: Text(t.toUpperCase(),
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.1)),
      );

  Widget _nav(BuildContext context, IconData icon, String title, String sub, Widget page) =>
      ListTile(
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title),
        subtitle: Text(sub),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => page)),
      );
}
