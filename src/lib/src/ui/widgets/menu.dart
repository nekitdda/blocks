import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:youmuz/src/ui/theme.dart';
import 'package:youmuz/src/ui/tokens.dart';

/// Entry of a [GMenu]. With [children] it opens a submenu.
class GMenuItem {
  const GMenuItem({
    required this.label,
    this.icon,
    this.leading,
    this.onSelected,
    this.children,
    this.destructive = false,
    this.checked = false,
    this.enabled = true,
    this.trailing,
  });

  const GMenuItem.divider()
    : label = '',
      icon = null,
      leading = null,
      onSelected = null,
      children = null,
      destructive = false,
      checked = false,
      enabled = false,
      trailing = null;

  final String label;
  final IconData? icon;
  final Widget? leading;
  final VoidCallback? onSelected;
  final List<GMenuItem>? children;
  final bool destructive;
  final bool checked;
  final bool enabled;
  final String? trailing;

  bool get isDivider => label.isEmpty && children == null && onSelected == null && icon == null;
}

List<Widget> buildGMenuChildren(List<GMenuItem> items) {
  return [
    for (final item in items)
      if (item.isDivider)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 4),
          child: SizedBox(height: 1, child: ColoredBox(color: GColors.border)),
        )
      else if (item.children != null)
        SubmenuButton(
          style: graphiteMenuItemStyle(),
          menuStyle: const MenuStyle(),
          leadingIcon: _leading(item),
          trailingIcon: const Icon(LucideIcons.chevronRight, size: 14),
          menuChildren: item.children!.isEmpty
              ? [
                  MenuItemButton(
                    style: graphiteMenuItemStyle(),
                    child: Text('Пусто', style: GText.sm(color: GColors.mutedForeground)),
                  ),
                ]
              : buildGMenuChildren(item.children!),
          child: Text(item.label, maxLines: 1, overflow: TextOverflow.ellipsis),
        )
      else
        MenuItemButton(
          style: graphiteMenuItemStyle(
            foreground: item.destructive ? GColors.destructive : GColors.foreground,
          ),
          leadingIcon: _leading(item),
          trailingIcon: item.checked
              ? const Icon(LucideIcons.check, size: 14, color: GColors.brand)
              : (item.trailing != null
                    ? Text(item.trailing!, style: GText.xs(color: GColors.mutedForeground))
                    : null),
          onPressed: item.enabled ? item.onSelected : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: Text(item.label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
  ];
}

Widget? _leading(GMenuItem item) {
  if (item.leading != null) return item.leading;
  if (item.icon != null) return Icon(item.icon, size: 16);
  return null;
}

/// Dropdown / context menu on a Material [MenuAnchor] (keyboard navigation,
/// submenus) styled as a Graphite popover.
class GMenu extends StatefulWidget {
  const GMenu({
    required this.items,
    required this.builder,
    super.key,
    this.alignmentOffset = const Offset(0, 6),
    this.onOpen,
    this.onClose,
  });

  /// Built when the menu opens, so the entries reflect current state.
  final List<GMenuItem> Function() items;

  /// Trigger; call `menu.open()` (or `menu.open(position: ...)`).
  final Widget Function(BuildContext context, GMenuHandle menu) builder;
  final Offset alignmentOffset;
  final VoidCallback? onOpen;
  final VoidCallback? onClose;

  @override
  State<GMenu> createState() => _GMenuState();
}

/// Opens/closes a [GMenu] from its trigger.
class GMenuHandle {
  GMenuHandle._(this._state);

  final _GMenuState _state;

  bool get isOpen => _state._controller.isOpen;

  void open({Offset? position}) => _state._open(position);

  void close() => _state._controller.close();
}

class _GMenuState extends State<GMenu> {
  final MenuController _controller = MenuController();
  late final GMenuHandle _handle = GMenuHandle._(this);
  List<GMenuItem> _items = const [];

  void _open(Offset? position) {
    // Entries are built right before opening so they reflect current state.
    setState(() => _items = widget.items());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.open(position: position);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      controller: _controller,
      alignmentOffset: widget.alignmentOffset,
      consumeOutsideTap: true,
      onOpen: widget.onOpen,
      onClose: widget.onClose,
      menuChildren: buildGMenuChildren(_items),
      builder: (context, _, _) => widget.builder(context, _handle),
    );
  }
}

/// Opens [items] at the pointer on right click and on long press.
class GContextMenuRegion extends StatelessWidget {
  const GContextMenuRegion({required this.items, required this.child, super.key, this.onOpen, this.onClose});

  final List<GMenuItem> Function() items;
  final Widget child;
  final VoidCallback? onOpen;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return GMenu(
      items: items,
      alignmentOffset: Offset.zero,
      onOpen: onOpen,
      onClose: onClose,
      builder: (context, menu) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onSecondaryTapUp: (d) => menu.open(position: d.localPosition),
        onLongPressStart: (d) => menu.open(position: d.localPosition),
        child: child,
      ),
    );
  }
}
