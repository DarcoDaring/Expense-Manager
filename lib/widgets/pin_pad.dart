import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/lock_service.dart';

/// Dots + numeric keypad. [onSubmit] gets the full PIN and returns an error
/// message to show (and clear the dots), or null when the PIN was accepted.
class PinPad extends StatefulWidget {
  final Future<String?> Function(String pin) onSubmit;
  final Widget? bottomLeft;

  const PinPad({super.key, required this.onSubmit, this.bottomLeft});

  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> with SingleTickerProviderStateMixin {
  String _pin = '';
  String? _error;
  bool _busy = false;
  late final AnimationController _shake =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 380));

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  Future<void> _tap(String d) async {
    if (_busy || _pin.length >= LockService.pinLength) return;
    HapticFeedback.selectionClick();
    setState(() {
      _pin += d;
      _error = null;
    });
    if (_pin.length == LockService.pinLength) {
      _busy = true;
      final err = await widget.onSubmit(_pin);
      _busy = false;
      if (!mounted) return;
      if (err != null) {
        HapticFeedback.heavyImpact();
        _shake.forward(from: 0);
        setState(() {
          _error = err;
          _pin = '';
        });
      }
    }
  }

  void _back() {
    if (_busy || _pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _shake,
          builder: (_, child) {
            final dx = (1 - _shake.value) * 14 * ((_shake.value * 12).floor().isEven ? 1 : -1);
            return Transform.translate(offset: Offset(_shake.isAnimating ? dx : 0, 0), child: child);
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < LockService.pinLength; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < _pin.length
                        ? (_error != null ? cs.error : cs.primary)
                        : Colors.transparent,
                    border: Border.all(
                        color: _error != null ? cs.error : cs.outline, width: 1.6),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(
          height: 36,
          child: Center(
            child: Text(_error ?? '',
                style: TextStyle(color: cs.error, fontWeight: FontWeight.w500)),
          ),
        ),
        const SizedBox(height: 8),
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [for (final d in row) _key(label: d, onTap: () => _tap(d))],
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(width: 96, height: 76, child: Center(child: widget.bottomLeft)),
            _key(label: '0', onTap: () => _tap('0')),
            _key(icon: Icons.backspace_outlined, onTap: _back),
          ],
        ),
      ],
    );
  }

  Widget _key({String? label, IconData? icon, required VoidCallback onTap}) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 96,
      height: 76,
      child: Center(
        child: InkResponse(
          onTap: onTap,
          radius: 40,
          child: Container(
            width: 68,
            height: 68,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: icon == null ? cs.surfaceContainerHighest.withValues(alpha: .6) : null,
            ),
            child: icon != null
                ? Icon(icon, color: cs.onSurfaceVariant)
                : Text(label!,
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w500)),
          ),
        ),
      ),
    );
  }
}
