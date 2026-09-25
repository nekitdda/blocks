import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Interaction state of a custom control (`hover:`, `active:`, `focus-visible:`).
@immutable
class GStates {
  const GStates({
    this.hovered = false,
    this.pressed = false,
    this.focused = false,
    this.enabled = true,
  });

  final bool hovered;
  final bool pressed;

  /// Keyboard focus (focus ring), not pointer focus.
  final bool focused;
  final bool enabled;

  bool get highlighted => hovered || focused;
}

/// Pointer, keyboard (Enter/Space) and semantics handling for controls that
/// draw their own states.
class GPressable extends StatefulWidget {
  const GPressable({
    required this.builder,
    super.key,
    this.onTap,
    this.onDoubleTap,
    this.onSecondaryTapUp,
    this.onLongPressStart,
    this.cursor,
    this.focusable = true,
    this.semanticLabel,
    this.tooltip,
    this.selected,
    this.focusNode,
    this.autofocus = false,
    this.onHover,
  });

  final Widget Function(BuildContext context, GStates states) builder;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final void Function(TapUpDetails details)? onSecondaryTapUp;
  final void Function(LongPressStartDetails details)? onLongPressStart;
  final MouseCursor? cursor;
  final bool focusable;
  final String? semanticLabel;
  final String? tooltip;
  final bool? selected;
  final FocusNode? focusNode;
  final bool autofocus;
  final ValueChanged<bool>? onHover;

  @override
  State<GPressable> createState() => _GPressableState();
}

class _GPressableState extends State<GPressable> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  /// Used when [GPressable.focusable] is false: keeps hover handling (which
  /// `FocusableActionDetector.enabled` would also switch off) while staying
  /// out of keyboard traversal.
  FocusNode? _inertFocus;

  FocusNode? get _focusNode {
    if (widget.focusable) return widget.focusNode;
    return _inertFocus ??= FocusNode(canRequestFocus: false, skipTraversal: true);
  }

  @override
  void dispose() {
    _inertFocus?.dispose();
    super.dispose();
  }

  bool get _enabled =>
      widget.onTap != null ||
      widget.onDoubleTap != null ||
      widget.onSecondaryTapUp != null ||
      widget.onLongPressStart != null;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _enabled;
    Widget child = widget.builder(
      context,
      GStates(
        hovered: _hovered && enabled,
        pressed: _pressed && enabled,
        focused: _focused && enabled,
        enabled: enabled,
      ),
    );

    child = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap == null ? null : (_) => _setPressed(true),
      onTapUp: widget.onTap == null ? null : (_) => _setPressed(false),
      onTapCancel: widget.onTap == null ? null : () => _setPressed(false),
      onTap: widget.onTap,
      onDoubleTap: widget.onDoubleTap,
      onSecondaryTapUp: widget.onSecondaryTapUp,
      onLongPressStart: widget.onLongPressStart,
      child: child,
    );

    child = FocusableActionDetector(
      enabled: enabled,
      focusNode: _focusNode,
      autofocus: widget.autofocus && widget.focusable,
      mouseCursor: enabled
          ? (widget.cursor ?? SystemMouseCursors.click)
          : MouseCursor.defer,
      onShowHoverHighlight: (value) {
        if (_hovered != value) {
          setState(() => _hovered = value);
          widget.onHover?.call(value);
        }
      },
      onShowFocusHighlight: (value) {
        if (_focused != value) setState(() => _focused = value);
      },
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap?.call();
            return null;
          },
        ),
      },
      child: child,
    );

    child = Semantics(
      button: widget.onTap != null,
      enabled: enabled,
      selected: widget.selected,
      label: widget.semanticLabel,
      child: child,
    );

    if (widget.tooltip != null && widget.tooltip!.isNotEmpty) {
      child = Tooltip(message: widget.tooltip, child: child);
    }
    return child;
  }
}

/// `active:scale-95`.
class GPressScale extends StatelessWidget {
  const GPressScale({required this.pressed, required this.child, super.key, this.scale = 0.95});

  final bool pressed;
  final double scale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: pressed ? scale : 1,
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeOut,
      child: child,
    );
  }
}

/// 1px amber focus ring (`focus-visible:ring-1 ring-ring`) around [child].
class GFocusRing extends StatelessWidget {
  const GFocusRing({
    required this.visible,
    required this.child,
    super.key,
    this.radius = 999,
  });

  final bool visible;
  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius + 2),
        border: Border.all(
          color: visible ? const Color(0xFFD9A441) : const Color(0x00000000),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(1),
      child: child,
    );
  }
}
