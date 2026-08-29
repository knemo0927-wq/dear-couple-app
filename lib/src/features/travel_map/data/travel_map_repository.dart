import 'dart:developer' as developer;
import 'dart:math';
import 'dart:typed_data';

import 'package:couple_chat_app/src/features/travel_map/data/map_query_scope.dart';
import 'package:couple_chat_app/src/features/travel_map/data/map_photo_query.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TravelCity {
  const TravelCity({
    required this.id,
    required this.code,
    required this.name,
    required this.regionGroup,
    required this.centerLat,
    required this.centerLng,
    required this.sortOrder,
  });

  final String id;
  final String code;
  final String name;
  final String regionGroup;
  final double centerLat;
  final double centerLng;
  final int sortOrder;

  factory TravelCity.fromMap(Map<String, dynamic> map) {
    double parseDouble(dynamic value) {
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0;
      return 0;
    }

    return TravelCity(
      id: map['id'] as String,
      code: map['code'] as String,
      name: map['name'] as String,
      regionGroup: map['region_group'] as String,
      centerLat: parseDouble(map['center_lat']),
      centerLng: parseDouble(map['center_lng']),
      sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
    );
  }
}

class TravelCityVisit {
  const TravelCityVisit({
    required this.id,
    required this.coupleId,
    required this.cityId,
    required this.colorHex,
    required this.visitedAt,
    required this.memo,
    required this.updatedBy,
    required this.updatedAt,
  });

  final String id;
  final String coupleId;
  final String cityId;
  final String colorHex;
  final DateTime? visitedAt;
  final String? memo;
  final String updatedBy;
  final DateTime updatedAt;

  factory TravelCityVisit.fromMap(Map<String, dynamic> map) {
    return TravelCityVisit(
      id: map['id'] as String,
      coupleId: map['couple_id'] as String,
      cityId: map['city_id'] as String,
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

class TravelCityPhoto {
  const TravelCityPhoto({
    required this.id,
    required this.coupleId,
    required this.cityId,
    required this.storagePath,
    required this.caption,
    required this.uploadedBy,
    required this.createdAt,
    required this.signedUrl,
  });

  final String id;
  final String coupleId;
  final String cityId;
  final String storagePath;
  final String? caption;
  final String uploadedBy;
  final DateTime createdAt;
  final String? signedUrl;

  factory TravelCityPhoto.fromMap(
    Map<String, dynamic> map,
    String? signedUrl,
  ) {
    return TravelCityPhoto(
      id: map['id'] as String,
      coupleId: map['couple_id'] as String,
      cityId: map['city_id'] as String,
      storagePath: map['storage_path'] as String,
      caption: map['caption'] as String?,
      uploadedBy: map['uploaded_by'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      signedUrl: signedUrl,
    );
  }
}

typedef TravelCityPhotoSignFailureHandler = void Function(
  Object error,
  StackTrace stackTrace,
);

Future<List<TravelCityPhoto>> resolveTravelCityPhotoRows(
  Iterable<Map<String, dynamic>> rows, {
  required MapPhotoUrlSigner signer,
  TravelCityPhotoSignFailureHandler? onSignFailure,
}) async {
  final result = <TravelCityPhoto>[];
  for (final map in rows) {
    final path = map['storage_path'] as String;
    String? signedUrl;
    try {
      signedUrl = await signer(path);
    } on Exception catch (error, stackTrace) {
      onSignFailure?.call(error, stackTrace);
    }
    result.add(TravelCityPhoto.fromMap(map, signedUrl));
  }
  return result;
}

class TravelMapRepository {
  TravelMapRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client {
    _photoUrlCache = MapPhotoSignedUrlCache(
      signer: (path) =>
          _client.storage.from(_photoBucket).createSignedUrl(path, 3600),
    );
  }

  final SupabaseClient _client;
  late final MapPhotoSignedUrlCache _photoUrlCache;
  static const String _photoBucket = 'travel-city-photos';

  Future<List<TravelCity>> fetchCities() async {
    final rows = await _client
        .from('travel_cities')
        .select('id,code,name,region_group,center_lat,center_lng,sort_order')
        .order('sort_order') as List;

    return rows
        .map((row) => TravelCity.fromMap(Map<String, dynamic>.from(row as Map)))
        .toList(growable: false);
  }

  Stream<List<TravelCityVisit>> watchVisits(String coupleId) {
    final scope = coupleScopedMapQuery(coupleId);
    return _client
        .from('travel_city_visits')
        .stream(primaryKey: ['id'])
        .eq(CoupleScopedMapQuery.column, scope.value)
        .order('updated_at')
        .map(
          (rows) => rows
              .map(
                (row) => TravelCityVisit.fromMap(
                  Map<String, dynamic>.from(row),
                ),
              )
              .toList(growable: false),
        );
  }

  Future<void> upsertVisit({
    required String coupleId,
    required String cityId,
    required String colorHex,
    DateTime? visitedAt,
    String? memo,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw const AuthException('AUTH_REQUIRED');
    }

    await _client.from('travel_city_visits').upsert(
      {
        'couple_id': coupleId,
        'city_id': cityId,
        'color_hex': colorHex,
        'visited_at': visitedAt?.toIso8601String().split('T').first,
        'memo': memo,
        'updated_by': userId,
      },
      onConflict: 'couple_id,city_id',
    );
  }

  Future<void> deleteVisit({
    required String coupleId,
    required String cityId,
  }) async {
    await _client
        .from('travel_city_visits')
        .delete()
        .eq('couple_id', coupleId)
        .eq('city_id', cityId);
  }

  Stream<List<TravelCityPhoto>> watchCityPhotos({
    required String coupleId,
    required String cityId,
  }) async* {
    final scope = mapPhotoQueryScope(
      coupleId: coupleId,
      placeId: cityId,
    );
    final source = _client
        .from('travel_city_photos')
        .stream(primaryKey: ['id'])
        .eq(MapPhotoQueryScope.column, scope.value)
        .order('created_at', ascending: false)
        .limit(scope.limit);

    try {
      await for (final rows in source) {
        yield await resolveTravelCityPhotoRows(
          rows.map(Map<String, dynamic>.from),
          signer: _photoUrlCache.resolve,
          onSignFailure: (error, stackTrace) {
            developer.log(
              'Failed to create a travel photo signed URL.',
              name: 'dear.travel_map.photos',
              error: error,
              stackTrace: stackTrace,
            );
          },
        );
      }
    } catch (error, stackTrace) {
      developer.log(
        'Failed to load the travel city photo stream.',
        name: 'dear.travel_map.photos',
        error: error,
        stackTrace: stackTrace,
      );
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> uploadCityPhoto({
    required String coupleId,
    required String cityId,
    required Uint8List bytes,
    required String extension,
    String? caption,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw const AuthException('AUTH_REQUIRED');
    }

    final normalizedExt = extension.trim().toLowerCase();
    final sanitizedExt = normalizedExt.replaceAll(RegExp('[^a-z0-9]'), '');
    final safeExt = sanitizedExt.isEmpty ? 'jpg' : sanitizedExt;
    final random = Random().nextInt(1 << 30);
    final photoId = '${DateTime.now().microsecondsSinceEpoch}_$random';
    final path = 'couples/$coupleId/cities/$cityId/$photoId.$safeExt';

    await _client.storage.from(_photoBucket).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: false),
        );

    try {
      await _client.from('travel_city_photos').insert({
        'couple_id': coupleId,
        'city_id': cityId,
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

  Future<void> deleteCityPhoto(TravelCityPhoto photo) async {
    final deletedRows = await _client
        .from('travel_city_photos')
        .delete()
        .eq(CoupleScopedMapQuery.column, photo.coupleId)
        .eq('city_id', photo.cityId)
        .eq('id', photo.id)
        .select('id') as List;
    if (deletedRows.isEmpty) {
      throw StateError('MAP_PHOTO_DELETE_NOT_ALLOWED');
    }
    await _client.storage.from(_photoBucket).remove([photo.storagePath]);
    _photoUrlCache.remove(photo.storagePath);
  }
}
