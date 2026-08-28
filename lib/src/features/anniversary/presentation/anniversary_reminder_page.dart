import 'package:couple_chat_app/src/common/dear_design.dart';
import 'package:couple_chat_app/src/features/anniversary/data/anniversary_providers.dart';
import 'package:couple_chat_app/src/features/auth/data/auth_providers.dart';
import 'package:couple_chat_app/src/features/chat/data/memory_album_providers.dart';
import 'package:couple_chat_app/src/features/chat/data/memory_album_repository.dart';
import 'package:couple_chat_app/src/features/notifications/data/notification_preferences.dart';
import 'package:couple_chat_app/src/features/settings/data/couple_prefs_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

const _assetBase = 'assets/images/anniversary';
const _heroRingAsset = '$_assetBase/anniv_hero_ring.png';
const _smallHeartAsset = '$_assetBase/anniv_small_heart.png';
const _eventHeartAsset = '$_assetBase/anniv_event_heart.png';
const _eventRingAsset = '$_assetBase/anniv_event_ring.png';
const _eventGiftAsset = '$_assetBase/anniv_event_gift.png';
const _avatarOneAsset = '$_assetBase/anniv_default_avatar_1.png';
const _avatarTwoAsset = '$_assetBase/anniv_default_avatar_2.png';
const _dashboardPreviewCount = 5;

extension _AnniversaryThemeContext on BuildContext {
  ColorScheme get anniversaryColors => Theme.of(this).colorScheme;
}

class _AnniversaryAsset extends StatelessWidget {
  const _AnniversaryAsset({
    required this.asset,
    required this.width,
    required this.height,
    this.fit,
  });

  final String asset;
  final double width;
  final double height;
  final BoxFit? fit;

  @override
  Widget build(BuildContext context) {
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final cacheWidth = (width * pixelRatio).round().clamp(1, 4096).toInt();
    final cacheHeight = (height * pixelRatio).round().clamp(1, 4096).toInt();
    return Image.asset(
      asset,
      width: width,
      height: height,
      cacheWidth: cacheWidth,
      cacheHeight: cacheHeight,
      fit: fit,
    );
  }
}

class AnniversaryReminderPage extends ConsumerStatefulWidget {
  const AnniversaryReminderPage({this.initialEntryId, super.key});

  final String? initialEntryId;

  @override
  ConsumerState<AnniversaryReminderPage> createState() =>
      _AnniversaryReminderPageState();
}

class _AnniversaryReminderPageState
    extends ConsumerState<AnniversaryReminderPage> {
  bool _saving = false;
  bool _openedInitialEntry = false;

  Future<void> _addReminder(String coupleId) async {
    if (_saving) return;
    final draft = await _showAnniversaryEditor(
      context,
      coupleId: coupleId,
      title: '기념일 추가',
      submitLabel: '추가하기',
    );
    if (!mounted || draft == null) return;

    setState(() => _saving = true);
    try {
      await ref.read(addAnniversaryProvider)(
        coupleId: coupleId,
        title: draft.title,
        eventDate: draft.eventDate,
        repeat: draft.repeat,
        reminderEnabled: draft.reminderEnabled,
        reminderDaysBefore: draft.reminderDaysBefore,
        reminderHour: draft.reminderHour,
        note: draft.note,
        linkedAlbumId: draft.linkedAlbumId,
      );
      if (!mounted) return;
      _showResultMessage(context, '${draft.title}을(를) 추가했어요.');
    } catch (e) {
      if (!mounted) return;
      _showResultMessage(context, _anniversaryErrorMessage(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openMoreMenu(DateTime? anniversaryDate) async {
    final action = await showModalBottomSheet<_AnniversaryMenuAction>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AnniversaryMenuSheet(
        hasRelationshipDate: anniversaryDate != null,
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _AnniversaryMenuAction.fullList:
        await context.push('/anniversary-reminders/all');
        return;
      case _AnniversaryMenuAction.notifications:
        await context.push('/notifications');
        return;
      case _AnniversaryMenuAction.relationshipDate:
        await context.push('/profile');
        return;
    }
  }

  Future<void> _openHeroDetail({
    required DateTime? anniversaryDate,
    required AnniversaryTimelineEntry? nextEntry,
  }) async {
    final action = await showModalBottomSheet<_HeroDetailAction>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _HeroDetailSheet(
        anniversaryDate: anniversaryDate,
        nextEntry: nextEntry,
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _HeroDetailAction.fullList:
        await context.push('/anniversary-reminders/all');
        return;
      case _HeroDetailAction.relationshipDate:
        await context.push('/profile');
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(myProfileProvider);
    final anniversaryDateAsync = ref.watch(anniversaryDateProvider);
    final profile = profileAsync.valueOrNull;
    final canAdd = profile?.isPaired == true && !_saving;

    return Scaffold(
      body: DearBackground(
        child: SafeArea(
          child: profileAsync.when(
            loading: () => const _AnniversaryPageLoadingState(),
            error: (error, _) => _AnniversaryStandaloneError(
              onRetry: () => ref.invalidate(myProfileProvider),
            ),
            data: (profile) {
              if (profile == null || !profile.isPaired) {
                return const Center(child: Text('커플 연결 후 사용할 수 있어요.'));
              }

              final anniversaryDate = anniversaryDateAsync.valueOrNull;
              final timelineAsync = ref.watch(
                upcomingAnniversaryTimelineProvider(
                  AnniversaryTimelineQuery(
                    coupleId: profile.coupleId!,
                    limit: _dashboardPreviewCount,
                  ),
                ),
              );
              final timeline = timelineAsync.valueOrNull ??
                  const <AnniversaryTimelineEntry>[];
              final nextEntry = timeline.isEmpty ? null : timeline.first;
              final customItemsAsync = ref.watch(
                anniversaryItemsProvider(profile.coupleId!),
              );
              final customItems =
                  customItemsAsync.valueOrNull ?? const <AnniversaryItem>[];
              final initialEntryId = widget.initialEntryId?.trim();
              if (!_openedInitialEntry &&
                  initialEntryId != null &&
                  initialEntryId.isNotEmpty &&
                  !timelineAsync.isLoading &&
                  !customItemsAsync.isLoading) {
                AnniversaryTimelineEntry? initialEntry;
                for (final entry in timeline) {
                  if (entry.stableId == initialEntryId ||
                      entry.customItem?.id == initialEntryId) {
                    initialEntry = entry;
                    break;
                  }
                }
                if (initialEntry == null) {
                  for (final item in customItems) {
                    if (item.id != initialEntryId) continue;
                    initialEntry = AnniversaryTimelineEntry(
                      stableId: 'custom:${item.id}',
                      title: item.title,
                      eventDate: nextCustomAnniversaryOccurrence(
                            item,
                            today: DateTime.now(),
                          ) ??
                          item.eventDate,
                      kind: AnniversaryTimelineKind.custom,
                      customItem: item,
                    );
                    break;
                  }
                }
                if (initialEntry != null) {
                  _openedInitialEntry = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    _showAnniversaryEntryDetails(
                      context: context,
                      ref: ref,
                      coupleId: profile.coupleId!,
                      entry: initialEntry!,
                    );
                  });
                }
              }
              final avatarUrls = ref
                  .watch(coupleAvatarUrlMapProvider(profile.coupleId!))
                  .valueOrNull;
              final globalReminderEnabled = ref
                      .watch(notificationPreferencesProvider(profile.userId))
                      .valueOrNull
                      ?.anniversaryEnabled ??
                  true;

              return Stack(
                children: [
                  CustomScrollView(
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                        sliver: SliverToBoxAdapter(
                          child: _AnniversaryHeader(
                            onBack: () => _leaveAnniversary(context),
                            onMore: () => _openMoreMenu(anniversaryDate),
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
                        sliver: SliverToBoxAdapter(
                          child: _AnniversaryHeroCard(
                            anniversaryDate: anniversaryDate,
                            loading: anniversaryDateAsync.isLoading,
                            avatarUrls: _orderedAvatarUrls(
                              avatarUrls,
                              profile.userId,
                            ),
                            nextEntry: nextEntry,
                            onOpenDetail: () => _openHeroDetail(
                              anniversaryDate: anniversaryDate,
                              nextEntry: nextEntry,
                            ),
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
                        sliver: SliverToBoxAdapter(
                          child: _SectionHeader(
                            title: '다가오는 기념일',
                            actionLabel: '전체 보기',
                            onAction: () =>
                                context.push('/anniversary-reminders/all'),
                          ),
                        ),
                      ),
                      if (timelineAsync.isLoading)
                        const SliverPadding(
                          padding: EdgeInsets.fromLTRB(28, 14, 28, 0),
                          sliver: SliverToBoxAdapter(
                            child: _AnniversaryListSkeleton(),
                          ),
                        )
                      else if (timelineAsync.hasError)
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(28, 14, 28, 0),
                          sliver: SliverToBoxAdapter(
                            child: _AnniversaryErrorCard(
                              onRetry: () {
                                ref.invalidate(anniversaryDateProvider);
                                ref.invalidate(
                                  anniversaryItemsProvider(profile.coupleId!),
                                );
                              },
                            ),
                          ),
                        )
                      else if (timeline.isEmpty)
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(28, 14, 28, 0),
                          sliver: SliverToBoxAdapter(
                            child: _EmptyAnniversaryCard(
                              onAdd: () => _addReminder(profile.coupleId!),
                            ),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(28, 14, 28, 0),
                          sliver: SliverList.separated(
                            itemBuilder: (context, index) {
                              final item = timeline[index];
                              final reminderEnabled = item.isCustom
                                  ? item.reminderEnabled &&
                                      globalReminderEnabled
                                  : globalReminderEnabled;
                              return _TimelineEventTile(
                                showLineAbove: index != 0,
                                showLineBelow: index != timeline.length - 1,
                                child: _AnniversaryEventTile(
                                  title: item.title,
                                  dateLabel:
                                      _dateWithWeekdayLabel(item.eventDate),
                                  dday: _dday(item.eventDate),
                                  iconAsset: _iconAssetFor(item),
                                  reminderEnabled: reminderEnabled,
                                  onTap: () => _showAnniversaryEntryDetails(
                                    context: context,
                                    ref: ref,
                                    coupleId: profile.coupleId!,
                                    entry: item,
                                  ),
                                  onBell: item.isCustom
                                      ? () => _showAnniversaryEntryDetails(
                                            context: context,
                                            ref: ref,
                                            coupleId: profile.coupleId!,
                                            entry: item,
                                          )
                                      : () => context.push('/notifications'),
                                ),
                              );
                            },
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemCount: timeline.length,
                          ),
                        ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(28, 24, 28, 126),
                        sliver: SliverToBoxAdapter(
                          child: _NotificationSettingsCard(
                            onTap: () => context.push('/notifications'),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Positioned(
                    right: 20,
                    bottom: 18,
                    child: _BottomAddButton(
                      saving: _saving,
                      onTap:
                          canAdd ? () => _addReminder(profile.coupleId!) : null,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class AnniversaryFullListPage extends ConsumerStatefulWidget {
  const AnniversaryFullListPage({super.key});

  @override
  ConsumerState<AnniversaryFullListPage> createState() =>
      _AnniversaryFullListPageState();
}

class _AnniversaryFullListPageState
    extends ConsumerState<AnniversaryFullListPage> {
  final ScrollController _scrollController = ScrollController();
  bool _saving = false;
  String? _activeCoupleId;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_loadNextPageNearBottom);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_loadNextPageNearBottom)
      ..dispose();
    super.dispose();
  }

  void _loadNextPageNearBottom() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final coupleId = _activeCoupleId;
    if (position.extentAfter < 520 && coupleId != null) {
      ref.read(anniversaryTimelineFeedProvider(coupleId).notifier).loadMore();
    }
  }

  Future<void> _addReminder(String coupleId) async {
    if (_saving) return;
    final draft = await _showAnniversaryEditor(
      context,
      coupleId: coupleId,
      title: '기념일 추가',
      submitLabel: '추가하기',
    );
    if (!mounted || draft == null) return;
    setState(() => _saving = true);
    try {
      await ref.read(addAnniversaryProvider)(
        coupleId: coupleId,
        title: draft.title,
        eventDate: draft.eventDate,
        repeat: draft.repeat,
        reminderEnabled: draft.reminderEnabled,
        reminderDaysBefore: draft.reminderDaysBefore,
        reminderHour: draft.reminderHour,
        note: draft.note,
        linkedAlbumId: draft.linkedAlbumId,
      );
      if (!mounted) return;
      _showResultMessage(context, '${draft.title}을(를) 추가했어요.');
      await ref
          .read(anniversaryTimelineFeedProvider(coupleId).notifier)
          .refresh();
    } catch (error) {
      if (!mounted) return;
      _showResultMessage(context, _anniversaryErrorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(myProfileProvider);

    return Scaffold(
      body: DearBackground(
        child: SafeArea(
          child: profileAsync.when(
            loading: () => const _AnniversaryPageLoadingState(),
            error: (error, _) => _AnniversaryStandaloneError(
              onRetry: () => ref.invalidate(myProfileProvider),
            ),
            data: (profile) {
              if (profile == null || !profile.isPaired) {
                return const Center(child: Text('커플 연결 후 사용할 수 있어요.'));
              }

              final coupleId = profile.coupleId!;
              _activeCoupleId = coupleId;
              final timelineFeed =
                  ref.watch(anniversaryTimelineFeedProvider(coupleId));
              final timeline = timelineFeed.items;
              final globalReminderEnabled = ref
                      .watch(notificationPreferencesProvider(profile.userId))
                      .valueOrNull
                      ?.anniversaryEnabled ??
                  true;

              return CustomScrollView(
                controller: _scrollController,
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    sliver: SliverToBoxAdapter(
                      child: _FullListHeader(
                        title: '전체 기념일',
                        onBack: () => _leaveAnniversary(context),
                      ),
                    ),
                  ),
                  if (timelineFeed.isLoadingInitial && timeline.isEmpty)
                    const SliverPadding(
                      padding: EdgeInsets.fromLTRB(28, 24, 28, 0),
                      sliver: SliverToBoxAdapter(
                        child: _AnniversaryListSkeleton(itemCount: 5),
                      ),
                    )
                  else if (timelineFeed.error != null && timeline.isEmpty)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
                      sliver: SliverToBoxAdapter(
                        child: _AnniversaryErrorCard(
                          onRetry: () {
                            ref
                                .read(
                                  anniversaryTimelineFeedProvider(coupleId)
                                      .notifier,
                                )
                                .refresh();
                          },
                        ),
                      ),
                    )
                  else if (timeline.isEmpty)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
                      sliver: SliverToBoxAdapter(
                        child: _EmptyAnniversaryCard(
                          onAdd: () => _addReminder(coupleId),
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(28, 22, 28, 0),
                      sliver: SliverList.separated(
                        itemBuilder: (context, index) {
                          final item = timeline[index];
                          final reminderEnabled = item.isCustom
                              ? item.reminderEnabled && globalReminderEnabled
                              : globalReminderEnabled;
                          return _TimelineEventTile(
                            showLineAbove: index != 0,
                            showLineBelow: index != timeline.length - 1,
                            child: _AnniversaryEventTile(
                              title: item.title,
                              dateLabel: _dateWithWeekdayLabel(item.eventDate),
                              dday: _dday(item.eventDate),
                              iconAsset: _iconAssetFor(item),
                              reminderEnabled: reminderEnabled,
                              onTap: () async {
                                await _showAnniversaryEntryDetails(
                                  context: context,
                                  ref: ref,
                                  coupleId: coupleId,
                                  entry: item,
                                );
                                if (!context.mounted) return;
                                await ref
                                    .read(
                                      anniversaryTimelineFeedProvider(coupleId)
                                          .notifier,
                                    )
                                    .refresh();
                              },
                              onBell: item.isCustom
                                  ? () async {
                                      await _showAnniversaryEntryDetails(
                                        context: context,
                                        ref: ref,
                                        coupleId: coupleId,
                                        entry: item,
                                      );
                                      if (!context.mounted) return;
                                      await ref
                                          .read(
                                            anniversaryTimelineFeedProvider(
                                              coupleId,
                                            ).notifier,
                                          )
                                          .refresh();
                                    }
                                  : () => context.push('/notifications'),
                            ),
                          );
                        },
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemCount: timeline.length,
                      ),
                    ),
                  if (timeline.isNotEmpty)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(28, 22, 28, 36),
                      sliver: SliverToBoxAdapter(
                        child: Center(
                          child: timelineFeed.isLoadingMore
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : timelineFeed.error != null &&
                                      timelineFeed.hasMore
                                  ? TextButton.icon(
                                      onPressed: () => ref
                                          .read(
                                            anniversaryTimelineFeedProvider(
                                              coupleId,
                                            ).notifier,
                                          )
                                          .loadMore(),
                                      icon: const Icon(Icons.refresh_rounded),
                                      label: const Text('다음 기념일 다시 불러오기'),
                                    )
                                  : Text(
                                      timelineFeed.hasMore
                                          ? '스크롤하면 다음 15개를 불러와요'
                                          : '다가오는 기념일을 모두 확인했어요',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: context.anniversaryColors
                                                .onSurfaceVariant,
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

enum _AnniversaryMenuAction {
  fullList,
  notifications,
  relationshipDate,
}

enum _HeroDetailAction {
  fullList,
  relationshipDate,
}

enum _AutomaticDetailAction {
  fullList,
  notifications,
}

enum _CustomDetailAction {
  edit,
  delete,
}

class _AnniversaryEditorDraft {
  const _AnniversaryEditorDraft({
    required this.title,
    required this.eventDate,
    required this.repeat,
    required this.reminderEnabled,
    required this.reminderDaysBefore,
    required this.reminderHour,
    required this.note,
    required this.linkedAlbumId,
  });

  final String title;
  final DateTime eventDate;
  final AnniversaryRepeat repeat;
  final bool reminderEnabled;
  final int reminderDaysBefore;
  final int reminderHour;
  final String? note;
  final String? linkedAlbumId;
}

Future<_AnniversaryEditorDraft?> _showAnniversaryEditor(
  BuildContext context, {
  required String coupleId,
  required String title,
  required String submitLabel,
  AnniversaryItem? initialItem,
}) {
  return showModalBottomSheet<_AnniversaryEditorDraft>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AnniversaryEditorSheet(
      coupleId: coupleId,
      title: title,
      submitLabel: submitLabel,
      initialItem: initialItem,
    ),
  );
}

Future<void> _showAnniversaryEntryDetails({
  required BuildContext context,
  required WidgetRef ref,
  required String coupleId,
  required AnniversaryTimelineEntry entry,
}) async {
  if (!entry.isCustom) {
    await _showAutomaticAnniversaryEntryDetails(context, entry);
    return;
  }

  final item = entry.customItem!;
  final action = await showModalBottomSheet<_CustomDetailAction>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _CustomAnniversaryDetailSheet(
      item: item,
      occurrenceDate: entry.eventDate,
    ),
  );
  if (!context.mounted || action == null) return;

  switch (action) {
    case _CustomDetailAction.edit:
      final draft = await _showAnniversaryEditor(
        context,
        coupleId: coupleId,
        title: '기념일 수정',
        submitLabel: '수정 완료',
        initialItem: item,
      );
      if (!context.mounted || draft == null) return;
      try {
        await ref.read(updateAnniversaryProvider)(
          id: item.id,
          title: draft.title,
          eventDate: draft.eventDate,
          repeat: draft.repeat,
          reminderEnabled: draft.reminderEnabled,
          reminderDaysBefore: draft.reminderDaysBefore,
          reminderHour: draft.reminderHour,
          note: draft.note,
          linkedAlbumId: draft.linkedAlbumId,
        );
        if (!context.mounted) return;
        _showResultMessage(context, '${draft.title}을(를) 수정했어요.');
      } catch (error) {
        if (!context.mounted) return;
        _showResultMessage(context, _anniversaryErrorMessage(error));
      }
      return;
    case _CustomDetailAction.delete:
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('기념일을 삭제할까요?'),
          content: Text('${item.title}은(는) 목록에서 사라져요.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('취소'),
            ),
            FilledButton(
              key: const ValueKey('confirm-anniversary-delete'),
              onPressed: () => Navigator.pop(dialogContext, true),
              style: FilledButton.styleFrom(
                  backgroundColor: context.anniversaryColors.primary),
              child: const Text('삭제'),
            ),
          ],
        ),
      );
      if (!context.mounted || confirmed != true) return;
      try {
        await ref.read(removeAnniversaryProvider)(item.id);
        if (!context.mounted) return;
        _showResultMessage(context, '${item.title}을(를) 삭제했어요.');
      } catch (error) {
        if (!context.mounted) return;
        _showResultMessage(context, _anniversaryErrorMessage(error));
      }
      return;
  }
}

Future<void> _showAutomaticAnniversaryEntryDetails(
  BuildContext context,
  AnniversaryTimelineEntry entry,
) async {
  final action = await showModalBottomSheet<_AutomaticDetailAction>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AutomaticAnniversaryDetailSheet(entry: entry),
  );
  if (!context.mounted || action == null) return;
  switch (action) {
    case _AutomaticDetailAction.fullList:
      await context.push('/anniversary-reminders/all');
      return;
    case _AutomaticDetailAction.notifications:
      await context.push('/notifications');
      return;
  }
}

String _iconAssetFor(AnniversaryTimelineEntry entry) {
  return switch (entry.kind) {
    AnniversaryTimelineKind.hundredDay => _eventHeartAsset,
    AnniversaryTimelineKind.yearly => _eventRingAsset,
    AnniversaryTimelineKind.custom => _eventGiftAsset,
  };
}

String _anniversaryErrorMessage(Object error) {
  final raw = error.toString();
  if (raw.contains('TITLE_REQUIRED')) return '기념일 이름을 입력해 주세요.';
  if (raw.contains('AUTH_REQUIRED')) return '다시 로그인한 뒤 시도해 주세요.';
  return '저장하지 못했어요. 연결을 확인하고 다시 시도해 주세요.';
}

void _showResultMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

void _leaveAnniversary(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go('/chat-list');
  }
}

List<String> _orderedAvatarUrls(
    Map<String, String>? avatarUrls, String userId) {
  if (avatarUrls == null || avatarUrls.isEmpty) return const [];
  final myUrl = avatarUrls[userId];
  final others = avatarUrls.entries
      .where((entry) => entry.key != userId)
      .map((entry) => entry.value)
      .where((url) => url.trim().isNotEmpty)
      .toList();
  return [
    if (myUrl != null && myUrl.trim().isNotEmpty) myUrl,
    ...others,
  ];
}

class _HeroAnniversaryMessage {
  const _HeroAnniversaryMessage({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;
}

_HeroAnniversaryMessage _heroAnniversaryMessage(
  DateTime anniversaryDate, {
  AnniversaryTimelineEntry? nextEntry,
}) {
  final start = DateUtils.dateOnly(anniversaryDate);
  final today = DateUtils.dateOnly(DateTime.now());
  final dayCount = today.difference(start).inDays + 1;

  if (dayCount > 0 && dayCount % 100 == 0) {
    return _HeroAnniversaryMessage(
      title: '$dayCount일 기념일이에요',
      subtitle: '오늘의 마음을 기록해요',
    );
  }

  final yearCount = today.year - start.year;
  if (yearCount >= 1 && anniversaryDateForYear(start, yearCount) == today) {
    return _HeroAnniversaryMessage(
      title: '$yearCount번째 기념일이에요',
      subtitle: '처음 만난 그날을 기억해요',
    );
  }

  final fallback = buildUpcomingAnniversaryTimeline(
    relationshipStart: start,
    customItems: const <AnniversaryItem>[],
    limit: 1,
    now: today,
  );
  final next = nextEntry ?? (fallback.isEmpty ? null : fallback.first);
  final daysUntil = next?.eventDate.difference(today).inDays;
  return _HeroAnniversaryMessage(
    title: next == null
        ? '다가오는 기념일을 기다려요'
        : daysUntil == 0
            ? '오늘은 ${next.title}이에요'
            : '${next.title}까지 $daysUntil일 남았어요',
    subtitle: next == null
        ? '함께한 시간을 차곡차곡 쌓아가요'
        : '${_dateWithWeekdayCompactLabel(next.eventDate)}에 만나요',
  );
}

String _dateLabel(DateTime date) {
  final normalized = DateUtils.dateOnly(date);
  return '${normalized.year}.${normalized.month.toString().padLeft(2, '0')}.${normalized.day.toString().padLeft(2, '0')}';
}

String _dateWithWeekdayLabel(DateTime date) {
  const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
  final normalized = DateUtils.dateOnly(date);
  return '${_dateLabel(normalized)} (${weekdays[normalized.weekday - 1]})';
}

String _dateWithWeekdayCompactLabel(DateTime date) {
  const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
  final normalized = DateUtils.dateOnly(date);
  return '${_dateLabel(normalized)}(${weekdays[normalized.weekday - 1]})';
}

String _dday(DateTime date) {
  final today = DateUtils.dateOnly(DateTime.now());
  final eventDay = DateUtils.dateOnly(date);
  final diff = eventDay.difference(today).inDays;
  if (diff == 0) return 'D-day';
  if (diff > 0) return 'D-$diff';
  return 'D+${diff.abs()}';
}

class _AnniversaryHeader extends StatelessWidget {
  const _AnniversaryHeader({
    required this.onBack,
    required this.onMore,
  });

  final VoidCallback onBack;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 58,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: _RoundedIconButton(
              icon: Icons.arrow_back_ios_new_rounded,
              label: '뒤로가기',
              size: 54,
              iconSize: 22,
              onTap: onBack,
            ),
          ),
          Text(
            '기념일',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: context.anniversaryColors.onSurface,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: _RoundedIconButton(
              icon: Icons.more_horiz_rounded,
              label: '더보기',
              size: 54,
              iconSize: 28,
              onTap: onMore,
            ),
          ),
        ],
      ),
    );
  }
}

class _FullListHeader extends StatelessWidget {
  const _FullListHeader({
    required this.title,
    required this.onBack,
  });

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 58,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: _RoundedIconButton(
              icon: Icons.arrow_back_ios_new_rounded,
              label: '뒤로가기',
              size: 54,
              iconSize: 22,
              onTap: onBack,
            ),
          ),
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: context.anniversaryColors.onSurface,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
          ),
        ],
      ),
    );
  }
}

class _AnniversaryHeroCard extends StatelessWidget {
  const _AnniversaryHeroCard({
    required this.anniversaryDate,
    required this.loading,
    required this.avatarUrls,
    required this.nextEntry,
    required this.onOpenDetail,
  });

  final DateTime? anniversaryDate;
  final bool loading;
  final List<String> avatarUrls;
  final AnniversaryTimelineEntry? nextEntry;
  final VoidCallback onOpenDetail;

  @override
  Widget build(BuildContext context) {
    final dday = anniversaryDate == null
        ? 'D+ -'
        : anniversaryDdayLabel(anniversaryDate!);
    final dateLabel = anniversaryDate == null
        ? '기준일을 설정해 주세요'
        : '${anniversaryDateKoreanLabel(anniversaryDate!)}부터 함께';
    final heroMessage = anniversaryDate == null
        ? const _HeroAnniversaryMessage(
            title: '처음 만난 날을 설정해 주세요',
            subtitle: '우리의 기념일을 함께 기억해요',
          )
        : _heroAnniversaryMessage(
            anniversaryDate!,
            nextEntry: nextEntry,
          );

    return Container(
      key: const ValueKey('anniversary-hero-surface'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            context.anniversaryColors.surface,
            context.anniversaryColors.primaryContainer,
          ],
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: dearSoftShadow(1.25),
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: context.anniversaryColors.outline),
      ),
      child: Stack(
        children: [
          const Positioned(
            right: -10,
            top: 48,
            child: _AnniversaryAsset(
              asset: _heroRingAsset,
              width: 224,
              height: 136,
              fit: BoxFit.contain,
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '우리의 기념일',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: context.anniversaryColors.primary,
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: context.anniversaryColors.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      loading ? 'D+ -' : dday,
                      style:
                          Theme.of(context).textTheme.displayMedium?.copyWith(
                                color: context.anniversaryColors.onSurface,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0,
                                height: 0.98,
                              ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            dateLabel,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                  color: context
                                      .anniversaryColors.onSurfaceVariant,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const _AnniversaryAsset(
                          asset: _smallHeartAsset,
                          width: 22,
                          height: 22,
                        ),
                      ],
                    ),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
              _HeroProfilePanel(
                avatarUrls: avatarUrls,
                title: heroMessage.title,
                subtitle: heroMessage.subtitle,
                onTap: onOpenDetail,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OverlappedAvatars extends StatelessWidget {
  const _OverlappedAvatars({required this.avatarUrls});

  final List<String> avatarUrls;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 86,
      height: 48,
      child: Stack(
        children: [
          _AvatarImage(
            asset: _avatarOneAsset,
            url: avatarUrls.isNotEmpty ? avatarUrls[0] : null,
          ),
          Positioned(
            left: 38,
            child: _AvatarImage(
              asset: _avatarTwoAsset,
              url: avatarUrls.length > 1 ? avatarUrls[1] : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _AvatarImage extends StatelessWidget {
  const _AvatarImage({
    required this.asset,
    this.url,
  });

  final String asset;
  final String? url;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: dearSoftShadow(0.5),
      ),
      child: ClipOval(
        child: url == null || url!.trim().isEmpty
            ? _AnniversaryAsset(
                asset: asset,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
              )
            : Image.network(
                url!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _AnniversaryAsset(
                  asset: asset,
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                ),
              ),
      ),
    );
  }
}

class _HeroProfilePanel extends StatelessWidget {
  const _HeroProfilePanel({
    required this.avatarUrls,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final List<String> avatarUrls;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.6;
    return Material(
      color: context.anniversaryColors.surface.withValues(alpha: 0.92),
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
          decoration: const BoxDecoration(),
          child: largeText
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _OverlappedAvatars(avatarUrls: avatarUrls),
                        const SizedBox(width: 4),
                        const _AnniversaryAsset(
                          asset: _smallHeartAsset,
                          width: 20,
                          height: 20,
                        ),
                        const Spacer(),
                        const _DecorativeChevron(
                          boxSize: 44,
                          iconSize: 14,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: context.anniversaryColors.onSurfaceVariant,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      subtitle,
                      maxLines: 2,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: context.anniversaryColors.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0,
                          ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    _OverlappedAvatars(avatarUrls: avatarUrls),
                    const SizedBox(width: 4),
                    const _AnniversaryAsset(
                      asset: _smallHeartAsset,
                      width: 20,
                      height: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                  color: context
                                      .anniversaryColors.onSurfaceVariant,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            subtitle,
                            maxLines: 1,
                            softWrap: false,
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(
                                  color: context
                                      .anniversaryColors.onSurfaceVariant,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0,
                                ),
                          ),
                        ],
                      ),
                    ),
                    const _DecorativeChevron(
                      boxSize: 44,
                      iconSize: 14,
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: context.anniversaryColors.onSurface,
                  fontWeight: FontWeight.w900,
                ),
          ),
        ),
        TextButton(
          onPressed: onAction,
          child: Text(
            actionLabel,
            style: TextStyle(
              color: context.anniversaryColors.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const _DecorativeChevron(iconSize: 14),
      ],
    );
  }
}

class _TimelineEventTile extends StatelessWidget {
  const _TimelineEventTile({
    required this.showLineAbove,
    required this.showLineBelow,
    required this.child,
  });

  final bool showLineAbove;
  final bool showLineBelow;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.6;
    if (largeText) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            child: Padding(
              padding: const EdgeInsets.only(top: 28),
              child: Center(
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: context.anniversaryColors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(child: child),
        ],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 24,
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: showLineAbove
                        ? Container(
                            width: 2,
                            color: context.anniversaryColors.outlineVariant,
                          )
                        : const SizedBox(width: 2),
                  ),
                ),
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: context.anniversaryColors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                Expanded(
                  child: Center(
                    child: showLineBelow
                        ? Container(
                            width: 2,
                            color: context.anniversaryColors.outlineVariant,
                          )
                        : const SizedBox(width: 2),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _AnniversaryEventTile extends StatelessWidget {
  const _AnniversaryEventTile({
    required this.title,
    required this.dateLabel,
    required this.dday,
    required this.iconAsset,
    required this.reminderEnabled,
    required this.onTap,
    required this.onBell,
  });

  final String title;
  final String dateLabel;
  final String dday;
  final String iconAsset;
  final bool reminderEnabled;
  final VoidCallback onTap;
  final VoidCallback onBell;

  @override
  Widget build(BuildContext context) {
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.6;
    final eventIconSize = largeText ? 38.0 : 44.0;
    final eventIcon = Container(
      width: largeText ? 60 : 68,
      height: largeText ? 60 : 68,
      decoration: BoxDecoration(
        color: context.anniversaryColors.primaryContainer,
        shape: BoxShape.circle,
        border: Border.all(color: context.anniversaryColors.surface, width: 3),
      ),
      child: Center(
        child: _AnniversaryAsset(
          asset: iconAsset,
          width: eventIconSize,
          height: eventIconSize,
        ),
      ),
    );
    return Material(
      color: context.anniversaryColors.surface,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.fromLTRB(18, 16, 14, largeText ? 24 : 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: context.anniversaryColors.outlineVariant),
            boxShadow: dearSoftShadow(0.65),
          ),
          child: largeText
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        eventIcon,
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
                                      color:
                                          context.anniversaryColors.onSurface,
                                      fontWeight: FontWeight.w900,
                                    ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                dateLabel,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: context
                                          .anniversaryColors.onSurfaceVariant,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _DdayChip(label: dday),
                        const Spacer(),
                        _RoundedIconButton(
                          icon: reminderEnabled
                              ? Icons.notifications_rounded
                              : Icons.notifications_none_rounded,
                          label: reminderEnabled ? '알림 켜짐' : '알림 꺼짐',
                          size: 44,
                          iconSize: 22,
                          toggled: reminderEnabled,
                          onTap: onBell,
                        ),
                        const _DecorativeChevron(iconSize: 18),
                      ],
                    ),
                  ],
                )
              : Row(
                  children: [
                    eventIcon,
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(
                                        color:
                                            context.anniversaryColors.onSurface,
                                        fontWeight: FontWeight.w900,
                                      ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              _DdayChip(label: dday),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            dateLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: context
                                          .anniversaryColors.onSurfaceVariant,
                                      fontWeight: FontWeight.w700,
                                    ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _RoundedIconButton(
                      icon: reminderEnabled
                          ? Icons.notifications_rounded
                          : Icons.notifications_none_rounded,
                      label: reminderEnabled ? '알림 켜짐' : '알림 꺼짐',
                      size: 44,
                      iconSize: 22,
                      toggled: reminderEnabled,
                      onTap: onBell,
                    ),
                    const _DecorativeChevron(iconSize: 18),
                  ],
                ),
        ),
      ),
    );
  }
}

class _DdayChip extends StatelessWidget {
  const _DdayChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 54),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: context.anniversaryColors.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: context.anniversaryColors.primary,
              fontWeight: FontWeight.w900,
            ),
      ),
    );
  }
}

class _EmptyAnniversaryCard extends StatelessWidget {
  const _EmptyAnniversaryCard({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: context.anniversaryColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: context.anniversaryColors.outlineVariant),
        boxShadow: dearSoftShadow(0.6),
      ),
      child: Column(
        children: [
          const _AnniversaryAsset(
            asset: _eventHeartAsset,
            width: 52,
            height: 52,
          ),
          const SizedBox(height: 12),
          Text(
            '등록된 기념일이 없어요',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: context.anniversaryColors.onSurface,
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            '함께 기억하고 싶은 날을 추가해 주세요.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: context.anniversaryColors.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: onAdd,
            child: const Text('기념일 추가하기'),
          ),
        ],
      ),
    );
  }
}

class _NotificationSettingsCard extends StatelessWidget {
  const _NotificationSettingsCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const ValueKey('anniversary-notification-card'),
      color: context.anniversaryColors.surface,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: context.anniversaryColors.outlineVariant),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: context.anniversaryColors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: Icon(
                    Icons.notifications_rounded,
                    color: Theme.of(context).colorScheme.primary,
                    size: 24,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '알림 설정',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: context.anniversaryColors.onSurface,
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '기념일 전에 미리 알려드릴게요',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: context.anniversaryColors.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ),
              ),
              const _DecorativeChevron(iconSize: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomAddButton extends StatelessWidget {
  const _BottomAddButton({
    required this.saving,
    required this.onTap,
  });

  final bool saving;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final label = saving ? '기념일 저장 중' : '기념일 추가';
    return Tooltip(
      message: label,
      child: Opacity(
        opacity: onTap == null ? 0.58 : 1,
        child: Semantics(
          button: true,
          enabled: onTap != null,
          label: label,
          onTap: onTap,
          excludeSemantics: true,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: const ValueKey('add-anniversary'),
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: DearGradients.cta,
                  boxShadow: [
                    BoxShadow(
                      color: context.anniversaryColors.primary
                          .withValues(alpha: 0.28),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Center(
                  child: saving
                      ? Text(
                          '저장',
                          style:
                              Theme.of(context).textTheme.labelMedium?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                  ),
                        )
                      : const Icon(
                          Icons.add_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundedIconButton extends StatelessWidget {
  const _RoundedIconButton({
    required this.icon,
    required this.label,
    required this.size,
    required this.iconSize,
    required this.onTap,
    this.toggled,
  }) : assert(size >= DearTouchTargets.minimum);

  final IconData icon;
  final String label;
  final double size;
  final double iconSize;
  final VoidCallback onTap;
  final bool? toggled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        enabled: true,
        label: label,
        toggled: toggled,
        onTap: onTap,
        excludeSemantics: true,
        child: Material(
          color: scheme.surface.withValues(alpha: 0.86),
          borderRadius: BorderRadius.circular(size * 0.5),
          child: InkWell(
            borderRadius: BorderRadius.circular(size * 0.5),
            onTap: onTap,
            child: SizedBox(
              width: size,
              height: size,
              child: Center(
                child: Icon(
                  icon,
                  color: toggled == null
                      ? scheme.onSurface
                      : toggled!
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                  size: iconSize,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DecorativeChevron extends StatelessWidget {
  const _DecorativeChevron({required this.iconSize, this.boxSize});

  final double iconSize;
  final double? boxSize;

  @override
  Widget build(BuildContext context) {
    final icon = Icon(
      Icons.chevron_right_rounded,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      size: iconSize,
    );
    return ExcludeSemantics(
      child: boxSize == null
          ? icon
          : SizedBox.square(
              dimension: boxSize,
              child: Center(child: icon),
            ),
    );
  }
}

class _AnniversaryEditorSheet extends ConsumerStatefulWidget {
  const _AnniversaryEditorSheet({
    required this.coupleId,
    required this.title,
    required this.submitLabel,
    this.initialItem,
  });

  final String coupleId;
  final String title;
  final String submitLabel;
  final AnniversaryItem? initialItem;

  @override
  ConsumerState<_AnniversaryEditorSheet> createState() =>
      _AnniversaryEditorSheetState();
}

class _AnniversaryEditorSheetState
    extends ConsumerState<_AnniversaryEditorSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _noteController;
  late DateTime _eventDate;
  late AnniversaryRepeat _repeat;
  late bool _reminderEnabled;
  late int _reminderDaysBefore;
  late int _reminderHour;
  String? _linkedAlbumId;
  String? _titleError;

  @override
  void initState() {
    super.initState();
    final item = widget.initialItem;
    _titleController = TextEditingController(text: item?.title ?? '');
    _noteController = TextEditingController(text: item?.note ?? '');
    _eventDate = DateUtils.dateOnly(item?.eventDate ?? DateTime.now());
    _repeat = item?.repeat ?? AnniversaryRepeat.none;
    _reminderEnabled = item?.reminderEnabled ?? true;
    _reminderDaysBefore = item?.reminderDaysBefore ?? 0;
    _reminderHour = item?.reminderHour ?? 9;
    _linkedAlbumId = item?.linkedAlbumId;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _eventDate,
      firstDate: DateTime(1900),
      lastDate: DateTime(DateTime.now().year + 50, 12, 31),
    );
    if (picked != null && mounted) setState(() => _eventDate = picked);
  }

  Future<void> _pickReminderHour() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _reminderHour, minute: 0),
      helpText: '알림 시간',
    );
    if (picked != null && mounted) {
      setState(() => _reminderHour = picked.hour);
    }
  }

  void _submit() {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _titleError = '기념일 이름을 입력해 주세요.');
      return;
    }
    Navigator.pop(
      context,
      _AnniversaryEditorDraft(
        title: title,
        eventDate: _eventDate,
        repeat: _repeat,
        reminderEnabled: _reminderEnabled,
        reminderDaysBefore: _reminderDaysBefore,
        reminderHour: _reminderHour,
        note: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
        linkedAlbumId: _linkedAlbumId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final albumsAsync = ref.watch(memoryAlbumsProvider(widget.coupleId));
    final albums = albumsAsync.valueOrNull ?? const <MemoryAlbum>[];
    if (albumsAsync.hasValue &&
        _linkedAlbumId != null &&
        !albums.any((album) => album.id == _linkedAlbumId)) {
      _linkedAlbumId = null;
    }
    final reminderDayOptions = <int>{
      0,
      1,
      3,
      7,
      14,
      30,
      _reminderDaysBefore,
    }.toList()
      ..sort();

    return _BottomSheetFrame(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          24,
          10,
          24,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SheetHandle(title: widget.title),
            const SizedBox(height: 22),
            TextField(
              key: const ValueKey('anniversary-title-field'),
              controller: _titleController,
              autofocus: widget.initialItem == null,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              onChanged: (_) {
                if (_titleError != null) setState(() => _titleError = null);
              },
              decoration: InputDecoration(
                labelText: '기념일 이름',
                hintText: '예: 처음 여행한 날',
                errorText: _titleError,
              ),
            ),
            const SizedBox(height: 12),
            _EditorOptionCard(
              child: ListTile(
                key: const ValueKey('anniversary-date-field'),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                title: const Text('날짜'),
                subtitle: Text(_dateWithWeekdayLabel(_eventDate)),
                trailing: const Icon(Icons.calendar_today_rounded),
                onTap: _pickDate,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('anniversary-note-field'),
              controller: _noteController,
              minLines: 2,
              maxLines: 4,
              maxLength: 500,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(
                labelText: '메모',
                hintText: '함께 기억하고 싶은 이야기를 남겨요',
              ),
            ),
            const SizedBox(height: 10),
            _EditorOptionCard(
              child: albumsAsync.hasValue
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                      child: DropdownButtonFormField<String?>(
                        key: const ValueKey('anniversary-linked-album'),
                        initialValue: _linkedAlbumId,
                        decoration: const InputDecoration(
                          labelText: '연결 앨범',
                          helperText: '이 날과 관련된 추억 앨범을 연결해요',
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('연결 안 함'),
                          ),
                          ...albums.map(
                            (album) => DropdownMenuItem<String?>(
                              value: album.id,
                              child: Text(
                                album.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                        onChanged: (value) =>
                            setState(() => _linkedAlbumId = value),
                      ),
                    )
                  : ListTile(
                      key: const ValueKey('anniversary-linked-album'),
                      title: const Text('연결 앨범'),
                      subtitle: Text(
                        albumsAsync.hasError ? '앨범을 불러오지 못했어요' : '앨범을 불러오고 있어요',
                      ),
                      trailing: albumsAsync.hasError
                          ? const Icon(Icons.cloud_off_rounded)
                          : const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                    ),
            ),
            const SizedBox(height: 10),
            _EditorOptionCard(
              child: SwitchListTile.adaptive(
                key: const ValueKey('anniversary-repeat-switch'),
                value: _repeat == AnniversaryRepeat.yearly,
                title: const Text('매년 반복'),
                subtitle: const Text('해마다 같은 날짜에 다시 보여요'),
                activeThumbColor: context.anniversaryColors.primary,
                onChanged: (value) => setState(
                  () => _repeat =
                      value ? AnniversaryRepeat.yearly : AnniversaryRepeat.none,
                ),
              ),
            ),
            const SizedBox(height: 10),
            _EditorOptionCard(
              child: Column(
                children: [
                  SwitchListTile.adaptive(
                    key: const ValueKey('anniversary-reminder-switch'),
                    value: _reminderEnabled,
                    title: const Text('개별 알림'),
                    subtitle: const Text('이 기념일을 미리 알려드려요'),
                    activeThumbColor: context.anniversaryColors.primary,
                    onChanged: (value) =>
                        setState(() => _reminderEnabled = value),
                  ),
                  if (_reminderEnabled) ...[
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: DropdownButtonFormField<int>(
                        key: const ValueKey('anniversary-reminder-days'),
                        initialValue: _reminderDaysBefore,
                        decoration: const InputDecoration(labelText: '알림 시점'),
                        items: reminderDayOptions
                            .map(
                              (days) => DropdownMenuItem(
                                value: days,
                                child: Text(days == 0 ? '당일' : '$days일 전'),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _reminderDaysBefore = value);
                          }
                        },
                      ),
                    ),
                    ListTile(
                      key: const ValueKey('anniversary-reminder-hour'),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16),
                      title: const Text('알림 시간'),
                      trailing: Text(
                        _hourLabel(_reminderHour),
                        style: TextStyle(
                          color: context.anniversaryColors.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      onTap: _pickReminderHour,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 54,
              child: FilledButton(
                key: const ValueKey('save-anniversary'),
                onPressed: _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: context.anniversaryColors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(widget.submitLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnniversaryMenuSheet extends StatelessWidget {
  const _AnniversaryMenuSheet({required this.hasRelationshipDate});

  final bool hasRelationshipDate;

  @override
  Widget build(BuildContext context) {
    return _BottomSheetFrame(
      scrollable: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _SheetHandle(title: '기념일 메뉴'),
            const SizedBox(height: 14),
            _SheetActionTile(
              icon: Icons.calendar_month_rounded,
              title: '전체 기념일',
              subtitle: '다가오는 날을 15개씩 확인해요',
              onTap: () => Navigator.pop(
                context,
                _AnniversaryMenuAction.fullList,
              ),
            ),
            _SheetActionTile(
              icon: Icons.notifications_active_rounded,
              title: '알림 설정',
              subtitle: '전체 기념일 알림을 관리해요',
              onTap: () => Navigator.pop(
                context,
                _AnniversaryMenuAction.notifications,
              ),
            ),
            _SheetActionTile(
              icon: Icons.favorite_rounded,
              title: hasRelationshipDate ? '처음 만난 날 변경' : '처음 만난 날 설정',
              subtitle: '자동 100일·주년의 기준일을 관리해요',
              onTap: () => Navigator.pop(
                context,
                _AnniversaryMenuAction.relationshipDate,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroDetailSheet extends StatelessWidget {
  const _HeroDetailSheet({
    required this.anniversaryDate,
    required this.nextEntry,
  });

  final DateTime? anniversaryDate;
  final AnniversaryTimelineEntry? nextEntry;

  @override
  Widget build(BuildContext context) {
    return _BottomSheetFrame(
      scrollable: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 10, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SheetHandle(title: '우리의 기념일'),
            const SizedBox(height: 20),
            Row(
              children: [
                const _AnniversaryAsset(
                  asset: _heroRingAsset,
                  width: 108,
                  height: 78,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        anniversaryDate == null
                            ? '처음 만난 날을 설정해 주세요'
                            : anniversaryDdayLabel(anniversaryDate!),
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  color: context.anniversaryColors.onSurface,
                                  fontWeight: FontWeight.w900,
                                ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        anniversaryDate == null
                            ? '기준일을 설정하면 100일과 주년을 자동으로 계산해요.'
                            : '${anniversaryDateKoreanLabel(anniversaryDate!)}부터 함께',
                        style: TextStyle(
                            color: context.anniversaryColors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (nextEntry != null) ...[
              const SizedBox(height: 18),
              _DetailInfoRow(label: '다음 기념일', value: nextEntry!.title),
              _DetailInfoRow(
                label: '날짜',
                value: _dateWithWeekdayLabel(nextEntry!.eventDate),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(context, _HeroDetailAction.fullList),
              child: const Text('전체 기념일 보기'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(context, _HeroDetailAction.relationshipDate),
              child: Text(
                anniversaryDate == null ? '처음 만난 날 설정' : '기준일 변경',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AutomaticAnniversaryDetailSheet extends StatelessWidget {
  const _AutomaticAnniversaryDetailSheet({required this.entry});

  final AnniversaryTimelineEntry entry;

  @override
  Widget build(BuildContext context) {
    final description = entry.kind == AnniversaryTimelineKind.hundredDay
        ? '처음 만난 날부터 100일 단위로 자동 계산된 기념일이에요.'
        : '처음 만난 날짜를 기준으로 자동 계산된 주년이에요.';
    return _BottomSheetFrame(
      scrollable: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 10, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SheetHandle(title: '기념일 상세'),
            const SizedBox(height: 18),
            Center(
              child: _AnniversaryAsset(
                asset: _iconAssetFor(entry),
                width: 76,
                height: 76,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              entry.title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: context.anniversaryColors.onSurface,
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              '${_dateWithWeekdayLabel(entry.eventDate)} · ${_dday(entry.eventDate)}',
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: context.anniversaryColors.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Text(
              description,
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: context.anniversaryColors.onSurfaceVariant),
            ),
            const SizedBox(height: 22),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(context, _AutomaticDetailAction.notifications),
              child: const Text('알림 설정'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(context, _AutomaticDetailAction.fullList),
              child: const Text('전체 기념일 보기'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomAnniversaryDetailSheet extends StatelessWidget {
  const _CustomAnniversaryDetailSheet({
    required this.item,
    required this.occurrenceDate,
  });

  final AnniversaryItem item;
  final DateTime occurrenceDate;

  @override
  Widget build(BuildContext context) {
    final reminder = !item.reminderEnabled
        ? '꺼짐'
        : '${item.reminderDaysBefore == 0 ? '당일' : '${item.reminderDaysBefore}일 전'} ${_hourLabel(item.reminderHour)}';
    return _BottomSheetFrame(
      scrollable: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 10, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SheetHandle(title: '기념일 상세'),
            const SizedBox(height: 16),
            const Center(
              child: _AnniversaryAsset(
                asset: _eventGiftAsset,
                width: 76,
                height: 76,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              item.title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: context.anniversaryColors.onSurface,
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              '${_dateWithWeekdayLabel(occurrenceDate)} · ${_dday(occurrenceDate)}',
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: context.anniversaryColors.onSurfaceVariant),
            ),
            const SizedBox(height: 18),
            _DetailInfoRow(
              label: '반복',
              value: item.repeat == AnniversaryRepeat.yearly ? '매년' : '반복 안 함',
            ),
            _DetailInfoRow(label: '알림', value: reminder),
            _DetailInfoRow(
              label: '연결 앨범',
              value: item.linkedAlbumId == null ? '연결 안 함' : '추억 앨범 연결됨',
            ),
            if (item.note?.trim().isNotEmpty ?? false) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: context.anniversaryColors.surfaceContainer
                      .withValues(alpha: 0.48),
                  borderRadius: BorderRadius.circular(DearRadii.medium),
                ),
                child: Text(
                  item.note!,
                  style: TextStyle(
                    color: context.anniversaryColors.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const ValueKey('edit-anniversary'),
              onPressed: () => Navigator.pop(context, _CustomDetailAction.edit),
              icon: const Icon(Icons.edit_rounded),
              label: const Text('수정'),
            ),
            const SizedBox(height: 4),
            TextButton.icon(
              key: const ValueKey('delete-anniversary'),
              onPressed: () =>
                  Navigator.pop(context, _CustomDetailAction.delete),
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('삭제'),
              style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomSheetFrame extends StatelessWidget {
  const _BottomSheetFrame({required this.child, this.scrollable = false});

  final Widget child;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final content = DecoratedBox(
      decoration: BoxDecoration(
        color: context.anniversaryColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: child,
    );
    return SafeArea(
      top: false,
      child: scrollable ? SingleChildScrollView(child: content) : content,
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 42,
          height: 4,
          decoration: BoxDecoration(
            color: context.anniversaryColors.outlineVariant,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: context.anniversaryColors.onSurface,
                fontWeight: FontWeight.w900,
              ),
        ),
      ],
    );
  }
}

class _SheetActionTile extends StatelessWidget {
  const _SheetActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      minLeadingWidth: 44,
      leading: CircleAvatar(
        backgroundColor: context.anniversaryColors.primaryContainer,
        foregroundColor: context.anniversaryColors.primary,
        child: Icon(icon),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

class _EditorOptionCard extends StatelessWidget {
  const _EditorOptionCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.anniversaryColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.anniversaryColors.outlineVariant),
      ),
      child: child,
    );
  }
}

class _DetailInfoRow extends StatelessWidget {
  const _DetailInfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          SizedBox(
            width: 82,
            child: Text(label,
                style: TextStyle(
                    color: context.anniversaryColors.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: context.anniversaryColors.onSurface,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnniversaryListSkeleton extends StatelessWidget {
  const _AnniversaryListSkeleton({this.itemCount = 3});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        itemCount,
        (index) => Container(
          height: 102,
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: context.anniversaryColors.surface.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: context.anniversaryColors.outlineVariant),
          ),
          child: Row(
            children: [
              const SizedBox(width: 18),
              Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  color: context.anniversaryColors.primaryContainer,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 112,
                      height: 14,
                      color: context.anniversaryColors.primaryContainer,
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: 150,
                      height: 11,
                      color: context.anniversaryColors.surfaceContainerHigh,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnniversaryPageLoadingState extends StatelessWidget {
  const _AnniversaryPageLoadingState();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _loadingCircle(context, 54),
              Container(
                width: 82,
                height: 24,
                decoration: _loadingDecoration(context, 12),
              ),
              _loadingCircle(context, 54),
            ],
          ),
          const SizedBox(height: 22),
          Container(
            height: 320,
            decoration: _loadingDecoration(context, 30),
          ),
          const SizedBox(height: 28),
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: 150,
              height: 22,
              decoration: _loadingDecoration(context, 10),
            ),
          ),
          const SizedBox(height: 14),
          const _AnniversaryListSkeleton(),
        ],
      ),
    );
  }

  static Widget _loadingCircle(BuildContext context, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: context.anniversaryColors.primaryContainer,
        shape: BoxShape.circle,
      ),
    );
  }

  static BoxDecoration _loadingDecoration(
    BuildContext context,
    double radius,
  ) {
    return BoxDecoration(
      color: context.anniversaryColors.surface.withValues(alpha: 0.72),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: context.anniversaryColors.outlineVariant),
    );
  }
}

class _AnniversaryStandaloneError extends StatelessWidget {
  const _AnniversaryStandaloneError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: _AnniversaryErrorCard(onRetry: onRetry),
      ),
    );
  }
}

class _AnniversaryErrorCard extends StatelessWidget {
  const _AnniversaryErrorCard({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: context.anniversaryColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: context.anniversaryColors.outlineVariant),
      ),
      child: Column(
        children: [
          Icon(
            Icons.cloud_off_rounded,
            size: 38,
            color: context.anniversaryColors.primary,
          ),
          const SizedBox(height: 10),
          Text(
            '기념일을 불러오지 못했어요',
            style: TextStyle(
              color: context.anniversaryColors.onSurface,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '연결을 확인한 뒤 다시 시도해 주세요.',
            style: TextStyle(color: context.anniversaryColors.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          TextButton(onPressed: onRetry, child: const Text('다시 시도')),
        ],
      ),
    );
  }
}

String _hourLabel(int hour) {
  final period = hour < 12 ? '오전' : '오후';
  final displayHour = hour % 12 == 0 ? 12 : hour % 12;
  return '$period $displayHour시';
}
