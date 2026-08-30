import 'package:couple_chat_app/src/common/dear_design.dart';
import 'package:couple_chat_app/src/common/error_mapper.dart';
import 'package:couple_chat_app/src/features/auth/data/auth_providers.dart';
import 'package:couple_chat_app/src/features/notifications/data/notification_permission_service.dart';
import 'package:couple_chat_app/src/features/notifications/data/notification_preferences.dart';
import 'package:couple_chat_app/src/features/notifications/data/push_registration_providers.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class NotificationSettingsPage extends ConsumerStatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  ConsumerState<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState
    extends ConsumerState<NotificationSettingsPage>
    with WidgetsBindingObserver {
  String? _activeUserId;
  int _userGeneration = 0;
  NotificationPreferences? _baseline;
  NotificationPreferences? _draft;
  NotificationPreferences? _lastProviderSnapshot;
  String? _preferencesError;
  String? _saveError;
  bool _preferencesRetrying = false;
  bool _saving = false;
  bool _registering = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _activeUserId != null) {
      ref.invalidate(notificationSystemStatusProvider);
    }
  }

  Future<void> _save() async {
    final draft = _draft;
    final userId = _activeUserId;
    final generation = _userGeneration;
    if (draft == null || userId == null || draft.userId != userId || _saving) {
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(saveNotificationPreferencesProvider)(draft);
      if (!mounted ||
          generation != _userGeneration ||
          userId != _activeUserId) {
        return;
      }
      setState(() {
        _baseline = draft;
        _saveError = null;
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('알림 설정을 저장했어요.')),
      );
    } catch (error) {
      if (!mounted ||
          generation != _userGeneration ||
          userId != _activeUserId) {
        return;
      }
      setState(() {
        _saveError = _notificationSettingsError('저장하지', error);
        _saving = false;
      });
    }
  }

  Future<void> _retryPreferences() async {
    final userId = _activeUserId;
    final generation = _userGeneration;
    if (userId == null || _preferencesRetrying || _saving) return;
    setState(() => _preferencesRetrying = true);
    ref.invalidate(notificationPreferencesProvider(userId));
    try {
      await ref.read(notificationPreferencesProvider(userId).future);
    } catch (_) {
      // The provider error is rendered inline with the preserved draft.
    } finally {
      if (mounted && generation == _userGeneration && userId == _activeUserId) {
        setState(() => _preferencesRetrying = false);
      }
    }
  }

  Future<void> _connectSystemNotifications(String userId) async {
    if (_registering) return;
    final generation = _userGeneration;
    setState(() => _registering = true);
    try {
      final cachedStatus =
          ref.read(notificationSystemStatusProvider).valueOrNull;
      final NotificationSystemStatus systemStatus;
      if (cachedStatus != null) {
        systemStatus = cachedStatus;
      } else {
        systemStatus = await ref.read(notificationSystemStatusProvider.future);
      }
      if (!mounted ||
          generation != _userGeneration ||
          userId != _activeUserId) {
        return;
      }

      if (systemStatus.authorizationStatus == AuthorizationStatus.denied) {
        final opened = await ref.read(openNotificationSettingsProvider)();
        if (!mounted ||
            generation != _userGeneration ||
            userId != _activeUserId) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              opened
                  ? '기기 설정에서 Dear 알림을 허용한 뒤 돌아와 주세요.'
                  : '기기 설정을 열지 못했어요. 설정 앱에서 Dear 알림을 허용해 주세요.',
            ),
          ),
        );
        return;
      }

      final authorization =
          await ref.read(requestNotificationPermissionProvider)();
      ref.invalidate(notificationSystemStatusProvider);
      if (!mounted ||
          generation != _userGeneration ||
          userId != _activeUserId) {
        return;
      }
      if (!isNotificationAuthorizationGranted(authorization)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('알림을 켜지 않았어요. 필요할 때 기기 설정에서 변경할 수 있어요.'),
          ),
        );
        return;
      }

      await ref
          .read(pushRegistrationServiceProvider)
          .syncForSession(userId: userId);
      ref.invalidate(notificationSystemStatusProvider);
      final status = await ref.read(notificationSystemStatusProvider.future);
      if (!mounted ||
          generation != _userGeneration ||
          userId != _activeUserId) {
        return;
      }
      final message = status.isAuthorized && status.hasFcmToken
          ? '이 기기의 알림 연결을 완료했어요.'
          : '시스템 설정에서 Dear 알림을 허용해 주세요.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (error) {
      if (!mounted ||
          generation != _userGeneration ||
          userId != _activeUserId) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(toFriendlyErrorMessage(error))),
      );
    } finally {
      if (mounted && generation == _userGeneration && userId == _activeUserId) {
        setState(() => _registering = false);
      }
    }
  }

  void _update(
    NotificationPreferences Function(NotificationPreferences current) change,
  ) {
    final current = _draft;
    if (current == null || _saving || current.userId != _activeUserId) return;
    setState(() => _draft = change(current));
  }

  void _activateUser(String? userId) {
    if (_activeUserId == userId) return;
    _activeUserId = userId;
    _userGeneration += 1;
    _baseline = null;
    _draft = null;
    _lastProviderSnapshot = null;
    _preferencesError = null;
    _saveError = null;
    _preferencesRetrying = false;
    _saving = false;
    _registering = false;
  }

  void _consumePreferences(
    String userId,
    AsyncValue<NotificationPreferences> preferencesAsync,
  ) {
    if (preferencesAsync.hasError) {
      _preferencesError =
          _notificationSettingsError('불러오지', preferencesAsync.error!);
      return;
    }

    final loaded = preferencesAsync.valueOrNull;
    if (loaded == null || loaded.userId != userId) {
      return;
    }
    _preferencesError = null;
    if (_samePreferences(_lastProviderSnapshot, loaded)) return;

    final previousBaseline = _baseline;
    final currentDraft = _draft;
    final hasUnsavedChanges = previousBaseline != null &&
        currentDraft != null &&
        !_samePreferences(previousBaseline, currentDraft);
    _lastProviderSnapshot = loaded;
    _baseline = loaded;
    if (currentDraft == null || !hasUnsavedChanges) {
      _draft = loaded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authSessionProvider).valueOrNull;
    final userId = session?.user.id;
    _activateUser(userId);
    if (userId == null) {
      return const Scaffold(
        body: Center(child: Text('로그인 후 알림을 설정할 수 있어요.')),
      );
    }

    final preferencesAsync = ref.watch(notificationPreferencesProvider(userId));
    final systemStatusAsync = ref.watch(notificationSystemStatusProvider);
    _consumePreferences(userId, preferencesAsync);

    return Scaffold(
      appBar: AppBar(title: const Text('알림 설정')),
      body: DearBackground(
        child: _buildPreferencesBody(
          userId: userId,
          preferencesAsync: preferencesAsync,
          systemStatusAsync: systemStatusAsync,
        ),
      ),
    );
  }

  Widget _buildPreferencesBody({
    required String userId,
    required AsyncValue<NotificationPreferences> preferencesAsync,
    required AsyncValue<NotificationSystemStatus> systemStatusAsync,
  }) {
    final draft = _draft;
    if (draft == null) {
      if (_preferencesError != null) {
        return ListView(
          key: const Key('notification-preferences-initial-error'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(DearSpacing.space24),
          children: [
            const SizedBox(height: 120),
            DearInlineError(
              key: const Key('notification-preferences-error'),
              message: _preferencesError!,
              retryButtonKey:
                  const Key('notification-preferences-retry-button'),
              onRetry: _saving ? null : _retryPreferences,
              retrying: _preferencesRetrying,
            ),
          ],
        );
      }
      return const _NotificationSettingsSkeleton();
    }

    final inputsEnabled = !_saving;
    return ListView(
      key: const Key('notification-settings-content'),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        if (_preferencesError != null) ...[
          DearInlineError(
            key: const Key('notification-preferences-error'),
            message: _preferencesError!,
            retryButtonKey: const Key('notification-preferences-retry-button'),
            onRetry: _saving ? null : _retryPreferences,
            retrying: _preferencesRetrying,
          ),
          const SizedBox(height: DearSpacing.space16),
        ] else if (preferencesAsync.isLoading) ...[
          const DearInlineLoading(
            key: Key('notification-preferences-refreshing'),
            label: '알림 설정을 새로고침하는 중',
          ),
          const SizedBox(height: DearSpacing.space16),
        ],
        _SystemStatusCard(
          status: systemStatusAsync.valueOrNull,
          serverSynced: (_baseline ?? draft).isServerSynced,
          loading: systemStatusAsync.isLoading || _registering,
          onConnect: () => _connectSystemNotifications(userId),
        ),
        const SizedBox(height: 24),
        const _SectionLabel('받을 알림'),
        const SizedBox(height: 10),
        _SettingsSection(
          key: const Key('notification-receive-section'),
          children: [
            _PreferenceSwitchRow(
              icon: Icons.chat_bubble_outline_rounded,
              title: '메시지 알림',
              subtitle: '상대방이 메시지를 보내면 알려드려요',
              value: draft.messageEnabled,
              onChanged: inputsEnabled
                  ? (value) => _update(
                        (current) => current.copyWith(messageEnabled: value),
                      )
                  : null,
            ),
            _PreferenceSwitchRow(
              icon: Icons.image_outlined,
              title: '사진 알림',
              subtitle: '사진 메시지가 도착하면 알려드려요',
              value: draft.imageEnabled,
              onChanged: inputsEnabled
                  ? (value) => _update(
                        (current) => current.copyWith(imageEnabled: value),
                      )
                  : null,
            ),
            _PreferenceSwitchRow(
              icon: Icons.favorite_border_rounded,
              title: '기념일 알림',
              subtitle: '100일·주년·직접 추가한 날을 축하해요',
              value: draft.anniversaryEnabled,
              onChanged: inputsEnabled
                  ? (value) => _update(
                        (current) =>
                            current.copyWith(anniversaryEnabled: value),
                      )
                  : null,
            ),
            _PreferenceSwitchRow(
              icon: Icons.grid_4x4_rounded,
              title: '오목 초대 알림',
              subtitle: '상대방의 대국 신청과 재대결을 알려드려요',
              value: draft.gameEnabled,
              showDivider: false,
              onChanged: inputsEnabled
                  ? (value) => _update(
                        (current) => current.copyWith(gameEnabled: value),
                      )
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 24),
        const _SectionLabel('시간'),
        const SizedBox(height: 10),
        _SettingsSection(
          key: const Key('notification-time-section'),
          children: [
            _TimeSelectorRow(
              icon: Icons.celebration_outlined,
              title: '기념일 축하 시간',
              subtitle: '대한민국 시간 기준',
              hour: draft.anniversaryHour,
              enabled: draft.anniversaryEnabled,
              onChanged: inputsEnabled
                  ? (value) => _update(
                        (current) => current.copyWith(anniversaryHour: value),
                      )
                  : null,
            ),
            _PreferenceSwitchRow(
              icon: Icons.bedtime_outlined,
              title: '무음 시간',
              subtitle: '알림은 받되 소리 없이 표시해요',
              value: draft.quietEnabled,
              showDivider: !draft.quietEnabled,
              onChanged: inputsEnabled
                  ? (value) => _update(
                        (current) => current.copyWith(quietEnabled: value),
                      )
                  : null,
            ),
            if (draft.quietEnabled)
              _QuietHoursRow(
                startHour: draft.quietStartHour,
                endHour: draft.quietEndHour,
                onStartChanged: inputsEnabled
                    ? (value) => _update(
                          (current) => current.copyWith(quietStartHour: value),
                        )
                    : null,
                onEndChanged: inputsEnabled
                    ? (value) => _update(
                          (current) => current.copyWith(quietEndHour: value),
                        )
                    : null,
              ),
          ],
        ),
        const SizedBox(height: 24),
        if (_saveError != null) ...[
          DearInlineError(
            key: const Key('notification-save-error'),
            message: _saveError!,
            onRetry: _save,
            retrying: _saving,
            retryLabel: '다시 저장',
            retryingLabel: '다시 저장하는 중',
          ),
          const SizedBox(height: DearSpacing.space12),
        ],
        DearGradientButton(
          key: const Key('notification-save-button'),
          label: _saving ? '저장 중...' : '변경 사항 저장',
          icon: Icons.check_rounded,
          onPressed: _saving ? null : _save,
        ),
      ],
    );
  }
}

class _SystemStatusCard extends StatelessWidget {
  const _SystemStatusCard({
    required this.status,
    required this.serverSynced,
    required this.loading,
    required this.onConnect,
  });

  final NotificationSystemStatus? status;
  final bool serverSynced;
  final bool loading;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final authorized = status?.isAuthorized == true;
    final provisional = status?.isProvisional == true;
    final connected = authorized && status?.hasFcmToken == true;
    final denied = status?.authorizationStatus == AuthorizationStatus.denied;
    final title = connected
        ? provisional
            ? '알림이 조용히 연결됐어요'
            : '이 기기 알림이 연결됐어요'
        : denied
            ? '기기 설정에서 알림을 허용해 주세요'
            : authorized
                ? '알림 연결을 마무리해 주세요'
                : '둘만의 메시지와 기념일을 놓치지 않도록 알림을 켤까요?';
    final subtitle = connected
        ? provisional
            ? '현재는 조용히 전달될 수 있어요. 기기 설정에서 전체 허용으로 바꿀 수 있어요.'
            : '설정한 메시지와 기념일 알림을 받을 수 있어요.'
        : denied
            ? 'Dear가 알림을 보낼 수 있도록 기기 설정에서 권한을 변경해 주세요.'
            : authorized
                ? '권한은 허용됐어요. 이 기기에 알림 토큰만 안전하게 연결할게요.'
                : '알림을 켜면 메시지, 기념일, 오목 초대를 놓치지 않고 받을 수 있어요.';
    final actionLabel = denied
        ? '설정 열기'
        : authorized
            ? '다시 연결'
            : '알림 켜기';
    final containerColor =
        connected ? scheme.tertiaryContainer : scheme.primaryContainer;
    final foreground =
        connected ? scheme.onTertiaryContainer : scheme.onPrimaryContainer;
    final details = Column(
      key: const Key('notification-system-details'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: foreground,
              ),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: foreground,
                height: 1.35,
              ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _ConnectionStatusChip(
              label: status?.permissionLabel ?? '권한 확인 중',
              connected: authorized,
            ),
            _ConnectionStatusChip(
              label: 'Dear 설정 저장',
              connected: serverSynced,
            ),
          ],
        ),
      ],
    );

    Widget icon() => DearIconBubble(
          icon: connected
              ? Icons.notifications_active_rounded
              : Icons.notifications_none_rounded,
          size: 48,
          iconSize: 24,
          background: scheme.surface,
          color: connected ? scheme.tertiary : scheme.primary,
        );

    Widget connectButton({required bool expanded}) => SizedBox(
          width: expanded ? double.infinity : null,
          height: DearTouchTargets.minimum,
          child: TextButton(
            key: const Key('notification-connect-button'),
            onPressed: loading ? null : onConnect,
            child: Text(loading ? '연결 중...' : actionLabel),
          ),
        );

    return LayoutBuilder(
      builder: (context, constraints) {
        final reflow = MediaQuery.textScalerOf(context).scale(1) >= 1.6 ||
            constraints.maxWidth < 320;
        return Container(
          key: const Key('notification-system-status-card'),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: containerColor,
            borderRadius: BorderRadius.circular(DearRadii.control),
            border: Border.all(color: scheme.outline),
          ),
          child: reflow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ExcludeSemantics(child: icon()),
                        const SizedBox(width: DearSpacing.space12),
                        Expanded(child: details),
                      ],
                    ),
                    if (!connected) ...[
                      const SizedBox(height: DearSpacing.space12),
                      connectButton(expanded: true),
                    ],
                  ],
                )
              : Row(
                  children: [
                    ExcludeSemantics(child: icon()),
                    const SizedBox(width: DearSpacing.space12),
                    Expanded(child: details),
                    if (!connected) ...[
                      const SizedBox(width: DearSpacing.space8),
                      connectButton(expanded: false),
                    ],
                  ],
                ),
        );
      },
    );
  }
}

class _ConnectionStatusChip extends StatelessWidget {
  const _ConnectionStatusChip({
    required this.label,
    required this.connected,
  });

  final String label;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = connected ? scheme.primary : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: DearSpacing.space4,
        children: [
          Icon(
            connected ? Icons.check_circle_rounded : Icons.info_outline_rounded,
            size: 13,
            color: color,
          ),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Text(
      label,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: scheme.onSurface,
            fontWeight: FontWeight.w900,
          ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(children: children),
    );
  }
}

class _PreferenceSwitchRow extends StatelessWidget {
  const _PreferenceSwitchRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.showDivider = true,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        SwitchListTile(
          contentPadding: const EdgeInsets.fromLTRB(14, 5, 10, 5),
          secondary: Icon(icon, color: scheme.primary),
          title: Text(title),
          subtitle: Text(subtitle),
          value: value,
          onChanged: onChanged,
        ),
        if (showDivider)
          Divider(height: 1, indent: 54, color: scheme.outlineVariant),
      ],
    );
  }
}

class _TimeSelectorRow extends StatelessWidget {
  const _TimeSelectorRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.hour,
    required this.enabled,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final int hour;
  final bool enabled;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selectorEnabled = enabled && onChanged != null;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final reflow = MediaQuery.textScalerOf(context).scale(1) >= 1.6 ||
                  constraints.maxWidth < 280;
              final details = Row(
                key: const Key('notification-anniversary-time-details'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    icon,
                    color: enabled ? scheme.primary : theme.disabledColor,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
              final dropdown = DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  key: const Key('notification-anniversary-hour-dropdown'),
                  value: hour,
                  borderRadius: BorderRadius.circular(DearRadii.chip),
                  onChanged: selectorEnabled
                      ? (value) {
                          if (value != null) onChanged?.call(value);
                        }
                      : null,
                  items: List.generate(
                    24,
                    (value) => DropdownMenuItem(
                      value: value,
                      child: Text(_hourLabel(value)),
                    ),
                  ),
                ),
              );
              if (reflow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    details,
                    const SizedBox(height: DearSpacing.space8),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: dropdown,
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: details),
                  const SizedBox(width: DearSpacing.space8),
                  dropdown,
                ],
              );
            },
          ),
        ),
        Divider(height: 1, indent: 54, color: scheme.outlineVariant),
      ],
    );
  }
}

class _QuietHoursRow extends StatelessWidget {
  const _QuietHoursRow({
    required this.startHour,
    required this.endHour,
    required this.onStartChanged,
    required this.onEndChanged,
  });

  final int startHour;
  final int endHour;
  final ValueChanged<int>? onStartChanged;
  final ValueChanged<int>? onEndChanged;

  @override
  Widget build(BuildContext context) {
    Widget selector({
      required String label,
      required int value,
      required ValueChanged<int>? onChanged,
      required Key key,
    }) {
      return DropdownButtonFormField<int>(
        key: key,
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label, isDense: true),
        items: List.generate(
          24,
          (hour) => DropdownMenuItem(
            value: hour,
            child: Text(_hourLabel(hour)),
          ),
        ),
        onChanged: onChanged == null
            ? null
            : (next) {
                if (next != null) onChanged(next);
              },
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final reflow = MediaQuery.textScalerOf(context).scale(1) >= 1.6 ||
              constraints.maxWidth < 280;
          final start = selector(
            label: '시작',
            value: startHour,
            onChanged: onStartChanged,
            key: const Key('notification-quiet-start-dropdown'),
          );
          final end = selector(
            label: '종료',
            value: endHour,
            onChanged: onEndChanged,
            key: const Key('notification-quiet-end-dropdown'),
          );
          if (reflow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                start,
                const SizedBox(height: DearSpacing.space12),
                end,
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: start),
              const SizedBox(width: DearSpacing.space12),
              Expanded(child: end),
            ],
          );
        },
      ),
    );
  }
}

class _NotificationSettingsSkeleton extends StatelessWidget {
  const _NotificationSettingsSkeleton();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: 6,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, index) => Container(
        height: index == 0 ? 92 : 68,
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.outlineVariant),
        ),
      ),
    );
  }
}

String _hourLabel(int hour) {
  final period = hour < 12 ? '오전' : '오후';
  final display = hour % 12 == 0 ? 12 : hour % 12;
  return '$period $display시';
}

String _notificationSettingsError(String action, Object error) {
  return '알림 설정을 $action 못했어요. ${toFriendlyErrorMessage(error)}';
}

bool _samePreferences(
  NotificationPreferences? first,
  NotificationPreferences? second,
) {
  if (identical(first, second)) return true;
  if (first == null || second == null) return false;
  return first.userId == second.userId &&
      first.messageEnabled == second.messageEnabled &&
      first.imageEnabled == second.imageEnabled &&
      first.anniversaryEnabled == second.anniversaryEnabled &&
      first.gameEnabled == second.gameEnabled &&
      first.quietEnabled == second.quietEnabled &&
      first.quietStartHour == second.quietStartHour &&
      first.quietEndHour == second.quietEndHour &&
      first.anniversaryHour == second.anniversaryHour &&
      first.timezone == second.timezone &&
      first.isServerSynced == second.isServerSynced;
}
