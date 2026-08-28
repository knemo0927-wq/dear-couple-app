import 'dart:math' as math;

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
    final scheme = Theme.of(context).colorScheme;
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
    final activityLabel =
        isPartnerOnline ? '온라인' : _activityLabel(latestActivity);
    final ddayLabel =
        anniversaryDate == null ? null : anniversaryDdayLabel(anniversaryDate);
    final textTheme = Theme.of(context).textTheme;
    final nameStyle =
        (largeText ? textTheme.titleMedium : textTheme.titleLarge)?.copyWith(
      color: scheme.onSurface,
      fontWeight: FontWeight.w900,
    );
    final activityStyle = textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
      fontWeight: FontWeight.w700,
    );
    final ddayStyle = textTheme.labelLarge?.copyWith(
      color: scheme.primary,
      fontWeight: FontWeight.w800,
    );
    final toolbarHeight = largeText
        ? _largeTextToolbarHeight(
            context,
            partnerName: partnerName,
            activityLabel: activityLabel,
            ddayLabel: ddayLabel,
            nameStyle: nameStyle,
            activityStyle: activityStyle,
            ddayStyle: ddayStyle,
          )
        : 72.0;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: toolbarHeight,
        centerTitle: false,
        leading: Center(
          child: DearIconButton(
            key: const ValueKey('chat-header-back'),
            tooltip: '뒤로가기',
            semanticLabel: '채팅 목록으로 돌아가기',
            onPressed: () {
              if (context.canPop()) {
                context.pop();
                return;
              }
              context.go('/chat-list');
            },
            color: scheme.onSurface,
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
          ),
        ),
        titleSpacing: 0,
        title: _ChatHeaderTitle(
          partnerName: partnerName,
          imageUrl: partnerAvatarUrl,
          isOnline: isPartnerOnline,
          activityLabel: activityLabel,
          ddayLabel: ddayLabel,
          largeText: largeText,
          nameStyle: nameStyle,
          activityStyle: activityStyle,
          ddayStyle: ddayStyle,
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: _ChatMoreMenuButton(
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
            ),
          ),
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

  double _largeTextToolbarHeight(
    BuildContext context, {
    required String partnerName,
    required String activityLabel,
    required String? ddayLabel,
    required TextStyle? nameStyle,
    required TextStyle? activityStyle,
    required TextStyle? ddayStyle,
  }) {
    const leadingWidth = 56.0;
    const actionWidth = DearTouchTargets.minimum + 6;
    final textWidth = math.max(
      72.0,
      MediaQuery.sizeOf(context).width - leadingWidth - actionWidth,
    );
    final textScaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);

    Size textSize(
      String text,
      TextStyle? style, {
      double maxWidth = double.infinity,
    }) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: direction,
        textScaler: textScaler,
      )..layout(maxWidth: maxWidth);
      return painter.size;
    }

    final nameSize = textSize(
      partnerName,
      nameStyle,
      maxWidth: textWidth,
    );
    final activitySize = textSize(
      activityLabel,
      activityStyle,
      maxWidth: textWidth,
    );
    var metadataHeight = activitySize.height;
    if (ddayLabel != null) {
      final labelSize = textSize(ddayLabel, ddayStyle);
      final pillSize = Size(
        labelSize.width + 12 * 2 + 5 + 14,
        math.max(DearIconSizes.small, labelSize.height) + DearSpacing.space16,
      );
      metadataHeight =
          activitySize.width + DearSpacing.space8 + pillSize.width <= textWidth
              ? math.max(activitySize.height, pillSize.height)
              : activitySize.height + DearSpacing.space4 + pillSize.height;
    }
    final columnHeight = nameSize.height + DearSpacing.space8 + metadataHeight;

    return math.max(
      108.0,
      math.max(48.0, columnHeight) + DearSpacing.space16,
    );
  }
}

class _ChatHeaderTitle extends StatelessWidget {
  const _ChatHeaderTitle({
    required this.partnerName,
    required this.imageUrl,
    required this.isOnline,
    required this.activityLabel,
    required this.ddayLabel,
    required this.largeText,
    required this.nameStyle,
    required this.activityStyle,
    required this.ddayStyle,
  });

  final String partnerName;
  final String? imageUrl;
  final bool isOnline;
  final String activityLabel;
  final String? ddayLabel;
  final bool largeText;
  final TextStyle? nameStyle;
  final TextStyle? activityStyle;
  final TextStyle? ddayStyle;

  @override
  Widget build(BuildContext context) {
    final dday = ddayLabel;
    return Row(
      key: const ValueKey('chat-header-title'),
      crossAxisAlignment:
          largeText ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        if (!largeText) ...[
          _ChatHeaderAvatar(
            imageUrl: imageUrl,
            isOnline: isOnline,
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                partnerName,
                key: const ValueKey('chat-header-partner-name'),
                maxLines: largeText ? null : 1,
                overflow:
                    largeText ? TextOverflow.visible : TextOverflow.ellipsis,
                softWrap: true,
                style: nameStyle,
              ),
              if (largeText) ...[
                const SizedBox(height: DearSpacing.space8),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: DearSpacing.space8,
                  runSpacing: DearSpacing.space4,
                  children: [
                    Text(
                      activityLabel,
                      key: const ValueKey('chat-header-activity'),
                      style: activityStyle,
                    ),
                    if (dday != null)
                      _HeaderPill(label: dday, textStyle: ddayStyle),
                  ],
                ),
              ] else ...[
                const SizedBox(height: 2),
                Text(
                  activityLabel,
                  key: const ValueKey('chat-header-activity'),
                  style: activityStyle,
                ),
              ],
            ],
          ),
        ),
        if (!largeText && dday != null) ...[
          const SizedBox(width: DearSpacing.space8),
          _HeaderPill(label: dday, textStyle: ddayStyle),
        ],
      ],
    );
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
    final scheme = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              shape: BoxShape.circle,
              // A white ring deliberately separates a photo from the app bar.
              border: Border.all(color: Colors.white, width: 3),
            ),
            clipBehavior: Clip.antiAlias,
            child: url == null || url.isEmpty
                ? Icon(Icons.person_rounded, color: scheme.primary)
                : Image.network(
                    url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Icon(
                      Icons.person_rounded,
                      color: scheme.primary,
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
                color: isOnline ? const Color(0xFF44B77B) : scheme.primary,
                shape: BoxShape.circle,
                // The status dot overlaps the avatar, so retain its white ring.
                border: Border.all(color: Colors.white, width: 3),
              ),
              child: Icon(
                isOnline ? Icons.circle : Icons.favorite_rounded,
                color: isOnline ? Colors.white : scheme.onPrimary,
                size: isOnline ? 9 : 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderPill extends StatelessWidget {
  const _HeaderPill({
    required this.label,
    required this.textStyle,
  });

  final String label;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      key: const ValueKey('chat-header-dday'),
      label: '함께한 날 $label',
      child: ExcludeSemantics(
        child: Container(
          key: const ValueKey('chat-header-dday-surface'),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(DearRadii.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: textStyle),
              const SizedBox(width: 5),
              Icon(
                Icons.favorite_rounded,
                color: scheme.primary,
                size: 14,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatMoreMenuButton extends StatefulWidget {
  const _ChatMoreMenuButton({required this.onSelected});

  final ValueChanged<String> onSelected;

  @override
  State<_ChatMoreMenuButton> createState() => _ChatMoreMenuButtonState();
}

class _ChatMoreMenuButtonState extends State<_ChatMoreMenuButton> {
  final _menuKey = GlobalKey<PopupMenuButtonState<String>>();

  void _openMenu() {
    _menuKey.currentState?.showButtonMenu();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      key: const ValueKey('chat-header-more'),
      container: true,
      button: true,
      label: '더보기',
      onTap: _openMenu,
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: DearTouchTargets.minimum,
        child: PopupMenuButton<String>(
          key: _menuKey,
          tooltip: '더보기',
          padding: EdgeInsets.zero,
          icon: Icon(
            Icons.more_horiz_rounded,
            key: const ValueKey('chat-header-more-icon'),
            color: scheme.onSurface,
          ),
          onSelected: widget.onSelected,
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
      ),
    );
  }
}
