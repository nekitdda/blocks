import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:window_manager/window_manager.dart';
import 'package:youmuz/src/features/core/providers/navigation_provider.dart';
import 'package:youmuz/src/features/core/views/layout/account_menu.dart';
import 'package:youmuz/src/features/search/providers/search_provider.dart';
import 'package:youmuz/src/ui/ui.dart';

bool get _isDesktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

/// Logo mark: a foreground disc with a background dot.
class GraphiteLogo extends StatelessWidget {
  const GraphiteLogo({super.key, this.showLabel = true});

  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: const BoxDecoration(color: GColors.foreground, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(color: GColors.background, shape: BoxShape.circle),
          ),
        ),
        if (showLabel) ...[
          const SizedBox(width: 8),
          Text(
            'YouMuz',
            style: GText.style(14, lineHeight: 20, weight: GText.semibold, tight: true),
          ),
        ],
      ],
    );
  }
}

class _NavItem {
  const _NavItem(this.section, this.label, this.icon);
  final AppSection section;
  final String label;
  final IconData icon;
}

const _navItems = [
  _NavItem(AppSection.home, 'Главная', LucideIcons.house),
  _NavItem(AppSection.wave, 'Моя волна', LucideIcons.audioLines),
  _NavItem(AppSection.liked, 'Коллекция', LucideIcons.library),
];

/// Desktop header (`h-16 px-8 gap-6`): logo, navigation pills, search,
/// profile. With the custom title bar it doubles as the drag area and hosts
/// the window buttons.
class GraphiteHeader extends StatefulWidget {
  const GraphiteHeader({super.key});

  @override
  State<GraphiteHeader> createState() => _GraphiteHeaderState();
}

class _GraphiteHeaderState extends State<GraphiteHeader> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  EffectCleanup? _querySync;

  @override
  void initState() {
    super.initState();
    // The query is cleared when the account changes; mirror that here.
    _querySync = effect(() {
      final q = searchQuerySignal();
      if (q.isEmpty && _searchController.text.isNotEmpty && !_searchFocus.hasFocus) {
        _searchController.clear();
      }
    });
  }

  @override
  void dispose() {
    _querySync?.call();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onSearch(String value) {
    setSearchQuery(value);
    if (value.trim().isNotEmpty && currentRootSignal.value != AppSection.search) {
      setSection(AppSection.search);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final horizontal = width >= GLayout.mediumBreakpoint ? 32.0 : 16.0;

    return SignalBuilder(
      builder: (context) {
        final root = currentRootSignal();
        final canGoBack = canGoBackSignal();
        final customTitlebar = _isDesktop && customTitlebarSignal();

        Widget bar = Container(
          height: GLayout.headerHeight,
          padding: EdgeInsets.only(left: horizontal, right: customTitlebar ? 12 : horizontal),
          child: Row(
            children: [
              GPressable(
                onTap: () => navigateTo(AppSection.home),
                semanticLabel: 'YouMuz — главная',
                builder: (context, s) => GraphiteLogo(showLabel: width >= 640),
              ),
              const SizedBox(width: 24),
              AnimatedSize(
                duration: GDurations.fast,
                child: canGoBack
                    ? Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: GCircleButton(
                          icon: LucideIcons.chevronLeft,
                          size: 32,
                          tooltip: 'Назад',
                          onPressed: goBack,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              Flexible(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final item in _navItems) ...[
                        GNavPill(
                          label: item.label,
                          active: root == item.section,
                          onPressed: () => navigateTo(item.section),
                        ),
                        const SizedBox(width: 4),
                      ],
                    ],
                  ),
                ),
              ),
              const Spacer(),
              if (width >= GLayout.wideBreakpoint)
                SizedBox(
                  width: 288,
                  child: GSearchField(
                    controller: _searchController,
                    focusNode: _searchFocus,
                    onChanged: _onSearch,
                    onSubmitted: _onSearch,
                    onTap: () {
                      if (_searchController.text.isNotEmpty) setSection(AppSection.search);
                    },
                  ),
                )
              else
                GCircleButton(
                  icon: LucideIcons.search,
                  size: 36,
                  tooltip: 'Поиск',
                  onPressed: () => navigateTo(AppSection.search),
                ),
              const SizedBox(width: 24),
              const AccountMenuButton(),
              if (customTitlebar) ...[
                const SizedBox(width: 16),
                const WindowButtons(),
              ],
            ],
          ),
        );

        if (customTitlebar) {
          bar = DragToMoveArea(child: bar);
        }
        return bar;
      },
    );
  }
}

/// Minimize / maximize / close for the frameless window.
class WindowButtons extends StatefulWidget {
  const WindowButtons({super.key});

  @override
  State<WindowButtons> createState() => _WindowButtonsState();
}

class _WindowButtonsState extends State<WindowButtons> with WindowListener {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    unawaited(windowManager.isMaximized().then((v) {
      if (mounted) setState(() => _maximized = v);
    }));
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => setState(() => _maximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GIconButton(
          icon: LucideIcons.minus,
          tooltip: 'Свернуть',
          background: true,
          onPressed: () => unawaited(windowManager.minimize()),
        ),
        GIconButton(
          icon: _maximized ? LucideIcons.copy : LucideIcons.square,
          size: 14,
          padding: 9,
          tooltip: _maximized ? 'Восстановить' : 'Развернуть',
          background: true,
          onPressed: () => unawaited(
            _maximized ? windowManager.unmaximize() : windowManager.maximize(),
          ),
        ),
        GIconButton(
          icon: LucideIcons.x,
          tooltip: 'Закрыть',
          background: true,
          hoverColor: GColors.destructive,
          onPressed: () => unawaited(windowManager.close()),
        ),
      ],
    );
  }
}
