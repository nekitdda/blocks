import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:window_manager/window_manager.dart';
import 'package:youmuz/src/app/init.dart';
import 'package:youmuz/src/app/system_tray.dart';
import 'package:youmuz/src/app/window_placement.dart';
import 'package:youmuz/src/features/auth/views/auth/auth_screens.dart';
import 'package:youmuz/src/features/core/providers/navigation_provider.dart';
import 'package:youmuz/src/features/core/providers/notification_provider.dart';
import 'package:youmuz/src/features/core/services/global_hotkey_service.dart';
import 'package:youmuz/src/ui/ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  final appInitialization = AppInit.initialize();
  final windowInitialization = isDesktop
      ? windowManager.ensureInitialized()
      : Future<void>.value();

  runApp(const MyApp());

  await Future.wait([appInitialization, windowInitialization]);

  Future<void>? windowReady;
  if (isDesktop) {
    final isCustom = customTitlebarSignal.value;
    customTitlebarSignal.value = isCustom;

    final savedBounds = await WindowPlacement.loadBounds();
    final savedMaximized = await WindowPlacement.loadMaximized();
    // On Wayland the compositor owns positioning; on other platforms the
    // saved monitor may be gone — in both cases restore size and center.
    final restoreBounds =
        savedBounds != null &&
            !WindowPlacement.isWayland &&
            await WindowPlacement.isPositionVisible(savedBounds)
        ? savedBounds
        : null;

    final windowOptions = WindowOptions(
      size: savedBounds?.size ?? WindowPlacement.defaultSize,
      minimumSize: WindowPlacement.minimumSize,
      center: restoreBounds == null,
      backgroundColor: GColors.background,
      skipTaskbar: false,
      titleBarStyle: isCustom ? TitleBarStyle.hidden : TitleBarStyle.normal,
    );
    windowReady = windowManager.waitUntilReadyToShow(windowOptions, () async {
      if (restoreBounds != null) {
        await windowManager.setBounds(restoreBounds);
      }
      if (savedMaximized) {
        await windowManager.maximize();
      }
      await windowManager.show();
      await windowManager.focus();
      WindowPlacement.track();
    });
  }

  // Defer optional desktop integrations until Flutter has rendered its first frame.
  await WidgetsBinding.instance.endOfFrame;

  if (windowReady != null) {
    await windowReady;
    await SystemTrayManager.instance.initialize();
    await GlobalHotkeyService.initialize();
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  static final ThemeData _theme = buildGraphiteTheme();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'YouMuz',
      debugShowCheckedModeBanner: false,
      theme: _theme,
      darkTheme: _theme,
      themeMode: ThemeMode.dark,
      scrollBehavior: const GraphiteScrollBehavior(),
      builder: (context, child) => GlobalNotificationListener(
        child: child ?? const SizedBox.shrink(),
      ),
      home: const RootScreen(),
    );
  }
}
