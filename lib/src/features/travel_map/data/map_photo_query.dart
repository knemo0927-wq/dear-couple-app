const int mapPhotoHeadLimit = 12;

class MapPhotoQueryScope {
  const MapPhotoQueryScope._(this.value);

  static const String column = 'realtime_scope';

  final String value;
  int get limit => mapPhotoHeadLimit;
}

MapPhotoQueryScope mapPhotoQueryScope({
  required String coupleId,
  required String placeId,
}) {
  final normalizedCoupleId = coupleId.trim();
  final normalizedPlaceId = placeId.trim();
  if (normalizedCoupleId.isEmpty) {
    throw ArgumentError.value(coupleId, 'coupleId', 'must not be empty');
  }
  if (normalizedPlaceId.isEmpty) {
    throw ArgumentError.value(placeId, 'placeId', 'must not be empty');
  }
  return MapPhotoQueryScope._('$normalizedCoupleId:$normalizedPlaceId');
}

typedef MapPhotoUrlSigner = Future<String> Function(String storagePath);
typedef MapPhotoClock = DateTime Function();

class MapPhotoSignedUrlCache {
  MapPhotoSignedUrlCache({
    required MapPhotoUrlSigner signer,
    MapPhotoClock? clock,
    this.validFor = const Duration(hours: 1),
    this.refreshBefore = const Duration(minutes: 5),
  })  : _signer = signer,
        _clock = clock ?? DateTime.now;

  final MapPhotoUrlSigner _signer;
  final MapPhotoClock _clock;
  final Duration validFor;
  final Duration refreshBefore;
  final Map<String, _CachedSignedUrl> _entries = {};

  Future<String> resolve(String storagePath) async {
    final now = _clock();
    final cached = _entries[storagePath];
    if (cached != null && cached.expiresAt.difference(now) > refreshBefore) {
      return cached.url;
    }

    final url = await _signer(storagePath);
    _entries[storagePath] = _CachedSignedUrl(
      url: url,
      expiresAt: now.add(validFor),
    );
    return url;
  }

  void remove(String storagePath) => _entries.remove(storagePath);
}

class _CachedSignedUrl {
  const _CachedSignedUrl({required this.url, required this.expiresAt});

  final String url;
  final DateTime expiresAt;
}
