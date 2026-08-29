import 'dart:async';

import 'package:couple_chat_app/src/app_router.dart';
import 'package:couple_chat_app/src/common/dear_connection_banner.dart';
import 'package:couple_chat_app/src/common/app_theme.dart';
import 'package:couple_chat_app/src/features/auth/data/auth_providers.dart';
import 'package:couple_chat_app/src/features/notifications/data/notification_route.dart';
import 'package:couple_chat_app/src/features/settings/data/theme_mode_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

class CoupleChatApp extends ConsumerStatefulWidget {
  const CoupleChatApp({super.key});

  @override
  ConsumerState<CoupleChatApp> createState() => _CoupleChatAppState();
}

class _CoupleChatAppState extends ConsumerState<CoupleChatApp>
    with WidgetsBindingObserver {
  StreamSubscription<RemoteMessage>? _openedSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<List<Map<String, dynamic>>>? _inviteSub;
  ProviderSubscription<AsyncValue<Session?>>? _sessionSub;
  bool _checkedInitialMessage = false;
  String? _pendingRoute;
  String? _currentInviteUserId;
  final Set<String> _shownInviteIds = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sessionSub =
        ref.listenManual<AsyncValue<Session?>>(authSessionProvider, (_, next) {
      final userId = next.valueOrNull?.user.id;
      _syncInviteStream(userId);
      if (userId != null) {
        _checkLatestPendingInvite(userId, navigate: true);
      }
    });
    _syncInviteStream(ref.read(authSessionProvider).valueOrNull?.user.id);

    try {
      _openedSub =
          FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpened);
      _foregroundSub =
          FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    } catch (_) {
      // Firebase unavailable in local/CI runtimes.
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_checkedInitialMessage) return;
    _checkedInitialMessage = true;
    _handleInitialMessage();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final userId = ref.read(authSessionProvider).valueOrNull?.user.id;
    if (userId != null) {
      _checkLatestPendingInvite(userId, navigate: true);
    }
  }

  Future<void> _handleInitialMessage() async {
    try {
      final message = await FirebaseMessaging.instance.getInitialMessage();
      if (message == null) return;
      _handleMessageOpened(message);
    } catch (_) {
      // Firebase unavailable in local/CI runtimes.
    }
  }

  void _syncInviteStream(String? userId) {
    if (_currentInviteUserId == userId) return;
    _currentInviteUserId = userId;
    unawaited(_inviteSub?.cancel());
    _inviteSub = null;
    if (userId == null) return;

    try {
      _inviteSub = Supabase.instance.client
          .from('omok_invites')
          .stream(primaryKey: ['id'])
          .eq('recipient_user_id', userId)
          .listen(_handleInviteRows);
    } catch (_) {
      // Supabase unavailable in local/CI runtimes.
    }
  }

  void _handleInviteRows(List<Map<String, dynamic>> rows) {
    final now = DateTime.now().toUtc();
    final pending = rows.where((row) {
      if (row['invite_type'] != 'push' || row['status'] != 'open') return false;
      final expiresRaw = row['expires_at'] as String?;
      if (expiresRaw == null) return false;
      return DateTime.parse(expiresRaw).isAfter(now);
    }).toList(growable: false)
      ..sort((a, b) =>
          (a['created_at'] as String).compareTo(b['created_at'] as String));

    if (pending.isEmpty) return;
    final latest = pending.last;
    final inviteId = latest['id'] as String?;
    if (inviteId == null || _shownInviteIds.contains(inviteId)) return;
    _shownInviteIds.add(inviteId);
    _showPushSnackBar(
      route: '/omok/invite/$inviteId',
      message: '오목 대결 신청이 도착했어요.',
      actionLabel: '입장',
    );
  }

  Future<void> _checkLatestPendingInvite(String userId,
      {required bool navigate}) async {
    try {
      final rows = await Supabase.instance.client
          .from('omok_invites')
          .select('id,expires_at,created_at')
          .eq('recipient_user_id', userId)
          .eq('invite_type', 'push')
          .eq('status', 'open')
          .gt('expires_at', DateTime.now().toUtc().toIso8601String())
          .order('created_at', ascending: false)
          .limit(1);
      if (rows.isEmpty) return;
      final inviteId = rows.first['id'] as String?;
      if (inviteId == null) return;
      final route = '/omok/invite/$inviteId';
      if (navigate) {
        _navigateWhenSessionReady(route);
      } else if (!_shownInviteIds.contains(inviteId)) {
        _shownInviteIds.add(inviteId);
        _showPushSnackBar(
          route: route,
          message: '오목 대결 신청이 도착했어요.',
          actionLabel: '입장',
        );
      }
    } catch (_) {
      // Ignore best-effort resume check failures.
    }
  }

  String? _routeFromMessage(RemoteMessage message) {
    final data = message.data;
    final eventType = data['eventType'];
    String? route;
    if (eventType == 'omok_invite_created') {
      final inviteId = data['inviteId'];
      if (inviteId != null && inviteId.isNotEmpty) {
        route = '/omok/invite/$inviteId';
      }
    }
    route ??= data['route'];
    return sanitizeNotificationRoute(route);
  }

  void _handleMessageOpened(RemoteMessage message) {
    final route = _routeFromMessage(message);
    if (route == null) return;
    _navigateWhenSessionReady(route);
  }

  void _handleForegroundMessage(RemoteMessage message) {
    final route = _routeFromMessage(message);
    if (route == null) return;
    _showPushSnackBar(
      route: route,
      message: _foregroundMessageText(message),
      actionLabel: '보기',
    );
  }

  String _foregroundMessageText(RemoteMessage message) {
    final eventType = message.data['eventType'] ?? message.data['type'];
    if (eventType == 'anniversary_congratulation') {
      final eventTitle = message.data['eventTitle'];
      if (eventTitle is String && eventTitle.isNotEmpty) {
        return '오늘은 $eventTitle 기념일이에요.';
      }
      return '오늘은 기념일이에요.';
    }
    return message.notification?.title ?? '새 알림이 도착했어요.';
  }

  void _showPushSnackBar({
    required String route,
    required String message,
    required String actionLabel,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      final messenger = rootScaffoldMessengerKey.currentState;
      if (messenger == null) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: actionLabel,
            onPressed: () => _navigateWhenSessionReady(route),
          ),
        ),
      );
    });
  }

  void _navigateWhenSessionReady(String route) {
    _pendingRoute = route;
    _tryConsumePendingRoute();
    Future<void>.delayed(
        const Duration(milliseconds: 700), _tryConsumePendingRoute);
    Future<void>.delayed(const Duration(seconds: 2), _tryConsumePendingRoute);
  }

  void _tryConsumePendingRoute() {
    final route = _pendingRoute;
    if (!mounted || route == null) return;

    final hasSession = ref.read(hasSessionStateProvider).valueOrNull ?? false;
    if (!hasSession) return;

    _pendingRoute = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(goRouterProvider).go(route);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sessionSub?.close();
    unawaited(_openedSub?.cancel());
    unawaited(_foregroundSub?.cancel());
    unawaited(_inviteSub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(goRouterProvider);
    final themeMode = ref.watch(
      themeModeControllerProvider.select((state) => state.mode),
    );

    ref.listen<AsyncValue<bool>>(hasSessionStateProvider, (previous, next) {
      if (next.valueOrNull == true) {
        _tryConsumePendingRoute();
      }
    });

    return MaterialApp.router(
      title: 'Dear',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      routerConfig: router,
      builder: (context, child) => DearConnectionBanner(child: child!),
    );
  }
}
