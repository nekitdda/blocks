import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:youmuz/src/ui/tokens.dart';
import 'package:youmuz/src/ui/widgets/buttons.dart';

/// Search field (`h-9 rounded-full bg-secondary px-4 text-sm`, amber ring
/// while focused).
class GSearchField extends StatefulWidget {
  const GSearchField({
    super.key,
    this.controller,
    this.focusNode,
    this.placeholder = 'Трек, альбом, исполнитель',
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.autofocus = false,
    this.height = 36,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String placeholder;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onTap;
  final bool autofocus;
  final double height;

  @override
  State<GSearchField> createState() => _GSearchFieldState();
}

class _GSearchFieldState extends State<GSearchField> {
  late final TextEditingController _controller =
      widget.controller ?? TextEditingController();
  late final FocusNode _focus = widget.focusNode ?? FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_rebuild);
    _controller.addListener(_rebuild);
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _focus.removeListener(_rebuild);
    _controller.removeListener(_rebuild);
    if (widget.controller == null) _controller.dispose();
    if (widget.focusNode == null) _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focus.hasFocus;
    return AnimatedContainer(
      duration: GDurations.fast,
      height: widget.height,
      padding: const EdgeInsets.only(left: 16, right: 6),
      decoration: BoxDecoration(
        color: GColors.secondary,
        borderRadius: BorderRadius.circular(GRadius.full),
        border: Border.all(color: focused ? GColors.ring : const Color(0x00000000)),
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.search, size: 16, color: GColors.mutedForeground),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              autofocus: widget.autofocus,
              onChanged: widget.onChanged,
              onSubmitted: widget.onSubmitted,
              onTap: widget.onTap,
              textInputAction: TextInputAction.search,
              textAlignVertical: TextAlignVertical.center,
              // Onest's ascent is tall; a unit line height keeps the text
              // optically centered in the pill.
              style: GText.sm().copyWith(height: 1.15),
              strutStyle: const StrutStyle(fontSize: 14, height: 1.15, forceStrutHeight: true),
              cursorColor: GColors.brand,
              cursorHeight: 16,
              decoration: InputDecoration(
                isCollapsed: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: widget.placeholder,
                hintStyle: GText.sm(color: GColors.mutedForeground).copyWith(height: 1.15),
              ),
            ),
          ),
          if (_controller.text.isNotEmpty)
            GIconButton(
              icon: LucideIcons.x,
              size: 14,
              padding: 6,
              tooltip: 'Очистить',
              onPressed: () {
                _controller.clear();
                widget.onChanged?.call('');
                _focus.requestFocus();
              },
            )
          else
            const SizedBox(width: 10),
        ],
      ),
    );
  }
}

/// Text input (`h-10 rounded-xl bg-secondary`) with an optional label.
class GTextField extends StatelessWidget {
  const GTextField({
    super.key,
    this.controller,
    this.label,
    this.placeholder,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.obscure = false,
    this.trailing,
    this.errorText,
    this.maxLines = 1,
    this.focusNode,
  });

  final TextEditingController? controller;
  final String? label;
  final String? placeholder;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final bool obscure;
  final Widget? trailing;
  final String? errorText;
  final int maxLines;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          Text(label!, style: GText.xs(color: GColors.mutedForeground)),
          const SizedBox(height: 8),
        ],
        TextField(
          controller: controller,
          focusNode: focusNode,
          autofocus: autofocus,
          obscureText: obscure,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          maxLines: maxLines,
          style: GText.sm(),
          decoration: InputDecoration(
            hintText: placeholder,
            suffixIcon: trailing,
            suffixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            errorText: errorText,
            errorStyle: GText.xs(color: GColors.destructive),
          ),
        ),
      ],
    );
  }
}
