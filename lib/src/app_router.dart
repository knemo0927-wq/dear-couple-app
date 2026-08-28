import 'package:couple_chat_app/src/config/app_config_provider.dart';
import 'package:couple_chat_app/src/common/dear_main_tab_nav.dart';
import 'package:couple_chat_app/src/features/auth/data/auth_providers.dart';
import 'package:couple_chat_app/src/features/auth/presentation/auth_gate.dart';
import 'package:couple_chat_app/src/features/auth/presentation/password_recovery_page.dart';
import 'package:couple_chat_app/src/features/anniversary/presentation/anniversary_reminder_page.dart';
import 'package:couple_chat_app/src/features/chat/presentation/chat_access_guard_page.dart';
import 'package:couple_chat_app/src/features/chat/presentation/chat_list_page.dart';
import 'package:couple_chat_app/src/features/chat/presentation/memory_album_page.dart';
import 'package:couple_chat_app/src/features/mini_games/presentation/mini_games_page.dart';
import 'package:couple_chat_app/src/features/mini_games/presentation/omok_game_page.dart';
import 'package:couple_chat_app/src/features/notifications/presentation/notification_inbox_page.dart';
import 'package:couple_chat_app/src/features/travel_map/presentation/travel_city_detail_page.dart';
import 'package:couple_chat_app/src/features/travel_map/presentation/travel_map_page.dart';
import 'package:couple_chat_app/src/features/world_map/presentation/world_country_detail_page.dart';
import 'package:couple_chat_app/src/features/world_map/presentation/world_map_page.dart';
import 'package:couple_chat_app/src/features/onboarding/presentation/onboarding_page.dart';
import 'package:couple_chat_app/src/features/settings/presentation/notification_settings_page.dart';
import 'package:couple_chat_app/src/features/settings/presentation/profile_settings_page.dart';
import 'package:couple_chat_app/src/routing/route_guard.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final routerInitialLocationProvider = Provider<String>((ref) => '/');

final goRouterProvider = Provider<GoRouter>((ref) {
  final config = ref.watch(appConfigProvider);
  final initialLocation = ref.watch(routerInitialLocationProvider);
  final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
  final homeNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'home');
  final albumNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'album');
  final moreNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'more');

  final hasSessionState = config.hasSupabaseConfig
      ? ref.watch(hasSessionStateProvider)
      : const AsyncValue<bool>.data(false);
  final passwordRecoveryState = config.hasSupabaseConfig
      ? ref.watch(authPasswordRecoveryProvider)
      : const AsyncValue<bool>.data(false);

  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: initialLocation,
    redirect: (context, state) {
      if (passwordRecoveryState.valueOrNull == true &&
          state.uri.path != '/reset-password') {
        return '/reset-password';
      }
      final hasSession = hasSessionState.valueOrNull ?? false;
      final hasAuthError = hasSessionState.hasError;

      return resolveTopLevelRedirect(
        hasSupabaseConfig: config.hasSupabaseConfig,
        hasSession: hasSession,
        hasAuthError: hasAuthError,
        location: state.uri.path,
      );
    },
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const PairingPage(),
      ),
      GoRoute(
        path: '/setup',
        builder: (context, state) => const SetupRequiredPage(),
      ),
      GoRoute(
        path: '/offline',
        builder: (context, state) => const OfflineFallbackPage(),
      ),
      GoRoute(
        path: '/auth',
        builder: (context, state) => const AuthPage(),
      ),
      GoRoute(
        path: '/reset-password',
        pageBuilder: (context, state) => buildDearAdaptivePage(
          context: context,
          key: state.pageKey,
          child: const PasswordRecoveryPage(),
        ),
      ),
      GoRoute(
        path: '/onboarding',
        pageBuilder: (context, state) => buildDearAdaptivePage(
          context: context,
          key: state.pageKey,
          child: const OnboardingPage(),
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => DearMainTabShell(
          navigationShell: navigationShell,
        ),
        branches: [
          StatefulShellBranch(
            navigatorKey: homeNavigatorKey,
            routes: [
              GoRoute(
                path: '/chat-list',
                pageBuilder: (context, state) => NoTransitionPage<void>(
                  key: state.pageKey,
                  child: const ChatListPage(),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: albumNavigatorKey,
            routes: [
              GoRoute(
                path: '/memory-album',
                pageBuilder: (context, state) => NoTransitionPage<void>(
                  key: state.pageKey,
                  child: const MemoryAlbumPage(),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: moreNavigatorKey,
            routes: [
              GoRoute(
                path: '/profile',
                pageBuilder: (context, state) => NoTransitionPage<void>(
                  key: state.pageKey,
                  child: const ProfileSettingsPage(),
                ),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/profile/edit',
        pageBuilder: (context, state) => buildDearAdaptivePage(
          context: context,
          key: state.pageKey,
          child: const ProfileEditPage(),
        ),
      ),
      GoRoute(
        path: '/notifications',
        pageBuilder: (context, state) => buildDearAdaptivePage(
          context: context,
          key: state.pageKey,
          child: const NotificationSettingsPage(),
        ),
      ),
      GoRoute(
        path: '/notification-inbox',
        pageBuilder: (context, state) => buildDearAdaptivePage(
          context: context,
          key: state.pageKey,
          child: const NotificationInboxPage(),
        ),
      ),
      GoRoute(
        path: '/anniversary-reminders',
        pageBuilder: (context, state) => buildDearAdaptivePage(
          context: context,
          key: state.pageKey,
          child: AnniversaryReminderPage(
            initialEntryId: state.uri.queryParameters['item'],
          ),
        ),
      ),
      GoRoute(
        path: '/anniversary-reminders/all',
        pageBuilder: (context, state) => buildDearAdaptivePage(
          context: context,
          key: state.pageKey,
          child: const AnniversaryFullListPage(),
        ),
      ),
      GoRoute(
        path: '/mini-games',
        pageBuilder: (context, state) => buildDearAdaptivePage(
          context: context,
          key: state.pageKey,
          child: const MiniGamesPage(),
        ),
      ),
      GoRoute(
        path: '/travel-map',
        pageBuilder: (context, state) => buildDearAdaptivePage(
          context: context,
          key: state.pageKey,
          child: const TravelMapPage(),
        ),
      ),
      GoRoute(
        path: '/travel-map/city/:cityId',
        pageBuilder: (context, state) => buildDearAdaptivePage(
          context: context,
          key: state.pageKey,
          child: TravelCityDetailPage(
              cityId: state.pathParameters['cityId'] ?? ''),
        ),
      ),
      GoRoute(
        path: '/world-map',
        pageBuilder: (context, state) => buildDearAdaptivePage(
          context: context,
          key: state.pageKey,
          child: const WorldMapPage(),
        ),
      ),
      GoRoute(
        path: '/world-map/country/:countryCode',
        pageBuilder: (context, state) => buildDearAdaptivePage(
          context: context,
          key: state.pageKey,
          child: WorldCountryDetailPage(
              countryCode: state.pathParameters['countryCode'] ?? ''),
        ),
      ),
      GoRoute(
        path: '/omok-wait/:inviteId',
        pageBuilder: (context, state) => buildDearAdaptivePage(
          context: context,
          key: state.pageKey,
          child: OmokInviteWaitPage(
            inviteId: state.pathParameters['inviteId'] ?? '',
            mode: state.uri.queryParameters['mode'],
          ),
        ),
      ),
      GoRoute(
        path: '/omok/invite/:inviteId',
        pageBuilder: (context, state) => buildDearAdaptivePage(
          context: context,
          key: state.pageKey,
          child: OmokInviteAcceptPage(
              inviteId: state.pathParameters['inviteId'] ?? ''),
        ),
      ),
      GoRoute(
        path: '/omok/:sessionId',
        pageBuilder: (context, state) => buildDearAdaptivePage(
          context: context,
          key: state.pageKey,
          child:
              OmokGamePage(sessionId: state.pathParameters['sessionId'] ?? ''),
        ),
      ),
      GoRoute(
        path: '/chat/:coupleId',
        builder: (context, state) {
          final coupleId = state.pathParameters['coupleId'];
          if (coupleId == null || !isValidCoupleId(coupleId)) {
            return const InvalidChatLinkPage();
          }
          return ChatAccessGuardPage(coupleId: coupleId);
        },
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

Page<void> buildDearAdaptivePage({
  required BuildContext context,
  required LocalKey key,
  required Widget child,
}) {
  if (MediaQuery.disableAnimationsOf(context)) {
    return NoTransitionPage<void>(key: key, child: child);
  }

  final platform = Theme.of(context).platform;
  if (platform == TargetPlatform.iOS || platform == TargetPlatform.macOS) {
    return CupertinoPage<void>(key: key, child: child);
  }
  return MaterialPage<void>(
    key: key,
    child: child,
  );
}

class SetupRequiredPage extends StatelessWidget {
  const SetupRequiredPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dear')),
      body: const Center(
        child: Text('SUPABASE_URL / SUPABASE_ANON_KEY를 dart-define으로 주입하세요'),
      ),
    );
  }
}

class OfflineFallbackPage extends StatelessWidget {
  const OfflineFallbackPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('오프라인 상태')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('네트워크 또는 인증 서버 상태를 확인해 주세요.'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => context.go('/'),
              child: const Text('다시 시도'),
            ),
          ],
        ),
      ),
    );
  }
}

class InvalidChatLinkPage extends StatelessWidget {
  const InvalidChatLinkPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('잘못된 채팅 링크')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('유효하지 않은 채팅 링크예요.'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => context.go('/'),
              child: const Text('홈으로 이동'),
            ),
          ],
        ),
      ),
    );
  }
}
