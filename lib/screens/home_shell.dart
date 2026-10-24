import 'package:flutter/material.dart';

import 'accounts_screen.dart';
import 'add_expense_screen.dart';
import 'expenses_screen.dart';
import 'notes_screen.dart';
import 'recurring_screen.dart';
import 'report_screen.dart';
import 'settings_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

/// What the round button in the middle of the bar does on the current tab.
class _CenterAction {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _CenterAction(this.icon, this.label, this.onTap);
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  /// The current page. Only the bar listens to it, so a page change redraws just
  /// the bar and never rebuilds the pages while they slide.
  final _index = ValueNotifier<int>(0);
  final _pages = PageController();

  /// Whether the Accounts balances are showing (the bar's eye button flips it).
  final _balanceVisible = ValueNotifier<bool>(false);
  final _recurringKey = GlobalKey<RecurringScreenState>();
  final _analysisKey = GlobalKey<ReportScreenState>();

  /// Built once, so the pages are not touched again while the bar changes.
  late final List<Widget> _pageList = [
    const _Keep(child: ExpensesScreen()),
    _Keep(child: ReportScreen(key: _analysisKey)),
    _Keep(child: AccountsScreen(balanceVisible: _balanceVisible)),
    _Keep(child: RecurringScreen(key: _recurringKey)),
    const _Keep(child: NotesScreen()),
    const _Keep(child: SettingsScreen()),
  ];

  DateTime? _pausedAt;

  /// The page a swipe handed over from the Recurring tabs started on, while it is moving.
  int? _handoffFrom;

  /// Coming back after this long starts again from Home.
  static const _awayLimit = Duration(minutes: 1);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _index.dispose();
    _balanceVisible.dispose();
    _pages.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _pausedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final away = _pausedAt == null ? Duration.zero : DateTime.now().difference(_pausedAt!);
      _pausedAt = null;
      if (away >= _awayLimit) {
        // Reopening the app lands on Home, not wherever it was left.
        Navigator.of(context).popUntil((r) => r.isFirst);
        if (_pages.hasClients) _pages.jumpToPage(0);
        _index.value = 0;
      }
    }
  }

  /// A tap on the bar slides to that page, with the same motion as a swipe.
  void _select(int i) {
    if (i == _index.value || !_pages.hasClients) return;
    _pages.animateToPage(
      i,
      duration: Duration(milliseconds: (i - _index.value).abs() > 1 ? 480 : 360),
      curve: Curves.easeInOutCubic,
    );
  }

  /// Runs whenever the page changes, by swipe or by tap.
  void _onPage(int i) {
    // A pending toast (e.g. "Expense deleted") shouldn't follow you to another page.
    ScaffoldMessenger.of(context).clearSnackBars();
    final left = _index.value;
    _index.value = i;
    if (left == 2 && i != 2) _balanceVisible.value = false;
    // Analysis starts from the top the next time. Wait until the slide has finished.
    if (left == 1) {
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted && _index.value != 1) _analysisKey.currentState?.resetView();
      });
    }
  }

  /// Swiping past the last Recurring tab (EMIs) or before the first (Subscriptions)
  /// carries on to the next / previous page, as one continuous swipe.
  bool _onInnerScroll(ScrollNotification n) {
    if (n.depth == 0 || n.metrics.axis != Axis.horizontal || !_pages.hasClients) return false;
    if (n is OverscrollNotification) {
      final ctx = n.context;
      if (ctx == null || ctx.findAncestorStateOfType<RecurringScreenState>() == null) {
        return false;
      }
      final pos = _pages.position;
      _handoffFrom ??= _pages.page?.round() ?? _index.value;
      pos.jumpTo((pos.pixels + n.overscroll).clamp(pos.minScrollExtent, pos.maxScrollExtent));
    } else if (n is ScrollEndNotification && _handoffFrom != null) {
      // Settle on a page, going on if the swipe got far enough or was a quick flick.
      final from = _handoffFrom!;
      _handoffFrom = null;
      final moved = (_pages.page ?? from.toDouble()) - from;
      final v = n.dragDetails?.primaryVelocity ?? 0;
      var target = from;
      if (moved > 0.25 || (moved > 0.02 && v < -400)) {
        target = from + 1;
      } else if (moved < -0.25 || (moved < -0.02 && v > 400)) {
        target = from - 1;
      }
      _pages.animateToPage(
        target.clamp(0, _pageList.length - 1),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
    return false;
  }

  void _push(Widget page) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  /// Add on Home, Notes and Recurring, the eye on Accounts, nothing elsewhere.
  _CenterAction? _centerFor(int i) => switch (i) {
        0 => _CenterAction(Icons.add_rounded, 'Add expense', () => _push(const AddExpenseScreen())),
        2 => _CenterAction(
            _balanceVisible.value ? Icons.visibility_off_rounded : Icons.visibility_rounded,
            _balanceVisible.value ? 'Hide balances' : 'Show balances',
            () => toggleBalances(context, _balanceVisible)),
        3 => _CenterAction(
            Icons.add_rounded, 'Add', () => _recurringKey.currentState?.addItem()),
        4 => _CenterAction(Icons.add_rounded, 'New note', () => _push(const NoteEditScreen())),
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          NotificationListener<ScrollNotification>(
            onNotification: _onInnerScroll,
            child: PageView(
            controller: _pages,
            onPageChanged: _onPage,
            physics: const _FlowPagePhysics(),
            // The pages fill the screen, so there is nothing to clip.
            clipBehavior: Clip.none,
            // Builds the neighbouring pages before they are swiped to, so nothing
            // has to be built in the middle of a slide.
            allowImplicitScrolling: true,
            children: _pageList,
            ),
          ),
          // The bar floats over the pages, so it changing size never re-lays them out.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ValueListenableBuilder<int>(
              valueListenable: _index,
              builder: (_, i, _) => ValueListenableBuilder<bool>(
                valueListenable: _balanceVisible,
                builder: (_, _, _) => RepaintBoundary(
                  child: _NavBar(index: i, onSelect: _select, center: _centerFor(i)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Page snapping with a slightly softer spring, so a swipe settles smoothly.
class _FlowPagePhysics extends PageScrollPhysics {
  const _FlowPagePhysics({super.parent});

  @override
  _FlowPagePhysics applyTo(ScrollPhysics? ancestor) =>
      _FlowPagePhysics(parent: buildParent(ancestor));

  @override
  SpringDescription get spring =>
      SpringDescription.withDampingRatio(mass: 0.6, stiffness: 80, ratio: 1.0);
}

/// Keeps a page alive while it is off screen, so its scroll position and state stay.
class _Keep extends StatefulWidget {
  final Widget child;
  const _Keep({required this.child});

  @override
  State<_Keep> createState() => _KeepState();
}

class _KeepState extends State<_Keep> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class _NavBar extends StatefulWidget {
  final int index;
  final ValueChanged<int> onSelect;
  final _CenterAction? center;
  const _NavBar({required this.index, required this.onSelect, required this.center});

  @override
  State<_NavBar> createState() => _NavBarState();
}

class _NavBarState extends State<_NavBar> {
  static const _bump = 30.0; // how far the round button rises above the bar
  static const _button = 66.0;
  static const _anim = Duration(milliseconds: 220);

  /// The last button shown, so it can shrink away smoothly when a page has none.
  _CenterAction? _last;

  int get index => widget.index;

  @override
  void initState() {
    super.initState();
    _last = widget.center;
  }

  @override
  void didUpdateWidget(_NavBar old) {
    super.didUpdateWidget(old);
    if (widget.center != null) _last = widget.center;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final show = widget.center != null;
    final c = widget.center ?? _last;
    return Stack(
      alignment: Alignment.topCenter,
      children: [
        AnimatedPadding(
          duration: _anim,
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.only(top: show ? _bump : 0),
          child: Container(
            decoration: BoxDecoration(
              color: cs.surfaceContainer,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
              border: Border(
                  top: BorderSide(color: cs.outlineVariant.withValues(alpha: .4))),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
                child: Row(
                  children: [
                    _item(context, 0, Icons.home_rounded, 'Home'),
                    _item(context, 1, Icons.bar_chart_rounded, 'Analysis'),
                    _item(context, 2, Icons.account_balance_rounded, 'Accounts'),
                    // Room for the round button, only while there is one. An empty box
                    // would stretch to the full height, so it is given none.
                    AnimatedContainer(
                      duration: _anim,
                      curve: Curves.easeOutCubic,
                      width: show ? _button - 8 : 0,
                      height: 0,
                    ),
                    _item(context, 3, Icons.event_repeat_rounded, 'Recurring'),
                    _item(context, 4, Icons.sticky_note_2_rounded, 'Notes'),
                    _item(context, 5, Icons.more_horiz_rounded, 'More'),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (c != null)
          Positioned(
            top: 0,
            child: IgnorePointer(
              ignoring: !show,
              child: AnimatedScale(
                scale: show ? 1 : 0,
                duration: _anim,
                curve: Curves.easeOutCubic,
                child: AnimatedOpacity(
                  opacity: show ? 1 : 0,
                  duration: _anim,
                  child: Semantics(
                    button: true,
                    label: c.label,
                    child: GestureDetector(
                      onTap: c.onTap,
                      child: Container(
                        width: _button,
                        height: _button,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: cs.onSurface,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: .25),
                              blurRadius: 14,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          transitionBuilder: (child, anim) => ScaleTransition(
                              scale: anim, child: FadeTransition(opacity: anim, child: child)),
                          child: Icon(c.icon,
                              key: ValueKey(c.icon), size: 34, color: cs.surface),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _item(BuildContext context, int i, IconData icon, String label) {
    final cs = Theme.of(context).colorScheme;
    final selected = index == i;
    final color = selected ? cs.onSurface : cs.onSurfaceVariant.withValues(alpha: .6);
    return Expanded(
      child: InkResponse(
        onTap: () => widget.onSelect(i),
        radius: 36,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 26, color: color),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(label,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: color,
                    )),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
