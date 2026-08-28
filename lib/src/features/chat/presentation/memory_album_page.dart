import 'dart:async';

import 'package:couple_chat_app/src/common/error_mapper.dart';
import 'package:couple_chat_app/src/common/dear_design.dart';
import 'package:couple_chat_app/src/features/auth/data/auth_providers.dart';
import 'package:couple_chat_app/src/features/chat/data/chat_providers.dart';
import 'package:couple_chat_app/src/features/chat/data/memory_album_providers.dart';
import 'package:couple_chat_app/src/features/chat/data/memory_album_repository.dart';
import 'package:couple_chat_app/src/features/chat/presentation/chat_image_view_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _albumEmptyCoverAsset = 'assets/images/album/album_empty_cover.png';

class MemoryAlbumPage extends ConsumerStatefulWidget {
  const MemoryAlbumPage({super.key});

  @override
  ConsumerState<MemoryAlbumPage> createState() => _MemoryAlbumPageState();
}

class _MemoryAlbumPageState extends ConsumerState<MemoryAlbumPage> {
  bool _creatingAlbum = false;
  bool _processingAlbumAction = false;

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(myProfileProvider);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('추억 앨범'),
        actions: [
          profileAsync.maybeWhen(
            data: (profile) {
              if (profile == null ||
                  !profile.isPaired ||
                  profile.coupleId == null) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(right: 20),
                child: _MemoryAlbumHeaderButton(
                  key: const ValueKey('new-album-button'),
                  tooltip: '새 앨범',
                  onPressed: _creatingAlbum
                      ? null
                      : () => _showCreateAlbumSheet(profile.coupleId!),
                  icon: Icons.add_rounded,
                  iconSize: 32,
                ),
              );
            },
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: DearBackground(
        child: Stack(
          children: [
            Positioned.fill(
              child: profileAsync.when(
                loading: () => const _AlbumLoadingSkeleton(),
                error: (error, _) => _AlbumErrorState(
                  message: '연결 정보를 불러오지 못했어요.',
                  onRetry: () => ref.invalidate(myProfileProvider),
                ),
                data: (profile) {
                  if (profile == null ||
                      !profile.isPaired ||
                      profile.coupleId == null) {
                    return const Center(child: Text('커플 연결 후 사용할 수 있어요.'));
                  }

                  return _AlbumListView(
                    coupleId: profile.coupleId!,
                    onCreateAlbum: () =>
                        _showCreateAlbumSheet(profile.coupleId!),
                    onOpenAlbum: (album) => _openAlbumDetail(
                      coupleId: profile.coupleId!,
                      album: album,
                    ),
                    onAlbumActions: (album) => _showAlbumActionSheet(
                      coupleId: profile.coupleId!,
                      album: album,
                    ),
                    onViewAllPhotos: () => _openAllPhotos(
                      coupleId: profile.coupleId!,
                      currentUserId: profile.userId,
                    ),
                  );
                },
              ),
            ),
            if (_creatingAlbum || _processingAlbumAction)
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: Semantics(
                  liveRegion: true,
                  label: '앨범 변경 저장 중',
                  child: const LinearProgressIndicator(
                    key: ValueKey('album-operation-progress'),
                    minHeight: 4,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _openAlbumDetail({
    required String coupleId,
    required MemoryAlbum album,
  }) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => _MemoryAlbumDetailPage(
          coupleId: coupleId,
          album: album,
        ),
      ),
    );
  }

  void _openAllPhotos({
    required String coupleId,
    required String currentUserId,
  }) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => _AllMemoryPhotosPage(
          coupleId: coupleId,
          currentUserId: currentUserId,
        ),
      ),
    );
  }

  Future<void> _showCreateAlbumSheet(String coupleId) async {
    final result = await showModalBottomSheet<_CreateAlbumDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _CreateMemoryAlbumSheet(),
    );
    if (!mounted || result == null || result.name.trim().isEmpty) return;

    setState(() => _creatingAlbum = true);
    try {
      final album = await ref.read(createMemoryAlbumProvider)(
        coupleId: coupleId,
        name: result.name,
        coverBytes: result.coverImage?.bytes,
        coverExtension: result.coverImage?.extension,
      );
      if (!mounted) return;
      await ref.read(memoryAlbumFeedProvider(coupleId).notifier).refresh();
      ref.invalidate(recentMemoryAlbumPhotosProvider(coupleId));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${album.name} 앨범을 만들었어요.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(toFriendlyErrorMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _creatingAlbum = false);
    }
  }

  Future<void> _showAlbumActionSheet({
    required String coupleId,
    required MemoryAlbum album,
  }) async {
    if (_processingAlbumAction) return;

    final action = await showModalBottomSheet<_AlbumAction>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _AlbumActionSheet(album: album),
    );
    if (!mounted || action == null) return;

    switch (action) {
      case _AlbumAction.featured:
        await _setFeaturedAlbum(coupleId: coupleId, album: album);
        return;
      case _AlbumAction.edit:
        await _showEditAlbumSheet(coupleId: coupleId, album: album);
        return;
      case _AlbumAction.delete:
        await _confirmDeleteAlbum(coupleId: coupleId, album: album);
        return;
    }
  }

  Future<void> _showEditAlbumSheet({
    required String coupleId,
    required MemoryAlbum album,
  }) async {
    final result = await showModalBottomSheet<_CreateAlbumDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CreateMemoryAlbumSheet(
        title: '앨범 수정',
        submitLabel: '수정 완료',
        initialName: album.name,
        initialCoverStoragePath: album.coverStoragePath,
      ),
    );
    if (!mounted || result == null || result.name.trim().isEmpty) return;

    setState(() => _processingAlbumAction = true);
    try {
      final updatedAlbum = await ref.read(updateMemoryAlbumProvider)(
        coupleId: coupleId,
        albumId: album.id,
        name: result.name,
        coverBytes: result.coverImage?.bytes,
        coverExtension: result.coverImage?.extension,
      );
      if (!mounted) return;
      await ref.read(memoryAlbumFeedProvider(coupleId).notifier).refresh();
      ref.invalidate(recentMemoryAlbumPhotosProvider(coupleId));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${updatedAlbum.name} 앨범을 수정했어요.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(toFriendlyErrorMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _processingAlbumAction = false);
    }
  }

  Future<void> _confirmDeleteAlbum({
    required String coupleId,
    required MemoryAlbum album,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('앨범을 삭제할까요?'),
          content: Text(
            '${album.name} 앨범과 안에 있는 사진 기록이 삭제돼요. 이 작업은 되돌릴 수 없어요.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('취소'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: DearColors.error,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('삭제'),
            ),
          ],
        );
      },
    );
    if (!mounted || confirmed != true) return;

    setState(() => _processingAlbumAction = true);
    try {
      await ref.read(deleteMemoryAlbumProvider)(
        coupleId: coupleId,
        albumId: album.id,
      );
      if (!mounted) return;
      await ref.read(memoryAlbumFeedProvider(coupleId).notifier).refresh();
      ref.invalidate(recentMemoryAlbumPhotosProvider(coupleId));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${album.name} 앨범을 삭제했어요.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(toFriendlyErrorMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _processingAlbumAction = false);
    }
  }

  Future<void> _setFeaturedAlbum({
    required String coupleId,
    required MemoryAlbum album,
  }) async {
    if (album.isFeatured) return;

    setState(() => _processingAlbumAction = true);
    try {
      await ref.read(setFeaturedMemoryAlbumProvider)(
        coupleId: coupleId,
        albumId: album.id,
      );
      if (!mounted) return;
      await ref.read(memoryAlbumFeedProvider(coupleId).notifier).refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${album.name}을 대표 앨범으로 설정했어요.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(toFriendlyErrorMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _processingAlbumAction = false);
    }
  }
}

class _MemoryAlbumDetailPage extends ConsumerStatefulWidget {
  const _MemoryAlbumDetailPage({
    required this.coupleId,
    required this.album,
  });

  final String coupleId;
  final MemoryAlbum album;

  @override
  ConsumerState<_MemoryAlbumDetailPage> createState() =>
      _MemoryAlbumDetailPageState();
}

class _MemoryAlbumDetailPageState
    extends ConsumerState<_MemoryAlbumDetailPage> {
  late MemoryAlbum _album;
  bool _uploading = false;
  int _uploadedCount = 0;
  int _uploadTotal = 0;
  List<PickedChatImage> _retryableUploads = const [];
  bool _cancelRemainingUploads = false;

  @override
  void initState() {
    super.initState();
    _album = widget.album;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_album.name),
        actions: [
          if (_retryableUploads.isNotEmpty && !_uploading)
            _MemoryAlbumHeaderButton(
              key: const ValueKey('retry-album-photos-button'),
              tooltip: '실패하거나 취소한 사진 다시 올리기',
              onPressed: _retryFailedUploads,
              icon: Icons.refresh_rounded,
              iconSize: 26,
            ),
          Padding(
            padding: const EdgeInsets.only(right: 20),
            child: _MemoryAlbumHeaderButton(
              key: const ValueKey('upload-album-photos-button'),
              tooltip: _uploading ? '남은 사진 업로드 취소' : '사진 여러 장 올리기',
              onPressed:
                  _uploading ? _cancelPendingUploads : _pickAndUploadPhotos,
              icon: _uploading ? Icons.close_rounded : Icons.add_rounded,
              iconSize: _uploading ? 26 : 32,
            ),
          ),
        ],
      ),
      body: DearBackground(
        child: _AlbumDetailView(
          coupleId: widget.coupleId,
          album: _album,
          uploading: _uploading,
          uploadedCount: _uploadedCount,
          uploadTotal: _uploadTotal,
          onUploadPhoto: _pickAndUploadPhotos,
          onSetCoverPhoto: _setAlbumCoverPhoto,
        ),
      ),
    );
  }

  Future<void> _setAlbumCoverPhoto(MemoryAlbumPhoto photo) async {
    try {
      await ref.read(setMemoryAlbumCoverPhotoProvider)(
        coupleId: widget.coupleId,
        albumId: _album.id,
        photoId: photo.id,
      );
      if (!mounted) return;
      setState(() {
        _album = _album.copyWith(
          coverPhotoId: photo.id,
          coverStoragePath: photo.storagePath,
        );
      });
      await ref
          .read(memoryAlbumFeedProvider(widget.coupleId).notifier)
          .refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('대표 사진을 설정했어요.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(toFriendlyErrorMessage(error))),
      );
    }
  }

  Future<void> _pickAndUploadPhotos() async {
    if (_uploading) return;
    final pickedImages = await ref.read(chatPickImagesProvider)();
    if (!mounted || pickedImages.isEmpty) return;

    final validImages = <PickedChatImage>[];
    var unsupportedCount = 0;
    var tooLargeCount = 0;
    for (final picked in pickedImages) {
      if (!isSupportedImageExtension(picked.extension)) {
        unsupportedCount++;
      } else if (isImageTooLarge(picked.bytes.length)) {
        tooLargeCount++;
      } else {
        validImages.add(picked);
      }
    }

    if (validImages.isEmpty) {
      final reason = unsupportedCount > 0
          ? 'jpg, png, webp 사진만 올릴 수 있어요.'
          : '사진이 너무 커요. 최대 ${formatImageSizeLabel(chatImageMaxBytes)}까지 가능해요.';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(reason)));
      return;
    }

    await _uploadPhotos(
      validImages,
      unsupportedCount: unsupportedCount,
      tooLargeCount: tooLargeCount,
    );
  }

  void _cancelPendingUploads() {
    if (!_uploading || _cancelRemainingUploads) return;
    setState(() => _cancelRemainingUploads = true);
  }

  Future<void> _retryFailedUploads() async {
    if (_uploading || _retryableUploads.isEmpty) return;
    final retry = List<PickedChatImage>.of(_retryableUploads);
    await _uploadPhotos(retry);
  }

  Future<void> _uploadPhotos(
    List<PickedChatImage> images, {
    int unsupportedCount = 0,
    int tooLargeCount = 0,
  }) async {
    if (_uploading || images.isEmpty) return;
    setState(() {
      _uploading = true;
      _cancelRemainingUploads = false;
      _retryableUploads = const [];
      _uploadedCount = 0;
      _uploadTotal = images.length;
    });

    var succeededCount = 0;
    var processedCount = 0;
    final retryable = <PickedChatImage>[];
    for (var index = 0; index < images.length; index++) {
      if (_cancelRemainingUploads) {
        retryable.addAll(images.skip(index));
        break;
      }
      final picked = images[index];
      try {
        await ref.read(uploadMemoryAlbumPhotoProvider)(
          coupleId: widget.coupleId,
          albumId: _album.id,
          bytes: picked.bytes,
          extension: picked.extension,
        );
        succeededCount++;
      } catch (_) {
        retryable.add(picked);
      }
      processedCount++;
      if (mounted) setState(() => _uploadedCount = processedCount);
    }
    if (!mounted) return;

    final skippedParts = <String>[];
    if (unsupportedCount > 0) {
      skippedParts.add('지원 안 되는 사진 $unsupportedCount장 제외');
    }
    if (tooLargeCount > 0) {
      skippedParts.add('용량 큰 사진 $tooLargeCount장 제외');
    }
    final skippedLabel =
        skippedParts.isEmpty ? '' : ' (${skippedParts.join(', ')})';

    if (succeededCount > 0) {
      final args = MemoryAlbumPhotoFeedArgs(
        coupleId: widget.coupleId,
        albumId: _album.id,
      );
      await Future.wait([
        ref.read(memoryAlbumPhotoFeedProvider(args).notifier).refresh(),
        ref.read(memoryAlbumFeedProvider(widget.coupleId).notifier).refresh(),
      ]);
      ref.invalidate(recentMemoryAlbumPhotosProvider(widget.coupleId));
      if (!mounted) return;
    }

    setState(() {
      _uploading = false;
      _cancelRemainingUploads = false;
      _retryableUploads = List.unmodifiable(retryable);
      _uploadedCount = 0;
      _uploadTotal = 0;
    });

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    if (retryable.isNotEmpty) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '사진 $succeededCount장은 올라갔고 ${retryable.length}장은 남겨뒀어요.$skippedLabel',
          ),
          action: SnackBarAction(
            label: '다시 시도',
            onPressed: _retryFailedUploads,
          ),
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${_album.name}에 사진 $succeededCount장을 올렸어요.$skippedLabel',
          ),
        ),
      );
    }
  }
}

enum _PhotoUploaderFilter { all, mine, partner }

enum _PhotoDateFilterChoice { all, last7Days, last30Days, thisYear, custom }

class _AllMemoryPhotosPage extends ConsumerStatefulWidget {
  const _AllMemoryPhotosPage({
    required this.coupleId,
    required this.currentUserId,
  });

  final String coupleId;
  final String currentUserId;

  @override
  ConsumerState<_AllMemoryPhotosPage> createState() =>
      _AllMemoryPhotosPageState();
}

class _AllMemoryPhotosPageState extends ConsumerState<_AllMemoryPhotosPage> {
  DateTimeRange? _dateRange;
  _PhotoUploaderFilter _uploaderFilter = _PhotoUploaderFilter.all;
  final Set<String> _selectedPhotoIds = <String>{};
  bool _selectionMode = false;
  bool _processingSelection = false;

  DateTime? get _createdAtOrAfter {
    final start = _dateRange?.start;
    return start == null ? null : DateTime(start.year, start.month, start.day);
  }

  DateTime? get _createdAtBefore {
    final end = _dateRange?.end;
    return end == null
        ? null
        : DateTime(end.year, end.month, end.day).add(const Duration(days: 1));
  }

  MemoryAlbumPhotoFeedArgs get _feedArgs => MemoryAlbumPhotoFeedArgs(
        coupleId: widget.coupleId,
        createdAtOrAfter: _createdAtOrAfter,
        createdAtBefore: _createdAtBefore,
        uploadedBy: _uploaderFilter == _PhotoUploaderFilter.mine
            ? widget.currentUserId
            : null,
        excludedUploader: _uploaderFilter == _PhotoUploaderFilter.partner
            ? widget.currentUserId
            : null,
      );

  bool get _hasActiveFilters =>
      _dateRange != null || _uploaderFilter != _PhotoUploaderFilter.all;

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(memoryAlbumPhotoFeedProvider(_feedArgs));
    final visibleIds = feed.items.map((photo) => photo.id).toSet();
    _selectedPhotoIds.removeWhere((id) => !visibleIds.contains(id));

    return PopScope(
      canPop: !_selectionMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selectionMode && !_processingSelection) {
          _exitSelectionMode();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: _selectionMode
              ? Semantics(
                  container: true,
                  liveRegion: true,
                  label: '사진 ${_selectedPhotoIds.length}장 선택됨',
                  child: ExcludeSemantics(
                    child: Text('${_selectedPhotoIds.length}장 선택'),
                  ),
                )
              : const Text('전체 사진'),
          actions: _selectionMode
              ? [
                  DearIconButton(
                    key: const ValueKey('select-all-memory-photos'),
                    onPressed: _processingSelection || feed.items.isEmpty
                        ? null
                        : () => _toggleSelectAll(feed.items),
                    tooltip: _selectedPhotoIds.length == feed.items.length
                        ? '전체 선택 해제'
                        : '전체 사진 선택',
                    toggled: _selectedPhotoIds.length == feed.items.length,
                    icon: const Icon(Icons.select_all_rounded),
                    selectedIcon: const Icon(Icons.deselect_rounded),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    key: const ValueKey('cancel-photo-selection'),
                    onPressed: _processingSelection ? null : _exitSelectionMode,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(
                        DearTouchTargets.minimum,
                        DearTouchTargets.minimum,
                      ),
                    ),
                    child: const Text('선택 취소'),
                  ),
                  const SizedBox(width: 8),
                ]
              : [
                  TextButton.icon(
                    key: const ValueKey('start-photo-selection'),
                    onPressed: feed.items.isEmpty ? null : _enterSelectionMode,
                    icon: const Icon(Icons.check_circle_outline_rounded),
                    label: const Text('선택'),
                  ),
                  const SizedBox(width: 8),
                ],
        ),
        body: DearBackground(
          child: Column(
            children: [
              _AllPhotoFilterBar(
                dateRange: _dateRange,
                uploaderFilter: _uploaderFilter,
                enabled: !_selectionMode && !_processingSelection,
                onChooseDate: _chooseDateRange,
                onClearDate: _dateRange == null ? null : _clearDateRange,
                onUploaderChanged: _setUploaderFilter,
              ),
              Expanded(
                child: _AllMemoryPhotosView(
                  args: _feedArgs,
                  hasActiveFilters: _hasActiveFilters,
                  selectionMode: _selectionMode,
                  selectedPhotoIds: _selectedPhotoIds,
                  onToggleSelection: _togglePhotoSelection,
                  onBeginSelection: _beginSelectionWithPhoto,
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: _selectionMode
            ? _PhotoSelectionActionBar(
                selectedCount: _selectedPhotoIds.length,
                processing: _processingSelection,
                onMove: _selectedPhotoIds.isEmpty ? null : _moveSelectedPhotos,
                onDelete:
                    _selectedPhotoIds.isEmpty ? null : _deleteSelectedPhotos,
              )
            : null,
      ),
    );
  }

  void _enterSelectionMode() {
    if (_selectionMode || _processingSelection) return;
    setState(() => _selectionMode = true);
  }

  void _beginSelectionWithPhoto(MemoryAlbumPhoto photo) {
    if (_processingSelection) return;
    setState(() {
      _selectionMode = true;
      _selectedPhotoIds.add(photo.id);
    });
  }

  void _exitSelectionMode() {
    if (_processingSelection) return;
    setState(() {
      _selectionMode = false;
      _selectedPhotoIds.clear();
    });
  }

  void _togglePhotoSelection(MemoryAlbumPhoto photo) {
    if (_processingSelection) return;
    setState(() {
      if (!_selectedPhotoIds.remove(photo.id)) {
        _selectedPhotoIds.add(photo.id);
      }
    });
  }

  void _toggleSelectAll(List<MemoryAlbumPhoto> photos) {
    if (_processingSelection) return;
    setState(() {
      if (_selectedPhotoIds.length == photos.length) {
        _selectedPhotoIds.clear();
      } else {
        _selectedPhotoIds
          ..clear()
          ..addAll(photos.map((photo) => photo.id));
      }
    });
  }

  Future<void> _chooseDateRange() async {
    if (_selectionMode || _processingSelection) return;
    final choice = await showModalBottomSheet<_PhotoDateFilterChoice>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const _PhotoDateFilterSheet(),
    );
    if (!mounted || choice == null) return;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (choice) {
      case _PhotoDateFilterChoice.all:
        setState(() => _dateRange = null);
        return;
      case _PhotoDateFilterChoice.last7Days:
        setState(() {
          _dateRange = DateTimeRange(
            start: today.subtract(const Duration(days: 6)),
            end: today,
          );
        });
        return;
      case _PhotoDateFilterChoice.last30Days:
        setState(() {
          _dateRange = DateTimeRange(
            start: today.subtract(const Duration(days: 29)),
            end: today,
          );
        });
        return;
      case _PhotoDateFilterChoice.thisYear:
        setState(() {
          _dateRange = DateTimeRange(
            start: DateTime(today.year),
            end: today,
          );
        });
        return;
      case _PhotoDateFilterChoice.custom:
        await _chooseCustomDateRange(today);
        return;
    }
  }

  Future<void> _chooseCustomDateRange(DateTime today) async {
    final initialStart = _dateRange?.start ?? today;
    final start = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(today.year + 1, 12, 31),
      initialDate: initialStart,
      helpText: '시작 날짜',
      cancelText: '취소',
      confirmText: '다음',
    );
    if (!mounted || start == null) return;
    final initialEnd = _dateRange?.end;
    final end = await showDatePicker(
      context: context,
      firstDate: start,
      lastDate: DateTime(today.year + 1, 12, 31),
      initialDate: initialEnd != null && !initialEnd.isBefore(start)
          ? initialEnd
          : start,
      helpText: '마지막 날짜',
      cancelText: '취소',
      confirmText: '적용',
    );
    if (!mounted || end == null) return;
    setState(() => _dateRange = DateTimeRange(start: start, end: end));
  }

  void _clearDateRange() {
    if (_selectionMode || _processingSelection) return;
    setState(() => _dateRange = null);
  }

  void _setUploaderFilter(_PhotoUploaderFilter filter) {
    if (_selectionMode || _processingSelection || filter == _uploaderFilter) {
      return;
    }
    setState(() => _uploaderFilter = filter);
  }

  Future<void> _deleteSelectedPhotos() async {
    if (_processingSelection || _selectedPhotoIds.isEmpty) return;
    final count = _selectedPhotoIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('사진 $count장을 삭제할까요?'),
        content: const Text('선택한 사진은 모든 앨범에서 삭제되며 되돌릴 수 없어요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: DearColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true || _processingSelection) return;

    setState(() => _processingSelection = true);
    try {
      final deletedCount = await ref.read(deleteMemoryAlbumPhotosProvider)(
        coupleId: widget.coupleId,
        photoIds: _selectedPhotoIds,
      );
      if (!mounted) return;
      await _finishBulkAction('사진 $deletedCount장을 삭제했어요.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _processingSelection = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(toFriendlyErrorMessage(error))),
      );
    }
  }

  Future<void> _moveSelectedPhotos() async {
    if (_processingSelection || _selectedPhotoIds.isEmpty) return;
    late final List<MemoryAlbum> albums;
    try {
      albums = await ref
          .read(memoryAlbumRepositoryProvider)
          .fetchAlbums(widget.coupleId);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('앨범 목록을 불러오지 못했어요. 다시 시도해 주세요.')),
      );
      return;
    }
    if (!mounted) return;
    if (albums.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('사진을 옮길 앨범이 없어요.')),
      );
      return;
    }

    final destination = await showModalBottomSheet<MemoryAlbum>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _MovePhotosAlbumSheet(albums: albums),
    );
    if (!mounted || destination == null || _processingSelection) return;
    final count = _selectedPhotoIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${destination.name}(으)로 옮길까요?'),
        content: Text('선택한 사진 $count장의 앨범 위치가 변경돼요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('이동'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true || _processingSelection) return;

    setState(() => _processingSelection = true);
    try {
      final movedCount = await ref.read(moveMemoryAlbumPhotosProvider)(
        coupleId: widget.coupleId,
        photoIds: _selectedPhotoIds,
        destinationAlbumId: destination.id,
      );
      if (!mounted) return;
      final message = movedCount == 0
          ? '선택한 사진이 이미 ${destination.name}에 있어요.'
          : '사진 $movedCount장을 ${destination.name}(으)로 옮겼어요.';
      await _finishBulkAction(message);
    } catch (error) {
      if (!mounted) return;
      setState(() => _processingSelection = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(toFriendlyErrorMessage(error))),
      );
    }
  }

  Future<void> _finishBulkAction(String message) async {
    await Future.wait([
      ref.read(memoryAlbumPhotoFeedProvider(_feedArgs).notifier).refresh(),
      ref.read(memoryAlbumFeedProvider(widget.coupleId).notifier).refresh(),
    ]);
    ref.invalidate(recentMemoryAlbumPhotosProvider(widget.coupleId));
    if (!mounted) return;
    setState(() {
      _processingSelection = false;
      _selectionMode = false;
      _selectedPhotoIds.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

String _memoryAlbumRecentLabel(DateTime updatedAt) {
  final localUpdatedAt = updatedAt.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final updatedDate = DateTime(
    localUpdatedAt.year,
    localUpdatedAt.month,
    localUpdatedAt.day,
  );
  final days = today.difference(updatedDate).inDays;

  if (days <= 0) return '최근 추가 오늘';
  if (days < 30) return '최근 추가 $days일 전';
  return '최근 추가 ${localUpdatedAt.year}.${localUpdatedAt.month.toString().padLeft(2, '0')}.${localUpdatedAt.day.toString().padLeft(2, '0')}';
}

enum _AlbumAction { featured, edit, delete }

class _MemoryAlbumHeaderButton extends StatelessWidget {
  const _MemoryAlbumHeaderButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.iconSize = 26,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onPressed,
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: DearColors.coralSoft,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Icon(icon, color: DearColors.coral, size: iconSize),
        ),
      ),
    );
  }
}

class _AlbumLoadingSkeleton extends StatelessWidget {
  const _AlbumLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: '앨범을 불러오는 중',
      child: ExcludeSemantics(
        child: ListView(
          key: const ValueKey('album-loading-skeleton'),
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          children: const [
            _SkeletonBox(height: 286, radius: 26),
            SizedBox(height: 20),
            _SkeletonBox(height: 22, width: 112),
            SizedBox(height: 12),
            _SkeletonBox(height: 82, radius: 22),
            SizedBox(height: 10),
            _SkeletonBox(height: 82, radius: 22),
            SizedBox(height: 24),
            _RecentPhotosSkeleton(),
          ],
        ),
      ),
    );
  }
}

class _RecentPhotosSkeleton extends StatelessWidget {
  const _RecentPhotosSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 112,
      child: Row(
        children: [
          Expanded(child: _SkeletonBox(height: 112, radius: 16)),
          SizedBox(width: 10),
          Expanded(child: _SkeletonBox(height: 112, radius: 16)),
          SizedBox(width: 10),
          Expanded(child: _SkeletonBox(height: 112, radius: 16)),
        ],
      ),
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  const _SkeletonBox({
    required this.height,
    this.width,
    this.radius = 12,
  });

  final double height;
  final double? width;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: DearColors.blushDeep.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class _AlbumErrorState extends StatelessWidget {
  const _AlbumErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: message,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: DearCard(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const DearIconBubble(
                  icon: Icons.cloud_off_rounded,
                  size: 60,
                ),
                const SizedBox(height: 14),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: DearColors.ink,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  key: const ValueKey('album-error-retry'),
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('다시 시도'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Widget? _albumFeedInlineStatus({
  required String keyPrefix,
  required bool isRefreshing,
  required Object? error,
  required MemoryAlbumFeedFailureKind? failureKind,
  required String refreshingLabel,
  required String refreshErrorMessage,
  required String realtimeErrorMessage,
  required VoidCallback onRetry,
}) {
  if (isRefreshing) {
    return DearInlineLoading(
      key: ValueKey('$keyPrefix-refreshing'),
      label: refreshingLabel,
    );
  }
  if (error == null ||
      (failureKind != MemoryAlbumFeedFailureKind.refresh &&
          failureKind != MemoryAlbumFeedFailureKind.realtime)) {
    return null;
  }
  return DearInlineError(
    key: ValueKey('$keyPrefix-inline-error'),
    message: failureKind == MemoryAlbumFeedFailureKind.realtime
        ? realtimeErrorMessage
        : refreshErrorMessage,
    onRetry: onRetry,
    retryLabel: '다시 연결하기',
  );
}

class _AlbumEmptyCoverArtwork extends StatelessWidget {
  const _AlbumEmptyCoverArtwork({required this.imageKey, this.width = 220});

  final Key imageKey;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: '함께 추억을 모으는 기본 앨범 표지',
      child: ExcludeSemantics(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: SizedBox(
            width: width,
            child: AspectRatio(
              aspectRatio: 3 / 2,
              child: Image.asset(
                _albumEmptyCoverAsset,
                key: imageKey,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
                cacheWidth: 1024,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CreateAlbumDraft {
  const _CreateAlbumDraft({required this.name, this.coverImage});

  final String name;
  final PickedChatImage? coverImage;
}

class _CreateMemoryAlbumSheet extends ConsumerStatefulWidget {
  const _CreateMemoryAlbumSheet({
    this.title = '새 앨범 만들기',
    this.submitLabel = '앨범 만들기',
    this.initialName,
    this.initialCoverStoragePath,
  });

  final String title;
  final String submitLabel;
  final String? initialName;
  final String? initialCoverStoragePath;

  @override
  ConsumerState<_CreateMemoryAlbumSheet> createState() =>
      _CreateMemoryAlbumSheetState();
}

class _CreateMemoryAlbumSheetState
    extends ConsumerState<_CreateMemoryAlbumSheet> {
  late final TextEditingController _nameController;
  PickedChatImage? _coverImage;
  bool _picking = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName ?? '');
    _nameController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickCoverImage() async {
    setState(() => _picking = true);
    try {
      final picked = await ref.read(chatPickImageProvider)();
      if (!mounted || picked == null) return;

      if (!isSupportedImageExtension(picked.extension)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('jpg, png, webp 사진만 선택할 수 있어요.')),
        );
        return;
      }
      if (isImageTooLarge(picked.bytes.length)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '대표 사진이 너무 커요. 최대 ${formatImageSizeLabel(chatImageMaxBytes)}까지 가능해요.',
            ),
          ),
        );
        return;
      }

      setState(() => _coverImage = picked);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Widget _buildCoverPicker(BuildContext context) {
    if (_coverImage != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.memory(
              _coverImage!.bytes,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.medium,
            ),
            _AlbumCoverBadge(
              label: widget.initialName == null ? '대표 사진' : '새 대표 사진',
            ),
          ],
        ),
      );
    }

    if (widget.initialCoverStoragePath != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _AlbumSignedImage(storagePath: widget.initialCoverStoragePath),
            const _AlbumCoverBadge(label: '현재 대표 사진'),
          ],
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          _albumEmptyCoverAsset,
          key: const ValueKey('album-sheet-default-cover'),
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          cacheWidth: 1024,
        ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: DearColors.ink.withValues(alpha: 0.58),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              child: Text(
                _picking ? '표지 사진 선택 중' : '눌러서 표지 사진 선택',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = _nameController.text.trim();
    final canCreate = name.isNotEmpty && !_picking;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: DearColors.ink,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                    TextButton(
                      key: const ValueKey('cancel-album-sheet'),
                      onPressed: () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(
                          DearTouchTargets.minimum,
                          DearTouchTargets.minimum,
                        ),
                      ),
                      child: const Text('취소'),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _nameController,
                  autofocus: true,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: '앨범 이름',
                    hintText: '예: 우리의 봄, 부산 마라톤',
                  ),
                  onSubmitted: (_) => FocusScope.of(context).unfocus(),
                ),
                const SizedBox(height: 16),
                Text(
                  '표지 사진 (선택)',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: DearColors.ink,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  '고르지 않으면 기본 표지가 사용돼요.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: DearColors.secondary,
                      ),
                ),
                const SizedBox(height: 10),
                Semantics(
                  button: true,
                  enabled: !_picking,
                  label: _picking
                      ? '표지 사진 선택 중'
                      : _coverImage != null ||
                              widget.initialCoverStoragePath != null
                          ? '표지 사진 변경'
                          : '표지 사진 선택, 선택 사항',
                  onTap: _picking ? null : _pickCoverImage,
                  excludeSemantics: true,
                  child: InkWell(
                    key: const ValueKey('album-cover-picker'),
                    borderRadius: BorderRadius.circular(22),
                    onTap: _picking ? null : _pickCoverImage,
                    child: AspectRatio(
                      aspectRatio: 3 / 2,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: DearColors.blush,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: DearColors.line),
                        ),
                        child: _buildCoverPicker(context),
                      ),
                    ),
                  ),
                ),
                if (_coverImage != null) ...[
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      key: const ValueKey('use-default-album-cover'),
                      onPressed: () => setState(() => _coverImage = null),
                      child: Text(
                        widget.initialCoverStoragePath == null
                            ? '표지 없이 만들기'
                            : '기존 표지 사용',
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const ValueKey('submit-album-sheet'),
                    onPressed: !canCreate
                        ? null
                        : () => Navigator.of(context).pop(
                              _CreateAlbumDraft(
                                name: name,
                                coverImage: _coverImage,
                              ),
                            ),
                    child: Text(widget.submitLabel),
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

class _AlbumCoverBadge extends StatelessWidget {
  const _AlbumCoverBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 12,
      top: 12,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: DearColors.ink.withValues(alpha: 0.44),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
      ),
    );
  }
}

class _AlbumActionSheet extends StatelessWidget {
  const _AlbumActionSheet({required this.album});

  final MemoryAlbum album;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(26),
            boxShadow: dearSoftShadow(0.5),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: DearColors.line,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: SizedBox(
                        width: 56,
                        height: 56,
                        child: _AlbumSignedImage(
                          storagePath: album.coverStoragePath,
                          iconSize: 28,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            album.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  color: DearColors.ink,
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '사진 ${album.photoCount}장',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: DearColors.secondary,
                                      fontWeight: FontWeight.w600,
                                    ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ListTile(
                  enabled: !album.isFeatured,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  leading: DearIconBubble(
                    icon: Icons.favorite_rounded,
                    size: 44,
                    iconSize: 22,
                    background: album.isFeatured
                        ? DearColors.blushDeep
                        : DearColors.coralSoft,
                    color: DearColors.coral,
                  ),
                  title: Text(
                    album.isFeatured ? '이미 대표 앨범이에요' : '대표 앨범으로 설정',
                  ),
                  subtitle: const Text('홈 상단에 보이는 앨범으로 공유해요'),
                  onTap: album.isFeatured
                      ? null
                      : () => Navigator.of(context).pop(_AlbumAction.featured),
                ),
                const SizedBox(height: 4),
                ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  leading: const DearIconBubble(
                    icon: Icons.edit_rounded,
                    size: 44,
                    iconSize: 22,
                  ),
                  title: const Text('앨범 수정'),
                  subtitle: const Text('앨범명과 대표 사진을 바꿔요'),
                  onTap: () => Navigator.of(context).pop(_AlbumAction.edit),
                ),
                const SizedBox(height: 4),
                ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  leading: const DearIconBubble(
                    icon: Icons.delete_outline_rounded,
                    size: 44,
                    iconSize: 22,
                    background: Color(0xFFFFECEF),
                    color: DearColors.error,
                  ),
                  title: const Text('앨범 삭제'),
                  subtitle: const Text('앨범과 사진 기록을 삭제해요'),
                  textColor: DearColors.error,
                  iconColor: DearColors.error,
                  onTap: () => Navigator.of(context).pop(_AlbumAction.delete),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentPhotosHeader extends StatelessWidget {
  const _RecentPhotosHeader({
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
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: DearColors.ink,
                fontWeight: FontWeight.w900,
              ),
        ),
        const Spacer(),
        TextButton(
          onPressed: onAction,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            minimumSize: const Size(44, 44),
            foregroundColor: DearColors.secondary,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                actionLabel,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: DearColors.secondary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(width: 2),
              const Icon(Icons.chevron_right_rounded, size: 22),
            ],
          ),
        ),
      ],
    );
  }
}

class _RecentMemoryPhotosGrid extends StatelessWidget {
  const _RecentMemoryPhotosGrid({
    required this.photosAsync,
    required this.onRetry,
  });

  final AsyncValue<List<MemoryAlbumPhoto>> photosAsync;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return photosAsync.when(
      loading: () => const _RecentPhotosSkeleton(),
      error: (error, _) => DearCard(
        padding: const EdgeInsets.fromLTRB(18, 12, 10, 12),
        shadowOpacity: 0.25,
        child: Row(
          children: [
            Expanded(
              child: Text(
                '최근 사진을 불러오지 못했어요.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: DearColors.secondary,
                    ),
              ),
            ),
            TextButton(onPressed: onRetry, child: const Text('다시 시도')),
          ],
        ),
      ),
      data: (photos) {
        if (photos.isEmpty) {
          return DearCard(
            padding: const EdgeInsets.all(20),
            shadowOpacity: 0.25,
            child: Row(
              children: [
                const DearIconBubble(
                  icon: Icons.photo_rounded,
                  size: 52,
                  iconSize: 26,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    '아직 최근 추억 사진이 없어요.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: DearColors.secondary,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ],
            ),
          );
        }

        final recentPhotos = photos.take(10).toList(growable: false);
        return SizedBox(
          height: 112,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: recentPhotos.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final photo = recentPhotos[index];
              return SizedBox.square(
                dimension: 112,
                child: _MemoryAlbumPhotoTile(
                  storagePath: photo.storagePath,
                  heroTag: 'recent-memory-album-${photo.id}',
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _AlbumSignedImage extends StatefulWidget {
  const _AlbumSignedImage({
    required this.storagePath,
    this.iconSize = 38,
    this.fit = BoxFit.cover,
  });

  final String? storagePath;
  final double iconSize;
  final BoxFit fit;

  @override
  State<_AlbumSignedImage> createState() => _AlbumSignedImageState();
}

class _AlbumSignedImageState extends State<_AlbumSignedImage> {
  static final Map<String, _CachedAlbumSignedImageUrl> _signedUrlCache =
      <String, _CachedAlbumSignedImageUrl>{};
  static final Map<String, Future<String>> _inflightSignedUrlRequests =
      <String, Future<String>>{};
  static const Duration _signedUrlRefreshInterval = Duration(minutes: 55);

  Future<String>? _signedUrlFuture;
  int _retryGeneration = 0;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant _AlbumSignedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.storagePath != widget.storagePath) _resolve();
  }

  void _resolve() {
    final storagePath = widget.storagePath;
    _signedUrlFuture =
        storagePath == null ? null : _resolveSignedUrl(storagePath);
  }

  void _retry() {
    final storagePath = widget.storagePath;
    if (storagePath == null) return;
    _signedUrlCache.remove(storagePath);
    _inflightSignedUrlRequests.remove(storagePath);
    setState(() {
      _retryGeneration++;
      _signedUrlFuture = _resolveSignedUrl(storagePath);
    });
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
      _signedUrlCache[storagePath] = _CachedAlbumSignedImageUrl(
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
    final future = _signedUrlFuture;
    if (future == null) {
      return Image.asset(
        _albumEmptyCoverAsset,
        key: const ValueKey('default-album-cover'),
        fit: widget.fit,
        filterQuality: FilterQuality.medium,
        cacheWidth: 1024,
        semanticLabel: '기본 앨범 표지',
      );
    }

    return FutureBuilder<String>(
      future: future,
      builder: (context, snapshot) {
        final storagePath = widget.storagePath!;
        if (snapshot.hasError) {
          return _AlbumImageFailure(
            key: ValueKey('retry-album-cover-$storagePath'),
            retryLabel: '앨범 표지 다시 불러오기',
            onRetry: _retry,
          );
        }
        final imageUrl = snapshot.data;
        if (imageUrl == null) {
          return Stack(
            fit: StackFit.expand,
            children: [
              Opacity(
                opacity: 0.48,
                child: Image.asset(
                  _albumEmptyCoverAsset,
                  fit: widget.fit,
                  filterQuality: FilterQuality.low,
                  cacheWidth: 1024,
                ),
              ),
              Center(
                child: SizedBox.square(
                  dimension: widget.iconSize.clamp(20, 28),
                  child: const CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ],
          );
        }

        return Image.network(
          imageUrl,
          key: ValueKey('album-cover-network-$_retryGeneration'),
          fit: widget.fit,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
          errorBuilder: (context, error, stackTrace) {
            return _AlbumImageFailure(
              key: ValueKey('retry-album-cover-network-$storagePath'),
              retryLabel: '앨범 표지 다시 불러오기',
              onRetry: _retry,
            );
          },
        );
      },
    );
  }
}

class _AlbumImageFailure extends StatelessWidget {
  const _AlbumImageFailure({
    required this.retryLabel,
    required this.onRetry,
    this.retryAlignment = Alignment.center,
    super.key,
  });

  final String retryLabel;
  final VoidCallback onRetry;
  final Alignment retryAlignment;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      liveRegion: true,
      label: '이미지를 불러오지 못했어요',
      child: Stack(
        fit: StackFit.expand,
        children: [
          Opacity(
            opacity: 0.4,
            child: Image.asset(
              _albumEmptyCoverAsset,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.low,
              cacheWidth: 1024,
            ),
          ),
          Align(
            alignment: retryAlignment,
            child: Material(
              color: Colors.transparent,
              child: DearIconButton(
                tooltip: retryLabel,
                semanticLabel: retryLabel,
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                color: DearColors.coralText,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.9),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AlbumListView extends ConsumerWidget {
  const _AlbumListView({
    required this.coupleId,
    required this.onCreateAlbum,
    required this.onOpenAlbum,
    required this.onAlbumActions,
    required this.onViewAllPhotos,
  });

  final String coupleId;
  final VoidCallback onCreateAlbum;
  final ValueChanged<MemoryAlbum> onOpenAlbum;
  final ValueChanged<MemoryAlbum> onAlbumActions;
  final VoidCallback onViewAllPhotos;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albumFeed = ref.watch(memoryAlbumFeedProvider(coupleId));
    final recentPhotosAsync =
        ref.watch(recentMemoryAlbumPhotosProvider(coupleId));
    final controller = ref.read(memoryAlbumFeedProvider(coupleId).notifier);
    final inlineStatus = _albumFeedInlineStatus(
      keyPrefix: 'album-feed',
      isRefreshing: albumFeed.isRefreshing,
      error: albumFeed.error,
      failureKind: albumFeed.failureKind,
      refreshingLabel: '앨범을 다시 불러오는 중',
      refreshErrorMessage: '앨범을 새로 불러오지 못했어요. 기존 앨범은 그대로 보여드려요.',
      realtimeErrorMessage: '새 앨범 소식을 연결하지 못했어요. 현재 앨범은 그대로 볼 수 있어요.',
      onRetry: () => controller.retry(),
    );

    if (!albumFeed.hasLoadedOnce && albumFeed.isLoadingInitial) {
      return const _AlbumLoadingSkeleton();
    }
    if (!albumFeed.hasLoadedOnce && albumFeed.error != null) {
      return _AlbumErrorState(
        message: '앨범을 불러오지 못했어요.',
        onRetry: () => controller.retry(),
      );
    }
    final albums = albumFeed.items;
    if (albums.isEmpty) {
      return ListView(
        key: const ValueKey('album-empty-state'),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 116),
        children: [
          if (inlineStatus != null) ...[
            inlineStatus,
            const SizedBox(height: 16),
          ],
          DearCard(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const _AlbumEmptyCoverArtwork(
                  imageKey: ValueKey('album-empty-cover-artwork'),
                ),
                const SizedBox(height: 14),
                Text(
                  '첫 앨범을 만들어보세요',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: DearColors.ink,
                        fontWeight: FontWeight.w900,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  '둘만의 사진을 모아 한 장씩 쌓아갈 수 있어요.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: DearColors.muted,
                      ),
                ),
                const SizedBox(height: 18),
                DearGradientButton(
                  onPressed: onCreateAlbum,
                  icon: Icons.add_photo_alternate_rounded,
                  label: '첫 앨범 만들기',
                ),
              ],
            ),
          ),
        ],
      );
    }

    final coverAlbum = albums.firstWhere(
      (album) => album.isFeatured,
      orElse: () => albums.firstWhere(
        (album) => album.coverStoragePath != null,
        orElse: () => albums.first,
      ),
    );
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.extentAfter < 320 &&
            albumFeed.hasMore &&
            !albumFeed.isRefreshing &&
            albumFeed.failureKind != MemoryAlbumFeedFailureKind.loadMore) {
          unawaited(
            controller.loadMore(),
          );
        }
        return false;
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 116),
        children: [
          if (inlineStatus != null) ...[
            inlineStatus,
            const SizedBox(height: 16),
          ],
          _AlbumCoverCard(
            album: coverAlbum,
            large: true,
            onTap: () => onOpenAlbum(coverAlbum),
            onActions: () => onAlbumActions(coverAlbum),
          ),
          const SizedBox(height: 24),
          _RecentPhotosHeader(
            title: '최근 추억',
            actionLabel: '전체 보기',
            onAction: onViewAllPhotos,
          ),
          const SizedBox(height: 12),
          _RecentMemoryPhotosGrid(
            photosAsync: recentPhotosAsync,
            onRetry: () =>
                ref.invalidate(recentMemoryAlbumPhotosProvider(coupleId)),
          ),
          const SizedBox(height: 28),
          _AllAlbumsSection(
            albums: albums,
            onOpenAlbum: onOpenAlbum,
            onAlbumActions: onAlbumActions,
          ),
          if (albumFeed.isLoadingMore) ...[
            const SizedBox(height: 18),
            const DearInlineLoading(label: '앨범을 더 불러오는 중'),
          ] else if (albumFeed.error != null &&
              albumFeed.failureKind == MemoryAlbumFeedFailureKind.loadMore) ...[
            const SizedBox(height: 12),
            Center(
              child: OutlinedButton.icon(
                key: const ValueKey('retry-album-page'),
                onPressed: () => controller.retry(),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('앨범 더 불러오기 다시 시도'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AlbumCoverCard extends StatelessWidget {
  const _AlbumCoverCard({
    required this.album,
    required this.onTap,
    required this.onActions,
    this.large = false,
  });

  final MemoryAlbum album;
  final VoidCallback onTap;
  final VoidCallback onActions;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.6;
    final subtitle =
        '사진 ${album.photoCount}장  •  ${_memoryAlbumRecentLabel(album.updatedAt)}';

    return DearCard(
      key: ValueKey('album-cover-card-${album.id}'),
      padding: EdgeInsets.zero,
      radius: large ? DearRadii.large : DearRadii.medium,
      shadowOpacity: large ? 0.55 : 0.35,
      child: Material(
        color: Colors.transparent,
        borderRadius:
            BorderRadius.circular(large ? DearRadii.large : DearRadii.medium),
        child: InkWell(
          borderRadius:
              BorderRadius.circular(large ? DearRadii.large : DearRadii.medium),
          onTap: onTap,
          onLongPress: onActions,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: large ? 210 : 94,
                decoration: BoxDecoration(
                  color: DearColors.blush,
                  border: const Border(
                    bottom: BorderSide(color: DearColors.line),
                  ),
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(
                        large ? DearRadii.large : DearRadii.medium),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(
                      large ? DearRadii.large : DearRadii.medium,
                    ),
                  ),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: _AlbumSignedImage(
                          storagePath: album.coverStoragePath,
                          iconSize: large ? 52 : 38,
                          fit: BoxFit.cover,
                        ),
                      ),
                      if (large)
                        Positioned(
                          right: 16,
                          top: 14,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: DearColors.ink.withValues(alpha: 0.42),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.18),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.favorite_rounded,
                                  size: 16,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '대표 앨범',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelLarge
                                      ?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(large ? 20 : 12),
                child: largeText
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            album.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: (large
                                    ? Theme.of(context).textTheme.titleLarge
                                    : Theme.of(context).textTheme.titleMedium)
                                ?.copyWith(
                              color: DearColors.ink,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: DearColors.secondary,
                                    ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              IconButton(
                                key: ValueKey(
                                  'album-card-menu-${album.id}',
                                ),
                                tooltip: '앨범 메뉴',
                                onPressed: onActions,
                                icon: const Icon(Icons.more_vert_rounded),
                                color: DearColors.secondary,
                              ),
                              Container(
                                width: 56,
                                height: 56,
                                decoration: const BoxDecoration(
                                  color: DearColors.blushDeep,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.chevron_right_rounded,
                                  color: DearColors.coral,
                                ),
                              ),
                            ],
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  album.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: (large
                                          ? Theme.of(context)
                                              .textTheme
                                              .titleLarge
                                          : Theme.of(context)
                                              .textTheme
                                              .titleMedium)
                                      ?.copyWith(
                                    color: DearColors.ink,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: DearColors.secondary,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            key: ValueKey('album-card-menu-${album.id}'),
                            tooltip: '앨범 메뉴',
                            onPressed: onActions,
                            icon: const Icon(Icons.more_vert_rounded),
                            color: DearColors.secondary,
                          ),
                          Container(
                            width: large ? 56 : 38,
                            height: large ? 56 : 38,
                            decoration: const BoxDecoration(
                              color: DearColors.blushDeep,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.chevron_right_rounded,
                              color: DearColors.coral,
                            ),
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

class _AllAlbumsSection extends StatelessWidget {
  const _AllAlbumsSection({
    required this.albums,
    required this.onOpenAlbum,
    required this.onAlbumActions,
  });

  final List<MemoryAlbum> albums;
  final ValueChanged<MemoryAlbum> onOpenAlbum;
  final ValueChanged<MemoryAlbum> onAlbumActions;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '전체 앨범',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: DearColors.ink,
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: DearColors.coralSoft,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${albums.length}',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: DearColors.coralText,
                      fontWeight: FontWeight.w900,
                    ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (final album in albums) ...[
          _AlbumListRow(
            album: album,
            onTap: () => onOpenAlbum(album),
            onActions: () => onAlbumActions(album),
          ),
          if (album != albums.last) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _AlbumListRow extends StatelessWidget {
  const _AlbumListRow({
    required this.album,
    required this.onTap,
    required this.onActions,
  });

  final MemoryAlbum album;
  final VoidCallback onTap;
  final VoidCallback onActions;

  @override
  Widget build(BuildContext context) {
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.6;
    return Container(
      constraints: const BoxConstraints(minHeight: 82),
      decoration: BoxDecoration(
        color: DearColors.card.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: DearColors.line),
        boxShadow: dearSoftShadow(0.22),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          onLongPress: onActions,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    width: 62,
                    height: 62,
                    child: _AlbumSignedImage(
                      storagePath: album.coverStoragePath,
                      iconSize: 28,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              album.name,
                              maxLines: largeText ? 2 : 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                    color: DearColors.ink,
                                    fontWeight: FontWeight.w900,
                                  ),
                            ),
                          ),
                          if (album.isFeatured && !largeText) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: DearColors.coralSoft,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '대표',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      color: DearColors.coralText,
                                      fontWeight: FontWeight.w900,
                                    ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '사진 ${album.photoCount}장  •  ${_memoryAlbumRecentLabel(album.updatedAt)}',
                        maxLines: largeText ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: DearColors.secondary,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      if (album.isFeatured && largeText) ...[
                        const SizedBox(height: 5),
                        Text(
                          '대표 앨범',
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: DearColors.coralText,
                                    fontWeight: FontWeight.w900,
                                  ),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  key: ValueKey('album-row-menu-${album.id}'),
                  tooltip: '앨범 메뉴',
                  onPressed: onActions,
                  icon: const Icon(Icons.more_vert_rounded),
                  color: DearColors.secondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AlbumDetailView extends ConsumerWidget {
  const _AlbumDetailView({
    required this.coupleId,
    required this.album,
    required this.uploading,
    required this.uploadedCount,
    required this.uploadTotal,
    required this.onUploadPhoto,
    required this.onSetCoverPhoto,
  });

  final String coupleId;
  final MemoryAlbum album;
  final bool uploading;
  final int uploadedCount;
  final int uploadTotal;
  final VoidCallback onUploadPhoto;
  final ValueChanged<MemoryAlbumPhoto> onSetCoverPhoto;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final args = MemoryAlbumPhotoFeedArgs(
      coupleId: coupleId,
      albumId: album.id,
    );
    final feed = ref.watch(memoryAlbumPhotoFeedProvider(args));
    final controller = ref.read(memoryAlbumPhotoFeedProvider(args).notifier);
    final inlineStatus = _albumFeedInlineStatus(
      keyPrefix: 'album-photo-feed',
      isRefreshing: feed.isRefreshing,
      error: feed.error,
      failureKind: feed.failureKind,
      refreshingLabel: '앨범 사진을 다시 불러오는 중',
      refreshErrorMessage: '사진을 새로 불러오지 못했어요. 기존 사진은 그대로 보여드려요.',
      realtimeErrorMessage: '새 사진 소식을 연결하지 못했어요. 현재 사진은 그대로 볼 수 있어요.',
      onRetry: () => controller.retry(),
    );

    if (!feed.hasLoadedOnce && feed.isLoadingInitial) {
      return const _PhotoGridSkeleton();
    }
    if (!feed.hasLoadedOnce && feed.error != null) {
      return _AlbumErrorState(
        message: '사진을 불러오지 못했어요.',
        onRetry: () => controller.retry(),
      );
    }
    if (feed.items.isEmpty) {
      return Column(
        children: [
          if (inlineStatus != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: inlineStatus,
            ),
          Expanded(
            child: _AlbumEmptyPhotoState(
              albumName: album.name,
              uploading: uploading,
              uploadedCount: uploadedCount,
              uploadTotal: uploadTotal,
              onUploadPhoto: onUploadPhoto,
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        if (uploading)
          _AlbumUploadStatus(
            uploadedCount: uploadedCount,
            uploadTotal: uploadTotal,
          ),
        if (inlineStatus != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: inlineStatus,
          ),
        Expanded(
          child: _PaginatedMemoryPhotoGrid(
            photos: feed.items,
            heroPrefix: 'memory-album',
            coverPhotoId: album.coverPhotoId,
            isLoadingMore: feed.isLoadingMore,
            loadMoreError:
                feed.failureKind == MemoryAlbumFeedFailureKind.loadMore
                    ? feed.error
                    : null,
            onLoadMore: () =>
                feed.failureKind == MemoryAlbumFeedFailureKind.loadMore
                    ? controller.retry()
                    : controller.loadMore(),
            onSetCoverPhoto: onSetCoverPhoto,
          ),
        ),
      ],
    );
  }
}

class _AllMemoryPhotosView extends ConsumerWidget {
  const _AllMemoryPhotosView({
    required this.args,
    required this.hasActiveFilters,
    required this.selectionMode,
    required this.selectedPhotoIds,
    required this.onToggleSelection,
    required this.onBeginSelection,
  });

  final MemoryAlbumPhotoFeedArgs args;
  final bool hasActiveFilters;
  final bool selectionMode;
  final Set<String> selectedPhotoIds;
  final ValueChanged<MemoryAlbumPhoto> onToggleSelection;
  final ValueChanged<MemoryAlbumPhoto> onBeginSelection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(memoryAlbumPhotoFeedProvider(args));
    final controller = ref.read(memoryAlbumPhotoFeedProvider(args).notifier);
    final inlineStatus = _albumFeedInlineStatus(
      keyPrefix: 'all-photo-feed',
      isRefreshing: feed.isRefreshing,
      error: feed.error,
      failureKind: feed.failureKind,
      refreshingLabel: '전체 사진을 다시 불러오는 중',
      refreshErrorMessage: '전체 사진을 새로 불러오지 못했어요. 기존 사진은 그대로 보여드려요.',
      realtimeErrorMessage: '새 사진 소식을 연결하지 못했어요. 현재 사진은 그대로 볼 수 있어요.',
      onRetry: () => controller.retry(),
    );

    if (!feed.hasLoadedOnce && feed.isLoadingInitial) {
      return const _PhotoGridSkeleton();
    }
    if (!feed.hasLoadedOnce && feed.error != null) {
      return _AlbumErrorState(
        message: '전체 사진을 불러오지 못했어요.',
        onRetry: () => controller.retry(),
      );
    }
    if (feed.items.isEmpty) {
      return Column(
        children: [
          if (inlineStatus != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: inlineStatus,
            ),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: DearCard(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const _AlbumEmptyCoverArtwork(
                        imageKey: ValueKey('all-photo-empty-cover-artwork'),
                        width: 180,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        hasActiveFilters
                            ? '조건에 맞는 사진이 없어요.'
                            : '아직 모아볼 사진이 없어요.',
                        key: const ValueKey('all-photo-empty-message'),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: DearColors.ink,
                              fontWeight: FontWeight.w800,
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

    return Column(
      children: [
        if (inlineStatus != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: inlineStatus,
          ),
        Expanded(
          child: _PaginatedMemoryPhotoGrid(
            photos: feed.items,
            heroPrefix: 'all-memory-album',
            isLoadingMore: feed.isLoadingMore,
            loadMoreError:
                feed.failureKind == MemoryAlbumFeedFailureKind.loadMore
                    ? feed.error
                    : null,
            selectionMode: selectionMode,
            selectedPhotoIds: selectedPhotoIds,
            onToggleSelection: onToggleSelection,
            onBeginSelection: onBeginSelection,
            onLoadMore: () =>
                feed.failureKind == MemoryAlbumFeedFailureKind.loadMore
                    ? controller.retry()
                    : controller.loadMore(),
          ),
        ),
      ],
    );
  }
}

class _AllPhotoFilterBar extends StatelessWidget {
  const _AllPhotoFilterBar({
    required this.dateRange,
    required this.uploaderFilter,
    required this.enabled,
    required this.onChooseDate,
    required this.onClearDate,
    required this.onUploaderChanged,
  });

  final DateTimeRange? dateRange;
  final _PhotoUploaderFilter uploaderFilter;
  final bool enabled;
  final VoidCallback onChooseDate;
  final VoidCallback? onClearDate;
  final ValueChanged<_PhotoUploaderFilter> onUploaderChanged;

  String get _dateLabel {
    final range = dateRange;
    if (range == null) return '전체 날짜';
    String format(DateTime date) =>
        '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}';
    if (DateUtils.isSameDay(range.start, range.end)) return format(range.start);
    return '${format(range.start)}–${format(range.end)}';
  }

  String get _uploaderLabel => switch (uploaderFilter) {
        _PhotoUploaderFilter.all => '모든 업로더',
        _PhotoUploaderFilter.mine => '내가 올린 사진',
        _PhotoUploaderFilter.partner => '상대가 올린 사진',
      };

  @override
  Widget build(BuildContext context) {
    return Material(
      color: DearColors.card.withValues(alpha: 0.96),
      child: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          key: const ValueKey('all-photo-filter-scroll'),
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              InputChip(
                key: const ValueKey('all-photo-date-filter'),
                avatar: const Icon(Icons.calendar_month_rounded, size: 18),
                label: Text(_dateLabel),
                tooltip: '사진 날짜 필터',
                onPressed: enabled ? onChooseDate : null,
                onDeleted: enabled ? onClearDate : null,
              ),
              const SizedBox(width: 8),
              PopupMenuButton<_PhotoUploaderFilter>(
                key: const ValueKey('all-photo-uploader-filter'),
                enabled: enabled,
                initialValue: uploaderFilter,
                tooltip: '사진 업로더 필터',
                onSelected: onUploaderChanged,
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: _PhotoUploaderFilter.all,
                    child: Text('모든 업로더'),
                  ),
                  PopupMenuItem(
                    value: _PhotoUploaderFilter.mine,
                    child: Text('내가 올린 사진'),
                  ),
                  PopupMenuItem(
                    value: _PhotoUploaderFilter.partner,
                    child: Text('상대가 올린 사진'),
                  ),
                ],
                child: Chip(
                  avatar: const Icon(Icons.person_outline_rounded, size: 18),
                  label: Text(_uploaderLabel),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoDateFilterSheet extends StatelessWidget {
  const _PhotoDateFilterSheet();

  @override
  Widget build(BuildContext context) {
    Widget item({
      required String label,
      required IconData icon,
      required _PhotoDateFilterChoice value,
    }) {
      return ListTile(
        leading: DearIconBubble(icon: icon, size: 44, iconSize: 22),
        title: Text(
          label,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: DearColors.ink,
                fontWeight: FontWeight.w800,
              ),
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => Navigator.of(context).pop(value),
      );
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: DearColors.card,
            borderRadius: BorderRadius.circular(24),
            boxShadow: dearSoftShadow(0.45),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '사진 날짜 필터',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: DearColors.ink,
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  ),
                ),
                item(
                  label: '모든 날짜',
                  icon: Icons.all_inclusive_rounded,
                  value: _PhotoDateFilterChoice.all,
                ),
                item(
                  label: '최근 7일',
                  icon: Icons.today_rounded,
                  value: _PhotoDateFilterChoice.last7Days,
                ),
                item(
                  label: '최근 30일',
                  icon: Icons.date_range_rounded,
                  value: _PhotoDateFilterChoice.last30Days,
                ),
                item(
                  label: '올해',
                  icon: Icons.calendar_month_rounded,
                  value: _PhotoDateFilterChoice.thisYear,
                ),
                item(
                  label: '직접 날짜 선택',
                  icon: Icons.edit_calendar_rounded,
                  value: _PhotoDateFilterChoice.custom,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PhotoSelectionActionBar extends StatelessWidget {
  const _PhotoSelectionActionBar({
    required this.selectedCount,
    required this.processing,
    required this.onMove,
    required this.onDelete,
  });

  final int selectedCount;
  final bool processing;
  final VoidCallback? onMove;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: processing ? '선택한 사진 처리 중' : '사진 $selectedCount장 선택됨',
      child: Material(
        elevation: 12,
        color: DearColors.card,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const ValueKey('move-selected-memory-photos'),
                    onPressed: processing ? null : onMove,
                    icon: const Icon(Icons.drive_file_move_rounded),
                    label: const Text('이동'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    key: const ValueKey('delete-selected-memory-photos'),
                    style: FilledButton.styleFrom(
                      backgroundColor: DearColors.error,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: processing ? null : onDelete,
                    icon: processing
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.delete_outline_rounded),
                    label: Text(processing ? '처리 중' : '삭제'),
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

class _MovePhotosAlbumSheet extends StatelessWidget {
  const _MovePhotosAlbumSheet({required this.albums});

  final List<MemoryAlbum> albums;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: DearColors.card,
            borderRadius: BorderRadius.circular(24),
            boxShadow: dearSoftShadow(0.45),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '이동할 앨범 선택',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: DearColors.ink,
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  ),
                ),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: 10),
                    itemCount: albums.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, color: DearColors.line),
                    itemBuilder: (context, index) {
                      final album = albums[index];
                      return ListTile(
                        key: ValueKey('move-destination-${album.id}'),
                        leading: const DearIconBubble(
                          icon: Icons.photo_album_outlined,
                          size: 44,
                          iconSize: 22,
                        ),
                        title: Text(album.name),
                        subtitle: Text('사진 ${album.photoCount}장'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.of(context).pop(album),
                      );
                    },
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

class _AlbumEmptyPhotoState extends StatelessWidget {
  const _AlbumEmptyPhotoState({
    required this.albumName,
    required this.uploading,
    required this.uploadedCount,
    required this.uploadTotal,
    required this.onUploadPhoto,
  });

  final String albumName;
  final bool uploading;
  final int uploadedCount;
  final int uploadTotal;
  final VoidCallback onUploadPhoto;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: DearCard(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _AlbumEmptyCoverArtwork(
                imageKey: ValueKey('album-photo-empty-cover-artwork'),
                width: 190,
              ),
              const SizedBox(height: 14),
              Text(
                '$albumName에 사진을 더해요',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: DearColors.ink,
                      fontWeight: FontWeight.w900,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                '좋았던 장면을 여러 장 올려 앨범을 채워보세요.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: DearColors.muted,
                    ),
              ),
              const SizedBox(height: 18),
              if (uploading) ...[
                _AlbumUploadStatus(
                  uploadedCount: uploadedCount,
                  uploadTotal: uploadTotal,
                ),
              ] else
                DearGradientButton(
                  onPressed: onUploadPhoto,
                  icon: Icons.add_photo_alternate_rounded,
                  label: '사진 올리기',
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AlbumUploadStatus extends StatelessWidget {
  const _AlbumUploadStatus({
    required this.uploadedCount,
    required this.uploadTotal,
  });

  final int uploadedCount;
  final int uploadTotal;

  @override
  Widget build(BuildContext context) {
    final progress = uploadTotal == 0 ? null : uploadedCount / uploadTotal;
    return Container(
      key: const ValueKey('album-upload-status'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      color: DearColors.card.withValues(alpha: 0.96),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '사진 업로드 중 $uploadedCount/$uploadTotal',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: DearColors.ink,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            borderRadius: BorderRadius.circular(999),
          ),
        ],
      ),
    );
  }
}

class _PaginatedMemoryPhotoGrid extends StatelessWidget {
  const _PaginatedMemoryPhotoGrid({
    required this.photos,
    required this.heroPrefix,
    required this.isLoadingMore,
    required this.onLoadMore,
    this.loadMoreError,
    this.coverPhotoId,
    this.onSetCoverPhoto,
    this.selectionMode = false,
    this.selectedPhotoIds = const <String>{},
    this.onToggleSelection,
    this.onBeginSelection,
  });

  final List<MemoryAlbumPhoto> photos;
  final String heroPrefix;
  final bool isLoadingMore;
  final VoidCallback onLoadMore;
  final Object? loadMoreError;
  final String? coverPhotoId;
  final ValueChanged<MemoryAlbumPhoto>? onSetCoverPhoto;
  final bool selectionMode;
  final Set<String> selectedPhotoIds;
  final ValueChanged<MemoryAlbumPhoto>? onToggleSelection;
  final ValueChanged<MemoryAlbumPhoto>? onBeginSelection;

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (loadMoreError == null && notification.metrics.extentAfter < 360) {
          onLoadMore();
        }
        return false;
      },
      child: GridView.builder(
        key: const ValueKey('memory-album-photo-grid'),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        itemCount:
            photos.length + (isLoadingMore || loadMoreError != null ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == photos.length) {
            if (isLoadingMore) {
              return Semantics(
                container: true,
                liveRegion: true,
                label: '사진을 더 불러오는 중',
                child: const ExcludeSemantics(
                  child: Center(
                    child: SizedBox.square(
                      dimension: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
              );
            }
            return Semantics(
              container: true,
              liveRegion: true,
              label: '사진을 더 불러오지 못했어요',
              child: Center(
                child: DearIconButton(
                  key: const ValueKey('album-load-more-retry'),
                  tooltip: '사진 더 불러오기 다시 시도',
                  onPressed: onLoadMore,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ),
            );
          }
          final photo = photos[index];
          return _MemoryAlbumPhotoTile(
            storagePath: photo.storagePath,
            heroTag: '$heroPrefix-${photo.id}',
            isCover: photo.id == coverPhotoId,
            selectionMode: selectionMode,
            selected: selectedPhotoIds.contains(photo.id),
            semanticsLabel: '추억 사진 ${index + 1}',
            onToggleSelection: onToggleSelection == null
                ? null
                : () => onToggleSelection!(photo),
            onBeginSelection: onBeginSelection == null
                ? null
                : () => onBeginSelection!(photo),
            onSetAsCover:
                onSetCoverPhoto == null ? null : () => onSetCoverPhoto!(photo),
          );
        },
      ),
    );
  }
}

class _PhotoGridSkeleton extends StatelessWidget {
  const _PhotoGridSkeleton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: '앨범 사진을 불러오는 중',
      child: ExcludeSemantics(
        child: GridView.builder(
          key: const ValueKey('album-photo-loading-skeleton'),
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: 12,
          itemBuilder: (_, __) => const _SkeletonBox(height: 100, radius: 16),
        ),
      ),
    );
  }
}

class _MemoryAlbumPhotoTile extends ConsumerStatefulWidget {
  const _MemoryAlbumPhotoTile({
    required this.storagePath,
    required this.heroTag,
    this.isCover = false,
    this.onSetAsCover,
    this.selectionMode = false,
    this.selected = false,
    this.semanticsLabel = '추억 사진',
    this.onToggleSelection,
    this.onBeginSelection,
  });

  final String storagePath;
  final String heroTag;
  final bool isCover;
  final VoidCallback? onSetAsCover;
  final bool selectionMode;
  final bool selected;
  final String semanticsLabel;
  final VoidCallback? onToggleSelection;
  final VoidCallback? onBeginSelection;

  @override
  ConsumerState<_MemoryAlbumPhotoTile> createState() =>
      _MemoryAlbumPhotoTileState();
}

class _MemoryAlbumPhotoTileState extends ConsumerState<_MemoryAlbumPhotoTile> {
  static final Map<String, _CachedAlbumSignedImageUrl> _signedUrlCache =
      <String, _CachedAlbumSignedImageUrl>{};
  static final Map<String, Future<String>> _inflightSignedUrlRequests =
      <String, Future<String>>{};
  static const Duration _signedUrlRefreshInterval = Duration(minutes: 55);

  late Future<String> _signedUrlFuture;
  int _retryGeneration = 0;

  @override
  void initState() {
    super.initState();
    _signedUrlFuture = _resolveSignedUrl(widget.storagePath);
  }

  @override
  void didUpdateWidget(covariant _MemoryAlbumPhotoTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.storagePath != widget.storagePath) {
      _retryGeneration = 0;
      _signedUrlFuture = _resolveSignedUrl(widget.storagePath);
    }
  }

  void _retryImage() {
    final storagePath = widget.storagePath;
    _signedUrlCache.remove(storagePath);
    _inflightSignedUrlRequests.remove(storagePath);
    setState(() {
      _retryGeneration++;
      _signedUrlFuture = _resolveSignedUrl(storagePath);
    });
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

    final request = ref
        .read(createMemoryAlbumPhotoUrlsProvider)([storagePath])
        .then((urls) {
      if (urls.isEmpty) throw StateError('SIGNED_URL_NOT_FOUND');
      final url = urls.first;
      _signedUrlCache[storagePath] = _CachedAlbumSignedImageUrl(
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

  void _showPhotoActions() {
    if (widget.onSetAsCover == null) return;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: dearSoftShadow(0.45),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      leading: const DearIconBubble(
                        icon: Icons.favorite_rounded,
                        size: 44,
                        iconSize: 22,
                      ),
                      title: Text(
                        widget.isCover ? '이미 대표 사진이에요' : '대표 사진으로 설정',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: DearColors.ink,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      subtitle: Text(
                        '앨범 목록의 큰 사진으로 보여져요',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: DearColors.secondary,
                            ),
                      ),
                      enabled: !widget.isCover,
                      onTap: widget.isCover
                          ? null
                          : () {
                              Navigator.of(context).pop();
                              widget.onSetAsCover?.call();
                            },
                    ),
                    const Divider(height: 1, color: DearColors.line),
                    ListTile(
                      leading: const Icon(
                        Icons.close_rounded,
                        color: DearColors.secondary,
                      ),
                      title: Text(
                        '닫기',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: DearColors.secondary,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _signedUrlFuture,
      builder: (context, snapshot) {
        final imageUrl = snapshot.data;
        final VoidCallback? onTap = widget.selectionMode
            ? widget.onToggleSelection
            : imageUrl == null
                ? null
                : () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ChatImageViewPage(
                          imageUrl: imageUrl,
                          heroTag: widget.heroTag,
                        ),
                      ),
                    );
                  };
        final VoidCallback? onLongPress = widget.selectionMode
            ? widget.onToggleSelection
            : widget.onBeginSelection ??
                (widget.onSetAsCover == null ? null : _showPhotoActions);
        return Semantics(
          key: ValueKey('memory-photo-semantics-${widget.storagePath}'),
          container: true,
          explicitChildNodes: true,
          button: true,
          enabled: onTap != null,
          selected: widget.selectionMode ? widget.selected : null,
          label: widget.selectionMode
              ? '${widget.semanticsLabel}, ${widget.selected ? '선택됨' : '선택 안 됨'}'
              : widget.semanticsLabel,
          hint: widget.selectionMode
              ? (widget.selected ? '선택됨, 선택 해제' : '선택')
              : '사진 크게 보기',
          onTap: onTap,
          onLongPress: onLongPress,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: DearTouchTargets.minimum,
              minHeight: DearTouchTargets.minimum,
            ),
            child: GestureDetector(
              key: ValueKey('memory-photo-${widget.storagePath}'),
              onTap: onTap,
              onLongPress: onLongPress,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Hero(
                  tag: widget.heroTag,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: DearColors.blush,
                          border: Border.all(color: DearColors.line),
                        ),
                        child: Center(
                          child: Icon(
                            Icons.image_rounded,
                            color: DearColors.coral.withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                      if (snapshot.hasError)
                        Positioned.fill(
                          child: _AlbumImageFailure(
                            key: ValueKey(
                              'retry-memory-photo-${widget.storagePath}',
                            ),
                            retryLabel: '사진 다시 불러오기',
                            onRetry: _retryImage,
                            retryAlignment: Alignment.topLeft,
                          ),
                        ),
                      if (imageUrl != null)
                        Image.network(
                          imageUrl,
                          key: ValueKey(
                            'memory-photo-network-$_retryGeneration',
                          ),
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                          filterQuality: FilterQuality.medium,
                          loadingBuilder: (context, child, loadingProgress) =>
                              child,
                          errorBuilder: (context, error, stackTrace) {
                            return _AlbumImageFailure(
                              key: ValueKey(
                                'retry-memory-photo-network-${widget.storagePath}',
                              ),
                              retryLabel: '사진 다시 불러오기',
                              onRetry: _retryImage,
                              retryAlignment: Alignment.topLeft,
                            );
                          },
                        ),
                      if (widget.isCover)
                        Positioned(
                          right: 7,
                          top: 7,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: DearColors.ink.withValues(alpha: 0.48),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 5,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.favorite_rounded,
                                    color: Colors.white,
                                    size: 12,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    '대표',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w800,
                                          height: 1,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      if (widget.selectionMode)
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: widget.selected
                                  ? DearColors.coral.withValues(alpha: 0.24)
                                  : Colors.transparent,
                              border: Border.all(
                                color: widget.selected
                                    ? DearColors.coral
                                    : Colors.white.withValues(alpha: 0.72),
                                width: widget.selected ? 3 : 1,
                              ),
                            ),
                          ),
                        ),
                      if (widget.selectionMode)
                        Positioned(
                          right: 7,
                          top: 7,
                          child: Icon(
                            widget.selected
                                ? Icons.check_circle_rounded
                                : Icons.radio_button_unchecked_rounded,
                            color: widget.selected
                                ? DearColors.coral
                                : Colors.white,
                            shadows: const [
                              Shadow(color: Colors.black38, blurRadius: 4),
                            ],
                          ),
                        ),
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

class _CachedAlbumSignedImageUrl {
  const _CachedAlbumSignedImageUrl({
    required this.url,
    required this.issuedAt,
  });

  final String url;
  final DateTime issuedAt;
}
