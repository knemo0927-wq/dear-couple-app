import 'package:couple_chat_app/src/common/dear_design.dart';
import 'package:couple_chat_app/src/features/anniversary/data/anniversary_providers.dart';
import 'package:couple_chat_app/src/features/auth/data/auth_providers.dart';
import 'package:couple_chat_app/src/features/chat/data/chat_providers.dart';
import 'package:couple_chat_app/src/features/chat/data/memory_album_providers.dart';
import 'package:couple_chat_app/src/features/chat/data/memory_album_repository.dart';
import 'package:couple_chat_app/src/features/notifications/data/notification_inbox.dart';
import 'package:couple_chat_app/src/features/settings/data/couple_prefs_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

String? _homeChatTimeLabel(DateTime? date) {
  if (date == null) return null;

  final local = date.toLocal();
  final period = local.hour < 12 ? '오전' : '오후';
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  return '$period $hour:$minute';
}

String? _otherProfileValue(
  Map<String, String>? values,
  String currentUserId,
) {
  if (values == null) return null;
  for (final entry in values.entries) {
    final value = entry.value.trim();
    if (entry.key != currentUserId && value.isNotEmpty) return value;
  }
  return null;
}

class ChatListPage extends ConsumerWidget {
  const ChatListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(myProfileProvider);
    final anniversaryAsync = ref.watch(anniversaryDateProvider);

    return profileAsync.when(
      loading: () => const Scaffold(
        appBar: _HomeAppBar(),
        body: DearBackground(child: _HomeLoadingSkeleton()),
      ),
      error: (error, _) => Scaffold(
        appBar: const _HomeAppBar(),
        body: DearBackground(
          child: _HomeLoadError(
            onRetry: () => ref.invalidate(myProfileProvider),
          ),
        ),
      ),
      data: (profile) {
        if (profile == null) {
          return const Scaffold(body: Center(child: Text('로그인이 필요합니다.')));
        }

        final unreadCountAsync = profile.isPaired
            ? ref.watch(chatUnreadCountProvider(profile.coupleId!))
            : const AsyncValue<int>.data(0);
        final unreadCount = unreadCountAsync.valueOrNull ?? 0;
        final chatPreview = profile.isPaired
            ? ref
                .watch(chatConversationPreviewProvider(profile.coupleId!))
                .valueOrNull
            : null;

        final notificationInboxAsync =
            ref.watch(notificationInboxProvider(profile.userId));
        final notificationUnreadCount = (notificationInboxAsync.valueOrNull ??
                const <NotificationInboxItem>[])
            .where((notification) => notification.isUnread)
            .length;
        final gameUnreadCount = (notificationInboxAsync.valueOrNull ??
                const <NotificationInboxItem>[])
            .where(
              (notification) =>
                  notification.isUnread && notification.category == 'game',
            )
            .length;

        final anniversaryDate = anniversaryAsync.valueOrNull;
        final nextAnniversaryAsync = profile.isPaired
            ? ref.watch(
                upcomingAnniversaryTimelineProvider(
                  AnniversaryTimelineQuery(
                    coupleId: profile.coupleId!,
                    limit: 1,
                  ),
                ),
              )
            : const AsyncValue<List<AnniversaryTimelineEntry>>.data(
                <AnniversaryTimelineEntry>[],
              );
        final chatPath = profile.isPaired ? '/chat/${profile.coupleId!}' : '/';
        final displayName = profile.isPaired
            ? '우리'
            : (profile.nickname.trim().isEmpty
                ? 'Dear'
                : profile.nickname.trim());
        final avatarUrlMap = profile.isPaired && profile.coupleId != null
            ? ref
                .watch(coupleAvatarUrlMapProvider(profile.coupleId!))
                .valueOrNull
            : null;
        final avatarUrls =
            avatarUrlMap?.values.toList(growable: false) ?? const <String>[];
        final partnerAvatarUrl =
            _otherProfileValue(avatarUrlMap, profile.userId);
        final nicknameMap = profile.isPaired && profile.coupleId != null
            ? ref
                .watch(coupleNicknameMapProvider(profile.coupleId!))
                .valueOrNull
            : null;
        final partnerName =
            _otherProfileValue(nicknameMap, profile.userId) ?? '상대방';
        final nextTimeline = nextAnniversaryAsync.valueOrNull;
        final nextAnniversaryEntry =
            nextTimeline == null || nextTimeline.isEmpty
                ? null
                : nextTimeline.first;

        return Scaffold(
          appBar: _HomeAppBar(
            unreadCount: notificationUnreadCount,
            onNotifications: () => context.push('/notification-inbox'),
          ),
          body: DearBackground(
            child: SafeArea(
              top: false,
              child: ListView(
                key: const PageStorageKey<String>('dear-home-scroll'),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                children: [
                  _HomeGreeting(
                    displayName: displayName,
                    leftAvatarUrl: avatarUrls.isNotEmpty ? avatarUrls[0] : null,
                    rightAvatarUrl:
                        avatarUrls.length > 1 ? avatarUrls[1] : null,
                  ),
                  const SizedBox(height: 18),
                  _RelationshipHero(
                    isPaired: profile.isPaired,
                    anniversaryDate: anniversaryDate,
                    onOpen: () => context.push('/anniversary-reminders'),
                  ),
                  const SizedBox(height: 14),
                  _PrimaryChatCard(
                    isPaired: profile.isPaired,
                    unreadCount: unreadCount,
                    latestPreview: chatPreview?.text,
                    latestTimeLabel: _homeChatTimeLabel(chatPreview?.createdAt),
                    partnerName: partnerName,
                    partnerAvatarUrl: partnerAvatarUrl,
                    onTap: () => context.push(chatPath),
                  ),
                  const SizedBox(height: 16),
                  _NextAnniversaryCard(
                    anniversaryDate: anniversaryDate,
                    upcoming: nextAnniversaryEntry,
                    loading: nextAnniversaryAsync.isLoading,
                    hasError: nextAnniversaryAsync.hasError,
                  ),
                  const SizedBox(height: 22),
                  _RecentMemoriesStrip(coupleId: profile.coupleId),
                  const SizedBox(height: 22),
                  const _SectionTitle(
                    title: '빠른 실행',
                    subtitle: '자주 찾는 우리의 기능을 바로 열어보세요.',
                  ),
                  const SizedBox(height: 12),
                  _FeatureGrid(
                    items: [
                      _FeatureItem(
                        glyph: _FeatureGlyph.anniversary,
                        title: '기념일',
                        subtitle: anniversaryDate == null
                            ? 'D-day 설정'
                            : anniversaryDdayLabel(anniversaryDate),
                        onTap: () => context.push('/anniversary-reminders'),
                      ),
                      _FeatureItem(
                        glyph: _FeatureGlyph.koreaMap,
                        title: '여행 지도',
                        subtitle: '함께한 장소 보기',
                        onTap: () => context.push('/travel-map'),
                      ),
                      _FeatureItem(
                        glyph: _FeatureGlyph.omok,
                        title: '오목',
                        subtitle: gameUnreadCount > 0
                            ? '새 요청 $gameUnreadCount개'
                            : '한 판 하러 가기',
                        badgeCount: gameUnreadCount,
                        onTap: () => context.push('/mini-games'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HomeLoadingSkeleton extends StatelessWidget {
  const _HomeLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        physics: const NeverScrollableScrollPhysics(),
        children: [
          Row(
            children: [
              Expanded(child: _skeleton(scheme, height: 54)),
              const SizedBox(width: 28),
              _skeleton(scheme, width: 116, height: 68, radius: 34),
            ],
          ),
          const SizedBox(height: 18),
          _skeleton(scheme, height: 168, radius: 28),
          const SizedBox(height: 14),
          _skeleton(scheme, height: 90),
          const SizedBox(height: 18),
          _skeleton(scheme, height: 88),
          const SizedBox(height: 22),
          _skeleton(scheme, height: 168, radius: 14),
        ],
      ),
    );
  }

  Widget _skeleton(
    ColorScheme scheme, {
    double? width,
    required double height,
    double radius = DearRadii.medium,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: scheme.outlineVariant),
      ),
    );
  }
}

class _HomeLoadError extends StatelessWidget {
  const _HomeLoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 44,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              '홈을 불러오지 못했어요.\n연결을 확인하고 다시 시도해 주세요.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.45,
                  ),
            ),
            const SizedBox(height: 16),
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

class _HomeGreeting extends StatelessWidget {
  const _HomeGreeting({
    required this.displayName,
    required this.leftAvatarUrl,
    required this.rightAvatarUrl,
  });

  final String displayName;
  final String? leftAvatarUrl;
  final String? rightAvatarUrl;

  @override
  Widget build(BuildContext context) {
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.6;
    final scheme = Theme.of(context).colorScheme;
    if (largeText) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: '안녕하세요, $displayName '),
                TextSpan(
                  text: '♥',
                  style: TextStyle(color: scheme.primary),
                ),
              ],
            ),
            key: const ValueKey('home-greeting-title'),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: scheme.onSurface,
                  fontSize: 21,
                  fontWeight: FontWeight.w600,
                  height: 1.18,
                  letterSpacing: 0,
                ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  '오늘도 좋은 하루 보내세요',
                  maxLines: 2,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                      ),
                ),
              ),
              const SizedBox(width: 12),
              DearAvatarPair(
                leftImageUrl: leftAvatarUrl,
                rightImageUrl: rightAvatarUrl,
                size: 58,
              ),
            ],
          ),
        ],
      );
    }
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      '안녕하세요, $displayName',
                      maxLines: largeText ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: scheme.onSurface,
                            fontSize: 21,
                            fontWeight: FontWeight.w600,
                            height: 1.18,
                            letterSpacing: 0,
                          ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    '♥',
                    style: TextStyle(
                      color: scheme.primary,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '오늘도 좋은 하루 보내세요',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                    ),
              ),
            ],
          ),
        ),
        DearAvatarPair(
          leftImageUrl: leftAvatarUrl,
          rightImageUrl: rightAvatarUrl,
          size: 68,
        ),
      ],
    );
  }
}

class _HomeAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _HomeAppBar({
    this.unreadCount = 0,
    this.onNotifications,
  });

  final int unreadCount;
  final VoidCallback? onNotifications;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppBar(
      title: const _DearHomeTitle(),
      centerTitle: false,
      actions: [
        Semantics(
          button: true,
          label: unreadCount > 0 ? '읽지 않은 알림 $unreadCount개' : '알림',
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                tooltip: '알림',
                onPressed: onNotifications,
                icon: Icon(
                  Icons.notifications_none_rounded,
                  key: const ValueKey('home-notifications-icon'),
                  color: scheme.onSurface,
                  size: 28,
                ),
              ),
              if (unreadCount > 0)
                Positioned(
                  right: 5,
                  top: 4,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 18),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: scheme.surfaceContainerLowest,
                        width: 1.5,
                      ),
                    ),
                    child: Text(
                      unreadCount > 99 ? '99+' : '$unreadCount',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: scheme.onPrimary,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 6),
      ],
    );
  }
}

class _DearHomeTitle extends StatelessWidget {
  const _DearHomeTitle();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const DearLogoMark(size: 34),
        const SizedBox(width: 8),
        Text(
          'Dear',
          style: Theme.of(context).appBarTheme.titleTextStyle?.copyWith(
                color: scheme.primary,
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
        ),
      ],
    );
  }
}

class _RelationshipHero extends StatelessWidget {
  const _RelationshipHero({
    required this.isPaired,
    required this.anniversaryDate,
    required this.onOpen,
  });

  final bool isPaired;
  final DateTime? anniversaryDate;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dday = !isPaired
        ? '연결 대기'
        : anniversaryDate == null
            ? 'D+ -'
            : anniversaryDdayLabel(anniversaryDate!);
    final firstDateLabel = anniversaryDate == null
        ? '설정 전'
        : anniversaryDateKoreanLabel(anniversaryDate!);

    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.6;

    final titleStyle = Theme.of(context).textTheme.titleSmall?.copyWith(
          color: scheme.primary,
          fontSize: 16,
          fontWeight: FontWeight.w700,
          height: 1.1,
        );
    final ddayStyle = Theme.of(context).textTheme.displayMedium?.copyWith(
          color: scheme.primary,
          fontWeight: FontWeight.w800,
          fontSize: 44,
          letterSpacing: 0,
          height: 0.96,
        );
    final dateStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          height: 1.2,
        );

    final content = largeText
        ? Padding(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('우리의 연애', style: titleStyle),
                const SizedBox(height: 12),
                Text(dday, style: ddayStyle),
                const SizedBox(height: 8),
                Text('$firstDateLabel부터 함께 ♥', style: dateStyle),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.bottomRight,
                  child: ExcludeSemantics(
                    child: SizedBox(
                      width: 132,
                      height: 104,
                      child: Image.asset(
                        'assets/images/dear_home_hero_mascots.png',
                        fit: BoxFit.contain,
                        alignment: Alignment.bottomRight,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          )
        : SizedBox(
            height: 168,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final imageWidth = constraints.maxWidth * 0.4;
                final textWidth = constraints.maxWidth * 0.58;

                return Stack(
                  children: [
                    Positioned(
                      right: 24,
                      bottom: 10,
                      width: imageWidth,
                      height: 132,
                      child: ExcludeSemantics(
                        child: Image.asset(
                          'assets/images/dear_home_hero_mascots.png',
                          fit: BoxFit.contain,
                          alignment: Alignment.bottomRight,
                        ),
                      ),
                    ),
                    Positioned(
                      left: 28,
                      top: 32,
                      width: textWidth,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('우리의 연애', style: titleStyle),
                          const SizedBox(height: 20),
                          Text(dday, maxLines: 1, style: ddayStyle),
                          const SizedBox(height: 13),
                          Text(
                            '$firstDateLabel부터 함께 ♥',
                            maxLines: 2,
                            style: dateStyle,
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          );

    return Semantics(
      key: const ValueKey('relationship-hero'),
      button: true,
      label: '기념일, $dday, $firstDateLabel부터 함께',
      onTap: onOpen,
      excludeSemantics: true,
      child: DearCard(
        padding: EdgeInsets.zero,
        radius: 28,
        gradient: DearGradients.softCardFor(context),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onOpen,
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}

class _PrimaryChatCard extends StatelessWidget {
  const _PrimaryChatCard({
    required this.isPaired,
    required this.unreadCount,
    required this.latestPreview,
    required this.latestTimeLabel,
    required this.partnerName,
    required this.partnerAvatarUrl,
    required this.onTap,
  });

  final bool isPaired;
  final int unreadCount;
  final String? latestPreview;
  final String? latestTimeLabel;
  final String partnerName;
  final String? partnerAvatarUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.6;
    final stackedMeta = largeText || MediaQuery.sizeOf(context).width < 360;
    final scheme = Theme.of(context).colorScheme;
    return DearCard(
      key: const ValueKey('primary-chat-card'),
      padding: EdgeInsets.zero,
      color: scheme.surface,
      borderColor: scheme.outlineVariant,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(DearRadii.medium),
        child: InkWell(
          borderRadius: BorderRadius.circular(DearRadii.medium),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Row(
              children: [
                _PartnerAvatar(imageUrl: partnerAvatarUrl),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              key: const ValueKey('primary-chat-title'),
                              '$partnerName님과 채팅',
                              maxLines: largeText ? null : 1,
                              overflow: largeText
                                  ? TextOverflow.visible
                                  : TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
                                    color: scheme.onSurface,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    height: 1.15,
                                  ),
                            ),
                          ),
                          if (unreadCount > 0 && !stackedMeta) ...[
                            const SizedBox(width: 8),
                            Container(
                              constraints: const BoxConstraints(minWidth: 20),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.primaryContainer,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                unreadCount > 99 ? '99+' : '$unreadCount',
                                textAlign: TextAlign.center,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      color: scheme.primary,
                                      fontWeight: FontWeight.w800,
                                      height: 1,
                                    ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        key: const ValueKey('primary-chat-preview'),
                        isPaired
                            ? (latestPreview ?? '아직 대화가 없어요')
                            : '먼저 연결을 완료해 주세요.',
                        maxLines: largeText ? null : 1,
                        overflow: largeText
                            ? TextOverflow.visible
                            : TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                            ),
                      ),
                      if (stackedMeta &&
                          (latestTimeLabel != null || unreadCount > 0)) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (latestTimeLabel != null)
                              Text(
                                latestTimeLabel!,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w400,
                                    ),
                              ),
                            if (unreadCount > 0)
                              Text(
                                '${unreadCount > 99 ? '99+' : unreadCount}개 안 읽음',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      color: scheme.primary,
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (!stackedMeta) ...[
                  const SizedBox(width: 10),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (latestTimeLabel != null)
                        Text(
                          latestTimeLabel!,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w400,
                                  ),
                        )
                      else
                        const SizedBox(height: 16),
                      const SizedBox(height: 10),
                      if (unreadCount > 0)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            shape: BoxShape.circle,
                          ),
                        )
                      else
                        const SizedBox(width: 8, height: 8),
                    ],
                  ),
                ],
                const SizedBox(width: 8),
                ExcludeSemantics(
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 24,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PartnerAvatar extends StatelessWidget {
  const _PartnerAvatar({required this.imageUrl});

  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final imageUrl = this.imageUrl?.trim();
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('primary-chat-avatar'),
      width: 56,
      height: 56,
      foregroundDecoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: ClipOval(
        child: imageUrl == null || imageUrl.isEmpty
            ? ColoredBox(
                color: scheme.primaryContainer,
                child: Icon(
                  Icons.person_rounded,
                  color: scheme.onPrimaryContainer,
                ),
              )
            : Image.network(
                imageUrl,
                key: const ValueKey('primary-chat-avatar-image'),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => ColoredBox(
                  color: scheme.primaryContainer,
                  child: Icon(
                    Icons.person_rounded,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ),
      ),
    );
  }
}

class _NextAnniversaryCard extends StatelessWidget {
  const _NextAnniversaryCard({
    required this.anniversaryDate,
    required this.upcoming,
    required this.loading,
    required this.hasError,
  });

  final DateTime? anniversaryDate;
  final AnniversaryTimelineEntry? upcoming;
  final bool loading;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final today = DateUtils.dateOnly(DateTime.now());
    final daysUntil = upcoming == null
        ? null
        : DateUtils.dateOnly(upcoming!.eventDate).difference(today).inDays;
    final title = loading
        ? '가장 가까운 날을 찾고 있어요'
        : hasError
            ? '기념일을 불러오지 못했어요'
            : upcoming == null
                ? '다음 기념일을 준비해요'
                : daysUntil == 0
                    ? '오늘은 ${upcoming!.title}이에요'
                    : '${upcoming!.title}까지 $daysUntil일';
    final subtitle = upcoming == null
        ? anniversaryDate == null
            ? '관계 설정에서 우리의 시작일을 등록해 주세요.'
            : '기념일 화면에서 기억할 날을 추가해 보세요.'
        : _dateWithDots(upcoming!.eventDate);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '다음 기념일',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: scheme.onSurface,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 10),
        DearCard(
          padding: EdgeInsets.zero,
          shadowOpacity: 0.35,
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(DearRadii.medium),
            child: InkWell(
              borderRadius: BorderRadius.circular(DearRadii.medium),
              onTap: () => context.push('/anniversary-reminders'),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Image.asset(
                        'assets/images/anniversary/anniv_event_heart.png',
                        width: 38,
                        height: 38,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                  color: scheme.onSurface,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                          ),
                        ],
                      ),
                    ),
                    ExcludeSemantics(
                      child: Icon(
                        Icons.chevron_right_rounded,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

String _dateWithDots(DateTime date) {
  final normalized = DateUtils.dateOnly(date);
  final month = normalized.month.toString().padLeft(2, '0');
  final day = normalized.day.toString().padLeft(2, '0');
  return '${normalized.year}.$month.$day';
}

class _HomeFeatureIcon extends StatelessWidget {
  const _HomeFeatureIcon({
    required this.glyph,
    this.size = 52,
    super.key,
  });

  final _FeatureGlyph glyph;
  final double size;

  @override
  Widget build(BuildContext context) {
    final decodeSize = (size * MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(1, 512)
        .toInt();
    return Image.asset(
      glyph.assetPath,
      width: size,
      height: size,
      cacheWidth: decodeSize,
      cacheHeight: decodeSize,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
    );
  }
}

class _RecentMemoriesStrip extends ConsumerWidget {
  const _RecentMemoriesStrip({required this.coupleId});

  final String? coupleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final coupleId = this.coupleId;
    final photosAsync = coupleId == null
        ? const AsyncValue<List<MemoryAlbumPhoto>>.data(<MemoryAlbumPhoto>[])
        : ref.watch(recentMemoryAlbumPhotosProvider(coupleId));
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.6;
    final sectionTitle = Text(
      '최근 추억',
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: scheme.onSurface,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
    );
    final moreButton = TextButton(
      onPressed: coupleId == null ? null : () => context.go('/memory-album'),
      style: TextButton.styleFrom(
        foregroundColor: scheme.primary,
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        textStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      child: const Text('더보기'),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (largeText)
          SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: 4,
              children: [sectionTitle, moreButton],
            ),
          )
        else
          Row(
            children: [
              sectionTitle,
              const Spacer(),
              moreButton,
            ],
          ),
        const SizedBox(height: 14),
        photosAsync.when(
          loading: () => const _RecentMemoriesLoadingStrip(),
          error: (_, __) => _RecentMemoriesError(
            onRetry: coupleId == null
                ? null
                : () => ref.invalidate(
                      recentMemoryAlbumPhotosProvider(coupleId),
                    ),
          ),
          data: (photos) {
            if (photos.isEmpty) {
              return _RecentMemoriesEmptyStrip(
                onTap:
                    coupleId == null ? null : () => context.go('/memory-album'),
              );
            }

            return _RecentMemoriesMosaic(
              photos: photos.take(3).toList(growable: false),
            );
          },
        ),
      ],
    );
  }
}

class _RecentMemoriesLoadingStrip extends StatelessWidget {
  const _RecentMemoriesLoadingStrip();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 168,
      child: Row(
        children: [
          Expanded(flex: 2, child: _MemorySkeletonTile()),
          SizedBox(width: 8),
          Expanded(
            child: Column(
              children: [
                Expanded(child: _MemorySkeletonTile()),
                SizedBox(height: 8),
                Expanded(child: _MemorySkeletonTile()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentMemoriesEmptyStrip extends StatelessWidget {
  const _RecentMemoriesEmptyStrip({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DearCard(
      padding: EdgeInsets.zero,
      shadowOpacity: 0.25,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(DearRadii.medium),
        child: InkWell(
          borderRadius: BorderRadius.circular(DearRadii.medium),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                const _HomeFeatureIcon(glyph: _FeatureGlyph.album, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '아직 담긴 추억이 없어요. 첫 사진을 추가해 보세요.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                ExcludeSemantics(
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentMemoriesError extends StatelessWidget {
  const _RecentMemoriesError({required this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DearCard(
      padding: const EdgeInsets.all(16),
      shadowOpacity: 0.2,
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded, color: scheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '최근 추억을 불러오지 못했어요.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('다시 시도')),
        ],
      ),
    );
  }
}

class _MemorySkeletonTile extends StatelessWidget {
  const _MemorySkeletonTile();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.76),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
    );
  }
}

class _RecentMemoriesMosaic extends StatelessWidget {
  const _RecentMemoriesMosaic({required this.photos});

  final List<MemoryAlbumPhoto> photos;

  @override
  Widget build(BuildContext context) {
    if (photos.length == 1) {
      return SizedBox(
        height: 168,
        child: _RecentMemoryPhotoTile(photo: photos.first),
      );
    }

    return SizedBox(
      height: 168,
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: _RecentMemoryPhotoTile(photo: photos.first),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              children: [
                Expanded(child: _RecentMemoryPhotoTile(photo: photos[1])),
                if (photos.length > 2) ...[
                  const SizedBox(height: 8),
                  Expanded(child: _RecentMemoryPhotoTile(photo: photos[2])),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentMemoryPhotoTile extends StatefulWidget {
  const _RecentMemoryPhotoTile({required this.photo});

  final MemoryAlbumPhoto photo;

  @override
  State<_RecentMemoryPhotoTile> createState() => _RecentMemoryPhotoTileState();
}

class _RecentMemoryPhotoTileState extends State<_RecentMemoryPhotoTile> {
  static final Map<String, _CachedRecentMemoryUrl> _signedUrlCache =
      <String, _CachedRecentMemoryUrl>{};
  static final Map<String, Future<String>> _inflightSignedUrlRequests =
      <String, Future<String>>{};
  static const Duration _signedUrlRefreshInterval = Duration(minutes: 55);

  late Future<String> _signedUrlFuture;

  @override
  void initState() {
    super.initState();
    _signedUrlFuture = _resolveSignedUrl(widget.photo.storagePath);
  }

  @override
  void didUpdateWidget(covariant _RecentMemoryPhotoTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photo.storagePath != widget.photo.storagePath) {
      _signedUrlFuture = _resolveSignedUrl(widget.photo.storagePath);
    }
  }

  Future<String> _resolveSignedUrl(String storagePath) {
    final now = DateTime.now();
    final cached = _signedUrlCache[storagePath];
    if (cached != null &&
        now.difference(cached.issuedAt) < _signedUrlRefreshInterval) {
      return Future<String>.value(cached.url);
    }

    final inflight = _inflightSignedUrlRequests[storagePath];
    if (inflight != null) return inflight;

    final request = Supabase.instance.client.storage
        .from('memory-album-photos')
        .createSignedUrl(storagePath, 3600)
        .then((url) {
      _signedUrlCache[storagePath] = _CachedRecentMemoryUrl(
        url: url,
        issuedAt: DateTime.now(),
      );
      _inflightSignedUrlRequests.remove(storagePath);
      return url;
    }).catchError((error) {
      _inflightSignedUrlRequests.remove(storagePath);
      throw error;
    });

    _inflightSignedUrlRequests[storagePath] = request;
    return request;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<String>(
      future: _signedUrlFuture,
      builder: (context, snapshot) {
        final imageUrl = snapshot.data;
        return ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              color: scheme.surfaceContainer,
              border: Border.all(color: scheme.outlineVariant),
              boxShadow: dearSoftShadow(0.2),
            ),
            child: imageUrl == null
                ? const Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    filterQuality: FilterQuality.medium,
                    errorBuilder: (_, __, ___) => const Center(
                      child: _HomeFeatureIcon(
                        glyph: _FeatureGlyph.album,
                        size: 44,
                      ),
                    ),
                  ),
          ),
        );
      },
    );
  }
}

class _CachedRecentMemoryUrl {
  const _CachedRecentMemoryUrl({
    required this.url,
    required this.issuedAt,
  });

  final String url;
  final DateTime issuedAt;
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: scheme.onSurface,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontSize: 13,
                fontWeight: FontWeight.w400,
              ),
        ),
      ],
    );
  }
}

class _FeatureGrid extends StatelessWidget {
  const _FeatureGrid({required this.items});

  final List<_FeatureItem> items;

  @override
  Widget build(BuildContext context) {
    final scaledTitleSize = MediaQuery.textScalerOf(context).scale(14);
    final effectiveTextScale = scaledTitleSize / 14;

    return LayoutBuilder(
      builder: (context, constraints) {
        const columnCount = 3;
        const gap = DearSpacing.space8;
        final tileWidth =
            (constraints.maxWidth - (columnCount - 1) * gap) / columnCount;
        final useSingleColumn = effectiveTextScale >= 1.6 || tileWidth < 104;

        if (useSingleColumn) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < items.length; index++) ...[
                if (index > 0) const SizedBox(height: gap),
                _FeatureTile(item: items[index], singleColumn: true),
              ],
            ],
          );
        }

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columnCount,
            mainAxisSpacing: gap,
            crossAxisSpacing: gap,
            mainAxisExtent: 122,
          ),
          itemBuilder: (context, index) =>
              _FeatureTile(item: items[index], singleColumn: false),
        );
      },
    );
  }
}

enum _FeatureGlyph { album, anniversary, omok, koreaMap, worldMap, settings }

extension _FeatureGlyphAsset on _FeatureGlyph {
  String get assetPath => switch (this) {
        _FeatureGlyph.album => 'assets/images/home_icons/album.png',
        _FeatureGlyph.anniversary => 'assets/images/home_icons/anniversary.png',
        _FeatureGlyph.omok => 'assets/images/home_icons/omok.png',
        _FeatureGlyph.koreaMap => 'assets/images/home_icons/korea_map.png',
        _FeatureGlyph.worldMap => 'assets/images/home_icons/world_map.png',
        _FeatureGlyph.settings => 'assets/images/home_icons/settings.png',
      };
}

class _FeatureItem {
  const _FeatureItem({
    required this.glyph,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badgeCount = 0,
  });

  final _FeatureGlyph glyph;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final int badgeCount;
}

class _FeatureTile extends StatelessWidget {
  const _FeatureTile({required this.item, required this.singleColumn});

  final _FeatureItem item;
  final bool singleColumn;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final titleStyle = Theme.of(context).textTheme.titleSmall?.copyWith(
          color: scheme.onSurface,
          fontSize: 14,
          fontWeight: FontWeight.w800,
        );
    final subtitleStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
          fontSize: 11,
        );
    final badge = item.badgeCount > 0
        ? Container(
            constraints: const BoxConstraints(minWidth: 20),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '${item.badgeCount}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onPrimary,
                    fontWeight: FontWeight.w900,
                  ),
            ),
          )
        : null;

    final centeredContent = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: singleColumn ? DearSpacing.space16 : 6,
        vertical: singleColumn ? 14 : 10,
      ),
      child: Column(
        mainAxisSize: singleColumn ? MainAxisSize.min : MainAxisSize.max,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ExcludeSemantics(
            child: _HomeFeatureIcon(
              key: ValueKey('quick-action-${item.glyph.name}-icon'),
              glyph: item.glyph,
              size: DearIconSizes.feature,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            item.title,
            key: ValueKey('quick-action-${item.glyph.name}-title'),
            maxLines: singleColumn ? null : 1,
            overflow:
                singleColumn ? TextOverflow.visible : TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: titleStyle,
          ),
          const SizedBox(height: 2),
          Text(
            item.subtitle,
            key: ValueKey('quick-action-${item.glyph.name}-subtitle'),
            maxLines: singleColumn ? null : 1,
            overflow:
                singleColumn ? TextOverflow.visible : TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: subtitleStyle,
          ),
        ],
      ),
    );
    final content = Stack(
      fit: singleColumn ? StackFit.loose : StackFit.expand,
      alignment: Alignment.center,
      children: [
        if (singleColumn)
          SizedBox(width: double.infinity, child: centeredContent)
        else
          centeredContent,
        if (badge != null)
          Positioned(
            right: 7,
            top: 7,
            child: badge,
          ),
      ],
    );

    final semanticLabel = item.badgeCount > 0
        ? '${item.title}, ${item.subtitle}, 새 항목 ${item.badgeCount}개'
        : '${item.title}, ${item.subtitle}';

    return Semantics(
      key: ValueKey('quick-action-${item.glyph.name}'),
      button: true,
      label: semanticLabel,
      onTap: item.onTap,
      excludeSemantics: true,
      child: DearCard(
        padding: EdgeInsets.zero,
        shadowOpacity: 0.55,
        borderColor: scheme.outlineVariant,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(DearRadii.medium),
          child: InkWell(
            borderRadius: BorderRadius.circular(DearRadii.medium),
            onTap: item.onTap,
            child: content,
          ),
        ),
      ),
    );
  }
}
