import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/lock_service.dart';
import '../widgets/pin_pad.dart';

class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  static const _maxAttempts = 5;
  static const _cooldown = Duration(seconds: 30);

  int _failures = 0;
  DateTime? _lockedUntil;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Prompt for biometrics straight away once the first frame is up.
    WidgetsBinding.instance.addPostFrameCallback((_) => _biometric());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _biometric() async {
    final lock = context.read<LockService>();
    if (lock.enabled && lock.biometricEnabled) await lock.unlockWithBiometric();
  }

  int get _secondsLeft {
    final until = _lockedUntil;
    if (until == null) return 0;
    final s = until.difference(DateTime.now()).inSeconds + 1;
    return s > 0 ? s : 0;
  }

  Future<String?> _submit(String pin) async {
    if (_secondsLeft > 0) return 'Try again in $_secondsLeft s';
    final ok = await context.read<LockService>().unlockWithPin(pin);
    if (ok) return null;
    _failures++;
    if (_failures >= _maxAttempts) {
      _failures = 0;
      _lockedUntil = DateTime.now().add(_cooldown);
      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) return t.cancel();
        if (_secondsLeft == 0) t.cancel();
        setState(() {});
      });
      setState(() {});
      return 'Too many attempts. Wait ${_cooldown.inSeconds} s';
    }
    return 'Wrong PIN';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final lock = context.watch<LockService>();
    final waiting = _secondsLeft > 0;
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      gradient: LinearGradient(
                        colors: [cs.primary, cs.tertiary],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Icon(Icons.lock_rounded, color: cs.onPrimary, size: 34),
                  ),
                  const SizedBox(height: 20),
                  const Text('Welcome back',
                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(
                    waiting ? 'Locked for $_secondsLeft s' : 'Enter your PIN to unlock',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 28),
                  PinPad(
                    onSubmit: _submit,
                    bottomLeft: lock.biometricEnabled
                        ? IconButton(
                            iconSize: 34,
                            color: cs.primary,
                            onPressed: _biometric,
                            // No tooltip: the lock screen sits above the Navigator, so there is no Overlay.
                            icon: const Icon(Icons.fingerprint_rounded, semanticLabel: 'Use biometrics'),
                          )
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
