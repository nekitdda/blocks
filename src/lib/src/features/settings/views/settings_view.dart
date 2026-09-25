import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youmuz/src/features/auth/providers/auth_provider.dart';
import 'package:youmuz/src/features/auth/views/add_account.dart';
import 'package:youmuz/src/features/core/providers/navigation_provider.dart';
import 'package:youmuz/src/features/core/providers/notification_provider.dart';
import 'package:youmuz/src/features/core/services/global_hotkey_service.dart';
import 'package:youmuz/src/features/library/providers/library_provider.dart';
import 'package:youmuz/src/features/settings/views/lyrics_providers_dialog.dart';
import 'package:youmuz/src/features/settings/views/update_dialog.dart';
import 'package:youmuz/src/rust/api/content.dart' as rust;
import 'package:youmuz/src/rust/api/models.dart';
import 'package:youmuz/src/rust/api/simple.dart' as simple;
import 'package:youmuz/src/rust/app/context.dart';
import 'package:youmuz/src/ui/ui.dart';

const _repositoryUrl = 'https://github.com/nekitdda/YouMuz';

const _accountsNote =
    'Каждый аккаунт хранит собственную сессию, медиатеку, историю и настройки '
    'звука (качество, эквалайзер, эффекты, Discord, источники текстов). '
    'Настройки окна, трея, горячих клавиш и громкость общие для устройства.';

const _removeAccountMessage =
    'Аккаунт будет удалён с этого устройства вместе с его локальными данными: '
    'кэшем медиатеки, историей, настройками звука и скачанными треками.';

const _chevron = Icon(
  LucideIcons.chevronRight,
  size: 16,
  color: GColors.mutedForeground,
);

/// `focus-visible:ring-1 ring-ring` for full-width rows.
const _focusRing = BoxDecoration(
  border: Border.fromBorderSide(BorderSide(color: GColors.ring)),
);

bool get _isDesktop =>
    Platform.isWindows || Platform.isLinux || Platform.isMacOS;

String _formatBytes(int bytes) {
  if (bytes <= 0) return '0 Б';
  const suffixes = ['Б', 'КБ', 'МБ', 'ГБ', 'ТБ'];
  var i = 0;
  var size = bytes.toDouble();
  while (size >= 1024 && i < suffixes.length - 1) {
    size /= 1024;
    i++;
  }
  return '${size.toStringAsFixed(1)} ${suffixes[i]}';
}

class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  final _scrollController = ScrollController();
  late final EffectCleanup _disposeSessionEffect;

  // Read from the open session and reloaded whenever the account changes, so
  // one account's values never show up (or get written back) under another.
  AsyncState<String?> _downloadPath = const AsyncLoading();
  AsyncState<int> _cacheSize = const AsyncLoading();
  AsyncState<int> _trackCacheSize = const AsyncLoading();
  AsyncState<bool> _discordRpc = const AsyncLoading();
  AsyncState<bool> _customTitlebar = const AsyncLoading();
  AsyncState<bool> _updateCheck = const AsyncLoading();

  String? _version;
  bool _clearingCache = false;
  bool _clearingTracks = false;

  @override
  void initState() {
    super.initState();
    _disposeSessionEffect = effect(() {
      final ctx = appContextSignal.value;
      untracked(() => _loadSessionValues(ctx));
    });
    unawaited(_loadVersion());
  }

  @override
  void dispose() {
    _disposeSessionEffect();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadVersion() async {
    try {
      final version = await simple.getAppVersion();
      if (mounted) setState(() => _version = version);
    } on Object catch (e) {
      debugPrint('Failed to read the app version: $e');
    }
  }

  void _loadSessionValues(AppContext? ctx) {
    setState(() {
      _downloadPath = const AsyncLoading();
      _cacheSize = const AsyncLoading();
      _trackCacheSize = const AsyncLoading();
      _discordRpc = const AsyncLoading();
      _customTitlebar = const AsyncLoading();
      _updateCheck = const AsyncLoading();
    });
    if (ctx == null) return;
    unawaited(_loadDownloadPath(ctx));
    unawaited(_loadCacheSize(ctx));
    unawaited(_loadTrackCacheSize(ctx));
    unawaited(_loadDiscordRpc(ctx));
    unawaited(_loadCustomTitlebar(ctx));
    unawaited(_loadUpdateCheck(ctx));
  }

  Future<void> _loadDownloadPath(AppContext ctx) => _fetch(
    ctx,
    (c) => rust.getDownloadPath(ctx: c),
    (s) => _downloadPath = s,
  );

  Future<void> _loadCacheSize(AppContext ctx) =>
      _fetch(ctx, (c) => simple.getCacheSize(ctx: c), (s) => _cacheSize = s);

  Future<void> _loadTrackCacheSize(AppContext ctx) => _fetch(
    ctx,
    (c) => simple.getTrackCacheSize(ctx: c),
    (s) => _trackCacheSize = s,
  );

  Future<void> _loadDiscordRpc(AppContext ctx) => _fetch(
    ctx,
    (c) => simple.isDiscordRpcEnabled(ctx: c),
    (s) => _discordRpc = s,
  );

  Future<void> _loadCustomTitlebar(AppContext ctx) => _fetch(
    ctx,
    (c) => simple.isCustomTitlebarEnabled(ctx: c),
    (s) => _customTitlebar = s,
  );

  Future<void> _loadUpdateCheck(AppContext ctx) => _fetch(
    ctx,
    (c) => simple.isUpdateCheckEnabled(ctx: c),
    (s) => _updateCheck = s,
  );

  /// Applies the result of [fetch] unless the view is gone or another
  /// account's session was opened meanwhile.
  Future<void> _fetch<T>(
    AppContext ctx,
    Future<T> Function(AppContext ctx) fetch,
    void Function(AsyncState<T> state) apply,
  ) async {
    AsyncState<T> state;
    try {
      state = AsyncState.data(await fetch(ctx));
    } on Object catch (e, st) {
      state = AsyncState.error(e, st);
    }
    if (!mounted || !identical(appContextSignal.value, ctx)) return;
    setState(() => apply(state));
  }

  Future<bool> _trySave(Future<void> Function() save) async {
    try {
      await save();
      return true;
    } on Object catch (e) {
      showAppError('Не удалось сохранить настройку: $e');
      return false;
    }
  }

  Future<void> _setDiscordRpc(bool enabled) async {
    final ctx = appContextSignal.value;
    if (ctx == null) return;
    setState(() => _discordRpc = AsyncState.data(enabled));
    await _trySave(
      () => simple.setDiscordRpcEnabled(ctx: ctx, enabled: enabled),
    );
    await _loadDiscordRpc(ctx);
  }

  Future<void> _setCustomTitlebar(bool enabled) async {
    final ctx = appContextSignal.value;
    if (ctx == null) return;
    setState(() => _customTitlebar = AsyncState.data(enabled));
    final saved = await _trySave(
      () => simple.setCustomTitlebarEnabled(ctx: ctx, enabled: enabled),
    );
    await _loadCustomTitlebar(ctx);
    if (saved) {
      showAppSuccess('Изменения вступят в силу после перезапуска приложения');
    }
  }

  Future<void> _setCloseToTray(bool enabled) async {
    final ctx = appContextSignal.value;
    if (ctx == null) return;
    final saved = await _trySave(
      () => simple.setCloseToTrayEnabled(ctx: ctx, enabled: enabled),
    );
    if (saved) closeToTraySignal.value = enabled;
  }

  Future<void> _setUpdateCheck(bool enabled) async {
    final ctx = appContextSignal.value;
    if (ctx == null) return;
    setState(() => _updateCheck = AsyncState.data(enabled));
    await _trySave(
      () => simple.setUpdateCheckEnabled(ctx: ctx, enabled: enabled),
    );
    await _loadUpdateCheck(ctx);
  }

  Future<void> _pickDownloadPath() async {
    String? picked;
    try {
      picked = await FilePicker.getDirectoryPath();
    } on Object catch (e) {
      showAppError('Не удалось открыть выбор папки: $e');
      return;
    }
    final path = picked;
    if (path == null) return;
    final ctx = appContextSignal.value;
    if (ctx == null) return;
    if (await _trySave(() => rust.setDownloadPath(ctx: ctx, path: path))) {
      await _loadDownloadPath(ctx);
    }
  }

  Future<void> _clearCache() async {
    final ctx = appContextSignal.value;
    if (ctx == null || _clearingCache) return;
    setState(() => _clearingCache = true);
    try {
      await simple.clearCache(ctx: ctx);
      showAppSuccess('Кэш успешно очищен');
    } on Object catch (e) {
      showAppError('Не удалось очистить кэш: $e');
    } finally {
      if (mounted) setState(() => _clearingCache = false);
    }
    await _loadCacheSize(ctx);
  }

  Future<void> _clearTrackCache() async {
    final ctx = appContextSignal.value;
    if (ctx == null || _clearingTracks) return;
    final confirmed = await showGConfirm(
      context,
      title: 'Удалить скачанные треки?',
      message:
          'Треки, скачанные для прослушивания без интернета в этом аккаунте, '
          'будут удалены с устройства.',
      confirmLabel: 'Удалить',
      destructive: true,
    );
    // The confirmation was for this account's downloads only.
    if (!confirmed || !mounted || !identical(appContextSignal.value, ctx)) {
      return;
    }
    setState(() => _clearingTracks = true);
    try {
      await simple.clearTrackCache(ctx: ctx);
      unawaited(refreshDownloadedTracks());
      showAppSuccess('Скачанные треки успешно удалены');
    } on Object catch (e) {
      showAppError('Не удалось удалить скачанные треки: $e');
    } finally {
      if (mounted) setState(() => _clearingTracks = false);
    }
    await _loadTrackCacheSize(ctx);
  }

  Future<void> _openRepository() async {
    try {
      final opened = await launchUrl(
        Uri.parse(_repositoryUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) showAppError('Не удалось открыть ссылку');
    } on Object catch (e) {
      showAppError('Не удалось открыть ссылку: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Switches need a Material ancestor regardless of the surrounding layout.
    return Material(
      type: MaterialType.transparency,
      child: GScrollPage(
        controller: _scrollController,
        maxWidth: 880,
        children: [
          Semantics(
            header: true,
            child: Text('Настройки', style: GText.headline(30)),
          ),
          const SizedBox(height: 32),
          const _AccountsSection(),
          const SizedBox(height: 32),
          _buildListening(),
          if (_isDesktop) ...[
            const SizedBox(height: 32),
            _buildWindowAndSystem(),
          ],
          const SizedBox(height: 32),
          _buildStorage(),
          const SizedBox(height: 32),
          _buildAbout(),
        ],
      ),
    );
  }

  Widget _buildListening() {
    return _SettingsSection(
      label: 'Прослушивание',
      children: [
        _SettingsRow(
          title: 'Источники текста песен',
          description: 'Сервисы, в которых ищется синхронизированный текст',
          trailing: _chevron,
          onTap: () => LyricsProvidersDialog.show(context),
        ),
        if (_isDesktop)
          _SwitchRow(
            title: 'Discord Rich Presence',
            description: 'Показывать текущий трек в статусе Discord',
            value: _discordRpc.value ?? true,
            enabled: !_discordRpc.isLoading,
            onChanged: (v) => unawaited(_setDiscordRpc(v)),
          ),
      ],
    );
  }

  Widget _buildWindowAndSystem() {
    return _SettingsSection(
      label: 'Окно и система',
      children: [
        _SwitchRow(
          title: 'Собственная рамка окна',
          description:
              'Отключает стандартную рамку ОС. Применяется после перезапуска',
          value: _customTitlebar.value ?? false,
          enabled: !_customTitlebar.isLoading,
          onChanged: (v) => unawaited(_setCustomTitlebar(v)),
        ),
        SignalBuilder(
          builder: (context) => _SwitchRow(
            title: 'Сворачивать в трей при закрытии',
            description:
                'При нажатии на крестик приложение будет скрыто в трей',
            value: closeToTraySignal.value,
            onChanged: (v) => unawaited(_setCloseToTray(v)),
          ),
        ),
        if (GlobalHotkeyService.isSupported)
          _SettingsRow(
            title: 'Горячие клавиши',
            description: 'Глобальные сочетания клавиш, работающие вне окна',
            trailing: _chevron,
            onTap: () => unawaited(
              showGDialog<void>(
                context,
                builder: (context) => const _GlobalHotkeysDialog(),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildStorage() {
    String sizeLabel(AsyncState<int> size) => size.map(
      data: (bytes) => 'Занято: ${_formatBytes(bytes)}',
      error: (_, _) => 'Ошибка при получении размера',
      loading: () => 'Подсчёт…',
    );

    return _SettingsSection(
      label: 'Хранилище',
      children: [
        _SettingsRow(
          title: 'Путь для сохранения треков',
          description: _downloadPath.value ?? 'По умолчанию (Загрузки)',
          trailing: GButton(
            label: 'Изменить',
            size: GButtonSize.sm,
            variant: GButtonVariant.secondary,
            onPressed: () => unawaited(_pickDownloadPath()),
          ),
        ),
        _SettingsRow(
          title: 'Кэш изображений и данных',
          description: sizeLabel(_cacheSize),
          trailing: GButton(
            label: 'Очистить',
            size: GButtonSize.sm,
            variant: GButtonVariant.secondary,
            loading: _clearingCache,
            onPressed: () => unawaited(_clearCache()),
          ),
        ),
        _SettingsRow(
          title: 'Скачанные треки',
          description: '${sizeLabel(_trackCacheSize)} · в этом аккаунте',
          trailing: GButton(
            label: 'Удалить',
            size: GButtonSize.sm,
            variant: GButtonVariant.destructive,
            loading: _clearingTracks,
            onPressed: () => unawaited(_clearTrackCache()),
          ),
        ),
      ],
    );
  }

  Widget _buildAbout() {
    return _SettingsSection(
      label: 'О приложении',
      children: [
        _SettingsRow(
          leading: const _AppMark(),
          title: 'YouMuz',
          description: 'Альтернативный клиент для Яндекс Музыки',
          trailing: Text(
            _version == null ? '…' : 'Версия $_version',
            style: GText.time(size: 12),
          ),
        ),
        _SwitchRow(
          title: 'Проверка обновлений при запуске',
          description: 'Проверять наличие новых версий на GitHub при запуске',
          value: _updateCheck.value ?? true,
          enabled: !_updateCheck.isLoading,
          onChanged: (v) => unawaited(_setUpdateCheck(v)),
        ),
        _SettingsRow(
          title: 'Обновления',
          description: 'Сравнить установленную версию с последним релизом',
          trailing: GButton(
            label: 'Проверить',
            size: GButtonSize.sm,
            variant: GButtonVariant.secondary,
            onPressed: () => UpdateDialog.show(context),
          ),
        ),
        _SettingsRow(
          title: 'Исходный код',
          description: 'github.com/nekitdda/YouMuz',
          trailing: const Icon(
            LucideIcons.arrowUpRight,
            size: 16,
            color: GColors.mutedForeground,
          ),
          onTap: () => unawaited(_openRepository()),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Accounts
// ---------------------------------------------------------------------------

class _AccountsSection extends StatefulWidget {
  const _AccountsSection();

  @override
  State<_AccountsSection> createState() => _AccountsSectionState();
}

class _AccountsSectionState extends State<_AccountsSection> {
  /// Account this screen is currently switching to or removing.
  int? _pendingUid;

  Future<void> _open(StoredAccountDto account) async {
    if (account.needsLogin) {
      // The stored token was rejected: signing in again replaces it.
      await showAddAccountFlow(context);
      return;
    }
    await _runFor(account.uid, () => switchAccount(account.uid));
  }

  Future<void> _remove(StoredAccountDto account) async {
    final confirmed = await showGConfirm(
      context,
      title: 'Выйти из аккаунта?',
      message: _removeAccountMessage,
      confirmLabel: 'Выйти',
      destructive: true,
    );
    if (!confirmed) return;
    await _runFor(account.uid, () => removeAccount(account.uid));
  }

  Future<void> _runFor(int uid, Future<void> Function() action) async {
    if (mounted) setState(() => _pendingUid = uid);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _pendingUid = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final accounts = accountsSignal.value;
        final activeUid = activeAccountUidSignal.value;
        final busy = sessionTransitionSignal.value;

        return _SettingsSection(
          label: 'Аккаунты',
          note: _accountsNote,
          children: [
            if (accounts.isEmpty)
              const _SettingsRow(
                title: 'Нет сохранённых аккаунтов',
                description: 'Добавьте аккаунт Яндекса, чтобы войти в него',
              ),
            for (final account in accounts)
              _buildRow(account, activeUid: activeUid, busy: busy),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: GButton(
                  label: 'Добавить аккаунт',
                  icon: LucideIcons.userPlus,
                  variant: GButtonVariant.secondary,
                  onPressed: busy
                      ? null
                      : () => unawaited(showAddAccountFlow(context)),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildRow(
    StoredAccountDto account, {
    required int? activeUid,
    required bool busy,
  }) {
    final active = activeUid == null
        ? account.isActive
        : account.uid == activeUid;
    return _AccountRow(
      account: account,
      active: active,
      pending: busy && _pendingUid == account.uid,
      onTap: busy || active ? null : () => unawaited(_open(account)),
      onRemove: busy ? null : () => unawaited(_remove(account)),
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.account,
    required this.active,
    required this.pending,
    required this.onTap,
    required this.onRemove,
  });

  final StoredAccountDto account;
  final bool active;
  final bool pending;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  static const double _avatarSize = 36;

  @override
  Widget build(BuildContext context) {
    final name = accountDisplayName(account);
    final login = account.login.trim();
    final subtitle = login.isNotEmpty && login != name
        ? login
        : 'ID ${account.uid}';

    return GPressable(
      onTap: onTap,
      selected: active,
      semanticLabel: active
          ? '$name, текущий аккаунт'
          : account.needsLogin
          ? 'Войти снова: $name'
          : 'Переключиться на $name',
      builder: (context, s) => AnimatedContainer(
        duration: GDurations.fast,
        curve: GCurves.standard,
        color: s.highlighted ? GColors.secondary : const Color(0x00000000),
        foregroundDecoration: s.focused ? _focusRing : null,
        padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
        child: Row(
          children: [
            // The active ring adds 3.5px per side; a shared box keeps names
            // aligned across rows.
            SizedBox.square(
              dimension: _avatarSize + 7,
              child: Center(
                child: GAvatar(
                  name: name,
                  url: account.avatarUrl,
                  size: _avatarSize,
                  ring: active,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          style: GText.sm(weight: GText.medium),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (account.hasPlus) ...[
                        const SizedBox(width: 8),
                        const GBadge('Плюс', brand: true),
                      ],
                      if (active) ...[
                        const SizedBox(width: 6),
                        const GBadge('Активен'),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: subtitle),
                        if (account.needsLogin) ...[
                          const TextSpan(text: ' · '),
                          TextSpan(
                            text: 'Требуется вход',
                            style: GText.xs(
                              weight: GText.medium,
                              color: GColors.destructive,
                            ),
                          ),
                        ],
                      ],
                    ),
                    style: GText.xs(color: GColors.mutedForeground),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (pending)
              const Padding(
                padding: EdgeInsets.all(8),
                child: SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: GColors.mutedForeground,
                  ),
                ),
              )
            else
              GIconButton(
                icon: LucideIcons.trash2,
                tooltip: 'Выйти из аккаунта',
                hoverColor: GColors.destructive,
                onPressed: onRemove,
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Building blocks
// ---------------------------------------------------------------------------

/// Section label above a card whose rows are separated by hairlines.
class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.label,
    required this.children,
    this.note,
  });

  final String label;
  final List<Widget> children;
  final String? note;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Semantics(
            header: true,
            child: Text(label, style: GText.sm(weight: GText.medium)),
          ),
        ),
        GCard(
          padding: EdgeInsets.zero,
          child: ClipRRect(
            // Keeps row hover fills inside the rounded corners.
            borderRadius: BorderRadius.circular(GRadius.x2l),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) const GDivider(),
                  children[i],
                ],
              ],
            ),
          ),
        ),
        if (note != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
            child: Text(note!, style: GText.xs(color: GColors.mutedForeground)),
          ),
      ],
    );
  }
}

/// Title and optional description on the left, a control on the right.
/// With [onTap] the whole row is pressable and hovers to `secondary`.
class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.title,
    this.description,
    this.leading,
    this.trailing,
    this.onTap,
  });

  final String title;
  final String? description;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 12)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: GText.sm(weight: GText.medium)),
                if (description != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    description!,
                    style: GText.xs(color: GColors.mutedForeground),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 16), trailing!],
        ],
      ),
    );
    if (onTap == null) return content;
    return GPressable(
      onTap: onTap,
      builder: (context, s) => AnimatedContainer(
        duration: GDurations.fast,
        curve: GCurves.standard,
        color: s.highlighted ? GColors.secondary : const Color(0x00000000),
        foregroundDecoration: s.focused ? _focusRing : null,
        child: content,
      ),
    );
  }
}

/// Row toggled by a click anywhere on it, or Space/Enter while focused.
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    required this.value,
    required this.onChanged,
    this.description,
    this.enabled = true,
  });

  final String title;
  final String? description;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return _SettingsRow(
      title: title,
      description: description,
      onTap: enabled ? () => onChanged(!value) : null,
      // The row is the single focus target (GPressable only reports hover
      // while focusable), so the switch stays out of the tab order.
      trailing: ExcludeFocus(
        child: Switch(value: value, onChanged: enabled ? onChanged : null),
      ),
    );
  }
}

/// App mark from the header: a foreground disc with a background dot.
class _AppMark extends StatelessWidget {
  const _AppMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: GColors.foreground,
        shape: BoxShape.circle,
      ),
      child: Container(
        width: 12,
        height: 12,
        decoration: const BoxDecoration(
          color: GColors.background,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

/// Hairline-bordered group for rows inside a dialog (the dialog itself is
/// already `bg-card`).
class _OutlinedGroup extends StatelessWidget {
  const _OutlinedGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(GRadius.xl),
        border: Border.all(color: GColors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(GRadius.xl - 1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const GDivider(),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Global hotkeys
// ---------------------------------------------------------------------------

class _GlobalHotkeysDialog extends StatefulWidget {
  const _GlobalHotkeysDialog();

  @override
  State<_GlobalHotkeysDialog> createState() => _GlobalHotkeysDialogState();
}

class _GlobalHotkeysDialogState extends State<_GlobalHotkeysDialog> {
  bool _resetting = false;

  @override
  void initState() {
    super.initState();
    // Fresh state from Rust every time the dialog opens.
    unawaited(GlobalHotkeyService.refresh());
  }

  Future<void> _reset() async {
    setState(() => _resetting = true);
    await GlobalHotkeyService.resetDefaults();
    if (!mounted) return;
    setState(() => _resetting = false);
    showAppSuccess('Горячие клавиши сброшены по умолчанию');
  }

  Future<void> _edit(GlobalHotkeyBinding binding) async {
    final combo = await showGDialog<RecordedHotkey>(
      context,
      builder: (context) => _HotkeyDialog(binding: binding),
    );
    if (!mounted || combo == null) return;

    final error = await GlobalHotkeyService.updateBinding(
      binding.action,
      combo,
    );
    if (!mounted || error == null) return;
    showAppError(error);
  }

  @override
  Widget build(BuildContext context) {
    return GDialog(
      title: 'Горячие клавиши',
      description:
          'Глобальные сочетания работают, даже когда окно свёрнуто или '
          'неактивно.',
      width: 560,
      content: SingleChildScrollView(
        child: ValueListenableBuilder<int>(
          valueListenable: GlobalHotkeyService.changes,
          builder: (context, _, _) {
            final bindings = GlobalHotkeyService.bindings;
            final hotkeysEnabled = GlobalHotkeyService.hotkeysEnabled;
            return _OutlinedGroup(
              children: [
                _SwitchRow(
                  title: 'Использовать горячие клавиши',
                  description: hotkeysEnabled
                      ? 'Все включённые сочетания активны в системе'
                      : 'Все системные сочетания временно отключены',
                  value: hotkeysEnabled,
                  onChanged: (enabled) => unawaited(
                    GlobalHotkeyService.setAllEnabled(enabled: enabled),
                  ),
                ),
                for (final binding in bindings)
                  _HotkeyBindingRow(
                    binding: binding,
                    hotkeysEnabled: hotkeysEnabled,
                    onEnabledChanged: (enabled) => unawaited(
                      GlobalHotkeyService.setEnabled(
                        binding.action,
                        enabled: enabled,
                      ),
                    ),
                    onEdit: () => unawaited(_edit(binding)),
                  ),
              ],
            );
          },
        ),
      ),
      actions: [
        SizedBox(
          width: double.infinity,
          child: Row(
            children: [
              Flexible(
                child: GButton(
                  label: 'Сбросить по умолчанию',
                  icon: LucideIcons.rotateCcw,
                  variant: GButtonVariant.ghost,
                  loading: _resetting,
                  onPressed: () => unawaited(_reset()),
                ),
              ),
              const Spacer(),
              GButton(
                label: 'Готово',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HotkeyBindingRow extends StatelessWidget {
  const _HotkeyBindingRow({
    required this.binding,
    required this.hotkeysEnabled,
    required this.onEnabledChanged,
    required this.onEdit,
  });

  final GlobalHotkeyBinding binding;
  final bool hotkeysEnabled;
  final ValueChanged<bool> onEnabledChanged;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final active = binding.enabled && hotkeysEnabled;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              binding.action.title,
              style: GText.sm(
                weight: GText.medium,
                color: active ? GColors.foreground : GColors.mutedForeground,
              ),
            ),
          ),
          const SizedBox(width: 12),
          _KeyComboChip(
            label: binding.formattedCombo,
            active: active,
            onPressed: onEdit,
          ),
          const SizedBox(width: 12),
          Switch(value: binding.enabled, onChanged: onEnabledChanged),
        ],
      ),
    );
  }
}

/// Current combo in a key cap; clicking it records a new one.
class _KeyComboChip extends StatelessWidget {
  const _KeyComboChip({
    required this.label,
    required this.active,
    required this.onPressed,
  });

  final String label;
  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GPressable(
      onTap: onPressed,
      tooltip: 'Изменить сочетание',
      semanticLabel: 'Сочетание $label, изменить',
      builder: (context, s) {
        final iconColor = s.highlighted
            ? GColors.foreground
            : GColors.mutedForeground;
        return AnimatedContainer(
          duration: GDurations.fast,
          curve: GCurves.standard,
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: s.hovered ? GColors.accent : GColors.secondary,
            borderRadius: BorderRadius.circular(GRadius.md),
            border: Border.all(
              color: s.focused ? GColors.ring : GColors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: GText.style(
                  12,
                  lineHeight: 16,
                  weight: GText.medium,
                  mono: true,
                  color: active ? GColors.foreground : GColors.mutedForeground,
                ),
              ),
              const SizedBox(width: 8),
              Icon(LucideIcons.pencil, size: 12, color: iconColor),
            ],
          ),
        );
      },
    );
  }
}

class _HotkeyDialog extends StatefulWidget {
  const _HotkeyDialog({required this.binding});

  final GlobalHotkeyBinding binding;

  @override
  State<_HotkeyDialog> createState() => _HotkeyDialogState();
}

class _HotkeyDialogState extends State<_HotkeyDialog> {
  RecordedHotkey? _combo;

  void _save() {
    final combo = _combo;
    if (combo != null) {
      Navigator.pop(context, combo);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GDialog(
      title: widget.binding.action.title,
      description: 'Нажмите нужное сочетание клавиш',
      width: 420,
      content: Center(
        child: _HotkeyRecorder(
          initial: _combo,
          onRecorded: (combo) => setState(() => _combo = combo),
        ),
      ),
      actions: [
        GButton(
          label: 'Отмена',
          variant: GButtonVariant.secondary,
          onPressed: () => Navigator.pop(context),
        ),
        GButton(label: 'Сохранить', onPressed: _combo == null ? null : _save),
      ],
    );
  }
}

/// In-app hotkey capture: records the first non-modifier physical key while
/// the field is focused, showing the pending combo live. Replaces the
/// `HotKeyRecorder` widget from the removed `hotkey_manager` plugin.
class _HotkeyRecorder extends StatefulWidget {
  const _HotkeyRecorder({required this.initial, required this.onRecorded});

  final RecordedHotkey? initial;
  final ValueChanged<RecordedHotkey> onRecorded;

  @override
  State<_HotkeyRecorder> createState() => _HotkeyRecorderState();
}

class _HotkeyRecorderState extends State<_HotkeyRecorder> {
  final _focusNode = FocusNode();
  bool _focused = false;
  RecordedHotkey? _combo;

  /// Modifiers held so far, before a real key completes the combo.
  RecordedHotkey? _pending;

  @override
  void initState() {
    super.initState();
    _combo = widget.initial;
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    final hardware = HardwareKeyboard.instance;

    if (event is KeyUpEvent) {
      // Releasing every modifier without a key drops the live preview.
      if (_pending != null &&
          !hardware.isControlPressed &&
          !hardware.isAltPressed &&
          !hardware.isShiftPressed &&
          !hardware.isMetaPressed) {
        setState(() => _pending = null);
      }
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent) return KeyEventResult.handled;

    final combo = RecordedHotkey(
      usbHidUsage: event.physicalKey.usbHidUsage,
      ctrl: hardware.isControlPressed,
      alt: hardware.isAltPressed,
      shift: hardware.isShiftPressed,
      meta: hardware.isMetaPressed,
    );

    if (_isModifierKey(event.logicalKey)) {
      // Show the held modifiers live, but wait for a real key to record.
      setState(() => _pending = combo);
      return KeyEventResult.handled;
    }

    setState(() {
      _combo = combo;
      _pending = null;
    });
    widget.onRecorded(combo);
    return KeyEventResult.handled;
  }

  bool _isModifierKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.controlLeft ||
        key == LogicalKeyboardKey.controlRight ||
        key == LogicalKeyboardKey.altLeft ||
        key == LogicalKeyboardKey.altRight ||
        key == LogicalKeyboardKey.shiftLeft ||
        key == LogicalKeyboardKey.shiftRight ||
        key == LogicalKeyboardKey.metaLeft ||
        key == LogicalKeyboardKey.metaRight;
  }

  String _label(RecordedHotkey shown) {
    return [
      if (shown.ctrl) 'Ctrl',
      if (shown.alt) 'Alt',
      if (shown.shift) 'Shift',
      if (shown.meta) 'Win',
      if (identical(shown, _pending)) '…' else _keyLabel(shown.usbHidUsage),
    ].join(' + ');
  }

  String _keyLabel(int usage) {
    // Live display during recording only; the canonical name comes back from
    // Rust once the binding is saved. Without a mapping table here the raw
    // usage is shown for yet-unmapped keys, which the save flow rejects.
    const known = <int, String>{
      0x0007002C: 'Пробел',
      0x00070050: '←',
      0x0007004F: '→',
      0x00070052: '↑',
      0x00070051: '↓',
    };
    return known[usage] ?? String.fromCharCode(usage & 0xFF).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final shown = _pending ?? _combo;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKeyEvent,
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: _focusNode.requestFocus,
          child: AnimatedContainer(
            duration: GDurations.fast,
            curve: GCurves.standard,
            width: 280,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              color: GColors.secondary,
              borderRadius: BorderRadius.circular(GRadius.xl),
              border: Border.all(
                color: _focused ? GColors.ring : GColors.border,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  shown == null ? 'Нажмите сочетание...' : _label(shown),
                  textAlign: TextAlign.center,
                  style: shown == null
                      ? GText.sm(color: GColors.mutedForeground)
                      : GText.style(
                          15,
                          lineHeight: 22,
                          weight: GText.medium,
                          mono: true,
                        ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedContainer(
                      duration: GDurations.fast,
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: _focused
                            ? GColors.brand
                            : GColors.mutedForeground,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _focused ? 'Идёт запись' : 'Нажмите, чтобы записать',
                      style: GText.xs(color: GColors.mutedForeground),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
