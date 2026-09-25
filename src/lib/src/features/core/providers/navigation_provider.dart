import 'package:flutter/foundation.dart';
import 'package:signals_flutter/signals_flutter.dart';

enum AppSection {
  home,
  search,
  liked,
  playlists,
  album,
  artist,
  wave,
  playlist,
  account,
  yandexId,
}

@immutable
class NavState {
  final AppSection section;
  final String? id;

  const NavState(this.section, [this.id]);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NavState &&
          runtimeType == other.runtimeType &&
          section == other.section &&
          id == other.id;

  @override
  int get hashCode => section.hashCode ^ (id?.hashCode ?? 0);
}

/// Root sections (tabs). `playlists` opens inside the collection tab.
const List<AppSection> rootSections = [
  AppSection.home,
  AppSection.wave,
  AppSection.liked,
  AppSection.search,
  AppSection.account,
];

/// Currently active root tab
final FlutterSignal<AppSection> currentRootSignal = signal<AppSection>(
  AppSection.home,
);

/// Collection tab to show when the collection is opened through
/// `AppSection.liked` (tracks) or `AppSection.playlists`.
final FlutterSignal<AppSection> librarySectionRequestSignal = signal<AppSection>(
  AppSection.liked,
);

/// Navigation stacks for each tab
final FlutterSignal<Map<AppSection, List<NavState>>> rootStacksSignal =
    signal<Map<AppSection, List<NavState>>>({
      for (var root in rootSections) root: [NavState(root)],
    });

/// Navbar auto-hide setting
final FlutterSignal<bool> autoHideNavbarSignal = signal<bool>(
  false,
);

/// Custom titlebar setting
final FlutterSignal<bool> customTitlebarSignal = signal<bool>(
  true,
);

/// Close to tray setting
final FlutterSignal<bool> closeToTraySignal = signal<bool>(
  true,
);

/// Computed current navigation stack
final FlutterComputed<List<NavState>> navStackSignal = computed(
  () =>
      rootStacksSignal()[currentRootSignal()] ??
      [NavState(currentRootSignal())],
  options: const ComputedOptions(name: 'navStackSignal'),
);

/// Back button availability signal
final FlutterComputed<bool> canGoBackSignal = computed(
  () => navStackSignal().length > 1,
  options: const ComputedOptions(name: 'canGoBackSignal'),
);

/// Top of the active tab stack
final FlutterComputed<NavState> currentNavStateSignal = computed(
  () => navStackSignal().last,
  options: const ComputedOptions(name: 'currentNavStateSignal'),
);

/// Navigates to a new page
void navigateTo(AppSection section, [String? id]) {
  if (id == null &&
      (section == AppSection.playlists || section == AppSection.liked)) {
    librarySectionRequestSignal.value = section;
  }
  final target = section == AppSection.playlists && id == null
      ? AppSection.liked
      : section;
  final newState = NavState(target, id);
  final activeRoot = currentRootSignal.value;

  // Handle root section clicks
  if (rootSections.contains(target) && id == null) {
    if (activeRoot == target) {
      // Reset stack to root if already active
      final newStacks = Map<AppSection, List<NavState>>.from(
        rootStacksSignal.value,
      );
      newStacks[target] = [NavState(target)];
      rootStacksSignal.value = newStacks;
    } else {
      currentRootSignal.value = target;
    }
    return;
  }

  // Regular push transition
  final currentStack =
      rootStacksSignal.value[activeRoot] ?? [NavState(activeRoot)];
  if (currentStack.last == newState) return;

  final newStacks = Map<AppSection, List<NavState>>.from(
    rootStacksSignal.value,
  );
  newStacks[activeRoot] = List.unmodifiable([...currentStack, newState]);
  rootStacksSignal.value = newStacks;
}

/// Returns to the previous page (Pop)
void goBack() {
  final activeRoot = currentRootSignal.value;
  final currentStack = rootStacksSignal.value[activeRoot] ?? [];
  if (currentStack.length <= 1) return;

  final newStacks = Map<AppSection, List<NavState>>.from(
    rootStacksSignal.value,
  );
  newStacks[activeRoot] = List.unmodifiable(
    currentStack.sublist(0, currentStack.length - 1),
  );
  rootStacksSignal.value = newStacks;
}

void setSection(AppSection section) => navigateTo(section);

/// Back to the home tab with every tab stack emptied. Used when the account
/// changes: open pages (a playlist, an album) belong to the previous session.
void resetNavigation() {
  rootStacksSignal.value = {
    for (final root in rootSections) root: [NavState(root)],
  };
  currentRootSignal.value = AppSection.home;
}
