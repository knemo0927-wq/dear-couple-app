bool isValidCoupleId(String value) {
  final v = value.trim();
  if (v.isEmpty) return false;

  final uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  );
  return uuid.hasMatch(v);
}

String resolvePostLoginDestination(String? from) {
  if (from == null || from.isEmpty) return '/';
  if (!from.startsWith('/')) return '/';
  return from;
}

String? resolveTopLevelRedirect({
  required bool hasSupabaseConfig,
  required bool hasSession,
  required String location,
  required bool hasAuthError,
}) {
  if (!hasSupabaseConfig) {
    return location == '/setup' ? null : '/setup';
  }

  if (hasAuthError) {
    return location == '/offline' ? null : '/offline';
  }

  if (!hasSession) {
    if (location == '/auth' || location == '/onboarding') return null;
    return '/auth?from=${Uri.encodeComponent(location)}';
  }

  if (location == '/auth' ||
      location == '/onboarding' ||
      location == '/setup' ||
      location == '/offline') {
    return '/';
  }

  return null;
}
