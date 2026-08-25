import 'dart:math';
import 'dart:typed_data';

import 'package:couple_chat_app/src/features/travel_map/data/map_query_scope.dart';
import 'package:couple_chat_app/src/features/travel_map/data/map_photo_query.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class WorldCountry {
  const WorldCountry({
    required this.code,
    required this.iso3,
    required this.nameKo,
    required this.nameEn,
    required this.centerLat,
    required this.centerLng,
    required this.sortOrder,
  });

  final String code;
  final String iso3;
  final String nameKo;
  final String nameEn;
  final double centerLat;
  final double centerLng;
  final int sortOrder;

  String get displayName => nameKo.isNotEmpty ? nameKo : nameEn;

  factory WorldCountry.fromMap(Map<String, dynamic> map) {
    double parseDouble(dynamic value) {
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0;
      return 0;
    }

    return WorldCountry(
      code: map['code'] as String,
      iso3: map['iso3'] as String,
      nameKo: map['name_ko'] as String,
      nameEn: map['name_en'] as String,
      centerLat: parseDouble(map['center_lat']),
      centerLng: parseDouble(map['center_lng']),
      sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
    );
  }
}

class WorldCountryVisit {
  const WorldCountryVisit({
    required this.id,
    required this.coupleId,
    required this.countryCode,
    required this.colorHex,
    required this.visitedAt,
    required this.memo,
    required this.updatedBy,
    required this.updatedAt,
  });

  final String id;
  final String coupleId;
  final String countryCode;
  final String colorHex;
  final DateTime? visitedAt;
  final String? memo;
  final String updatedBy;
  final DateTime updatedAt;

  factory WorldCountryVisit.fromMap(Map<String, dynamic> map) {
    return WorldCountryVisit(
      id: map['id'] as String,
      coupleId: map['couple_id'] as String,
      countryCode: map['country_code'] as String,
      colorHex: map['color_hex'] as String,
      visitedAt: map['visited_at'] == null
          ? null
          : DateTime.parse(map['visited_at'] as String),
      memo: map['memo'] as String?,
      updatedBy: map['updated_by'] as String,
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}

class WorldCountryPhoto {
  const WorldCountryPhoto({
    required this.id,
    required this.coupleId,
    required this.countryCode,
    required this.storagePath,
    required this.caption,
    required this.uploadedBy,
    required this.createdAt,
    required this.signedUrl,
  });

  final String id;
  final String coupleId;
  final String countryCode;
  final String storagePath;
  final String? caption;
  final String uploadedBy;
  final DateTime createdAt;
  final String signedUrl;

  factory WorldCountryPhoto.fromMap(
    Map<String, dynamic> map,
    String signedUrl,
  ) {
    return WorldCountryPhoto(
      id: map['id'] as String,
      coupleId: map['couple_id'] as String,
      countryCode: map['country_code'] as String,
      storagePath: map['storage_path'] as String,
      caption: map['caption'] as String?,
      uploadedBy: map['uploaded_by'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      signedUrl: signedUrl,
    );
  }
}

class WorldMapRepository {
  WorldMapRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client {
    _photoUrlCache = MapPhotoSignedUrlCache(
      signer: (path) =>
          _client.storage.from(_photoBucket).createSignedUrl(path, 3600),
    );
  }

  final SupabaseClient _client;
  late final MapPhotoSignedUrlCache _photoUrlCache;
  static const String _photoBucket = 'world-country-photos';

  Future<List<WorldCountry>> fetchCountries() async {
    final rows = await _client
        .from('world_countries')
        .select('code,iso3,name_ko,name_en,center_lat,center_lng,sort_order')
        .order('sort_order') as List;
    return rows
        .map((row) =>
            WorldCountry.fromMap(Map<String, dynamic>.from(row as Map)))
        .toList(growable: false);
  }

  Stream<List<WorldCountryVisit>> watchVisits(String coupleId) {
    final scope = coupleScopedMapQuery(coupleId);
    return _client
        .from('world_country_visits')
        .stream(primaryKey: ['id'])
        .eq(CoupleScopedMapQuery.column, scope.value)
        .order('updated_at')
        .map(
          (rows) => rows
              .map(
                (row) => WorldCountryVisit.fromMap(
                  Map<String, dynamic>.from(row),
                ),
              )
              .toList(growable: false),
        );
  }

  Future<void> upsertVisit({
    required String coupleId,
    required String countryCode,
    required String colorHex,
    DateTime? visitedAt,
    String? memo,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw const AuthException('AUTH_REQUIRED');
    await _client.from('world_country_visits').upsert(
      {
        'couple_id': coupleId,
        'country_code': countryCode,
        'color_hex': colorHex,
        'visited_at': visitedAt?.toIso8601String().split('T').first,
        'memo': memo,
        'updated_by': userId,
      },
      onConflict: 'couple_id,country_code',
    );
  }

  Future<void> deleteVisit(
      {required String coupleId, required String countryCode}) async {
    await _client
        .from('world_country_visits')
        .delete()
        .eq('couple_id', coupleId)
        .eq('country_code', countryCode);
  }

  Stream<List<WorldCountryPhoto>> watchCountryPhotos({
    required String coupleId,
    required String countryCode,
  }) {
    final scope = mapPhotoQueryScope(
      coupleId: coupleId,
      placeId: countryCode,
    );
    return _client
        .from('world_country_photos')
        .stream(primaryKey: ['id'])
        .eq(MapPhotoQueryScope.column, scope.value)
        .order('created_at', ascending: false)
        .limit(scope.limit)
        .asyncMap((rows) async {
          final photos = <WorldCountryPhoto>[];
          for (final row in rows) {
            final map = Map<String, dynamic>.from(row);
            final storagePath = map['storage_path'] as String;
            final signedUrl = await _photoUrlCache.resolve(storagePath);
            photos.add(WorldCountryPhoto.fromMap(map, signedUrl));
          }
          return photos;
        });
  }

  Future<void> uploadCountryPhoto({
    required String coupleId,
    required String countryCode,
    required Uint8List bytes,
    required String extension,
    String? caption,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw const AuthException('AUTH_REQUIRED');

    final normalizedExtension = extension.trim().toLowerCase();
    final safeExtension = normalizedExtension.isEmpty
        ? 'jpg'
        : normalizedExtension.replaceAll(RegExp('[^a-z0-9]'), '');
    final randomPart = Random().nextInt(1 << 30);
    final photoId = '${DateTime.now().microsecondsSinceEpoch}_$randomPart';
    final path =
        'couples/$coupleId/countries/$countryCode/$photoId.${safeExtension.isEmpty ? 'jpg' : safeExtension}';

    await _client.storage.from(_photoBucket).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: false),
        );
    try {
      await _client.from('world_country_photos').insert({
        'couple_id': coupleId,
        'country_code': countryCode,
        'storage_path': path,
        'caption': caption,
        'uploaded_by': userId,
      });
    } catch (error, stackTrace) {
      try {
        await _client.storage.from(_photoBucket).remove([path]);
      } catch (_) {
        // Preserve the database error that caused the rollback.
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> deleteCountryPhoto(WorldCountryPhoto photo) async {
    final deletedRows = await _client
        .from('world_country_photos')
        .delete()
        .eq(CoupleScopedMapQuery.column, photo.coupleId)
        .eq('country_code', photo.countryCode)
        .eq('id', photo.id)
        .select('id') as List;
    if (deletedRows.isEmpty) {
      throw StateError('MAP_PHOTO_DELETE_NOT_ALLOWED');
    }
    await _client.storage.from(_photoBucket).remove([photo.storagePath]);
    _photoUrlCache.remove(photo.storagePath);
  }
}
