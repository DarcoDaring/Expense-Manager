import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'screens/home_shell.dart';
import 'screens/lock_screen.dart';
import 'screens/welcome_screen.dart';
import 'services/lock_service.dart';
import 'services/sync_service.dart';
import 'state/app_state.dart';
import 'theme.dart';
import 'widgets/ui_scale.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState();
  final lock = LockService();
  final sync = SyncService();
  try {
    await Future.wait([state.init(), lock.init()]);
    await sync.init(state);
  } catch (e, st) {
    // Show the failure instead of dying silently on a blank screen.
    runApp(StartupError('$e\n\n$st'));
    return;
  }
  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: state),
      ChangeNotifierProvider.value(value: lock),
      ChangeNotifierProvider.value(value: sync),
    ],
    child: const ExpenseApp(),
  ));
}

class ExpenseApp extends StatelessWidget {
  const ExpenseApp({super.key});

  @override
  Widget build(BuildContext context) {
    final mode = context.select<AppState, ThemeMode>((s) => s.themeMode);
    final welcomed = context.select<SyncService, bool>((s) => s.welcomed);
    return MaterialApp(
      title: 'Expense Manager',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: mode,
      // Wrapping the navigator lets the lock cover pushed routes too.
      builder: (context, child) => UiScale(child: LockGate(child: child!)),
      home: welcomed || !SyncService.supported ? const HomeShell() : const WelcomeScreen(),
    );
  }
}

/// Covers [child] with the lock screen whenever the app is locked, and
/// re-locks when the app goes to the background.
class LockGate extends StatefulWidget {
  final Widget child;
  const LockGate({super.key, required this.child});

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // `hidden` is skipped on purpose: it also fires for system dialogs.
    if (state == AppLifecycleState.paused) {
      context.read<LockService>().lock();
    } else if (state == AppLifecycleState.resumed) {
      // Statements may have been generated while the app was in the background.
      context.read<AppState>().syncCardEmis();
      context.read<SyncService>().onResume();
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = context.select<LockService, bool>((l) => l.locked);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: Theme.of(context).brightness == Brightness.dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: Stack(
        children: [
          // Keep the app mounted underneath so state survives a lock.
          Offstage(offstage: locked, child: TickerMode(enabled: !locked, child: widget.child)),
          if (locked) const Positioned.fill(child: LockScreen()),
        ],
      ),
    );
  }
}

class StartupError extends StatelessWidget {
  final String message;
  const StartupError(this.message, {super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Startup failed',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  SelectableText(message),
                ],
              ),
            ),
          ),
        ),
      );
}
