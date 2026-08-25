import 'package:couple_chat_app/src/common/dear_design.dart';
import 'package:couple_chat_app/src/common/error_mapper.dart';
import 'package:couple_chat_app/src/features/auth/data/auth_providers.dart';
import 'package:couple_chat_app/src/features/notifications/data/notification_preferences.dart';
import 'package:couple_chat_app/src/features/notifications/data/push_registration_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class NotificationSettingsPage extends ConsumerStatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  ConsumerState<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState
    extends ConsumerState<NotificationSettingsPage> {
  NotificationPreferences? _draft;
  bool _saving = false;
  bool _registering = false;

  Future<void> _save() async {
    final draft = _draft;
    if (draft == null || _saving) return;
    setState(() => _saving = true);
    try {
      await ref.read(saveNotificationPreferencesProvider)(draft);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('알림 설정을 저장했어요.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(toFriendlyErrorMessage(error))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _connectSystemNotifications(String userId) async {
    if (_registering) return;
    setState(() => _registering = true);
    try {
      await ref
          .read(pushRegistrationServiceProvider)
          .syncForSession(userId: userId);
      ref.invalidate(notificationSystemStatusProvider);
      final status = await ref.read(notificationSystemStatusProvider.future);
      if (!mounted) return;
      final message = status.isAuthorized && status.hasFcmToken
          ? '이 기기의 알림 연결을 완료했어요.'
          : '시스템 설정에서 Dear 알림을 허용해 주세요.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(toFriendlyErrorMessage(error))),
      );
    } finally {
      if (mounted) setState(() => _registering = false);
    }
  }

  void _update(
    NotificationPreferences Function(NotificationPreferences current) change,
  ) {
    final current = _draft;
    if (current == null) return;
    setState(() => _draft = change(current));
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authSessionProvider).valueOrNull;
    final userId = session?.user.id;
    if (userId == null) {
      return const Scaffold(
        body: Center(child: Text('로그인 후 알림을 설정할 수 있어요.')),
      );
    }

    final preferencesAsync = ref.watch(notificationPreferencesProvider(userId));
    final systemStatusAsync = ref.watch(notificationSystemStatusProvider);
    final loaded = preferencesAsync.valueOrNull;
    if (_draft == null && loaded != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _draft == null) setState(() => _draft = loaded);
      });
    }

    return Scaffold(
      appBar: AppBar(title: const Text('알림 설정')),
      body: DearBackground(
        child: preferencesAsync.when(
          loading: () => const _NotificationSettingsSkeleton(),
          error: (error, _) => _SettingsError(
            message: toFriendlyErrorMessage(error),
            onRetry: () =>
                ref.invalidate(notificationPreferencesProvider(userId)),
          ),
          data: (preferences) {
            final draft = _draft ?? preferences;
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                _SystemStatusCard(
                  status: systemStatusAsync.valueOrNull,
                  serverSynced: preferences.isServerSynced,
                  loading: systemStatusAsync.isLoading || _registering,
                  onConnect: () => _connectSystemNotifications(userId),
                ),
                const SizedBox(height: 24),
                const _SectionLabel('받을 알림'),
                const SizedBox(height: 10),
                _SettingsSection(
                  children: [
                    _PreferenceSwitchRow(
                      icon: Icons.chat_bubble_outline_rounded,
                      title: '메시지 알림',
                      subtitle: '상대방이 메시지를 보내면 알려드려요',
                      value: draft.messageEnabled,
                      onChanged: (value) => _update(
                        (current) => current.copyWith(messageEnabled: value),
                      ),
                    ),
                    _PreferenceSwitchRow(
                      icon: Icons.image_outlined,
                      title: '사진 알림',
                      subtitle: '사진 메시지가 도착하면 알려드려요',
                      value: draft.imageEnabled,
                      onChanged: (value) => _update(
                        (current) => current.copyWith(imageEnabled: value),
                      ),
                    ),
                    _PreferenceSwitchRow(
                      icon: Icons.favorite_border_rounded,
                      title: '기념일 알림',
                      subtitle: '100일·주년·직접 추가한 날을 축하해요',
                      value: draft.anniversaryEnabled,
                      onChanged: (value) => _update(
                        (current) =>
                            current.copyWith(anniversaryEnabled: value),
                      ),
                    ),
                    _PreferenceSwitchRow(
                      icon: Icons.grid_4x4_rounded,
                      title: '오목 초대 알림',
                      subtitle: '상대방의 대국 신청과 재대결을 알려드려요',
                      value: draft.gameEnabled,
                      showDivider: false,
                      onChanged: (value) => _update(
                        (current) => current.copyWith(gameEnabled: value),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const _SectionLabel('시간'),
                const SizedBox(height: 10),
                _SettingsSection(
                  children: [
                    _TimeSelectorRow(
                      icon: Icons.celebration_outlined,
                      title: '기념일 축하 시간',
                      subtitle: '대한민국 시간 기준',
                      hour: draft.anniversaryHour,
                      enabled: draft.anniversaryEnabled,
                      onChanged: (value) => _update(
                        (current) => current.copyWith(anniversaryHour: value),
                      ),
                    ),
                    _PreferenceSwitchRow(
                      icon: Icons.bedtime_outlined,
                      title: '무음 시간',
                      subtitle: '알림은 받되 소리 없이 표시해요',
                      value: draft.quietEnabled,
                      showDivider: !draft.quietEnabled,
                      onChanged: (value) => _update(
                        (current) => current.copyWith(quietEnabled: value),
                      ),
                    ),
                    if (draft.quietEnabled)
                      _QuietHoursRow(
                        startHour: draft.quietStartHour,
                        endHour: draft.quietEndHour,
                        onStartChanged: (value) => _update(
                          (current) => current.copyWith(quietStartHour: value),
                        ),
                        onEndChanged: (value) => _update(
                          (current) => current.copyWith(quietEndHour: value),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                DearGradientButton(
                  label: _saving ? '저장 중...' : '변경 사항 저장',
                  icon: Icons.check_rounded,
                  onPressed: _saving ? null : _save,
                ),
              ],
            );
          },
        ),
      ),
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
    final authorized = status?.isAuthorized == true;
    final provisional = status?.isProvisional == true;
    final connected = authorized && status?.hasFcmToken == true;
    final title = provisional
        ? '알림이 임시 허용됐어요'
        : connected
            ? '이 기기 알림이 연결됐어요'
            : authorized
                ? '알림 토큰을 연결해 주세요'
                : '시스템 알림을 허용해 주세요';
    final subtitle = provisional
        ? '조용히 전달될 수 있어요. 시스템 설정에서 전체 허용으로 바꿀 수 있어요.'
        : connected
            ? '설정한 메시지와 기념일 알림을 받을 수 있어요.'
            : '한 번만 연결하면 이후에는 자동으로 유지돼요.';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: connected ? const Color(0xFFF2FAF6) : DearColors.coralSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: connected ? const Color(0xFFB8E2D2) : DearColors.line,
        ),
      ),
      child: Row(
        children: [
          DearIconBubble(
            icon: connected
                ? Icons.notifications_active_rounded
                : Icons.notifications_none_rounded,
            size: 48,
            iconSize: 24,
            background: Colors.white,
            color: connected ? const Color(0xFF3A8D70) : DearColors.coral,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: DearColors.ink,
                      ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: DearColors.secondary,
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
                      label: 'FCM',
                      connected: status?.hasFcmToken == true,
                    ),
                    _ConnectionStatusChip(
                      label: 'APNs',
                      connected: status?.hasApnsToken == true,
                    ),
                    _ConnectionStatusChip(
                      label: '서버 설정',
                      connected: serverSynced,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (!connected)
            TextButton(
              onPressed: loading ? null : onConnect,
              child: Text(loading ? '연결 중' : '연결'),
            ),
        ],
      ),
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
    final color = connected ? const Color(0xFF2F725C) : DearColors.secondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: connected ? const Color(0xFFE8F5EF) : DearColors.blush,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: connected ? const Color(0xFFB8E2D2) : DearColors.line,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            connected ? Icons.check_circle_rounded : Icons.info_outline_rounded,
            size: 13,
            color: color,
          ),
          const SizedBox(width: 4),
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
    return Text(
      label,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: DearColors.ink,
            fontWeight: FontWeight.w900,
          ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DearColors.line),
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
  final ValueChanged<bool> onChanged;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SwitchListTile(
          contentPadding: const EdgeInsets.fromLTRB(14, 5, 10, 5),
          secondary: Icon(icon, color: DearColors.coral),
          title: Text(title),
          subtitle: Text(subtitle),
          value: value,
          onChanged: onChanged,
        ),
        if (showDivider)
          const Divider(height: 1, indent: 54, color: DearColors.line),
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
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
          child: Row(
            children: [
              Icon(icon,
                  color: enabled ? DearColors.coral : DearColors.disabled),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: DearColors.secondary,
                          ),
                    ),
                  ],
                ),
              ),
              DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: hour,
                  borderRadius: BorderRadius.circular(12),
                  onChanged: enabled
                      ? (value) {
                          if (value != null) onChanged(value);
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
              ),
            ],
          ),
        ),
        const Divider(height: 1, indent: 54, color: DearColors.line),
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
  final ValueChanged<int> onStartChanged;
  final ValueChanged<int> onEndChanged;

  @override
  Widget build(BuildContext context) {
    Widget selector(String label, int value, ValueChanged<int> onChanged) {
      return Expanded(
        child: DropdownButtonFormField<int>(
          initialValue: value,
          decoration: InputDecoration(labelText: label, isDense: true),
          items: List.generate(
            24,
            (hour) => DropdownMenuItem(
              value: hour,
              child: Text(_hourLabel(hour)),
            ),
          ),
          onChanged: (next) {
            if (next != null) onChanged(next);
          },
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      child: Row(
        children: [
          selector('시작', startHour, onStartChanged),
          const SizedBox(width: 10),
          selector('종료', endHour, onEndChanged),
        ],
      ),
    );
  }
}

class _NotificationSettingsSkeleton extends StatelessWidget {
  const _NotificationSettingsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: 6,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, index) => Container(
        height: index == 0 ? 92 : 68,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: DearColors.line),
        ),
      ),
    );
  }
}

class _SettingsError extends StatelessWidget {
  const _SettingsError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 42),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('다시 시도'),
            ),
          ],
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
