String? sanitizeNotificationRoute(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final uri = Uri.tryParse(value.trim());
  if (uri == null || uri.hasScheme || uri.hasAuthority) return null;
  final path = uri.path;
  final allowed = path == '/anniversary-reminders' ||
      path.startsWith('/chat/') ||
      path.startsWith('/omok/');
  return allowed ? uri.toString() : null;
}
