import 'dart:typed_data';

import 'package:couple_chat_app/src/features/world_map/data/world_map_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef UpsertWorldVisitAction = Future<void> Function({
  required String coupleId,
  required String countryCode,
  required String colorHex,
  DateTime? visitedAt,
  String? memo,
});

typedef DeleteWorldVisitAction = Future<void> Function({
  required String coupleId,
  required String countryCode,
});

typedef UploadWorldCountryPhotoAction = Future<void> Function({
  required String coupleId,
  required String countryCode,
  required Uint8List bytes,
  required String extension,
  String? caption,
});

typedef DeleteWorldCountryPhotoAction = Future<void> Function(
  WorldCountryPhoto photo,
);

final worldMapRepositoryProvider = Provider<WorldMapRepository>((ref) {
  return WorldMapRepository();
});

final worldCountriesProvider = FutureProvider<List<WorldCountry>>((ref) {
  return ref.watch(worldMapRepositoryProvider).fetchCountries();
});

final worldCountryVisitsProvider =
    StreamProvider.family<List<WorldCountryVisit>, String>((ref, coupleId) {
  return ref.watch(worldMapRepositoryProvider).watchVisits(coupleId);
});

final selectedWorldPaletteColorProvider =
    StateProvider<String>((ref) => '#E678A9');

final upsertWorldVisitProvider = Provider<UpsertWorldVisitAction>((ref) {
  final repository = ref.watch(worldMapRepositoryProvider);
  return ({
    required coupleId,
    required countryCode,
    required colorHex,
    visitedAt,
    memo,
  }) {
    return repository.upsertVisit(
      coupleId: coupleId,
      countryCode: countryCode,
      colorHex: colorHex,
      visitedAt: visitedAt,
      memo: memo,
    );
  };
});

final deleteWorldVisitProvider = Provider<DeleteWorldVisitAction>((ref) {
  final repository = ref.watch(worldMapRepositoryProvider);
  return ({required coupleId, required countryCode}) {
    return repository.deleteVisit(
      coupleId: coupleId,
      countryCode: countryCode,
    );
  };
});

final worldCountryPhotosProvider = StreamProvider.family<
    List<WorldCountryPhoto>,
    ({String coupleId, String countryCode})>((ref, args) {
  return ref.watch(worldMapRepositoryProvider).watchCountryPhotos(
        coupleId: args.coupleId,
        countryCode: args.countryCode,
      );
});

final uploadWorldCountryPhotoProvider =
    Provider<UploadWorldCountryPhotoAction>((ref) {
  final repository = ref.watch(worldMapRepositoryProvider);
  return ({
    required coupleId,
    required countryCode,
    required bytes,
    required extension,
    caption,
  }) {
    return repository.uploadCountryPhoto(
      coupleId: coupleId,
      countryCode: countryCode,
      bytes: bytes,
      extension: extension,
      caption: caption,
    );
  };
});

final deleteWorldCountryPhotoProvider =
    Provider<DeleteWorldCountryPhotoAction>((ref) {
  final repository = ref.watch(worldMapRepositoryProvider);
  return repository.deleteCountryPhoto;
});
