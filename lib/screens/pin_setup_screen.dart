import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/lock_service.dart';
import '../widgets/pin_pad.dart';

/// Create (or change) the app PIN. Pops with `true` once saved.
class PinSetupScreen extends StatefulWidget {
  final bool change;
  const PinSetupScreen({super.key, this.change = false});

  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

enum _Step { verifyOld, create, confirm }

class _PinSetupScreenState extends State<PinSetupScreen> {
  late _Step _step = widget.change ? _Step.verifyOld : _Step.create;
  String? _first;
  int _round = 0; // changes the PinPad key so it resets between steps

  String get _title => switch (_step) {
        _Step.verifyOld => 'Enter current PIN',
        _Step.create => 'Create a PIN',
        _Step.confirm => 'Confirm your PIN',
      };

  String get _hint => switch (_step) {
        _Step.verifyOld => 'Verify it is you before changing',
        _Step.create => 'Choose ${LockService.pinLength} digits you will remember',
        _Step.confirm => 'Enter the same PIN again',
      };

  Future<String?> _submit(String pin) async {
    final lock = context.read<LockService>();
    switch (_step) {
      case _Step.verifyOld:
        if (!await lock.verifyPin(pin)) return 'Wrong PIN';
        setState(() {
          _step = _Step.create;
          _round++;
        });
      case _Step.create:
        setState(() {
          _first = pin;
          _step = _Step.confirm;
          _round++;
        });
      case _Step.confirm:
        if (pin != _first) {
          setState(() {
            _first = null;
            _step = _Step.create;
            _round++;
          });
          return "PINs didn't match. Start again";
        }
        await lock.setPin(pin);
        if (mounted) Navigator.pop(context, true);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.change ? 'Change PIN' : 'Set up app lock')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.pin_rounded, size: 48, color: cs.primary),
                const SizedBox(height: 16),
                Text(_title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(_hint, style: TextStyle(color: cs.onSurfaceVariant)),
                const SizedBox(height: 28),
                PinPad(key: ValueKey(_round), onSubmit: _submit),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
