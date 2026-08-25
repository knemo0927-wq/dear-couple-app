import 'dart:async';
import 'dart:typed_data';

import 'package:couple_chat_app/src/features/chat/data/memory_album_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final memoryAlbumRepositoryProvider = Provider<MemoryAlbumRepository>(
  (ref) => MemoryAlbumRepository(),
);

final memoryAlbumsProvider =
    StreamProvider.family<List<MemoryAlbum>, String>((ref, coupleId) {
  final repository = ref.watch(memoryAlbumRepositoryProvider);
  return repository.watchAlbums(coupleId);
});

final memoryAlbumFeedProvider = StateNotifierProvider.autoDispose
    .family<MemoryAlbumFeedController, MemoryAlbumFeedState, String>(
        (ref, coupleId) {
  final repository = ref.watch(memoryAlbumRepositoryProvider);
  return MemoryAlbumFeedController(
    repository: repository,
    coupleId: coupleId,
  );
});

class MemoryAlbumFeedState {
  const MemoryAlbumFeedState({
    this.items = const [],
    this.nextCursor,
    this.hasMore = true,
    this.isLoadingInitial = true,
    this.isLoadingMore = false,
    this.error,
  });

  final List<MemoryAlbum> items;
  final MemoryAlbumCursor? nextCursor;
  final bool hasMore;
  final bool isLoadingInitial;
  final bool isLoadingMore;
  final Object? error;
}

class MemoryAlbumFeedController extends StateNotifier<MemoryAlbumFeedState> {
  MemoryAlbumFeedController({
    required MemoryAlbumRepository repository,
    required String coupleId,
  })  : _repository = repository,
        _coupleId = coupleId,
        super(const MemoryAlbumFeedState()) {
    _headSubscription = _repository
        .watchAlbumHead(coupleId: coupleId)
        .listen(_reconcileHead, onError: _handleHeadError);
    unawaited(refresh());
  }

  final MemoryAlbumRepository _repository;
  final String _coupleId;
  StreamSubscription<MemoryAlbumHeadSnapshot>? _headSubscription;
  MemoryAlbumHeadSnapshot? _latestHead;
  int _requestGeneration = 0;

  Future<void> refresh() async {
    final generation = ++_requestGeneration;
    state = MemoryAlbumFeedState(
      items: state.items,
      isLoadingInitial: state.items.isEmpty,
    );
    try {
      final page = await _repository.fetchAlbumPage(coupleId: _coupleId);
      if (!mounted || generation != _requestGeneration) return;
      final latestHead = _latestHead;
      final items = latestHead == null
          ? page.items
          : mergeMemoryAlbums(page.items, latestHead.items);
      state = MemoryAlbumFeedState(
        items: items,
        nextCursor: page.nextCursor,
        hasMore: latestHead?.isExhaustive == true ? false : page.hasMore,
        isLoadingInitial: false,
      );
    } catch (error) {
      if (!mounted || generation != _requestGeneration) return;
      state = MemoryAlbumFeedState(
        items: state.items,
        nextCursor: state.nextCursor,
        hasMore: state.hasMore,
        isLoadingInitial: false,
        error: error,
      );
    }
  }

  Future<void> loadMore() async {
    if (state.isLoadingInitial || state.isLoadingMore || !state.hasMore) return;
    final cursor = state.nextCursor;
    if (cursor == null) return;
    final generation = _requestGeneration;
    state = MemoryAlbumFeedState(
      items: state.items,
      nextCursor: cursor,
      hasMore: state.hasMore,
      isLoadingInitial: false,
      isLoadingMore: true,
    );
    try {
      final page = await _repository.fetchAlbumPage(
        coupleId: _coupleId,
        cursor: cursor,
      );
      if (!mounted || generation != _requestGeneration) return;
      state = MemoryAlbumFeedState(
        items: mergeMemoryAlbums(state.items, page.items),
        nextCursor: page.nextCursor,
        hasMore: page.hasMore,
        isLoadingInitial: false,
      );
    } catch (error) {
      if (!mounted || generation != _requestGeneration) return;
      state = MemoryAlbumFeedState(
        items: state.items,
        nextCursor: state.nextCursor,
        hasMore: state.hasMore,
        isLoadingInitial: false,
        error: error,
      );
    }
  }

  void _reconcileHead(MemoryAlbumHeadSnapshot snapshot) {
    if (!mounted) return;
    _latestHead = snapshot;
    final items = reconcileMemoryAlbumHeadWindow(state.items, snapshot);
    state = MemoryAlbumFeedState(
      items: items,
      nextCursor: snapshot.isExhaustive ? null : state.nextCursor,
      hasMore: snapshot.isExhaustive ? false : state.hasMore,
      isLoadingInitial: state.isLoadingInitial,
      isLoadingMore: state.isLoadingMore,
      error: state.error,
    );
  }

  void _handleHeadError(Object error, StackTrace stackTrace) {
    if (!mounted || state.items.isNotEmpty) return;
    state = MemoryAlbumFeedState(
      hasMore: state.hasMore,
      isLoadingInitial: false,
      error: error,
    );
  }

  @override
  void dispose() {
    _requestGeneration++;
    unawaited(_headSubscription?.cancel());
    super.dispose();
  }
}

final memoryAlbumPhotosProvider =
    StreamProvider.family<List<MemoryAlbumPhoto>, MemoryAlbumPhotosArgs>(
        (ref, args) {
  final repository = ref.watch(memoryAlbumRepositoryProvider);
  return repository.watchPhotos(coupleId: args.coupleId, albumId: args.albumId);
});

final recentMemoryAlbumPhotosProvider =
    StreamProvider.family<List<MemoryAlbumPhoto>, String>((ref, coupleId) {
  final repository = ref.watch(memoryAlbumRepositoryProvider);
  return repository.watchRecentPhotos(coupleId: coupleId, limit: 10);
});

final memoryAlbumPhotoFeedProvider = StateNotifierProvider.autoDispose.family<
    MemoryAlbumPhotoFeedController,
    MemoryAlbumPhotoFeedState,
    MemoryAlbumPhotoFeedArgs>((ref, args) {
  final repository = ref.watch(memoryAlbumRepositoryProvider);
  return MemoryAlbumPhotoFeedController(repository: repository, args: args);
});

class MemoryAlbumPhotoFeedArgs {
  const MemoryAlbumPhotoFeedArgs({
    required this.coupleId,
    this.albumId,
    this.createdAtOrAfter,
    this.createdAtBefore,
    this.uploadedBy,
    this.excludedUploader,
  });

  final String coupleId;
  final String? albumId;
  final DateTime? createdAtOrAfter;
  final DateTime? createdAtBefore;
  final String? uploadedBy;
  final String? excludedUploader;

  bool get hasFilters =>
      createdAtOrAfter != null ||
      createdAtBefore != null ||
      (uploadedBy?.isNotEmpty ?? false) ||
      (excludedUploader?.isNotEmpty ?? false);

  @override
  bool operator ==(Object other) {
    return other is MemoryAlbumPhotoFeedArgs &&
        other.coupleId == coupleId &&
        other.albumId == albumId &&
        other.createdAtOrAfter == createdAtOrAfter &&
        other.createdAtBefore == createdAtBefore &&
        other.uploadedBy == uploadedBy &&
        other.excludedUploader == excludedUploader;
  }

  @override
  int get hashCode => Object.hash(
        coupleId,
        albumId,
        createdAtOrAfter,
        createdAtBefore,
        uploadedBy,
        excludedUploader,
      );
}

class MemoryAlbumPhotoFeedState {
  const MemoryAlbumPhotoFeedState({
    this.items = const [],
    this.nextCursor,
    this.hasMore = true,
    this.isLoadingInitial = true,
    this.isLoadingMore = false,
    this.error,
  });

  final List<MemoryAlbumPhoto> items;
  final MemoryAlbumPhotoCursor? nextCursor;
  final bool hasMore;
  final bool isLoadingInitial;
  final bool isLoadingMore;
  final Object? error;
}

class MemoryAlbumPhotoFeedController
    extends StateNotifier<MemoryAlbumPhotoFeedState> {
  MemoryAlbumPhotoFeedController({
    required MemoryAlbumRepository repository,
    required MemoryAlbumPhotoFeedArgs args,
  })  : _repository = repository,
        _args = args,
        super(const MemoryAlbumPhotoFeedState()) {
    _realtimeSubscription = _repository
        .watchPhotoHeadWindow(
          coupleId: args.coupleId,
          albumId: args.albumId,
          createdAtOrAfter: args.createdAtOrAfter,
          createdAtBefore: args.createdAtBefore,
          uploadedBy: args.uploadedBy,
          excludedUploader: args.excludedUploader,
        )
        .listen(_mergeRealtimeHead, onError: _handleRealtimeError);
    _deletionSubscription = _repository
        .watchPhotoDeletions(
          coupleId: args.coupleId,
          albumId: args.albumId,
        )
        .listen(_applyDeletionEvents, onError: _handleDeletionError);
    unawaited(refresh());
  }

  final MemoryAlbumRepository _repository;
  final MemoryAlbumPhotoFeedArgs _args;
  StreamSubscription<MemoryAlbumPhotoHeadSnapshot>? _realtimeSubscription;
  StreamSubscription<List<MemoryAlbumPhotoDeletion>>? _deletionSubscription;
  MemoryAlbumPhotoHeadSnapshot? _latestRealtimeHead;
  final Set<String> _deletedPhotoIds = <String>{};
  int _requestGeneration = 0;

  Future<void> refresh() async {
    final generation = ++_requestGeneration;
    state = MemoryAlbumPhotoFeedState(
      items: state.items,
      isLoadingInitial: state.items.isEmpty,
    );
    try {
      final page = await _repository.fetchPhotoPage(
        coupleId: _args.coupleId,
        albumId: _args.albumId,
        createdAtOrAfter: _args.createdAtOrAfter,
        createdAtBefore: _args.createdAtBefore,
        uploadedBy: _args.uploadedBy,
        excludedUploader: _args.excludedUploader,
      );
      if (!mounted || generation != _requestGeneration) return;
      final fetched = _withoutDeleted(page.items);
      final latestHead = _latestRealtimeHead;
      final refreshed = latestHead == null
          ? fetched
          : _withoutDeleted(
              mergeMemoryAlbumPhotos(fetched, latestHead.items),
            );
      state = MemoryAlbumPhotoFeedState(
        items: refreshed,
        nextCursor: page.nextCursor,
        hasMore: page.hasMore,
        isLoadingInitial: false,
      );
    } catch (error) {
      if (!mounted || generation != _requestGeneration) return;
      state = MemoryAlbumPhotoFeedState(
        items: state.items,
        hasMore: state.hasMore,
        isLoadingInitial: false,
        error: error,
      );
    }
  }

  Future<void> loadMore() async {
    if (state.isLoadingInitial || state.isLoadingMore || !state.hasMore) return;
    final cursor = state.nextCursor;
    if (cursor == null) return;

    final generation = _requestGeneration;
    state = MemoryAlbumPhotoFeedState(
      items: state.items,
      nextCursor: state.nextCursor,
      hasMore: state.hasMore,
      isLoadingInitial: false,
      isLoadingMore: true,
    );
    try {
      final page = await _repository.fetchPhotoPage(
        coupleId: _args.coupleId,
        albumId: _args.albumId,
        cursor: cursor,
        createdAtOrAfter: _args.createdAtOrAfter,
        createdAtBefore: _args.createdAtBefore,
        uploadedBy: _args.uploadedBy,
        excludedUploader: _args.excludedUploader,
      );
      if (!mounted || generation != _requestGeneration) return;
      state = MemoryAlbumPhotoFeedState(
        items: _withoutDeleted(
          mergeMemoryAlbumPhotos(state.items, page.items),
        ),
        nextCursor: page.nextCursor,
        hasMore: page.hasMore,
        isLoadingInitial: false,
      );
    } catch (error) {
      if (!mounted || generation != _requestGeneration) return;
      state = MemoryAlbumPhotoFeedState(
        items: state.items,
        nextCursor: state.nextCursor,
        hasMore: state.hasMore,
        isLoadingInitial: false,
        error: error,
      );
    }
  }

  void _mergeRealtimeHead(MemoryAlbumPhotoHeadSnapshot snapshot) {
    if (!mounted) return;
    _latestRealtimeHead = snapshot;
    final reconciled = reconcileMemoryAlbumPhotoHeadWindow(
      state.items,
      snapshot,
    );
    state = MemoryAlbumPhotoFeedState(
      items: _withoutDeleted(reconciled),
      nextCursor: state.nextCursor,
      hasMore: state.hasMore,
      isLoadingInitial: state.isLoadingInitial,
      isLoadingMore: state.isLoadingMore,
      error: state.error,
    );
  }

  void _applyDeletionEvents(List<MemoryAlbumPhotoDeletion> events) {
    if (!mounted || events.isEmpty) return;
    _deletedPhotoIds.addAll(events.map((event) => event.photoId));
    final items = removeMemoryAlbumPhotosById(
      state.items,
      _deletedPhotoIds,
    );
    if (items.length == state.items.length) return;
    state = MemoryAlbumPhotoFeedState(
      items: items,
      nextCursor: state.nextCursor,
      hasMore: state.hasMore,
      isLoadingInitial: state.isLoadingInitial,
      isLoadingMore: state.isLoadingMore,
      error: state.error,
    );
  }

  List<MemoryAlbumPhoto> _withoutDeleted(
    Iterable<MemoryAlbumPhoto> photos,
  ) {
    return removeMemoryAlbumPhotosById(photos, _deletedPhotoIds);
  }

  void _handleRealtimeError(Object error, StackTrace stackTrace) {
    if (!mounted || state.items.isNotEmpty) return;
    state = MemoryAlbumPhotoFeedState(
      hasMore: state.hasMore,
      isLoadingInitial: false,
      error: error,
    );
  }

  void _handleDeletionError(Object error, StackTrace stackTrace) {
    if (!mounted || state.items.isNotEmpty || state.error != null) return;
    state = MemoryAlbumPhotoFeedState(
      hasMore: state.hasMore,
      isLoadingInitial: false,
      error: error,
    );
  }

  @override
  void dispose() {
    _requestGeneration++;
    unawaited(_realtimeSubscription?.cancel());
    unawaited(_deletionSubscription?.cancel());
    super.dispose();
  }
}

typedef CreateMemoryAlbumAction = Future<MemoryAlbum> Function({
  required String coupleId,
  required String name,
  Uint8List? coverBytes,
  String? coverExtension,
});

typedef UploadMemoryAlbumPhotoAction = Future<void> Function({
  required String coupleId,
  required String albumId,
  required Uint8List bytes,
  required String extension,
});

typedef UpdateMemoryAlbumAction = Future<MemoryAlbum> Function({
  required String coupleId,
  required String albumId,
  required String name,
  Uint8List? coverBytes,
  String? coverExtension,
});

typedef DeleteMemoryAlbumAction = Future<void> Function({
  required String coupleId,
  required String albumId,
});

typedef SetMemoryAlbumCoverPhotoAction = Future<void> Function({
  required String coupleId,
  required String albumId,
  required String photoId,
});

typedef SetFeaturedMemoryAlbumAction = Future<void> Function({
  required String coupleId,
  required String albumId,
});

typedef DeleteMemoryAlbumPhotosAction = Future<int> Function({
  required String coupleId,
  required Iterable<String> photoIds,
});

typedef MoveMemoryAlbumPhotosAction = Future<int> Function({
  required String coupleId,
  required Iterable<String> photoIds,
  required String destinationAlbumId,
});

typedef CreateMemoryAlbumPhotoUrlsAction = Future<List<String>> Function(
  List<String> storagePaths,
);

final createMemoryAlbumProvider = Provider<CreateMemoryAlbumAction>((ref) {
  final repository = ref.watch(memoryAlbumRepositoryProvider);
  return ({required coupleId, required name, coverBytes, coverExtension}) =>
      repository.createAlbum(
        coupleId: coupleId,
        name: name,
        coverBytes: coverBytes,
        coverExtension: coverExtension,
      );
});

final uploadMemoryAlbumPhotoProvider =
    Provider<UploadMemoryAlbumPhotoAction>((ref) {
  final repository = ref.watch(memoryAlbumRepositoryProvider);
  return (
          {required coupleId,
          required albumId,
          required bytes,
          required extension}) =>
      repository.uploadPhoto(
        coupleId: coupleId,
        albumId: albumId,
        bytes: bytes,
        extension: extension,
      );
});

final updateMemoryAlbumProvider = Provider<UpdateMemoryAlbumAction>((ref) {
  final repository = ref.watch(memoryAlbumRepositoryProvider);
  return ({
    required coupleId,
    required albumId,
    required name,
    coverBytes,
    coverExtension,
  }) =>
      repository.updateAlbum(
        coupleId: coupleId,
        albumId: albumId,
        name: name,
        coverBytes: coverBytes,
        coverExtension: coverExtension,
      );
});

final deleteMemoryAlbumProvider = Provider<DeleteMemoryAlbumAction>((ref) {
  final repository = ref.watch(memoryAlbumRepositoryProvider);
  return ({required coupleId, required albumId}) => repository.deleteAlbum(
        coupleId: coupleId,
        albumId: albumId,
      );
});

final createMemoryAlbumPhotoUrlsProvider =
    Provider<CreateMemoryAlbumPhotoUrlsAction>((ref) {
  final repository = ref.watch(memoryAlbumRepositoryProvider);
  return repository.createSignedUrls;
});

final setMemoryAlbumCoverPhotoProvider =
    Provider<SetMemoryAlbumCoverPhotoAction>((ref) {
  final repository = ref.watch(memoryAlbumRepositoryProvider);
  return ({required coupleId, required albumId, required photoId}) =>
      repository.setAlbumCoverPhoto(
        coupleId: coupleId,
        albumId: albumId,
        photoId: photoId,
      );
});

final setFeaturedMemoryAlbumProvider =
    Provider<SetFeaturedMemoryAlbumAction>((ref) {
  final repository = ref.watch(memoryAlbumRepositoryProvider);
  return ({required coupleId, required albumId}) => repository.setFeaturedAlbum(
        coupleId: coupleId,
        albumId: albumId,
      );
});

final deleteMemoryAlbumPhotosProvider =
    Provider<DeleteMemoryAlbumPhotosAction>((ref) {
  final repository = ref.watch(memoryAlbumRepositoryProvider);
  return ({required coupleId, required photoIds}) => repository.deletePhotos(
        coupleId: coupleId,
        photoIds: photoIds,
      );
});

final moveMemoryAlbumPhotosProvider =
    Provider<MoveMemoryAlbumPhotosAction>((ref) {
  final repository = ref.watch(memoryAlbumRepositoryProvider);
  return (
          {required coupleId,
          required photoIds,
          required destinationAlbumId}) =>
      repository.movePhotos(
        coupleId: coupleId,
        photoIds: photoIds,
        destinationAlbumId: destinationAlbumId,
      );
});

List<MemoryAlbum> reconcileMemoryAlbumHeadWindow(
  Iterable<MemoryAlbum> current,
  MemoryAlbumHeadSnapshot snapshot,
) {
  if (snapshot.isExhaustive) return snapshot.items;
  final boundary = snapshot.oldest;
  if (boundary == null) return snapshot.items;
  final older = current.where(
    (album) => compareMemoryAlbumsNewestFirst(album, boundary) > 0,
  );
  return mergeMemoryAlbums(older, snapshot.items);
}

/// Replaces the current realtime head while retaining cursor-loaded older rows.
/// This makes realtime DELETE events remove stale tiles instead of only merging
/// inserts and updates.
List<MemoryAlbumPhoto> reconcileMemoryAlbumPhotoHead(
  Iterable<MemoryAlbumPhoto> current,
  Iterable<MemoryAlbumPhoto> incoming, {
  int headSize = memoryAlbumPhotoPageSize,
}) {
  final head = mergeMemoryAlbumPhotos(const [], incoming);
  return reconcileMemoryAlbumPhotoHeadWindow(
    current,
    MemoryAlbumPhotoHeadSnapshot(
      items: head,
      oldestUnfiltered: head.isEmpty ? null : head.last,
      isExhaustive: head.length < headSize,
    ),
  );
}

List<MemoryAlbumPhoto> reconcileMemoryAlbumPhotoHeadWindow(
  Iterable<MemoryAlbumPhoto> current,
  MemoryAlbumPhotoHeadSnapshot snapshot,
) {
  if (snapshot.isExhaustive) return snapshot.items;
  final boundary = snapshot.oldestUnfiltered;
  if (boundary == null) return snapshot.items;
  final older = current.where(
    (photo) => compareMemoryAlbumPhotosNewestFirst(photo, boundary) > 0,
  );
  return mergeMemoryAlbumPhotos(older, snapshot.items);
}

class MemoryAlbumPhotosArgs {
  const MemoryAlbumPhotosArgs({required this.coupleId, required this.albumId});

  final String coupleId;
  final String albumId;

  @override
  bool operator ==(Object other) {
    return other is MemoryAlbumPhotosArgs &&
        other.coupleId == coupleId &&
        other.albumId == albumId;
  }

  @override
  int get hashCode => Object.hash(coupleId, albumId);
}
