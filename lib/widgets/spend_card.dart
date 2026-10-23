import 'package:flutter/material.dart';

/// The app's hero card: small coloured label, big amount, an inner pill with
/// one stat and an optional footer line.
class SpendCard extends StatelessWidget {
  final String label;
  final String? headerTrailing;
  final String amount;
  final String? pillLabel;
  final String? pillValue;
  final Widget? footer;

  const SpendCard({
    super.key,
    required this.label,
    required this.amount,
    this.headerTrailing,
    this.pillLabel,
    this.pillValue,
    this.footer,
  });

  /// Gradient + border shared by every hero surface.
  static BoxDecoration decoration(ColorScheme cs) => BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          colors: [
            cs.surfaceContainerHigh,
            Color.lerp(cs.surfaceContainerHigh, cs.error, .12)!,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: .5)),
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: decoration(cs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label.toUpperCase(),
                  style: TextStyle(
                      color: cs.error,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      fontSize: 13)),
              const Spacer(),
              if (headerTrailing != null)
                Text(headerTrailing!,
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(amount,
                style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800)),
          ),
          if (pillLabel != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: cs.surface.withValues(alpha: .5),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  Text(pillLabel!, style: TextStyle(color: cs.onSurfaceVariant)),
                  const Spacer(),
                  Text(pillValue ?? '',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                ],
              ),
            ),
          ],
          if (footer != null) ...[const SizedBox(height: 12), footer!],
        ],
      ),
    );
  }
}
