class CoupleScopedMapQuery {
  const CoupleScopedMapQuery._(this.value);

  static const String column = 'couple_id';

  final String value;
}

CoupleScopedMapQuery coupleScopedMapQuery(String coupleId) {
  final normalized = coupleId.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(coupleId, 'coupleId', 'must not be empty');
  }
  return CoupleScopedMapQuery._(normalized);
}
