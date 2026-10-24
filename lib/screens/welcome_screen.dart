import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/sync_service.dart';
import '../widgets/sync_ui.dart';

/// Shown once on a fresh install: connect Google to restore and sync, or skip.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  bool _busy = false;

  Future<void> _connect() async {
    setState(() => _busy = true);
    await connectGoogle(context);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final sky = dark
        ? const [Color(0xFF0F172A), Color(0xFF1E293B)]
        : const [Color(0xFFBFE3FA), Color(0xFFEAF5FD)];
    final cardTop = dark ? const Color(0xFF1E293B) : const Color(0xFFD9F0FF);
    final cardBottom = dark ? const Color(0xFF172033) : Colors.white;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: sky),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 380),
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [cardTop, cardBottom]),
                  border: Border.all(color: Colors.white.withValues(alpha: dark ? 0.08 : 0.9)),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: dark ? 0.4 : 0.08),
                        blurRadius: 30,
                        offset: const Offset(0, 14)),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: dark ? const Color(0xFF0F172A) : Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 12,
                              offset: const Offset(0, 4)),
                        ],
                      ),
                      child: Icon(Icons.login_rounded, size: 28, color: cs.onSurface),
                    ),
                    const SizedBox(height: 22),
                    Text('Sign in to Expense Manager',
                        textAlign: TextAlign.center,
                        style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Text(
                      'Keep your data safe in your own Google Drive. Reinstall or switch '
                      'phones and everything comes back, synced automatically.',
                      textAlign: TextAlign.center,
                      style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 26),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _busy ? null : _connect,
                        style: FilledButton.styleFrom(
                          backgroundColor: dark ? Colors.white : const Color(0xFF111827),
                          foregroundColor: dark ? const Color(0xFF111827) : Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: _busy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    width: 24,
                                    height: 24,
                                    alignment: Alignment.center,
                                    decoration: const BoxDecoration(
                                        color: Colors.white, shape: BoxShape.circle),
                                    child: const Text('G',
                                        style: TextStyle(
                                            color: Color(0xFF4285F4),
                                            fontWeight: FontWeight.w900,
                                            fontSize: 15)),
                                  ),
                                  const SizedBox(width: 12),
                                  const Text('Continue with Google',
                                      style: TextStyle(fontWeight: FontWeight.w700)),
                                ],
                              ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(children: [
                      Expanded(child: Divider(color: cs.outlineVariant)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text('or',
                            style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                      ),
                      Expanded(child: Divider(color: cs.outlineVariant)),
                    ]),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed:
                            _busy ? null : () => context.read<SyncService>().markWelcomed(),
                        child: const Text('Skip for now'),
                      ),
                    ),
                    Text('You can sign in later from the More tab.',
                        style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
