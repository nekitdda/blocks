import 'dart:async';
import 'dart:collection';

import 'package:material_ui/material_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:youmuz/src/ui/ui.dart';

enum AppNotificationLevel { error, warning, success }

class AppNotification {
  final String message;
  final AppNotificationLevel level;
  final DateTime timestamp;

  AppNotification({
    required this.message,
    this.level = AppNotificationLevel.error,
  }) : timestamp = DateTime.now();

  bool get isError => level == AppNotificationLevel.error;
}

final FlutterSignal<AppNotification?> appNotificationSignal =
    signal<AppNotification?>(null);

void showAppError(String message) {
  var msg = message;
  final lowerMsg = message.toLowerCase();
  if (lowerMsg.contains('networkerror') ||
      lowerMsg.contains('network error') ||
      lowerMsg.contains('connection error') ||
      lowerMsg.contains('timed out') ||
      lowerMsg.contains('timeout')) {
    msg = 'Отсутствует подключение к сети. Проверьте интернет-соединение.';
  }
  appNotificationSignal.value = AppNotification(message: msg);
}

void showAppWarning(String message) {
  appNotificationSignal.value = AppNotification(
    message: message,
    level: AppNotificationLevel.warning,
  );
}

void showAppSuccess(String message) {
  appNotificationSignal.value = AppNotification(
    message: message,
    level: AppNotificationLevel.success,
  );
}

/// Shows app notifications as a toast at the top center; notifications
/// arriving while one is visible are queued, not dropped.
class GlobalNotificationListener extends StatefulWidget {
  final Widget child;
  const GlobalNotificationListener({required this.child, super.key});

  @override
  State<GlobalNotificationListener> createState() =>
      _GlobalNotificationListenerState();
}

class _GlobalNotificationListenerState extends State<GlobalNotificationListener>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    duration: GDurations.slow,
    reverseDuration: GDurations.medium,
    vsync: this,
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: GCurves.emphasized,
    reverseCurve: GCurves.standard,
  );
  late final EffectCleanup _notificationEffect;
  AppNotification? _current;
  DateTime? _lastShown;
  final Queue<AppNotification> _pending = Queue();
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    _notificationEffect = effect(() {
      final notif = appNotificationSignal.value;
      if (notif == null) return;
      if (_lastShown != null && notif.timestamp.isBefore(_lastShown!)) return;
      _lastShown = notif.timestamp;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_show(notif));
      });
    });
  }

  @override
  void dispose() {
    _notificationEffect();
    _controller.dispose();
    _pending.clear();
    super.dispose();
  }

  Future<void> _show(AppNotification notif) async {
    if (_showing) {
      _pending.add(notif);
      return;
    }
    _showing = true;
    setState(() => _current = notif);
    await _controller.forward(from: 0);
    await Future<void>.delayed(Duration(seconds: notif.isError ? 5 : 3));
    if (!mounted) return;
    await _controller.reverse();
    if (!mounted) return;
    setState(() => _current = null);
    _showing = false;
    if (_pending.isNotEmpty) unawaited(_show(_pending.removeFirst()));
  }

  @override
  Widget build(BuildContext context) {
    final current = _current;
    return Stack(
      alignment: Alignment.topCenter,
      children: [
        widget.child,
        if (current != null)
          Positioned(
            top: 16 + MediaQuery.paddingOf(context).top,
            left: 16,
            right: 16,
            child: IgnorePointer(
              ignoring: false,
              child: AnimatedBuilder(
                animation: _curve,
                builder: (context, child) => Opacity(
                  opacity: _curve.value,
                  child: Transform.translate(
                    offset: Offset(0, (1 - _curve.value) * -12),
                    child: child,
                  ),
                ),
                child: Center(child: _Toast(notification: current, onClose: () => _controller.reverse())),
              ),
            ),
          ),
      ],
    );
  }
}

class _Toast extends StatelessWidget {
  const _Toast({required this.notification, required this.onClose});

  final AppNotification notification;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (notification.level) {
      AppNotificationLevel.error => (LucideIcons.circleAlert, GColors.destructive),
      AppNotificationLevel.warning => (LucideIcons.triangleAlert, GColors.brand),
      AppNotificationLevel.success => (LucideIcons.circleCheck, GColors.brand),
    };
    return Semantics(
      liveRegion: true,
      child: Material(
        type: MaterialType.transparency,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            decoration: BoxDecoration(
              color: GColors.popover,
              borderRadius: BorderRadius.circular(GRadius.xl),
              border: Border.all(color: GColors.border),
              boxShadow: const [
                BoxShadow(color: Color(0x55000000), blurRadius: 24, offset: Offset(0, 8)),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 12),
                Flexible(child: Text(notification.message, style: GText.sm())),
                const SizedBox(width: 4),
                GIconButton(icon: LucideIcons.x, size: 14, padding: 6, tooltip: 'Закрыть', onPressed: onClose),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
