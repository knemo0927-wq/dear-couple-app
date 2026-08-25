import 'dart:typed_data';

import 'package:couple_chat_app/src/features/travel_map/data/travel_map_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef UpsertTravelVisitAction = Future<void> Function({
  required String coupleId,
  required String cityId,
  required String colorHex,
  DateTime? visitedAt,
  String? memo,
});

typedef DeleteTravelVisitAction = Future<void> Function({
  required String coupleId,
  required String cityId,
});

typedef UploadTravelCityPhotoAction = Future<void> Function({
  required String coupleId,
  required String cityId,
  required Uint8List bytes,
  required String extension,
  String? caption,
});

typedef DeleteTravelCityPhotoAction = Future<void> Function(
    TravelCityPhoto photo);

final travelMapRepositoryProvider = Provider<TravelMapRepository>((ref) {
  return TravelMapRepository();
});

final travelCitiesProvider = FutureProvider<List<TravelCity>>((ref) {
  return ref.watch(travelMapRepositoryProvider).fetchCities();
});

final travelCityVisitsProvider =
    StreamProvider.family<List<TravelCityVisit>, String>((ref, coupleId) {
  return ref.watch(travelMapRepositoryProvider).watchVisits(coupleId);
});

final upsertTravelVisitProvider = Provider<UpsertTravelVisitAction>((ref) {
  final repository = ref.watch(travelMapRepositoryProvider);
  return ({
    required coupleId,
    required cityId,
    required colorHex,
    visitedAt,
    memo,
  }) {
    return repository.upsertVisit(
      coupleId: coupleId,
      cityId: cityId,
      colorHex: colorHex,
      visitedAt: visitedAt,
      memo: memo,
    );
  };
});

final deleteTravelVisitProvider = Provider<DeleteTravelVisitAction>((ref) {
  final repository = ref.watch(travelMapRepositoryProvider);
  return ({required coupleId, required cityId}) {
    return repository.deleteVisit(
      coupleId: coupleId,
      cityId: cityId,
    );
  };
});

final selectedTravelPaletteColorProvider =
    StateProvider<String>((ref) => '#E678A9');

final travelCityPhotosProvider = StreamProvider.family<List<TravelCityPhoto>,
    ({String coupleId, String cityId})>((ref, args) {
  return ref.watch(travelMapRepositoryProvider).watchCityPhotos(
        coupleId: args.coupleId,
        cityId: args.cityId,
      );
});

final uploadTravelCityPhotoProvider =
    Provider<UploadTravelCityPhotoAction>((ref) {
  final repository = ref.watch(travelMapRepositoryProvider);
  return ({
    required coupleId,
    required cityId,
    required bytes,
    required extension,
    caption,
  }) {
    return repository.uploadCityPhoto(
      coupleId: coupleId,
      cityId: cityId,
      bytes: bytes,
      extension: extension,
      caption: caption,
    );
  };
});

final deleteTravelCityPhotoProvider =
    Provider<DeleteTravelCityPhotoAction>((ref) {
  final repository = ref.watch(travelMapRepositoryProvider);
  return repository.deleteCityPhoto;
});
