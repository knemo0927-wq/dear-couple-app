import 'package:couple_chat_app/src/app_router.dart';
import 'package:couple_chat_app/src/common/app_theme.dart';
import 'package:couple_chat_app/src/config/app_config.dart';
import 'package:couple_chat_app/src/config/app_config_provider.dart';
import 'package:couple_chat_app/src/features/anniversary/data/anniversary_providers.dart';
import 'package:couple_chat_app/src/features/anniversary/data/anniversary_repository.dart';
import 'package:couple_chat_app/src/features/auth/data/auth_providers.dart';
import 'package:couple_chat_app/src/features/auth/data/auth_repository.dart';
import 'package:couple_chat_app/src/features/chat/data/chat_providers.dart';
import 'package:couple_chat_app/src/features/chat/data/chat_repository.dart';
import 'package:couple_chat_app/src/features/chat/data/memory_album_providers.dart';
import 'package:couple_chat_app/src/features/chat/data/memory_album_repository.dart';
import 'package:couple_chat_app/src/features/mini_games/data/omok_providers.dart';
import 'package:couple_chat_app/src/features/mini_games/data/omok_repository.dart';
import 'package:couple_chat_app/src/features/notifications/data/notification_inbox.dart';
import 'package:couple_chat_app/src/features/notifications/data/notification_preferences.dart';
import 'package:couple_chat_app/src/features/settings/data/couple_prefs_providers.dart';
import 'package:couple_chat_app/src/features/travel_map/data/travel_map_providers.dart';
import 'package:couple_chat_app/src/features/travel_map/data/travel_map_repository.dart';
import 'package:couple_chat_app/src/features/world_map/data/world_map_providers.dart';
import 'package:couple_chat_app/src/features/world_map/data/world_map_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _coupleId = '11111111-1111-4111-8111-111111111111';
const _profile = ProfileInfo(
  userId: 'user-1',
  nickname: '하루',
  pairingCode: 'DEAR',
  coupleId: _coupleId,
  avatarPath: null,
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'http://127.0.0.1:54321',
    anonKey: 'preview-key',
  );
  final requested = Uri.base.queryParameters['screen'] ?? 'home';
  final initialLocation = switch (requested) {
    'auth' => '/auth',
    'anniversary' => '/anniversary-reminders',
    'chat' => '/chat/$_coupleId',
    'more' => '/profile',
    'travel-map' => '/travel-map',
    'world-map' => '/world-map',
    _ => '/chat-list',
  };
  final signedIn = requested != 'auth';
  final relationshipStart = DateUtils.dateOnly(
    DateTime.now().subtract(const Duration(days: 981)),
  );
  final customAnniversary = AnniversaryItem(
    id: 'preview-anniversary',
    coupleId: _coupleId,
    title: '첫 여행',
    eventDate: DateUtils.dateOnly(
      DateTime.now().add(const Duration(days: 12)),
    ),
    createdAt: DateTime(2026, 1, 1),
    repeat: AnniversaryRepeat.yearly,
    reminderEnabled: true,
    reminderDaysBefore: 1,
    reminderHour: 9,
  );
  final previewAlbum = MemoryAlbum(
    id: 'preview-album',
    coupleId: _coupleId,
    name: '우리의 여름',
    createdBy: 'user-1',
    createdAt: DateTime.utc(2026, 6, 1),
    updatedAt: DateTime.utc(2026, 7, 12),
    photoCount: 0,
    isFeatured: true,
  );
  final previewMessages = <ChatMessage>[
    ChatMessage(
      id: 101,
      coupleId: _coupleId,
      senderId: 'user-2',
      body: '오늘 하루는 어땠어? 나는 네 생각 많이 했어 💗',
      imagePath: null,
      createdAt: DateTime.now().subtract(const Duration(minutes: 18)),
      heartCount: 1,
      isHeartedByMe: true,
    ),
    ChatMessage(
      id: 102,
      coupleId: _coupleId,
      senderId: 'user-1',
      body: '나도! 저녁 먹고 같이 산책할까?',
      imagePath: null,
      createdAt: DateTime.now().subtract(const Duration(minutes: 12)),
      heartCount: 0,
      isHeartedByMe: false,
      replyToMessageId: 101,
    ),
    ChatMessage(
      id: 103,
      coupleId: _coupleId,
      senderId: 'user-2',
      body: null,
      imagePath: 'preview-one.jpg',
      createdAt: DateTime.now().subtract(const Duration(minutes: 7)),
      heartCount: 0,
      isHeartedByMe: false,
    ),
    ChatMessage(
      id: 104,
      coupleId: _coupleId,
      senderId: 'user-2',
      body: null,
      imagePath: 'preview-two.jpg',
      createdAt: DateTime.now().subtract(const Duration(minutes: 7)),
      heartCount: 0,
      isHeartedByMe: false,
    ),
  ];
  const previewCities = <TravelCity>[
    TravelCity(
      id: 'seoul',
      code: 'SEOUL',
      name: '서울',
      regionGroup: '수도권',
      centerLat: 37.5665,
      centerLng: 126.978,
      sortOrder: 1,
    ),
    TravelCity(
      id: 'busan',
      code: 'BUSAN',
      name: '부산',
      regionGroup: '영남',
      centerLat: 35.1796,
      centerLng: 129.0756,
      sortOrder: 2,
    ),
    TravelCity(
      id: 'jeju',
      code: 'JEJU',
      name: '제주',
      regionGroup: '제주',
      centerLat: 33.4996,
      centerLng: 126.5312,
      sortOrder: 3,
    ),
    TravelCity(
      id: 'gangneung',
      code: 'SIG_32030',
      name: '강릉',
      regionGroup: '강원',
      centerLat: 37.7519,
      centerLng: 128.8761,
      sortOrder: 4,
    ),
  ];
  final previewCityVisits = <TravelCityVisit>[
    TravelCityVisit(
      id: 'visit-seoul',
      coupleId: _coupleId,
      cityId: 'seoul',
      colorHex: '#EF6F89',
      visitedAt: DateTime(2026, 5, 4),
      memo: '한강에서 함께 산책한 날',
      updatedBy: 'user-1',
      updatedAt: DateTime(2026, 7, 10),
    ),
    TravelCityVisit(
      id: 'visit-jeju',
      coupleId: _coupleId,
      cityId: 'jeju',
      colorHex: '#FDBB85',
      visitedAt: DateTime(2025, 9, 20),
      memo: '첫 비행기 여행',
      updatedBy: 'user-2',
      updatedAt: DateTime(2026, 6, 20),
    ),
  ];
  const previewCountries = <WorldCountry>[
    WorldCountry(
      code: 'KR',
      iso3: 'KOR',
      nameKo: '대한민국',
      nameEn: 'South Korea',
      centerLat: 36.5,
      centerLng: 127.8,
      sortOrder: 1,
    ),
    WorldCountry(
      code: 'JP',
      iso3: 'JPN',
      nameKo: '일본',
      nameEn: 'Japan',
      centerLat: 36.2,
      centerLng: 138.3,
      sortOrder: 2,
    ),
    WorldCountry(
      code: 'FR',
      iso3: 'FRA',
      nameKo: '프랑스',
      nameEn: 'France',
      centerLat: 46.2,
      centerLng: 2.2,
      sortOrder: 3,
    ),
    WorldCountry(
      code: 'US',
      iso3: 'USA',
      nameKo: '미국',
      nameEn: 'United States',
      centerLat: 39.8,
      centerLng: -98.6,
      sortOrder: 4,
    ),
  ];
  final previewCountryVisits = <WorldCountryVisit>[
    WorldCountryVisit(
      id: 'visit-japan',
      coupleId: _coupleId,
      countryCode: 'JP',
      colorHex: '#C9A7E1',
      visitedAt: DateTime(2026, 2, 14),
      memo: '겨울 온천 여행',
      updatedBy: 'user-1',
      updatedAt: DateTime(2026, 7, 9),
    ),
  ];

  runApp(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(
          const AppConfig(supabaseUrl: 'preview', supabaseAnonKey: 'preview'),
        ),
        hasSessionStateProvider.overrideWithValue(AsyncValue.data(signedIn)),
        authPasswordRecoveryProvider.overrideWith(
          (ref) => Stream.value(false),
        ),
        routerInitialLocationProvider.overrideWithValue(initialLocation),
        myProfileProvider
            .overrideWith((ref) async => signedIn ? _profile : null),
        myAvatarUrlProvider.overrideWith((ref) async => null),
        myAccountEmailProvider.overrideWithValue('dear@example.com'),
        anniversaryDateProvider.overrideWith(
          (ref) => Stream.value(relationshipStart),
        ),
        anniversaryItemsProvider.overrideWith(
          (ref, coupleId) => Stream.value([customAnniversary]),
        ),
        fetchAnniversaryTimelinePageProvider.overrideWithValue(
          ({required coupleId, cursor, pageSize = 15}) async {
            final all = buildUpcomingAnniversaryTimeline(
              relationshipStart: relationshipStart,
              customItems: [customAnniversary],
              limit: 200,
            );
            final start = cursor == null
                ? 0
                : all.indexWhere(
                    (item) =>
                        item.eventDate.isAfter(cursor.eventDate) ||
                        (DateUtils.isSameDay(
                              item.eventDate,
                              cursor.eventDate,
                            ) &&
                            item.stableId.compareTo(cursor.stableId) > 0),
                  );
            final safeStart = start < 0 ? all.length : start;
            final end = (safeStart + pageSize).clamp(0, all.length).toInt();
            final items = all.sublist(safeStart, end);
            final last = items.isEmpty ? null : items.last;
            return AnniversaryTimelinePage(
              items: items,
              nextCursor: last == null
                  ? null
                  : AnniversaryTimelineCursor(
                      eventDate: last.eventDate,
                      stableId: last.stableId,
                    ),
              hasMore: end < all.length,
            );
          },
        ),
        notificationPreferencesProvider.overrideWith(
          (ref, userId) =>
              Stream.value(NotificationPreferences.defaults(userId)),
        ),
        coupleAvatarUrlMapProvider.overrideWith(
          (ref, coupleId) => Stream.value(const <String, String>{}),
        ),
        coupleNicknameMapProvider.overrideWith(
          (ref, coupleId) => Stream.value(
            const {'user-1': '하루', 'user-2': '지안'},
          ),
        ),
        chatUnreadCountProvider.overrideWith(
          (ref, coupleId) => Stream.value(3),
        ),
        chatConversationPreviewProvider.overrideWith(
          (ref, coupleId) => Stream.value(
            ChatConversationPreview(
              text: '오늘 저녁에 같이 산책할까? 💗',
              createdAt: DateTime.now().subtract(const Duration(minutes: 8)),
            ),
          ),
        ),
        chatCurrentUserIdProvider.overrideWithValue('user-1'),
        chatWatchMessagesProvider.overrideWithValue(
          (coupleId) => Stream.value(previewMessages),
        ),
        chatSendReplyTextProvider.overrideWithValue(({
          required coupleId,
          required text,
          replyToMessageId,
        }) async {}),
        chatUploadImageProvider.overrideWithValue(({
          required coupleId,
          required bytes,
          required extension,
          required idempotencyKey,
          required isCancelled,
          onProgress,
        }) async {
          onProgress?.call(1);
          return ChatImageSendOutcome.sent;
        }),
        chatFetchMessagesPageProvider.overrideWithValue(({
          required coupleId,
          beforeMessageId,
          limit = ChatRepository.initialPageSize,
        }) async =>
            const ChatMessagePage(messages: [], hasMore: false)),
        chatToggleReactionProvider.overrideWithValue(({
          required messageId,
        }) async {}),
        chatPickImageProvider.overrideWithValue(() async => null),
        chatPickImagesProvider.overrideWithValue(
          () async => const <PickedChatImage>[],
        ),
        chatMarkReadProvider.overrideWithValue(({
          required coupleId,
          required lastReadMessageId,
          required lastReadAt,
        }) async {}),
        chatFetchMessageByIdProvider.overrideWithValue(({
          required coupleId,
          required messageId,
        }) async {
          for (final message in previewMessages) {
            if (message.id == messageId) return message;
          }
          return null;
        }),
        chatDeleteMessageProvider.overrideWithValue((messageId) async {}),
        chatResolveImageUrlProvider.overrideWithValue(
          (path) async =>
              'http://127.0.0.1:7357/assets/assets/images/dear_home_hero_mascots.png',
        ),
        chatWatchReactionMessageIdsProvider.overrideWithValue(
          (coupleId) => const Stream<int>.empty(),
        ),
        chatPartnerReadMarkerProvider.overrideWith(
          (ref, coupleId) => Stream.value(
            ChatReadMarker(
              lastReadMessageId: 102,
              lastReadAt: DateTime.now().subtract(const Duration(minutes: 10)),
            ),
          ),
        ),
        chatPartnerOnlineProvider.overrideWith(
          (ref, coupleId) => Stream.value(true),
        ),
        recentMemoryAlbumPhotosProvider.overrideWith(
          (ref, coupleId) => Stream.value(const []),
        ),
        memoryAlbumsProvider.overrideWith(
          (ref, coupleId) => Stream.value([previewAlbum]),
        ),
        memoryAlbumRepositoryProvider.overrideWithValue(
          _PreviewMemoryAlbumRepository([previewAlbum]),
        ),
        notificationInboxProvider.overrideWith(
          (ref, userId) => Stream.value(const <NotificationInboxItem>[]),
        ),
        enforceDomesticTravelCatalogIntegrityProvider.overrideWithValue(false),
        travelCitiesProvider.overrideWith((ref) async => previewCities),
        travelCityVisitsProvider.overrideWith(
          (ref, coupleId) => Stream.value(previewCityVisits),
        ),
        travelCityPhotosProvider.overrideWith(
          (ref, args) => Stream.value(const <TravelCityPhoto>[]),
        ),
        upsertTravelVisitProvider.overrideWithValue(({
          required coupleId,
          required cityId,
          required colorHex,
          visitedAt,
          memo,
        }) async {}),
        deleteTravelVisitProvider.overrideWithValue(({
          required coupleId,
          required cityId,
        }) async {}),
        worldCountriesProvider.overrideWith((ref) async => previewCountries),
        worldCountryVisitsProvider.overrideWith(
          (ref, coupleId) => Stream.value(previewCountryVisits),
        ),
        worldCountryPhotosProvider.overrideWith(
          (ref, args) => Stream.value(const <WorldCountryPhoto>[]),
        ),
        upsertWorldVisitProvider.overrideWithValue(({
          required coupleId,
          required countryCode,
          required colorHex,
          visitedAt,
          memo,
        }) async {}),
        deleteWorldVisitProvider.overrideWithValue(({
          required coupleId,
          required countryCode,
        }) async {}),
        rematchNotificationsProvider.overrideWith(
          (ref, userId) => Stream.value(const <OmokNotification>[]),
        ),
        authSignInProvider.overrideWithValue(({
          required email,
          required password,
        }) async {}),
        authSignUpProvider.overrideWithValue(({
          required email,
          required password,
        }) async =>
            const AuthSignUpResult(emailVerificationPending: true)),
        authPasswordResetProvider.overrideWithValue((email) async {}),
        authAppleSignInProvider.overrideWithValue(() async {}),
        addAnniversaryProvider.overrideWithValue(({
          required coupleId,
          required title,
          required eventDate,
          required repeat,
          required reminderEnabled,
          required reminderDaysBefore,
          required reminderHour,
          note,
          linkedAlbumId,
        }) async {}),
      ],
      child: const _PreviewApp(),
    ),
  );
}

class _PreviewMemoryAlbumRepository extends MemoryAlbumRepository {
  _PreviewMemoryAlbumRepository(this.albums)
      : super(
          client: SupabaseClient(
            'http://127.0.0.1:54321',
            'preview-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
        );

  final List<MemoryAlbum> albums;

  @override
  Stream<List<MemoryAlbum>> watchAlbums(String coupleId) =>
      Stream.value(albums);

  @override
  Stream<MemoryAlbumHeadSnapshot> watchAlbumHead({
    required String coupleId,
    int limit = memoryAlbumPageSize,
  }) {
    final items = mergeMemoryAlbums(const [], albums.take(limit));
    return Stream.value(
      MemoryAlbumHeadSnapshot(
        items: items,
        oldest: items.isEmpty ? null : items.last,
        isExhaustive: albums.length <= limit,
      ),
    );
  }

  @override
  Future<MemoryAlbumListPage> fetchAlbumPage({
    required String coupleId,
    MemoryAlbumCursor? cursor,
    int pageSize = memoryAlbumPageSize,
  }) async {
    return memoryAlbumPageFromRows(albums, pageSize: pageSize);
  }

  @override
  Stream<List<MemoryAlbumPhoto>> watchRecentPhotos({
    required String coupleId,
    int limit = 10,
  }) =>
      Stream.value(const []);

  @override
  Stream<List<MemoryAlbumPhotoDeletion>> watchPhotoDeletions({
    required String coupleId,
    String? albumId,
    int limit = memoryAlbumDeletionEventWindow,
  }) =>
      Stream.value(const []);

  @override
  Stream<MemoryAlbumPhotoHeadSnapshot> watchPhotoHeadWindow({
    required String coupleId,
    String? albumId,
    int limit = memoryAlbumPhotoPageSize,
    DateTime? createdAtOrAfter,
    DateTime? createdAtBefore,
    String? uploadedBy,
    String? excludedUploader,
  }) =>
      Stream.value(
        const MemoryAlbumPhotoHeadSnapshot(
          items: [],
          oldestUnfiltered: null,
          isExhaustive: true,
        ),
      );

  @override
  Stream<List<MemoryAlbumPhoto>> watchPhotoHead({
    required String coupleId,
    String? albumId,
    int limit = memoryAlbumPhotoPageSize,
    DateTime? createdAtOrAfter,
    DateTime? createdAtBefore,
    String? uploadedBy,
    String? excludedUploader,
  }) =>
      Stream.value(const []);

  @override
  Future<MemoryAlbumPhotoPage> fetchPhotoPage({
    required String coupleId,
    String? albumId,
    MemoryAlbumPhotoCursor? cursor,
    int pageSize = memoryAlbumPhotoPageSize,
    DateTime? createdAtOrAfter,
    DateTime? createdAtBefore,
    String? uploadedBy,
    String? excludedUploader,
  }) async {
    return const MemoryAlbumPhotoPage(
      items: [],
      nextCursor: null,
      hasMore: false,
    );
  }
}

class _PreviewApp extends ConsumerWidget {
  const _PreviewApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'Dear visual QA',
      theme: AppTheme.light(),
      routerConfig: ref.watch(goRouterProvider),
      builder: (context, child) {
        final requestedScale = double.tryParse(
          Uri.base.queryParameters['textScale'] ?? '',
        );
        if (child == null) return const SizedBox.shrink();
        if (requestedScale == null) return child;
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(
              requestedScale.clamp(1.0, 2.0).toDouble(),
            ),
          ),
          child: child,
        );
      },
    );
  }
}
