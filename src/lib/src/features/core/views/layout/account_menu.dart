import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:youmuz/src/features/auth/providers/auth_provider.dart';
import 'package:youmuz/src/features/auth/views/add_account.dart';
import 'package:youmuz/src/features/auth/views/yandex_id_view.dart';
import 'package:youmuz/src/features/core/providers/navigation_provider.dart';
import 'package:youmuz/src/rust/api/models.dart';
import 'package:youmuz/src/ui/ui.dart';

/// Header avatar with the account switcher (Telegram-style): the active
/// account, every other signed-in account one click away, "add account",
/// account management, settings and sign-out.
class AccountMenuButton extends StatelessWidget {
  const AccountMenuButton({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final active = activeStoredAccountSignal();
        final profile = accountSignal();
        // The open session's profile is the freshest source for its name.
        final name = profile != null
            ? (profile.displayName ?? profile.fullName ?? profile.login)
            : (active != null ? accountDisplayName(active) : 'Аккаунт');
        final avatarUrl = profile?.avatarUrl ?? active?.avatarUrl;
        final total = accountsSignal().length;

        return GMenu(
          alignmentOffset: const Offset(0, 8),
          items: () => _items(context),
          builder: (context, menu) => GPressable(
            onTap: () => menu.isOpen ? menu.close() : menu.open(),
            tooltip: 'Аккаунты',
            semanticLabel: 'Профиль: $name',
            builder: (context, s) => AnimatedContainer(
              duration: GDurations.fast,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: s.focused
                      ? GColors.ring
                      : (s.hovered ? GColors.border : const Color(0x00000000)),
                ),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  GAvatar(name: name, url: avatarUrl, size: size),
                  if (total > 1)
                    Positioned(
                      right: -3,
                      bottom: -3,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                        decoration: BoxDecoration(
                          color: GColors.secondary,
                          borderRadius: BorderRadius.circular(GRadius.full),
                          border: Border.all(color: GColors.background, width: 2),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '$total',
                          style: GText.style(9, lineHeight: 12, weight: GText.semibold),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  List<GMenuItem> _items(BuildContext context) {
    final accounts = accountsSignal.value;
    final activeUid = activeAccountUidSignal.value;
    final busy = sessionTransitionSignal.value;
    final profile = accountSignal.value;
    StoredAccountDto? active;
    for (final a in accounts) {
      if (a.uid == activeUid) active = a;
    }
    final others = accounts.where((a) => a.uid != activeUid).toList();

    return [
      GMenuItem(
        label: active != null ? accountDisplayName(active) : (profile?.login ?? 'Аккаунт'),
        leading: GAvatar(
          name: active != null ? accountDisplayName(active) : (profile?.login ?? '?'),
          url: profile?.avatarUrl ?? active?.avatarUrl,
          size: 24,
        ),
        trailing: (profile?.hasPlus ?? active?.hasPlus ?? false) ? 'Плюс' : null,
        checked: true,
        onSelected: () => setSection(AppSection.account),
      ),
      for (final a in others)
        GMenuItem(
          label: accountDisplayName(a),
          leading: Opacity(
            opacity: a.needsLogin ? 0.5 : 1,
            child: GAvatar(name: accountDisplayName(a), url: a.avatarUrl, size: 24),
          ),
          trailing: a.needsLogin ? 'Войти' : null,
          enabled: !busy,
          onSelected: () {
            if (a.needsLogin) {
              unawaited(showAddAccountFlow(context));
            } else {
              unawaited(switchAccount(a.uid));
            }
          },
        ),
      GMenuItem(
        label: 'Добавить аккаунт',
        icon: LucideIcons.userPlus,
        enabled: !busy,
        onSelected: () => unawaited(showAddAccountFlow(context)),
      ),
      const GMenuItem.divider(),
      GMenuItem(
        label: 'Управление аккаунтом',
        icon: LucideIcons.squareArrowOutUpRight,
        onSelected: () {
          if (Platform.isAndroid) {
            unawaited(
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  fullscreenDialog: true,
                  builder: (_) => const YandexIdView(fullscreen: true),
                ),
              ),
            );
          } else {
            setSection(AppSection.yandexId);
          }
        },
      ),
      GMenuItem(
        label: 'Настройки',
        icon: LucideIcons.settings,
        onSelected: () => setSection(AppSection.account),
      ),
      const GMenuItem.divider(),
      GMenuItem(
        label: 'Выйти из аккаунта',
        icon: LucideIcons.logOut,
        destructive: true,
        enabled: !busy,
        onSelected: () => unawaited(confirmSignOut(context)),
      ),
    ];
  }
}

/// Asks before signing the active account out on this device.
Future<void> confirmSignOut(BuildContext context) async {
  final others = accountsSignal.value.where((a) => !a.isActive && !a.needsLogin).length;
  final ok = await showGConfirm(
    context,
    title: 'Выйти из аккаунта?',
    message: others > 0
        ? 'Аккаунт будет удалён с этого устройства вместе с его локальными данными. Откроется другой ваш аккаунт.'
        : 'Аккаунт будет удалён с этого устройства вместе с его локальными данными.',
    confirmLabel: 'Выйти',
    destructive: true,
  );
  if (ok) await logout();
}

/// Dims the app while one session is closed and the next one opened.
class SessionTransitionOverlay extends StatelessWidget {
  const SessionTransitionOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final busy = sessionTransitionSignal();
        return IgnorePointer(
          ignoring: !busy,
          child: AnimatedOpacity(
            duration: GDurations.medium,
            opacity: busy ? 1 : 0,
            child: ColoredBox(
              color: GColors.background.withValues(alpha: 0.72),
              child: Center(
                child: GCard(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  border: true,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: GColors.brand),
                      ),
                      const SizedBox(width: 12),
                      Text('Переключение аккаунта…', style: GText.sm()),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
