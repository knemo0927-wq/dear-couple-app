import 'dart:convert';

import 'package:couple_chat_app/src/common/dear_design.dart';
import 'package:couple_chat_app/src/common/error_mapper.dart';
import 'package:couple_chat_app/src/features/auth/data/auth_providers.dart';
import 'package:couple_chat_app/src/features/auth/data/auth_repository.dart';
import 'package:couple_chat_app/src/features/settings/data/couple_prefs_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

typedef ShareDataExportAction = Future<void> Function(
  Map<String, dynamic> data, {
  Rect? sharePositionOrigin,
});

final shareDataExportProvider = Provider<ShareDataExportAction>((ref) {
  return (data, {sharePositionOrigin}) async {
    final date = DateTime.now().toIso8601String().split('T').first;
    final filename = 'dear-data-$date.json';
    final json = const JsonEncoder.withIndent('  ').convert(data);
    final file = XFile.fromData(
      Uint8List.fromList(utf8.encode(json)),
      mimeType: 'application/json',
      name: filename,
    );
    await Share.shareXFiles(
      [file],
      subject: 'Dear 데이터 내보내기',
      text: 'Dear에서 내보낸 계정 및 커플 데이터입니다.',
      fileNameOverrides: [filename],
      sharePositionOrigin: sharePositionOrigin,
    );
  };
});

/// Root destination for the More tab.
class ProfileSettingsPage extends ConsumerStatefulWidget {
  const ProfileSettingsPage({super.key});

  @override
  ConsumerState<ProfileSettingsPage> createState() =>
      _ProfileSettingsPageState();
}

class _ProfileSettingsPageState extends ConsumerState<ProfileSettingsPage> {
  String? _busyAction;

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(myProfileProvider);
    final avatarUrl = ref.watch(myAvatarUrlProvider).valueOrNull;
    final email = ref.watch(myAccountEmailProvider);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: false,
        title: const Text('더보기'),
      ),
      body: DearBackground(
        child: SafeArea(
          top: false,
          child: profileAsync.when(
            loading: () => const _MoreLoadingView(),
            error: (error, _) => _MoreErrorView(
              onRetry: () => ref.invalidate(myProfileProvider),
            ),
            data: (profile) {
              if (profile == null) {
                return const _MoreSignedOutView();
              }
              return _buildContent(
                context,
                profile: profile,
                avatarUrl: avatarUrl,
                email: email,
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context, {
    required ProfileInfo profile,
    required String? avatarUrl,
    required String? email,
  }) {
    final displayName = _profileDisplayName(profile);

    return ListView(
      key: const PageStorageKey<String>('more-root-scroll'),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        _ProfileHeader(
          displayName: displayName,
          avatarUrl: avatarUrl,
          isPaired: profile.isPaired,
          onEdit: () => context.push('/profile/edit'),
        ),
        const SizedBox(height: 26),
        const _SectionHeading(
          title: '우리의 기능',
          subtitle: '함께 쌓은 기록과 즐길 거리를 확인해요.',
        ),
        const SizedBox(height: 12),
        _FeatureGrid(
          onAnniversary: () => context.push('/anniversary-reminders'),
          onKoreaMap: () => context.push('/travel-map'),
          onWorldMap: () => context.push('/world-map'),
          onOmok: () => context.push('/mini-games'),
        ),
        const SizedBox(height: 26),
        const _SectionHeading(title: '알림과 화면'),
        const SizedBox(height: 10),
        _SettingsGroup(
          children: [
            _MoreTile(
              key: const ValueKey('more-notifications'),
              icon: Icons.notifications_none_rounded,
              title: '알림 설정',
              subtitle: '메시지, 기념일, 게임 알림을 관리해요.',
              onTap: () => context.push('/notifications'),
            ),
          ],
        ),
        const SizedBox(height: 26),
        const _SectionHeading(title: '계정'),
        const SizedBox(height: 10),
        _SettingsGroup(
          children: [
            _MoreTile(
              key: const ValueKey('more-account'),
              icon: Icons.alternate_email_rounded,
              title: '이메일 및 비밀번호',
              subtitle: email?.trim().isNotEmpty == true
                  ? email!
                  : '연결된 이메일 정보가 없어요.',
              onTap:
                  _busyAction == null ? () => _showAccountDialog(email) : null,
            ),
            _MoreTile(
              key: const ValueKey('more-connection'),
              icon: Icons.favorite_border_rounded,
              title: '연결 관리',
              subtitle: profile.isPaired
                  ? '상대와 안전하게 연결되어 있어요.'
                  : '초대 코드로 상대와 연결해 주세요.',
              onTap: _busyAction == null
                  ? () => _showConnectionSheet(profile)
                  : null,
            ),
            _MoreTile(
              key: const ValueKey('more-export'),
              icon: Icons.file_download_outlined,
              title: '데이터 내보내기',
              subtitle: '내 계정과 커플 기록을 JSON 파일로 받아요.',
              busy: _busyAction == 'export',
              onTap: _busyAction == null ? _exportData : null,
            ),
            _MoreTile(
              key: const ValueKey('more-logout'),
              icon: Icons.logout_rounded,
              title: '로그아웃',
              subtitle: '이 기기에서 Dear 계정 연결을 종료해요.',
              busy: _busyAction == 'logout',
              onTap: _busyAction == null ? _confirmLogout : null,
            ),
          ],
        ),
        const SizedBox(height: 26),
        const _SectionHeading(
          title: '위험 작업',
          subtitle: '삭제되는 범위를 확인한 뒤 진행해 주세요.',
        ),
        const SizedBox(height: 10),
        _DangerGroup(
          children: [
            if (profile.isPaired)
              _MoreTile(
                key: const ValueKey('more-disconnect'),
                icon: Icons.link_off_rounded,
                title: '커플 연결 해제',
                subtitle: '상대와의 연결을 끊고 페어링 화면으로 돌아가요.',
                danger: true,
                busy: _busyAction == 'disconnect',
                onTap: _busyAction == null ? _confirmDisconnect : null,
              ),
            _MoreTile(
              key: const ValueKey('more-delete-account'),
              icon: Icons.person_remove_outlined,
              title: '계정 삭제',
              subtitle: '계정과 복구할 수 없는 개인 데이터를 삭제해요.',
              danger: true,
              busy: _busyAction == 'delete',
              onTap: _busyAction == null ? _confirmDeleteAccount : null,
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _showAccountDialog(String? email) async {
    final normalizedEmail = email?.trim() ?? '';
    final sendReset = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('이메일 및 비밀번호'),
        content: Text(
          normalizedEmail.isEmpty
              ? '이 계정에는 비밀번호 재설정 메일을 보낼 이메일이 없어요.'
              : '$normalizedEmail\n\n비밀번호를 변경하려면 재설정 메일을 보내 주세요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('닫기'),
          ),
          if (normalizedEmail.isNotEmpty)
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('재설정 메일 보내기'),
            ),
        ],
      ),
    );
    if (sendReset != true || !mounted) return;

    await _runAction(
      key: 'password-reset',
      action: () => ref.read(authPasswordResetProvider)(normalizedEmail),
      successMessage: '비밀번호 재설정 메일을 보냈어요.',
    );
  }

  Future<void> _showConnectionSheet(ProfileInfo profile) async {
    if (!profile.isPaired) {
      context.go('/');
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '커플 연결',
                style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 8),
              const Text(
                '현재 상대와 연결되어 있어 채팅, 앨범, 기념일과 여행 기록을 함께 사용하고 있어요.',
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(text: profile.pairingCode),
                  );
                  if (!sheetContext.mounted) return;
                  Navigator.of(sheetContext).pop();
                  _showMessage('내 초대 코드를 복사했어요.');
                },
                icon: const Icon(Icons.copy_rounded),
                label: const Text('내 초대 코드 복사'),
              ),
              const SizedBox(height: 8),
              Text(
                '연결을 종료하려면 더보기 화면의 위험 작업에서 커플 연결 해제를 선택해 주세요.',
                style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                      color: DearColors.secondary,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _exportData() async {
    final renderBox = context.findRenderObject();
    final origin = renderBox is RenderBox
        ? renderBox.localToGlobal(Offset.zero) & renderBox.size
        : null;
    await _runAction(
      key: 'export',
      action: () async {
        final data = await ref.read(exportMyDataProvider)();
        if (!mounted) return;
        await ref.read(shareDataExportProvider)(
          data,
          sharePositionOrigin: origin,
        );
      },
    );
  }

  Future<void> _confirmLogout() async {
    final confirmed = await _showConfirmation(
      title: '로그아웃할까요?',
      message: '이 기기의 로그인 정보만 지워지며 커플 기록은 유지돼요.',
      confirmLabel: '로그아웃',
    );
    if (!confirmed || !mounted) return;
    await _runAction(
      key: 'logout',
      action: ref.read(authSignOutProvider),
      onSuccess: () {
        if (mounted) context.go('/auth');
      },
    );
  }

  Future<void> _confirmDisconnect() async {
    final confirmed = await _showConfirmation(
      title: '커플 연결을 해제할까요?',
      message:
          '두 계정의 연결이 함께 해제돼요. 공유 기록의 보존·삭제 정책은 서버 정책에 따라 처리되며, 다시 연결하려면 새 초대 코드가 필요해요.',
      confirmLabel: '연결 해제',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await _runAction(
      key: 'disconnect',
      action: ref.read(disconnectMyCoupleProvider),
      onSuccess: () {
        if (mounted) context.go('/');
      },
    );
  }

  Future<void> _confirmDeleteAccount() async {
    final confirmed = await _showConfirmation(
      title: '계정을 영구 삭제할까요?',
      message:
          '이 작업은 되돌릴 수 없어요. 내 프로필과 인증 계정이 삭제되며, 커플 공유 데이터는 서버의 보존 정책에 따라 함께 정리될 수 있어요.',
      confirmLabel: '계정 영구 삭제',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await _runAction(
      key: 'delete',
      action: ref.read(deleteMyAccountProvider),
      onSuccess: () {
        if (mounted) context.go('/auth');
      },
    );
  }

  Future<bool> _showConfirmation({
    required String title,
    required String message,
    required String confirmLabel,
    bool destructive = false,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('취소'),
              ),
              FilledButton(
                style: destructive
                    ? FilledButton.styleFrom(backgroundColor: DearColors.error)
                    : null,
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(confirmLabel),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _runAction({
    required String key,
    required Future<void> Function() action,
    String? successMessage,
    VoidCallback? onSuccess,
  }) async {
    if (_busyAction != null) return;
    setState(() => _busyAction = key);
    try {
      await action();
      if (!mounted) return;
      if (successMessage != null) _showMessage(successMessage);
      onSuccess?.call();
    } catch (error) {
      if (!mounted) return;
      _showMessage(toFriendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busyAction = null);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

/// Detail destination for profile and relationship presentation fields.
class ProfileEditPage extends ConsumerStatefulWidget {
  const ProfileEditPage({super.key});

  @override
  ConsumerState<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends ConsumerState<ProfileEditPage> {
  String? _busyAction;

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(myProfileProvider);
    final avatarUrl = ref.watch(myAvatarUrlProvider).valueOrNull;
    final anniversaryAsync = ref.watch(anniversaryDateProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('프로필 편집')),
      body: DearBackground(
        child: SafeArea(
          top: false,
          child: profileAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => _MoreErrorView(
              onRetry: () => ref.invalidate(myProfileProvider),
            ),
            data: (profile) {
              if (profile == null) return const _MoreSignedOutView();
              final anniversary = anniversaryAsync.valueOrNull;
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  Center(
                    child: _ProfileAvatar(
                      avatarUrl: avatarUrl,
                      radius: 48,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        key: const ValueKey('profile-photo-change'),
                        onPressed:
                            _busyAction == null ? _selectProfilePhoto : null,
                        icon: _busyAction == 'avatar'
                            ? const SizedBox.square(
                                dimension: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.photo_library_outlined),
                        label: const Text('사진 변경'),
                      ),
                      if (profile.avatarPath != null) ...[
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed:
                              _busyAction == null ? _clearProfilePhoto : null,
                          child: const Text('삭제'),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 28),
                  const _SectionHeading(title: '내 프로필'),
                  const SizedBox(height: 10),
                  _SettingsGroup(
                    children: [
                      _MoreTile(
                        key: const ValueKey('profile-edit-nickname'),
                        icon: Icons.badge_outlined,
                        title: '닉네임',
                        subtitle: _profileDisplayName(profile),
                        busy: _busyAction == 'nickname',
                        onTap: _busyAction == null
                            ? () => _editNickname(profile.nickname)
                            : null,
                      ),
                      _MoreTile(
                        icon: Icons.favorite_outline_rounded,
                        title: '연결 상태',
                        subtitle:
                            profile.isPaired ? '상대와 연결됨' : '아직 상대와 연결되지 않았어요.',
                        showChevron: false,
                      ),
                    ],
                  ),
                  const SizedBox(height: 26),
                  const _SectionHeading(title: '우리의 시작일'),
                  const SizedBox(height: 10),
                  _SettingsGroup(
                    children: [
                      _MoreTile(
                        key: const ValueKey('profile-edit-anniversary'),
                        icon: Icons.calendar_month_outlined,
                        title: '기념일 기준일',
                        subtitle: anniversary == null
                            ? '아직 설정되지 않았어요.'
                            : '${anniversaryDateKoreanLabel(anniversary)} · ${anniversaryDdayLabel(anniversary)}',
                        busy: _busyAction == 'anniversary',
                        onTap: profile.isPaired && _busyAction == null
                            ? () => _selectAnniversary(profile, anniversary)
                            : null,
                      ),
                      if (anniversary != null)
                        _MoreTile(
                          key: const ValueKey('profile-clear-anniversary'),
                          icon: Icons.restart_alt_rounded,
                          title: '기준일 초기화',
                          subtitle: '자동 기념일 계산 기준을 지워요.',
                          onTap: profile.isPaired && _busyAction == null
                              ? () => _clearAnniversary(profile)
                              : null,
                        ),
                    ],
                  ),
                  const SizedBox(height: 26),
                  const _SectionHeading(title: '내 초대 코드'),
                  const SizedBox(height: 10),
                  _InviteCodeCard(code: profile.pairingCode),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _editNickname(String current) async {
    final nickname = await _showNicknameEditDialog(
      context,
      initialValue: current,
    );
    if (nickname == null || !mounted) return;
    await _runEditAction(
      key: 'nickname',
      action: () => ref.read(updateMyNicknameProvider)(nickname),
      successMessage: '닉네임을 변경했어요.',
    );
  }

  Future<void> _selectProfilePhoto() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (picked == null || !mounted) return;
      final bytes = await picked.readAsBytes();
      final extension = _resolveImageExtension(picked.name);
      await _runEditAction(
        key: 'avatar',
        action: () => ref.read(updateMyAvatarProvider)(
          bytes: bytes,
          extension: extension,
        ),
        successMessage: '프로필 사진을 변경했어요.',
      );
    } catch (error) {
      if (mounted) _showEditMessage(toFriendlyErrorMessage(error));
    }
  }

  Future<void> _clearProfilePhoto() async {
    await _runEditAction(
      key: 'avatar',
      action: ref.read(clearMyAvatarProvider),
      successMessage: '프로필 사진을 삭제했어요.',
    );
  }

  Future<void> _selectAnniversary(
    ProfileInfo profile,
    DateTime? current,
  ) async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 5),
      helpText: '우리의 시작일 선택',
      cancelText: '취소',
      confirmText: '저장',
    );
    if (selected == null || !mounted || profile.coupleId == null) return;
    await _runEditAction(
      key: 'anniversary',
      action: () => ref.read(setAnniversaryDateProvider)(
        coupleId: profile.coupleId!,
        date: selected,
      ),
      successMessage: '우리의 시작일을 저장했어요.',
    );
  }

  Future<void> _clearAnniversary(ProfileInfo profile) async {
    final coupleId = profile.coupleId;
    if (coupleId == null) return;
    await _runEditAction(
      key: 'anniversary',
      action: () => ref.read(setAnniversaryDateProvider)(
        coupleId: coupleId,
        date: null,
      ),
      successMessage: '기준일을 초기화했어요.',
    );
  }

  Future<void> _runEditAction({
    required String key,
    required Future<void> Function() action,
    required String successMessage,
  }) async {
    if (_busyAction != null) return;
    setState(() => _busyAction = key);
    try {
      await action();
      if (mounted) _showEditMessage(successMessage);
    } catch (error) {
      if (mounted) _showEditMessage(toFriendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busyAction = null);
    }
  }

  void _showEditMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.displayName,
    required this.avatarUrl,
    required this.isPaired,
    required this.onEdit,
  });

  final String displayName;
  final String? avatarUrl;
  final bool isPaired;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return DearCard(
      radius: 18,
      padding: const EdgeInsets.all(18),
      shadowOpacity: 0.55,
      child: Row(
        children: [
          _ProfileAvatar(avatarUrl: avatarUrl, radius: 34),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: DearColors.ink,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Icon(
                      isPaired
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      size: 16,
                      color: isPaired ? DearColors.coral : DearColors.secondary,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        isPaired ? '상대와 연결됨' : '연결 대기 중',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: DearColors.secondary,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            key: const ValueKey('more-profile-edit'),
            onPressed: onEdit,
            child: const Text('편집'),
          ),
        ],
      ),
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.avatarUrl, required this.radius});

  final String? avatarUrl;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final url = avatarUrl?.trim();
    return CircleAvatar(
      radius: radius,
      backgroundColor: DearColors.coralSoft,
      foregroundImage: url == null || url.isEmpty
          ? null
          : NetworkImage(url) as ImageProvider,
      child: Icon(
        Icons.favorite_rounded,
        color: DearColors.coral,
        size: radius * 0.85,
      ),
    );
  }
}

class _FeatureGrid extends StatelessWidget {
  const _FeatureGrid({
    required this.onAnniversary,
    required this.onKoreaMap,
    required this.onWorldMap,
    required this.onOmok,
  });

  final VoidCallback onAnniversary;
  final VoidCallback onKoreaMap;
  final VoidCallback onWorldMap;
  final VoidCallback onOmok;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _FeatureButton(
                key: const ValueKey('more-anniversary'),
                icon: Icons.favorite_outline_rounded,
                label: '기념일',
                onTap: onAnniversary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _FeatureButton(
                key: const ValueKey('more-korea-map'),
                icon: Icons.map_outlined,
                label: '국내 지도',
                onTap: onKoreaMap,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _FeatureButton(
                key: const ValueKey('more-world-map'),
                icon: Icons.public_rounded,
                label: '세계 지도',
                onTap: onWorldMap,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _FeatureButton(
                key: const ValueKey('more-omok'),
                icon: Icons.grid_4x4_rounded,
                label: '오목',
                onTap: onOmok,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _FeatureButton extends StatelessWidget {
  const _FeatureButton({
    required this.icon,
    required this.label,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: DearColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: DearColors.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 86),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                DearIconBubble(icon: icon, size: 42, iconSize: 21),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: DearColors.ink,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: DearColors.muted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: DearColors.ink,
                fontWeight: FontWeight.w800,
              ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: DearColors.secondary,
                ),
          ),
        ],
      ],
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return _TileGroup(children: children);
  }
}

class _DangerGroup extends StatelessWidget {
  const _DangerGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return _TileGroup(
      backgroundColor: const Color(0xFFFFF8F8),
      borderColor: DearColors.error.withValues(alpha: 0.22),
      children: children,
    );
  }
}

class _TileGroup extends StatelessWidget {
  const _TileGroup({
    required this.children,
    this.backgroundColor = DearColors.card,
    this.borderColor = DearColors.line,
  });

  final List<Widget> children;
  final Color backgroundColor;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    final divided = <Widget>[];
    for (var index = 0; index < children.length; index++) {
      if (index > 0) {
        divided.add(const Divider(height: 1, indent: 64));
      }
      divided.add(children[index]);
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Column(children: divided),
    );
  }
}

class _MoreTile extends StatelessWidget {
  const _MoreTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.busy = false,
    this.danger = false,
    this.showChevron = true,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool busy;
  final bool danger;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final foreground = danger ? DearColors.error : DearColors.ink;
    return ListTile(
      minVerticalPadding: 14,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      leading: Icon(icon, color: danger ? DearColors.error : DearColors.coral),
      title: Text(
        title,
        style: TextStyle(color: foreground, fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: busy
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : showChevron && onTap != null
              ? const Icon(Icons.chevron_right_rounded)
              : null,
      onTap: onTap,
    );
  }
}

class _InviteCodeCard extends StatelessWidget {
  const _InviteCodeCard({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final value = code.trim();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: DearColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: DearColors.line),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 12, 18),
        child: Row(
          children: [
            Expanded(
              child: SelectableText(
                value.isEmpty ? '코드 없음' : value,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: DearColors.coralText,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                    ),
              ),
            ),
            IconButton(
              tooltip: '초대 코드 복사',
              onPressed: value.isEmpty
                  ? null
                  : () async {
                      await Clipboard.setData(ClipboardData(text: value));
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('초대 코드를 복사했어요.')),
                      );
                    },
              icon: const Icon(Icons.copy_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _MoreLoadingView extends StatelessWidget {
  const _MoreLoadingView();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: const [
        _Skeleton(height: 108),
        SizedBox(height: 26),
        _Skeleton(height: 18, width: 90),
        SizedBox(height: 12),
        _Skeleton(height: 182),
        SizedBox(height: 26),
        _Skeleton(height: 150),
        SizedBox(height: 16),
        _Skeleton(height: 260),
      ],
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton({required this.height, this.width});

  final double height;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        width: width ?? double.infinity,
        height: height,
        decoration: BoxDecoration(
          color: DearColors.coralSoft,
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }
}

class _MoreErrorView extends StatelessWidget {
  const _MoreErrorView({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const DearIconBubble(icon: Icons.wifi_off_rounded),
            const SizedBox(height: 16),
            const Text('프로필 정보를 불러오지 못했어요.'),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('다시 시도')),
          ],
        ),
      ),
    );
  }
}

class _MoreSignedOutView extends StatelessWidget {
  const _MoreSignedOutView();

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('로그인이 필요해요.'));
  }
}

Future<String?> _showNicknameEditDialog(
  BuildContext context, {
  required String initialValue,
}) async {
  final controller = TextEditingController(text: initialValue);
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('닉네임 변경'),
      content: TextField(
        controller: controller,
        maxLength: 20,
        autofocus: true,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(hintText: '닉네임을 입력해 주세요'),
        onSubmitted: (_) {
          final value = controller.text.trim();
          if (value.isNotEmpty) Navigator.of(dialogContext).pop(value);
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () {
            final value = controller.text.trim();
            if (value.isNotEmpty) Navigator.of(dialogContext).pop(value);
          },
          child: const Text('저장'),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}

String _profileDisplayName(ProfileInfo profile) {
  final nickname = profile.nickname.trim();
  if (nickname.isNotEmpty) return nickname;
  final end = profile.userId.length < 8 ? profile.userId.length : 8;
  return '사용자 ${profile.userId.substring(0, end)}';
}

String _resolveImageExtension(String filename) {
  final dotIndex = filename.lastIndexOf('.');
  if (dotIndex < 0 || dotIndex >= filename.length - 1) return 'jpg';
  final extension = filename.substring(dotIndex + 1).trim().toLowerCase();
  if (extension == 'jpeg') return 'jpg';
  return extension.isEmpty ? 'jpg' : extension;
}
