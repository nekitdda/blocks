import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:youmuz/src/ui/tokens.dart';
import 'package:youmuz/src/ui/widgets/buttons.dart';

/// Modal with the Graphite entrance: fade plus a slight scale-up.
Future<T?> showGDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: GColors.scrim,
    transitionDuration: GDurations.medium,
    pageBuilder: (context, _, _) => SafeArea(child: Builder(builder: builder)),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(parent: animation, curve: GCurves.emphasized);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Dialog panel: `bg-card rounded-3xl border`, title `text-lg font-semibold`,
/// description `text-sm text-muted-foreground`, actions on the right.
class GDialog extends StatelessWidget {
  const GDialog({
    super.key,
    this.title,
    this.description,
    this.content,
    this.actions = const [],
    this.width = 440,
    this.padding = const EdgeInsets.all(24),
    this.showClose = true,
    this.maxHeightFactor = 0.86,
  });

  final String? title;
  final String? description;
  final Widget? content;
  final List<Widget> actions;
  final double width;
  final EdgeInsets padding;
  final bool showClose;
  final double maxHeightFactor;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Center(
      child: Material(
        type: MaterialType.transparency,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: width.clamp(0, size.width - 32),
            maxHeight: size.height * maxHeightFactor,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: GColors.card,
              borderRadius: BorderRadius.circular(GRadius.x3l),
              border: Border.all(color: GColors.border),
              boxShadow: const [
                BoxShadow(color: Color(0x66000000), blurRadius: 40, offset: Offset(0, 16)),
              ],
            ),
            padding: padding,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (title != null || showClose)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: title == null
                            ? const SizedBox.shrink()
                            : Text(title!, style: GText.lg(weight: GText.semibold)),
                      ),
                      if (showClose)
                        Transform.translate(
                          offset: const Offset(8, -6),
                          child: GIconButton(
                            icon: LucideIcons.x,
                            tooltip: 'Закрыть',
                            onPressed: () => Navigator.of(context).maybePop(),
                          ),
                        ),
                    ],
                  ),
                if (description != null) ...[
                  const SizedBox(height: 6),
                  Text(description!, style: GText.sm(color: GColors.mutedForeground)),
                ],
                if (content != null) ...[
                  SizedBox(height: title != null || description != null ? 20 : 0),
                  Flexible(child: content!),
                ],
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: actions,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Yes/no confirmation. Resolves to `true` when confirmed.
Future<bool> showGConfirm(
  BuildContext context, {
  required String title,
  String? message,
  String confirmLabel = 'Подтвердить',
  String cancelLabel = 'Отмена',
  bool destructive = false,
}) async {
  final result = await showGDialog<bool>(
    context,
    builder: (context) => GDialog(
      title: title,
      description: message,
      width: 400,
      actions: [
        GButton(
          label: cancelLabel,
          variant: GButtonVariant.secondary,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        GButton(
          label: confirmLabel,
          variant: destructive ? GButtonVariant.destructive : GButtonVariant.primary,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Single-line text prompt (rename, create). Resolves to the entered text.
Future<String?> showGPrompt(
  BuildContext context, {
  required String title,
  String? initialValue,
  String? placeholder,
  String confirmLabel = 'Сохранить',
}) {
  final controller = TextEditingController(text: initialValue);
  return showGDialog<String>(
    context,
    builder: (context) {
      void submit() {
        final value = controller.text.trim();
        if (value.isNotEmpty) Navigator.of(context).pop(value);
      }

      return GDialog(
        title: title,
        width: 420,
        content: TextField(
          controller: controller,
          autofocus: true,
          style: GText.sm(),
          decoration: InputDecoration(hintText: placeholder),
          onSubmitted: (_) => submit(),
        ),
        actions: [
          GButton(
            label: 'Отмена',
            variant: GButtonVariant.secondary,
            onPressed: () => Navigator.of(context).pop(),
          ),
          GButton(label: confirmLabel, onPressed: submit),
        ],
      );
    },
  ).whenComplete(controller.dispose);
}
