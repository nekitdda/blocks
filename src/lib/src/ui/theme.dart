import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:youmuz/src/ui/tokens.dart';

/// Material theme mapped onto the Graphite tokens, so stock widgets (text
/// fields, switches, sliders, tooltips, menus, scrollbars) match the custom ones.
ThemeData buildGraphiteTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: GColors.foreground,
    onPrimary: GColors.background,
    primaryContainer: GColors.secondary,
    onPrimaryContainer: GColors.foreground,
    secondary: GColors.brand,
    onSecondary: GColors.brandForeground,
    secondaryContainer: GColors.accent,
    onSecondaryContainer: GColors.foreground,
    tertiary: GColors.brand,
    onTertiary: GColors.brandForeground,
    error: GColors.destructive,
    onError: GColors.background,
    surface: GColors.background,
    onSurface: GColors.foreground,
    onSurfaceVariant: GColors.mutedForeground,
    surfaceContainerLowest: GColors.background,
    surfaceContainerLow: GColors.muted,
    surfaceContainer: GColors.card,
    surfaceContainerHigh: GColors.secondary,
    surfaceContainerHighest: GColors.accent,
    outline: GColors.border,
    outlineVariant: GColors.border,
    shadow: Color(0xFF000000),
    scrim: GColors.scrim,
    inverseSurface: GColors.foreground,
    onInverseSurface: GColors.background,
    inversePrimary: GColors.background,
    surfaceTint: Colors.transparent,
  );

  final textTheme = TextTheme(
    displayLarge: GText.display(72),
    displayMedium: GText.display(48),
    displaySmall: GText.headline(36),
    headlineLarge: GText.headline(30),
    headlineMedium: GText.headline(24),
    headlineSmall: GText.sectionTitle(),
    titleLarge: GText.lg(weight: GText.semibold),
    titleMedium: GText.base(weight: GText.medium),
    titleSmall: GText.sm(weight: GText.medium),
    bodyLarge: GText.base(),
    bodyMedium: GText.sm(),
    bodySmall: GText.xs(color: GColors.mutedForeground),
    labelLarge: GText.sm(weight: GText.medium),
    labelMedium: GText.xs(weight: GText.medium),
    labelSmall: GText.style(11, lineHeight: 16, color: GColors.mutedForeground),
  );

  final inputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(GRadius.xl),
    borderSide: BorderSide.none,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    fontFamily: GFonts.sans,
    textTheme: textTheme,
    primaryTextTheme: textTheme,
    scaffoldBackgroundColor: GColors.background,
    canvasColor: GColors.background,
    cardColor: GColors.card,
    dividerColor: GColors.border,
    disabledColor: GColors.mutedForeground,
    hintColor: GColors.mutedForeground,
    splashFactory: NoSplash.splashFactory,
    splashColor: Colors.transparent,
    highlightColor: Colors.transparent,
    hoverColor: GColors.secondary,
    focusColor: GColors.secondary,
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    iconTheme: const IconThemeData(color: GColors.mutedForeground, size: 16),
    dividerTheme: const DividerThemeData(color: GColors.border, thickness: 1, space: 1),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: GColors.brand,
      selectionColor: GColors.brand.withValues(alpha: 0.3),
      selectionHandleColor: GColors.brand,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: GColors.secondary,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      hintStyle: GText.sm(color: GColors.mutedForeground),
      labelStyle: GText.sm(color: GColors.mutedForeground),
      border: inputBorder,
      enabledBorder: inputBorder,
      focusedBorder: inputBorder.copyWith(
        borderSide: const BorderSide(color: GColors.ring),
      ),
      errorBorder: inputBorder.copyWith(
        borderSide: const BorderSide(color: GColors.destructive),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? GColors.brandForeground : GColors.mutedForeground,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? GColors.brand : GColors.accent,
      ),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      overlayColor: WidgetStateProperty.all(Colors.transparent),
      thumbIcon: WidgetStateProperty.all(null),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? GColors.brand : Colors.transparent,
      ),
      checkColor: WidgetStateProperty.all(GColors.brandForeground),
      side: const BorderSide(color: GColors.mutedForeground, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      overlayColor: WidgetStateProperty.all(Colors.transparent),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? GColors.brand : GColors.mutedForeground,
      ),
      overlayColor: WidgetStateProperty.all(Colors.transparent),
    ),
    sliderTheme: SliderThemeData(
      trackHeight: 4,
      activeTrackColor: GColors.foreground,
      inactiveTrackColor: GColors.foreground20,
      thumbColor: GColors.foreground,
      overlayColor: Colors.transparent,
      overlayShape: SliderComponentShape.noOverlay,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6, elevation: 0, pressedElevation: 0),
      trackShape: const RoundedRectSliderTrackShape(),
      valueIndicatorColor: GColors.popover,
      valueIndicatorTextStyle: GText.xs(),
      showValueIndicator: ShowValueIndicator.onDrag,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: GColors.brand,
      linearTrackColor: GColors.accent,
      circularTrackColor: Colors.transparent,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: GColors.popover,
        borderRadius: BorderRadius.circular(GRadius.md),
        border: Border.all(color: GColors.border),
      ),
      textStyle: GText.xs(),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      waitDuration: const Duration(milliseconds: 500),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.hovered) ? 8 : 6,
      ),
      radius: const Radius.circular(GRadius.full),
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.dragged) || s.contains(WidgetState.hovered)
            ? GColors.mutedForeground.withValues(alpha: 0.6)
            : GColors.border,
      ),
      trackColor: WidgetStateProperty.all(Colors.transparent),
      crossAxisMargin: 2,
      mainAxisMargin: 4,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: GColors.card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      barrierColor: GColors.scrim,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GRadius.x3l),
        side: const BorderSide(color: GColors.border),
      ),
      titleTextStyle: GText.lg(weight: GText.semibold),
      contentTextStyle: GText.sm(color: GColors.mutedForeground),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: GColors.popover,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GRadius.xl),
        side: const BorderSide(color: GColors.border),
      ),
      textStyle: GText.sm(),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStateProperty.all(GColors.popover),
        surfaceTintColor: WidgetStateProperty.all(Colors.transparent),
        elevation: WidgetStateProperty.all(0),
        shadowColor: WidgetStateProperty.all(Colors.transparent),
        padding: WidgetStateProperty.all(const EdgeInsets.all(6)),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(GRadius.xl),
            side: const BorderSide(color: GColors.border),
          ),
        ),
      ),
    ),
    menuButtonTheme: MenuButtonThemeData(style: graphiteMenuItemStyle()),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: GColors.card,
      surfaceTintColor: Colors.transparent,
      modalBarrierColor: GColors.scrim,
      elevation: 0,
      showDragHandle: true,
      dragHandleColor: GColors.border,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(GRadius.x3l)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: GColors.popover,
      contentTextStyle: GText.sm(),
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GRadius.xl),
        side: const BorderSide(color: GColors.border),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: GColors.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: GText.base(weight: GText.semibold),
      iconTheme: const IconThemeData(color: GColors.foreground, size: 20),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
      },
    ),
  );
}

/// Menu rows: `h-9 px-3 rounded-lg text-sm`, hover `bg-secondary`.
ButtonStyle graphiteMenuItemStyle({Color foreground = GColors.foreground}) {
  return ButtonStyle(
    minimumSize: WidgetStateProperty.all(const Size(180, 36)),
    padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 12)),
    shape: WidgetStateProperty.all(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(GRadius.md)),
    ),
    backgroundColor: WidgetStateProperty.resolveWith(
      (s) => s.contains(WidgetState.hovered) ||
              s.contains(WidgetState.focused) ||
              s.contains(WidgetState.pressed)
          ? GColors.secondary
          : Colors.transparent,
    ),
    foregroundColor: WidgetStateProperty.resolveWith(
      (s) => s.contains(WidgetState.disabled) ? GColors.mutedForeground : foreground,
    ),
    iconColor: WidgetStateProperty.resolveWith(
      (s) => s.contains(WidgetState.hovered) || s.contains(WidgetState.focused)
          ? foreground
          : (foreground == GColors.foreground ? GColors.mutedForeground : foreground),
    ),
    iconSize: WidgetStateProperty.all(16),
    overlayColor: WidgetStateProperty.all(Colors.transparent),
    textStyle: WidgetStateProperty.all(GText.sm()),
    mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
  );
}

/// No overscroll glow, drag-to-scroll with mouse where touch is expected.
class GraphiteScrollBehavior extends MaterialScrollBehavior {
  const GraphiteScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.stylus,
    PointerDeviceKind.trackpad,
  };

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}
