import 'package:couple_chat_app/src/common/dear_design.dart';
import 'package:couple_chat_app/src/features/auth/data/auth_providers.dart';
import 'package:couple_chat_app/src/features/chat/data/chat_providers.dart';
import 'package:couple_chat_app/src/features/chat/presentation/chat_page.dart';
import 'package:couple_chat_app/src/features/chat/presentation/chat_media_page.dart';
import 'package:couple_chat_app/src/features/chat/presentation/chat_search_page.dart';
import 'package:couple_chat_app/src/features/settings/data/couple_prefs_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class ChatShellPage extends ConsumerWidget {
  const ChatShellPage({
    required this.coupleId,
    super.key,
  });

  final String coupleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.6;
    final myUserId = ref.watch(chatCurrentUserIdProvider);
    final nicknameMap =
        ref.watch(coupleNicknameMapProvider(coupleId)).valueOrNull ??
            const <String, String>{};
    final avatarMap =
        ref.watch(coupleAvatarUrlMapProvider(coupleId)).valueOrNull ??
            const <String, String>{};
    String? partnerUserId;
    for (final userId in {...nicknameMap.keys, ...avatarMap.keys}) {
      if (userId != myUserId) {
        partnerUserId = userId;
        break;
      }
    }
    final partnerName = partnerUserId == null
        ? '우리'
        : (nicknameMap[partnerUserId]?.trim().isNotEmpty == true
            ? nicknameMap[partnerUserId]!.trim()
            : '우리');
    final partnerAvatarUrl =
        partnerUserId == null ? null : avatarMap[partnerUserId];
    final anniversaryDate = ref.watch(anniversaryDateProvider).valueOrNull;
    final latestActivity =
        ref.watch(chatLatestMessageAtProvider(coupleId)).valueOrNull;
    final isPartnerOnline =
        ref.watch(chatPartnerOnlineProvider(coupleId)).valueOrNull ?? false;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: largeText ? 108 : 72,
        centerTitle: false,
        leading: IconButton(
          tooltip: '뒤로가기',
          onPressed: () {
            if (context.canPop()) {
              context.pop();
              return;
            }
            context.go('/chat-list');
          },
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
        ),
        titleSpacing: 0,
        title: Row(
          children: [
            _ChatHeaderAvatar(
              imageUrl: partnerAvatarUrl,
              isOnline: isPartnerOnline,
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    partnerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: DearColors.ink,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isPartnerOnline ? '온라인' : _activityLabel(latestActivity),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: DearColors.secondary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (anniversaryDate != null)
            _HeaderPill(label: anniversaryDdayLabel(anniversaryDate)),
          PopupMenuButton<String>(
            tooltip: '더보기',
            icon: const Icon(Icons.more_horiz_rounded),
            onSelected: (value) {
              if (value == 'search') {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ChatSearchPage(coupleId: coupleId),
                  ),
                );
              } else if (value == 'media') {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ChatMediaPage(coupleId: coupleId),
                  ),
                );
              } else if (value == 'settings') {
                context.push('/profile');
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'search',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.search_rounded),
                  title: Text('메시지 검색'),
                ),
              ),
              PopupMenuItem(
                value: 'media',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.photo_library_outlined),
                  title: Text('사진 모아보기'),
                ),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: 'settings',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.settings_outlined),
                  title: Text('채팅 설정'),
                ),
              ),
            ],
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: DearBackground(child: ChatPage(coupleId: coupleId)),
    );
  }

  String _activityLabel(DateTime? latestActivity) {
    if (latestActivity == null) return '아직 대화를 시작하지 않았어요';
    final difference = DateTime.now().difference(latestActivity.toLocal());
    if (difference.isNegative || difference.inMinutes < 1) return '방금 활동';
    if (difference.inHours < 1) return '${difference.inMinutes}분 전 활동';
    if (difference.inDays < 1) return '${difference.inHours}시간 전 활동';
    if (difference.inDays < 7) return '${difference.inDays}일 전 활동';
    return '마지막 활동 ${latestActivity.toLocal().month}/${latestActivity.toLocal().day}';
  }
}

class _ChatHeaderAvatar extends StatelessWidget {
  const _ChatHeaderAvatar({
    required this.imageUrl,
    required this.isOnline,
  });

  final String? imageUrl;
  final bool isOnline;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl?.trim();
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: DearColors.blushDeep,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
          ),
          clipBehavior: Clip.antiAlias,
          child: url == null || url.isEmpty
              ? const Icon(Icons.person_rounded, color: DearColors.coral)
              : Image.network(
                  url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.person_rounded,
                    color: DearColors.coral,
                  ),
                ),
        ),
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: isOnline ? const Color(0xFF44B77B) : DearColors.coral,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
            ),
            child: Icon(
              isOnline ? Icons.circle : Icons.favorite_rounded,
              color: Colors.white,
              size: isOnline ? 9 : 12,
            ),
          ),
        ),
      ],
    );
  }
}

class _HeaderPill extends StatelessWidget {
  const _HeaderPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: DearColors.blushDeep,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: DearColors.coralText,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(width: 5),
          const Icon(Icons.favorite_rounded, color: DearColors.coral, size: 14),
        ],
      ),
    );
  }
}
