import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

const memoryAlbumPhotoPageSize = 30;
const memoryAlbumPageSize = 30;
const memoryAlbumDeletionEventWindow = 200;

class MemoryAlbum {
  const MemoryAlbum({
    required this.id,
    required this.coupleId,
    required this.name,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.coverPhotoId,
    this.coverStoragePath,
    this.photoCount = 0,
    this.isFeatured = false,
  });

  final String id;
  final String coupleId;
  final String name;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? coverPhotoId;
  final String? coverStoragePath;
  final int photoCount;
  final bool isFeatured;

  MemoryAlbum copyWith({
    String? coverPhotoId,
    String? coverStoragePath,
    int? photoCount,
    DateTime? updatedAt,
    bool? isFeatured,
  }) {
    return MemoryAlbum(
      id: id,
      coupleId: coupleId,
      name: name,
      createdBy: createdBy,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      coverPhotoId: coverPhotoId ?? this.coverPhotoId,
      coverStoragePath: coverStoragePath ?? this.coverStoragePath,
      photoCount: photoCount ?? this.photoCount,
      isFeatured: isFeatured ?? this.isFeatured,
    );
  }

  factory MemoryAlbum.fromMap(Map<String, dynamic> map) {
    int parseCount(dynamic value) {
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    return MemoryAlbum(
      id: map['id'] as String,
      coupleId: map['couple_id'] as String,
      name: map['name'] as String,
      createdBy: map['created_by'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      coverPhotoId: map['cover_photo_id'] as String?,
      coverStoragePath: map['cover_storage_path'] as String?,
      photoCount: parseCount(map['photo_count']),
      isFeatured: map['is_featured'] as bool? ?? false,
    );
  }
}

class MemoryAlbumCursor {
  const MemoryAlbumCursor({
    required this.isFeatured,
    required this.updatedAt,
    required this.id,
  });

  final bool isFeatured;
  final DateTime updatedAt;
  final String id;

  @override
  bool operator ==(Object other) {
    return other is MemoryAlbumCursor &&
        other.isFeatured == isFeatured &&
        other.updatedAt == updatedAt &&
        other.id == id;
  }

  @override
  int get hashCode => Object.hash(isFeatured, updatedAt, id);
}

class MemoryAlbumListPage {
  const MemoryAlbumListPage({
    required this.items,
    required this.nextCursor,
    required this.hasMore,
  });

  final List<MemoryAlbum> items;
  final MemoryAlbumCursor? nextCursor;
  final bool hasMore;
}

class MemoryAlbumHeadSnapshot {
  const MemoryAlbumHeadSnapshot({
    required this.items,
    required this.oldest,
    required this.isExhaustive,
  });

  final List<MemoryAlbum> items;
  final MemoryAlbum? oldest;
  final bool isExhaustive;
}

class MemoryAlbumPhoto {
  const MemoryAlbumPhoto({
    required this.id,
    required this.albumId,
    required this.coupleId,
    required this.storagePath,
    required this.uploadedBy,
    required this.createdAt,
  });

  final String id;
  final String albumId;
  final String coupleId;
  final String storagePath;
  final String uploadedBy;
  final DateTime createdAt;

  factory MemoryAlbumPhoto.fromMap(Map<String, dynamic> map) {
    return MemoryAlbumPhoto(
      id: map['id'] as String,
      albumId: map['album_id'] as String,
      coupleId: map['couple_id'] as String,
      storagePath: map['storage_path'] as String,
      uploadedBy: map['uploaded_by'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}

class MemoryAlbumPhotoDeletion {
  const MemoryAlbumPhotoDeletion({
    required this.eventId,
    required this.photoId,
    required this.albumId,
    required this.coupleId,
    required this.deletedAt,
  });

  final int eventId;
  final String photoId;
  final String albumId;
  final String coupleId;
  final DateTime deletedAt;

  factory MemoryAlbumPhotoDeletion.fromMap(Map<String, dynamic> map) {
    final rawEventId = map['event_id'];
    return MemoryAlbumPhotoDeletion(
      eventId:
          rawEventId is int ? rawEventId : int.parse(rawEventId.toString()),
      photoId: map['photo_id'] as String,
      albumId: map['album_id'] as String,
      coupleId: map['couple_id'] as String,
      deletedAt: DateTime.parse(map['deleted_at'] as String),
    );
  }
}

class MemoryAlbumPhotoCursor {
  const MemoryAlbumPhotoCursor({required this.createdAt, required this.id});

  final DateTime createdAt;
  final String id;

  @override
  bool operator ==(Object other) {
    return other is MemoryAlbumPhotoCursor &&
        other.createdAt == createdAt &&
        other.id == id;
  }

  @override
  int get hashCode => Object.hash(createdAt, id);
}

class MemoryAlbumPhotoPage {
  const MemoryAlbumPhotoPage({
    required this.items,
    required this.nextCursor,
    required this.hasMore,
  });

  final List<MemoryAlbumPhoto> items;
  final MemoryAlbumPhotoCursor? nextCursor;
  final bool hasMore;
}

class MemoryAlbumPhotoHeadSnapshot {
  const MemoryAlbumPhotoHeadSnapshot({
    required this.items,
    required this.oldestUnfiltered,
    required this.isExhaustive,
  });

  final List<MemoryAlbumPhoto> items;
  final MemoryAlbumPhoto? oldestUnfiltered;
  final bool isExhaustive;
}

int compareMemoryAlbumsNewestFirst(MemoryAlbum a, MemoryAlbum b) {
  if (a.isFeatured != b.isFeatured) return a.isFeatured ? -1 : 1;
  final updatedAtOrder = b.updatedAt.compareTo(a.updatedAt);
  if (updatedAtOrder != 0) return updatedAtOrder;
  return b.id.compareTo(a.id);
}

List<MemoryAlbum> mergeMemoryAlbums(
  Iterable<MemoryAlbum> current,
  Iterable<MemoryAlbum> incoming,
) {
  final byId = <String, MemoryAlbum>{};
  for (final album in current) {
    byId[album.id] = album;
  }
  for (final album in incoming) {
    byId[album.id] = album;
  }
  final result = byId.values.toList(growable: false)
    ..sort(compareMemoryAlbumsNewestFirst);
  return List<MemoryAlbum>.unmodifiable(result);
}

MemoryAlbumListPage memoryAlbumPageFromRows(
  Iterable<MemoryAlbum> rows, {
  int pageSize = memoryAlbumPageSize,
  bool? hasMore,
}) {
  if (pageSize <= 0) {
    throw ArgumentError.value(pageSize, 'pageSize', 'must be positive');
  }
  final normalized = mergeMemoryAlbums(const [], rows);
  final resolvedHasMore = hasMore ?? normalized.length > pageSize;
  final items = normalized.take(pageSize).toList(growable: false);
  final last = items.isEmpty ? null : items.last;
  return MemoryAlbumListPage(
    items: List<MemoryAlbum>.unmodifiable(items),
    nextCursor: last == null
        ? null
        : MemoryAlbumCursor(
            isFeatured: last.isFeatured,
            updatedAt: last.updatedAt,
            id: last.id,
          ),
    hasMore: resolvedHasMore,
  );
}

List<MemoryAlbumPhoto> removeMemoryAlbumPhotosById(
  Iterable<MemoryAlbumPhoto> current,
  Iterable<String> deletedPhotoIds,
) {
  final deleted = deletedPhotoIds.toSet();
  if (deleted.isEmpty) return List<MemoryAlbumPhoto>.unmodifiable(current);
  return List<MemoryAlbumPhoto>.unmodifiable(
    current.where((photo) => !deleted.contains(photo.id)),
  );
}

/// Combines realtime and cursor-page results without duplicate photo IDs.
///
/// Newer values win when the same ID exists in both lists, then the result is
/// ordered deterministically by `(created_at DESC, id DESC)`.
List<MemoryAlbumPhoto> mergeMemoryAlbumPhotos(
  Iterable<MemoryAlbumPhoto> current,
  Iterable<MemoryAlbumPhoto> incoming,
) {
  final byId = <String, MemoryAlbumPhoto>{};
  for (final photo in current) {
    byId[photo.id] = photo;
  }
  for (final photo in incoming) {
    byId[photo.id] = photo;
  }

  final merged = byId.values.toList(growable: false)
    ..sort(compareMemoryAlbumPhotosNewestFirst);
  return List<MemoryAlbumPhoto>.unmodifiable(merged);
}

List<MemoryAlbumPhoto> filterMemoryAlbumPhotos(
  Iterable<MemoryAlbumPhoto> photos, {
  DateTime? createdAtOrAfter,
  DateTime? createdAtBefore,
  String? uploadedBy,
  String? excludedUploader,
}) {
  final normalizedUploader = uploadedBy?.trim();
  final normalizedExcludedUploader = excludedUploader?.trim();
  return List<MemoryAlbumPhoto>.unmodifiable(
    photos.where((photo) {
      final createdAt = photo.createdAt.toUtc();
      if (createdAtOrAfter != null &&
          createdAt.isBefore(createdAtOrAfter.toUtc())) {
        return false;
      }
      if (createdAtBefore != null &&
          !createdAt.isBefore(createdAtBefore.toUtc())) {
        return false;
      }
      if (normalizedUploader != null &&
          normalizedUploader.isNotEmpty &&
          photo.uploadedBy != normalizedUploader) {
        return false;
      }
      if (normalizedExcludedUploader != null &&
          normalizedExcludedUploader.isNotEmpty &&
          photo.uploadedBy == normalizedExcludedUploader) {
        return false;
      }
      return true;
    }),
  );
}

int compareMemoryAlbumPhotosNewestFirst(
  MemoryAlbumPhoto a,
  MemoryAlbumPhoto b,
) {
  final createdAtOrder = b.createdAt.compareTo(a.createdAt);
  if (createdAtOrder != 0) return createdAtOrder;
  return b.id.compareTo(a.id);
}

MemoryAlbumPhotoPage memoryAlbumPhotoPageFromRows(
  Iterable<MemoryAlbumPhoto> rows, {
  int pageSize = memoryAlbumPhotoPageSize,
}) {
  if (pageSize <= 0) {
    throw ArgumentError.value(pageSize, 'pageSize', 'must be positive');
  }

  final deduplicated = mergeMemoryAlbumPhotos(const [], rows);
  final hasMore = deduplicated.length > pageSize;
  final items = deduplicated.take(pageSize).toList(growable: false);
  final last = items.isEmpty ? null : items.last;
  return MemoryAlbumPhotoPage(
    items: List<MemoryAlbumPhoto>.unmodifiable(items),
    nextCursor: last == null
        ? null
        : MemoryAlbumPhotoCursor(createdAt: last.createdAt, id: last.id),
    hasMore: hasMore,
  );
}

class MemoryAlbumRepository {
  MemoryAlbumRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Stream<List<MemoryAlbum>> watchAlbums(String coupleId) {
    return watchAlbumHead(coupleId: coupleId).map((snapshot) => snapshot.items);
  }

  Stream<MemoryAlbumHeadSnapshot> watchAlbumHead({
    required String coupleId,
    int limit = memoryAlbumPageSize,
  }) {
    return _client
        .from('memory_albums')
        .stream(primaryKey: ['id'])
        .eq('couple_id', coupleId)
        .order('is_featured', ascending: false)
        .order('updated_at', ascending: false)
        .order('id', ascending: false)
        .limit(limit)
        .asyncMap((rows) async {
          final baseAlbums = rows
              .map<MemoryAlbum>(MemoryAlbum.fromMap)
              .toList(growable: false);
          final albums = await _fetchAlbumSummaries(
            coupleId: coupleId,
            albumIds: baseAlbums.map((album) => album.id),
          );
          final normalized = mergeMemoryAlbums(const [], albums);
          return MemoryAlbumHeadSnapshot(
            items: normalized,
            oldest: normalized.isEmpty ? null : normalized.last,
            isExhaustive: rows.length < limit,
          );
        });
  }

  Future<List<MemoryAlbum>> fetchAlbums(String coupleId) async {
    final albums = <MemoryAlbum>[];
    MemoryAlbumCursor? cursor;
    do {
      final page = await fetchAlbumPage(
        coupleId: coupleId,
        cursor: cursor,
      );
      albums.addAll(page.items);
      cursor = page.hasMore ? page.nextCursor : null;
    } while (cursor != null);
    return mergeMemoryAlbums(const [], albums);
  }

  Future<MemoryAlbumListPage> fetchAlbumPage({
    required String coupleId,
    MemoryAlbumCursor? cursor,
    int pageSize = memoryAlbumPageSize,
  }) async {
    if (pageSize <= 0) {
      throw ArgumentError.value(pageSize, 'pageSize', 'must be positive');
    }
    final response = await _client.rpc(
      'get_memory_album_page',
      params: {
        'target_couple_id': coupleId,
        'page_size': pageSize.clamp(1, 100),
        'cursor_is_featured': cursor?.isFeatured,
        'cursor_updated_at': cursor?.updatedAt.toUtc().toIso8601String(),
        'cursor_id': cursor?.id,
      },
    );
    final rows = (response as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);
    final hasMore = rows.isNotEmpty && rows.first['has_more'] == true;
    return memoryAlbumPageFromRows(
      rows.map<MemoryAlbum>(MemoryAlbum.fromMap),
      pageSize: pageSize,
      hasMore: hasMore,
    );
  }

  Future<MemoryAlbum?> fetchAlbumById({
    required String coupleId,
    required String albumId,
  }) async {
    final rows = await _fetchAlbumSummaries(
      coupleId: coupleId,
      albumIds: [albumId],
    );
    return rows.isEmpty ? null : rows.first;
  }

  Stream<List<MemoryAlbumPhotoDeletion>> watchPhotoDeletions({
    required String coupleId,
    String? albumId,
    int limit = memoryAlbumDeletionEventWindow,
  }) {
    return _client
        .from('memory_album_photo_deletions')
        .stream(primaryKey: ['event_id'])
        .eq('couple_id', coupleId)
        .order('event_id', ascending: false)
        .limit(limit)
        .map(
          (rows) => rows
              .where((row) => albumId == null || row['album_id'] == albumId)
              .map(
                (row) => MemoryAlbumPhotoDeletion.fromMap(
                  Map<String, dynamic>.from(row),
                ),
              )
              .toList(growable: false),
        );
  }

  Stream<List<MemoryAlbumPhoto>> watchPhotos({
    required String coupleId,
    required String albumId,
    int limit = memoryAlbumPhotoPageSize,
  }) {
    // Supabase stream currently accepts one server-side filter. album_id is
    // globally unique and RLS still enforces couple membership; the couple ID
    // check below is an additional client-side guard.
    return _client
        .from('memory_album_photos')
        .stream(primaryKey: ['id'])
        .eq('album_id', albumId)
        .order('created_at', ascending: false)
        .limit(limit)
        .map((rows) => mergeMemoryAlbumPhotos(
              const [],
              rows
                  .where((row) => row['couple_id'] == coupleId)
                  .map<MemoryAlbumPhoto>(MemoryAlbumPhoto.fromMap),
            ));
  }

  Stream<List<MemoryAlbumPhoto>> watchRecentPhotos({
    required String coupleId,
    int limit = 10,
  }) {
    return _client
        .from('memory_album_photos')
        .stream(primaryKey: ['id'])
        .eq('couple_id', coupleId)
        .order('created_at', ascending: false)
        .limit(limit)
        .map((rows) => mergeMemoryAlbumPhotos(
              const [],
              rows.map<MemoryAlbumPhoto>(MemoryAlbumPhoto.fromMap),
            ));
  }

  Stream<List<MemoryAlbumPhoto>> watchPhotoHead({
    required String coupleId,
    String? albumId,
    int limit = memoryAlbumPhotoPageSize,
    DateTime? createdAtOrAfter,
    DateTime? createdAtBefore,
    String? uploadedBy,
    String? excludedUploader,
  }) {
    return watchPhotoHeadWindow(
      coupleId: coupleId,
      albumId: albumId,
      limit: limit,
      createdAtOrAfter: createdAtOrAfter,
      createdAtBefore: createdAtBefore,
      uploadedBy: uploadedBy,
      excludedUploader: excludedUploader,
    ).map((snapshot) => snapshot.items);
  }

  Stream<MemoryAlbumPhotoHeadSnapshot> watchPhotoHeadWindow({
    required String coupleId,
    String? albumId,
    int limit = memoryAlbumPhotoPageSize,
    DateTime? createdAtOrAfter,
    DateTime? createdAtBefore,
    String? uploadedBy,
    String? excludedUploader,
  }) {
    final stream = albumId == null
        ? watchRecentPhotos(coupleId: coupleId, limit: limit)
        : watchPhotos(
            coupleId: coupleId,
            albumId: albumId,
            limit: limit,
          );
    return stream.map((photos) {
      return MemoryAlbumPhotoHeadSnapshot(
        items: filterMemoryAlbumPhotos(
          photos,
          createdAtOrAfter: createdAtOrAfter,
          createdAtBefore: createdAtBefore,
          uploadedBy: uploadedBy,
          excludedUploader: excludedUploader,
        ),
        oldestUnfiltered: photos.isEmpty ? null : photos.last,
        isExhaustive: photos.length < limit,
      );
    });
  }

  Future<List<MemoryAlbumPhoto>> fetchPhotos({
    required String coupleId,
    required String albumId,
  }) async {
    final rows = await _client
        .from('memory_album_photos')
        .select('id,album_id,couple_id,storage_path,uploaded_by,created_at')
        .eq('couple_id', coupleId)
        .eq('album_id', albumId)
        .order('created_at', ascending: false)
        .order('id', ascending: false);

    return rows
        .map<MemoryAlbumPhoto>((row) => MemoryAlbumPhoto.fromMap(row))
        .toList(growable: false);
  }

  Future<List<MemoryAlbumPhoto>> fetchRecentPhotos({
    required String coupleId,
    int limit = 10,
  }) async {
    final rows = await _client
        .from('memory_album_photos')
        .select('id,album_id,couple_id,storage_path,uploaded_by,created_at')
        .eq('couple_id', coupleId)
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .limit(limit);

    return rows
        .map<MemoryAlbumPhoto>((row) => MemoryAlbumPhoto.fromMap(row))
        .toList(growable: false);
  }

  Future<MemoryAlbumPhotoPage> fetchPhotoPage({
    required String coupleId,
    String? albumId,
    MemoryAlbumPhotoCursor? cursor,
    int pageSize = memoryAlbumPhotoPageSize,
    DateTime? createdAtOrAfter,
    DateTime? createdAtBefore,
    String? uploadedBy,
    String? excludedUploader,
  }) async {
    if (pageSize <= 0) {
      throw ArgumentError.value(pageSize, 'pageSize', 'must be positive');
    }

    var query = _client
        .from('memory_album_photos')
        .select('id,album_id,couple_id,storage_path,uploaded_by,created_at')
        .eq('couple_id', coupleId);
    if (albumId != null) {
      query = query.eq('album_id', albumId);
    }
    if (createdAtOrAfter != null) {
      query = query.gte(
        'created_at',
        createdAtOrAfter.toUtc().toIso8601String(),
      );
    }
    if (createdAtBefore != null) {
      query = query.lt(
        'created_at',
        createdAtBefore.toUtc().toIso8601String(),
      );
    }
    if (uploadedBy != null && uploadedBy.trim().isNotEmpty) {
      query = query.eq('uploaded_by', uploadedBy.trim());
    }
    if (excludedUploader != null && excludedUploader.trim().isNotEmpty) {
      query = query.neq('uploaded_by', excludedUploader.trim());
    }
    if (cursor != null) {
      final timestamp = cursor.createdAt.toUtc().toIso8601String();
      query = query.or(
        'created_at.lt.$timestamp,and(created_at.eq.$timestamp,id.lt.${cursor.id})',
      );
    }

    final rows = await query
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .limit(pageSize + 1);
    return memoryAlbumPhotoPageFromRows(
      rows.map<MemoryAlbumPhoto>(MemoryAlbumPhoto.fromMap),
      pageSize: pageSize,
    );
  }

  Future<MemoryAlbum> createAlbum({
    required String coupleId,
    required String name,
    Uint8List? coverBytes,
    String? coverExtension,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw const AuthException('AUTH_REQUIRED');

    final normalized = name.trim();
    if (normalized.isEmpty) throw const FormatException('ALBUM_NAME_REQUIRED');

    final row = await _client
        .from('memory_albums')
        .insert({
          'couple_id': coupleId,
          'name': normalized,
          'created_by': user.id,
        })
        .select('id,couple_id,name,created_by,created_at,updated_at')
        .single();

    var album = MemoryAlbum.fromMap(row);
    if (coverBytes == null || coverExtension == null) return album;

    final coverPhoto = await _uploadPhotoRow(
      coupleId: coupleId,
      albumId: album.id,
      bytes: coverBytes,
      extension: coverExtension,
    );
    await _setAlbumCoverPhoto(
      albumId: album.id,
      photoId: coverPhoto.id,
    );

    album = album.copyWith(
      coverPhotoId: coverPhoto.id,
      coverStoragePath: coverPhoto.storagePath,
      photoCount: 1,
      updatedAt: coverPhoto.createdAt,
    );
    return album;
  }

  Future<void> uploadPhoto({
    required String coupleId,
    required String albumId,
    required Uint8List bytes,
    required String extension,
  }) async {
    await _uploadPhotoRow(
      coupleId: coupleId,
      albumId: albumId,
      bytes: bytes,
      extension: extension,
    );
  }

  Future<MemoryAlbum> updateAlbum({
    required String coupleId,
    required String albumId,
    required String name,
    Uint8List? coverBytes,
    String? coverExtension,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw const AuthException('AUTH_REQUIRED');

    final normalized = name.trim();
    if (normalized.isEmpty) throw const FormatException('ALBUM_NAME_REQUIRED');

    await _client
        .from('memory_albums')
        .update({
          'name': normalized,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('couple_id', coupleId)
        .eq('id', albumId);

    if (coverBytes != null && coverExtension != null) {
      final coverPhoto = await _uploadPhotoRow(
        coupleId: coupleId,
        albumId: albumId,
        bytes: coverBytes,
        extension: coverExtension,
      );
      await _setAlbumCoverPhoto(
        albumId: albumId,
        photoId: coverPhoto.id,
      );
    }

    final album = await fetchAlbumById(
      coupleId: coupleId,
      albumId: albumId,
    );
    if (album == null) throw StateError('ALBUM_NOT_FOUND');
    return album;
  }

  Future<void> deleteAlbum({
    required String coupleId,
    required String albumId,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw const AuthException('AUTH_REQUIRED');

    final photos = await fetchPhotos(coupleId: coupleId, albumId: albumId);

    await _client
        .from('memory_album_photos')
        .delete()
        .eq('couple_id', coupleId)
        .eq('album_id', albumId);
    await _client
        .from('memory_albums')
        .delete()
        .eq('couple_id', coupleId)
        .eq('id', albumId);
    final storagePaths = photos
        .map((photo) => photo.storagePath)
        .where((path) => path.trim().isNotEmpty)
        .toList(growable: false);
    if (storagePaths.isEmpty) return;

    try {
      await _client.storage.from('memory-album-photos').remove(storagePaths);
    } catch (_) {
      // DB 삭제가 우선이다. 스토리지 정리는 실패해도 화면 상태를 막지 않는다.
    }
  }

  Future<int> deletePhotos({
    required String coupleId,
    required Iterable<String> photoIds,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw const AuthException('AUTH_REQUIRED');

    final ids = _normalizedPhotoIds(photoIds);
    if (ids.isEmpty) return 0;

    final photos = <MemoryAlbumPhoto>[];
    for (final chunk in _chunks(ids, 100)) {
      final rows = await _client
          .from('memory_album_photos')
          .select('id,album_id,couple_id,storage_path,uploaded_by,created_at')
          .eq('couple_id', coupleId)
          .inFilter('id', chunk);
      photos.addAll(rows.map<MemoryAlbumPhoto>(MemoryAlbumPhoto.fromMap));
    }
    if (photos.isEmpty) return 0;

    final verifiedIds = photos.map((photo) => photo.id).toList(growable: false);
    for (final chunk in _chunks(verifiedIds, 100)) {
      await _client
          .from('memory_album_photos')
          .delete()
          .eq('couple_id', coupleId)
          .inFilter('id', chunk);
    }

    await _touchAlbums(photos.map((photo) => photo.albumId));
    final storagePaths = photos
        .map((photo) => photo.storagePath)
        .where((path) => path.trim().isNotEmpty)
        .toList(growable: false);
    if (storagePaths.isNotEmpty) {
      try {
        for (final chunk in _chunks(storagePaths, 100)) {
          await _client.storage.from('memory-album-photos').remove(chunk);
        }
      } catch (_) {
        // DB가 원본 상태다. 실패한 스토리지 정리는 후속 정리 작업에 맡긴다.
      }
    }
    return photos.length;
  }

  Future<int> movePhotos({
    required String coupleId,
    required Iterable<String> photoIds,
    required String destinationAlbumId,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw const AuthException('AUTH_REQUIRED');

    final destinationId = destinationAlbumId.trim();
    if (destinationId.isEmpty) {
      throw const FormatException('DESTINATION_ALBUM_REQUIRED');
    }
    await _client
        .from('memory_albums')
        .select('id')
        .eq('couple_id', coupleId)
        .eq('id', destinationId)
        .single();

    final ids = _normalizedPhotoIds(photoIds);
    if (ids.isEmpty) return 0;
    final photos = <MemoryAlbumPhoto>[];
    for (final chunk in _chunks(ids, 100)) {
      final rows = await _client
          .from('memory_album_photos')
          .select('id,album_id,couple_id,storage_path,uploaded_by,created_at')
          .eq('couple_id', coupleId)
          .inFilter('id', chunk);
      photos.addAll(rows.map<MemoryAlbumPhoto>(MemoryAlbumPhoto.fromMap));
    }

    final moving = photos
        .where((photo) => photo.albumId != destinationId)
        .toList(growable: false);
    if (moving.isEmpty) return 0;
    final movingIds = moving.map((photo) => photo.id).toList(growable: false);
    final sourceAlbumIds =
        moving.map((photo) => photo.albumId).toSet().toList(growable: false);

    // 다른 앨범으로 이동한 사진을 이전 앨범의 대표 사진으로 남기지 않는다.
    for (final sourceChunk in _chunks(sourceAlbumIds, 100)) {
      for (final photoChunk in _chunks(movingIds, 100)) {
        await _client
            .from('memory_albums')
            .update({'cover_photo_id': null})
            .eq('couple_id', coupleId)
            .inFilter('id', sourceChunk)
            .inFilter('cover_photo_id', photoChunk);
      }
    }
    for (final chunk in _chunks(movingIds, 100)) {
      await _client
          .from('memory_album_photos')
          .update({'album_id': destinationId})
          .eq('couple_id', coupleId)
          .inFilter('id', chunk);
    }
    await _touchAlbums({...sourceAlbumIds, destinationId});
    return moving.length;
  }

  Future<void> setAlbumCoverPhoto({
    required String coupleId,
    required String albumId,
    required String photoId,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw const AuthException('AUTH_REQUIRED');

    await _client
        .from('memory_album_photos')
        .select('id')
        .eq('couple_id', coupleId)
        .eq('album_id', albumId)
        .eq('id', photoId)
        .single();
    await _setAlbumCoverPhoto(
      albumId: albumId,
      photoId: photoId,
    );
  }

  Future<void> setFeaturedAlbum({
    required String coupleId,
    required String albumId,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw const AuthException('AUTH_REQUIRED');

    try {
      await _client
          .from('memory_albums')
          .update({'is_featured': false}).eq('couple_id', coupleId);
      await _client
          .from('memory_albums')
          .update({
            'is_featured': true,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('couple_id', coupleId)
          .eq('id', albumId);
    } on PostgrestException catch (error) {
      if (_isMissingFeaturedColumn(error)) {
        throw StateError('MEMORY_ALBUM_FEATURED_SCHEMA_REQUIRED');
      }
      rethrow;
    }
  }

  Future<List<String>> createSignedUrls(List<String> storagePaths) {
    final storage = _client.storage.from('memory-album-photos');
    return Future.wait(
        storagePaths.map((path) => storage.createSignedUrl(path, 60)));
  }

  Future<List<MemoryAlbum>> _fetchAlbumSummaries({
    required String coupleId,
    required Iterable<String> albumIds,
  }) async {
    final ids = albumIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (ids.isEmpty) return const [];
    final response = await _client.rpc(
      'get_memory_album_summaries',
      params: {
        'target_couple_id': coupleId,
        'target_album_ids': ids,
      },
    );
    final rows = (response as List)
        .map(
          (row) => MemoryAlbum.fromMap(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList(growable: false);
    return mergeMemoryAlbums(const [], rows);
  }

  Future<MemoryAlbumPhoto> _uploadPhotoRow({
    required String coupleId,
    required String albumId,
    required Uint8List bytes,
    required String extension,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw const AuthException('AUTH_REQUIRED');

    final ext = extension.toLowerCase().replaceAll('.', '');
    final now = DateTime.now().toUtc();
    final path =
        'couples/$coupleId/albums/$albumId/${now.microsecondsSinceEpoch}.$ext';

    await _client.storage.from('memory-album-photos').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: false),
        );

    dynamic row;
    try {
      row = await _client
          .from('memory_album_photos')
          .insert({
            'album_id': albumId,
            'couple_id': coupleId,
            'storage_path': path,
            'uploaded_by': user.id,
          })
          .select('id,album_id,couple_id,storage_path,uploaded_by,created_at')
          .single();
    } catch (_) {
      try {
        await _client.storage.from('memory-album-photos').remove([path]);
      } catch (_) {
        // 원래 insert 오류를 보존한다.
      }
      rethrow;
    }

    await _touchAlbum(albumId);
    return MemoryAlbumPhoto.fromMap(row);
  }

  Future<void> _touchAlbum(String albumId) async {
    try {
      await _client.from('memory_albums').update({
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', albumId);
    } catch (_) {
      // updated_at trigger가 없을 때의 보조 갱신이다. 실패해도 업로드 자체는 유지한다.
    }
  }

  Future<void> _touchAlbums(Iterable<String> albumIds) async {
    final ids = albumIds.toSet();
    for (final albumId in ids) {
      await _touchAlbum(albumId);
    }
  }

  Future<void> _setAlbumCoverPhoto({
    required String albumId,
    required String photoId,
  }) async {
    try {
      await _client.from('memory_albums').update({
        'cover_photo_id': photoId,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', albumId);
    } on PostgrestException catch (error) {
      if (_isMissingCoverColumn(error)) {
        throw StateError('MEMORY_ALBUM_COVER_SCHEMA_REQUIRED');
      }
      rethrow;
    }
  }

  bool _isMissingCoverColumn(PostgrestException error) {
    final message = '${error.message} ${error.details ?? ''}';
    return message.contains('cover_photo_id') ||
        error.code == '42703' ||
        error.code == 'PGRST204';
  }

  bool _isMissingFeaturedColumn(PostgrestException error) {
    final message = '${error.message} ${error.details ?? ''}';
    return message.contains('is_featured') ||
        error.code == '42703' ||
        error.code == 'PGRST204';
  }
}

List<String> _normalizedPhotoIds(Iterable<String> photoIds) {
  return photoIds
      .map((id) => id.trim())
      .where((id) => id.isNotEmpty)
      .toSet()
      .toList(growable: false);
}

Iterable<List<T>> _chunks<T>(List<T> values, int size) sync* {
  for (var start = 0; start < values.length; start += size) {
    final end = (start + size).clamp(0, values.length);
    yield values.sublist(start, end);
  }
}
