import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:youmuz/src/features/album/views/album_view.dart';
import 'package:youmuz/src/features/artist/views/artist_view.dart';
import 'package:youmuz/src/features/auth/providers/auth_provider.dart';
import 'package:youmuz/src/features/auth/views/yandex_id_view.dart';
import 'package:youmuz/src/features/core/providers/navigation_provider.dart';
import 'package:youmuz/src/features/core/views/layout/account_menu.dart';
import 'package:youmuz/src/features/core/views/layout/header.dart';
import 'package:youmuz/src/features/core/views/layout/mobile_player.dart';
import 'package:youmuz/src/features/core/views/layout/player_bar.dart';
import 'package:youmuz/src/features/core/views/widgets/lyrics_view.dart';
import 'package:youmuz/src/features/home/views/home_view.dart';
import 'package:youmuz/src/features/library/views/library_view.dart';
import 'package:youmuz/src/features/library/views/playlist_view.dart';
import 'package:youmuz/src/features/playback/providers/playback_provider.dart';
import 'package:youmuz/src/features/playback/views/wave_view.dart';
import 'package:youmuz/src/features/search/views/search_view.dart';
import 'package:youmuz/src/features/settings/views/settings_view.dart';
import 'package:youmuz/src/ui/ui.dart';

bool isCompactLayout(BuildContext context) =>
    Platform.isAndroid || MediaQuery.sizeOf(context).width < GLayout.compactBreakpoint;

/// App shell: header, the page stacks of every tab, and the player.
class AppLayout extends StatefulWidget {
  const AppLayout({super.key});

  @override
  State<AppLayout> createState() => _AppLayoutState();
}

class _AppLayoutState extends State<AppLayout> {
  PageStorageBucket _bucket = PageStorageBucket();
  int? _bucketOwner;

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final compact = isCompactLayout(context);
        final isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
        final customTitlebar = isDesktop && customTitlebarSignal();
        final canGoBack = canGoBackSignal();
        final uid = activeAccountUidSignal();
        if (uid != _bucketOwner) {
          // Scroll positions belong to the account they were made in.
          _bucket = PageStorageBucket();
          _bucketOwner = uid;
        }

        return PopScope(
          canPop: !canGoBack,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && canGoBackSignal.value) goBack();
          },
          child: Scaffold(
            backgroundColor: GColors.background,
            resizeToAvoidBottomInset: false,
            body: SafeArea(
              top: !customTitlebar,
              bottom: false,
              child: Stack(
                children: [
                  Column(
                    children: [
                      if (compact) const _MobileHeader() else const GraphiteHeader(),
                      Expanded(
                        // Rebuilt per account: no page keeps state of the
                        // previous session.
                        child: KeyedSubtree(
                          key: ValueKey('session_$uid'),
                          child: PageStorage(
                            bucket: _bucket,
                            child: Stack(
                              children: [
                                for (final root in rootSections) _RootBucket(root: root),
                                const _LyricsOverlay(),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (compact) ...[
                        const MobileMiniPlayer(),
                        const MobileNavBar(),
                      ] else
                        const PlayerBar(),
                    ],
                  ),
                  const Positioned.fill(child: SessionTransitionOverlay()),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MobileHeader extends StatelessWidget {
  const _MobileHeader();

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final canGoBack = canGoBackSignal();
        return SizedBox(
          height: 56,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                if (canGoBack) ...[
                  GCircleButton(
                    icon: LucideIcons.chevronLeft,
                    size: 34,
                    tooltip: 'Назад',
                    onPressed: goBack,
                  ),
                  const SizedBox(width: 12),
                ],
                const GraphiteLogo(),
                const Spacer(),
                GIconButton(
                  icon: LucideIcons.settings,
                  size: 18,
                  tooltip: 'Настройки',
                  onPressed: () => navigateTo(AppSection.account),
                ),
                const SizedBox(width: 8),
                const AccountMenuButton(size: 30),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RootBucket extends StatelessWidget {
  const _RootBucket({required this.root});

  final AppSection root;

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final activeRoot = currentRootSignal();
        final stack = rootStacksSignal()[root] ?? [NavState(root)];
        final isVisible = activeRoot == root;

        return Offstage(
          offstage: !isVisible,
          child: TickerMode(
            enabled: isVisible,
            child: Stack(
              children: [
                for (var i = 0; i < stack.length; i++)
                  // Only the top page and the one below stay mounted.
                  if (i >= stack.length - 2)
                    _PageLayer(
                      key: ValueKey('page_${stack[i].section}_${stack[i].id}_$i'),
                      state: stack[i],
                      index: i,
                      isTop: i == stack.length - 1,
                    ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// One page in a tab stack. The top page fades in with a short slide; the
/// page below stays mounted (instant back) but hidden and inert.
class _PageLayer extends StatelessWidget {
  const _PageLayer({
    required this.state,
    required this.index,
    required this.isTop,
    super.key,
  });

  final NavState state;
  final int index;
  final bool isTop;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !isTop,
      child: ExcludeFocus(
        excluding: !isTop,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: isTop ? 0 : 1, end: isTop ? 1 : 0),
          duration: GDurations.medium,
          curve: GCurves.emphasized,
          builder: (context, t, child) => Opacity(
            opacity: t,
            child: Transform.translate(offset: Offset(0, (1 - t) * 8), child: child),
          ),
          child: KeyedSubtree(
            key: PageStorageKey('scroll_${state.section}_${state.id}_$index'),
            child: _sectionView(state),
          ),
        ),
      ),
    );
  }

  Widget _sectionView(NavState state) {
    switch (state.section) {
      case AppSection.home:
        return const HomeView();
      case AppSection.wave:
        return const WaveView();
      case AppSection.search:
        return const SearchView();
      case AppSection.liked:
      case AppSection.playlists:
        return const LibraryView();
      case AppSection.album:
        return AlbumView(albumId: state.id);
      case AppSection.artist:
        return ArtistView(artistId: state.id);
      case AppSection.playlist:
        final parts = state.id?.split(':') ?? const <String>[];
        return PlaylistView(
          uid: parts.isNotEmpty ? parts[0] : null,
          kind: parts.length > 1 ? parts[1] : null,
        );
      case AppSection.account:
        return const SettingsView();
      case AppSection.yandexId:
        return const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: YandexIdView(),
        );
    }
  }
}

/// Synced lyrics over the content area (toggled from the player).
class _LyricsOverlay extends StatelessWidget {
  const _LyricsOverlay();

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final trackId = currentTrackIdSignal();
        final visible = showLyricsSignal() && trackId != null;
        return IgnorePointer(
          ignoring: !visible,
          child: AnimatedOpacity(
            duration: GDurations.medium,
            curve: GCurves.standard,
            opacity: visible ? 1 : 0,
            child: visible
                ? ColoredBox(
                    color: GColors.background,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: GPageFrame(
                            maxWidth: 960,
                            padding: const EdgeInsets.fromLTRB(32, 8, 32, 0),
                            child: LyricsWidget(trackId: trackId, visible: visible),
                          ),
                        ),
                        Positioned(
                          top: 8,
                          right: 24,
                          child: GCircleButton(
                            icon: LucideIcons.x,
                            tooltip: 'Закрыть текст',
                            onPressed: () => showLyricsSignal.value = false,
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        );
      },
    );
  }
}
