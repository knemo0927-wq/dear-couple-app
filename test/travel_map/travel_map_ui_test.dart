import 'package:couple_chat_app/src/common/app_theme.dart';
import 'package:couple_chat_app/src/common/dear_design.dart';
import 'package:couple_chat_app/src/features/auth/data/auth_providers.dart';
import 'package:couple_chat_app/src/features/auth/data/auth_repository.dart';
import 'package:couple_chat_app/src/features/travel_map/data/map_location_service.dart';
import 'package:couple_chat_app/src/features/travel_map/data/travel_map_providers.dart';
import 'package:couple_chat_app/src/features/travel_map/data/travel_map_repository.dart';
import 'package:couple_chat_app/src/features/travel_map/presentation/travel_map_filter.dart';
import 'package:couple_chat_app/src/features/travel_map/presentation/travel_map_page.dart';
import 'package:couple_chat_app/src/features/travel_map/presentation/widgets/travel_map_explorer.dart';
import 'package:couple_chat_app/src/features/travel_map/presentation/widgets/travel_map_record_editor.dart';
import 'package:couple_chat_app/src/features/travel_map/presentation/widgets/travel_map_top_bar.dart';
import 'package:couple_chat_app/src/features/world_map/data/world_map_providers.dart';
import 'package:couple_chat_app/src/features/world_map/data/world_map_repository.dart';
import 'package:couple_chat_app/src/features/world_map/presentation/world_map_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  const profile = ProfileInfo(
    userId: 'user-1',
    nickname: '우리',
    pairingCode: 'ABCD',
    coupleId: 'couple-1',
    avatarPath: null,
  );

  testWidgets('다크 지도 화면은 컨트롤과 장소 목록에 의미 역할 색과 Reduce Motion을 적용한다',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final darkTheme = AppTheme.dark();
    final scheme = darkTheme.colorScheme;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myProfileProvider.overrideWith((ref) async => profile),
          travelCitiesProvider.overrideWith(
            (ref) async => const [
              TravelCity(
                id: 'seoul',
                code: 'METRO_11',
                name: '서울',
                regionGroup: '수도권',
                centerLat: 37.5665,
                centerLng: 126.978,
                sortOrder: 1,
              ),
            ],
          ),
          travelCityVisitsProvider.overrideWith(
            (ref, coupleId) => Stream.value(const <TravelCityVisit>[]),
          ),
          travelCityPhotosProvider.overrideWith(
            (ref, args) => Stream.value(const <TravelCityPhoto>[]),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          darkTheme: darkTheme,
          themeMode: ThemeMode.dark,
          home: const MediaQuery(
            data: MediaQueryData(
              size: Size(390, 844),
              disableAnimations: true,
            ),
            child: TravelMapPage(),
          ),
        ),
      ),
    );

    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey('travel-map-progress-surface')),
    );
    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(appBar.backgroundColor, scheme.surface.withValues(alpha: 0.94));

    final launcherMaterial = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(TravelMapSearchLauncher),
            matching: find.byType(Material),
          )
          .first,
    );
    final launcherText = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('travel-map-search-launcher')),
        matching: find.text('장소 목록 열기'),
      ),
    );
    expect(launcherMaterial.color, scheme.surface.withValues(alpha: 0.96));
    expect(launcherText.style?.color, scheme.onSurface);

    final progressSurface = tester.widget<Container>(
      find.byKey(const ValueKey('travel-map-progress-surface')),
    );
    final progressDecoration = progressSurface.decoration! as BoxDecoration;
    expect(progressDecoration.color, scheme.surface.withValues(alpha: 0.96));

    final zoomMaterial = tester.widget<Material>(
      find.byKey(const ValueKey('travel-map-zoom-controls')),
    );
    final zoomContainer = tester.widget<Container>(
      find
          .descendant(
            of: find.byKey(const ValueKey('travel-map-zoom-controls')),
            matching: find.byType(Container),
          )
          .first,
    );
    final zoomDecoration = zoomContainer.decoration! as BoxDecoration;
    final zoomBorder = zoomDecoration.border! as Border;
    expect(zoomMaterial.color, scheme.surface.withValues(alpha: 0.96));
    expect(zoomBorder.top.color, scheme.outline);

    await tester.tap(
      find.byKey(const ValueKey('travel-map-search-launcher')),
    );
    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey('travel-place-explorer-surface')),
    );
    final explorerSurface = tester.widget<Container>(
      find.byKey(const ValueKey('travel-place-explorer-surface')),
    );
    expect(
      (explorerSurface.decoration! as BoxDecoration).color,
      scheme.surfaceContainerLow,
    );
    final placeTitle = tester.widget<Text>(
      find
          .descendant(
            of: find.byKey(const ValueKey('travel-place-seoul')),
            matching: find.text('서울'),
          )
          .first,
    );
    expect(placeTitle.style?.color, scheme.onSurface);
    expect(
      placeTitle.style?.color,
      isNot(scheme.onSurface.withValues(alpha: 0.38)),
    );

    final seoulTile = find.byKey(const ValueKey('travel-place-seoul'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.scrollUntilVisible(
      seoulTile,
      280,
      scrollable: find
          .descendant(
            of: find.byType(TravelPlaceExplorerSheet),
            matching: find.byType(Scrollable),
          )
          .last,
    );
    await tester.tap(seoulTile);
    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey('travel-map-editor-expanded')),
    );
    final editorSurface = tester.widget<Container>(
      find.byKey(const ValueKey('travel-map-sheet-surface')),
    );
    final editorDecoration = editorSurface.decoration! as BoxDecoration;
    expect(editorDecoration.color, scheme.surfaceContainerLow);
    final memoField = tester.widget<TextField>(
      find.byKey(const ValueKey('travel-map-memo-field')),
    );
    expect(memoField.decoration?.fillColor, scheme.surface);
    expect(
      (memoField.decoration?.enabledBorder! as OutlineInputBorder)
          .borderSide
          .color,
      scheme.outline,
    );
    expect(
      tester
          .widget<AnimatedSwitcher>(
            find.byKey(const ValueKey('travel-map-editor-switcher')),
          )
          .duration,
      Duration.zero,
    );
    expect(
      tester
          .widget<AnimatedContainer>(
            find
                .descendant(
                  of: find.byType(TravelMapRecordEditor),
                  matching: find.byType(AnimatedContainer),
                )
                .first,
          )
          .duration,
      Duration.zero,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('공통 헤더는 뒤로가기, 제목, 세그먼트와 실제 더보기 동작을 제공한다', (tester) async {
    TravelMapSection? selectedSection;
    TravelMapMenuAction? selectedMenu;
    var backPressed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: TravelMapTopBar(
            section: TravelMapSection.korea,
            onBack: () => backPressed = true,
            onSectionSelected: (section) => selectedSection = section,
            onMenuSelected: (action) => selectedMenu = action,
          ),
        ),
      ),
    );

    expect(find.text('여행 지도'), findsOneWidget);
    expect(find.byTooltip('뒤로가기'), findsOneWidget);
    final semanticLabels = tester
        .widgetList<Semantics>(find.byType(Semantics))
        .map((widget) => widget.properties.label)
        .whereType<String>();
    expect(semanticLabels, containsAll(['국내 여행 지도', '세계 여행 지도']));
    expect(
      tester
          .getSize(find.byKey(const ValueKey('travel-map-segment-world')))
          .height,
      greaterThanOrEqualTo(44),
    );

    await tester.tap(
      find.byKey(const ValueKey('travel-map-segment-world')),
    );
    expect(selectedSection, TravelMapSection.world);

    await tester.tap(find.byTooltip('여행 지도 더보기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('방문한 곳 보기'));
    await tester.pumpAndSettle();
    expect(selectedMenu, TravelMapMenuAction.visited);

    await tester.tap(find.byTooltip('뒤로가기'));
    expect(backPressed, isTrue);
  });

  testWidgets('국내 세그먼트에서 세계 세그먼트로 기존 경로를 교체한다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: '/travel-map',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const SizedBox.shrink(),
        ),
        GoRoute(
          path: '/travel-map',
          builder: (_, __) => const TravelMapPage(),
        ),
        GoRoute(
          path: '/world-map',
          builder: (_, __) => const Scaffold(body: Text('world-route')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myProfileProvider.overrideWith((ref) async => profile),
          travelCitiesProvider.overrideWith(
            (ref) async => [
              const TravelCity(
                id: 'seoul',
                code: 'SEOUL',
                name: '서울',
                regionGroup: '수도권',
                centerLat: 37.5,
                centerLng: 127,
                sortOrder: 1,
              ),
            ],
          ),
          travelCityVisitsProvider.overrideWith(
            (ref, coupleId) => Stream.value(const <TravelCityVisit>[]),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(
      find.byKey(const ValueKey('travel-map-segment-world')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('world-route'), findsOneWidget);
  });

  testWidgets('공통 편집 시트는 저장 중 상태에서 중복 저장을 막는다', (tester) async {
    var saving = false;
    var saveCalls = 0;
    late StateSetter update;
    final memoController = TextEditingController();
    addTearDown(memoController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Align(
                alignment: Alignment.bottomCenter,
                child: TravelMapRecordEditor(
                  placeName: '서울',
                  regionLabel: '대한민국 · 수도권',
                  palette: const ['#EF6F89'],
                  selectedColor: '#EF6F89',
                  memoController: memoController,
                  visitedAt: null,
                  photos: const [],
                  photosLoading: false,
                  saving: saving,
                  deleting: false,
                  uploadingPhoto: false,
                  hasRecord: false,
                  onCollapse: () {},
                  onPickDate: () {},
                  onClearDate: () {},
                  onSelectColor: (_) {},
                  onSave: () {
                    saveCalls++;
                    update(() => saving = true);
                  },
                  onDelete: null,
                  onAddPhoto: null,
                  onDeletePhoto: (_) {},
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('travel-map-save-button')),
    );
    await tester.tap(find.byKey(const ValueKey('travel-map-save-button')));
    await tester.pump();
    expect(saveCalls, 1);
    expect(find.text('저장 중'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('travel-map-save-button')));
    await tester.pump();
    expect(saveCalls, 1);
  });

  testWidgets('현재 위치 권한이 영구 거절되면 앱 설정 진입 상태를 제공한다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final locationService = _FakeMapLocationService(
      failure: MapLocationFailureReason.permissionDeniedForever,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myProfileProvider.overrideWith((ref) async => profile),
          mapLocationServiceProvider.overrideWithValue(locationService),
          travelCitiesProvider.overrideWith(
            (ref) async => [
              const TravelCity(
                id: 'seoul',
                code: 'SEOUL',
                name: '서울',
                regionGroup: '수도권',
                centerLat: 37.5665,
                centerLng: 126.978,
                sortOrder: 1,
              ),
            ],
          ),
          travelCityVisitsProvider.overrideWith(
            (ref, coupleId) => Stream.value(const <TravelCityVisit>[]),
          ),
        ],
        child: const MaterialApp(home: TravelMapPage()),
      ),
    );

    final currentLocationButton = find.byTooltip('현재 위치');
    for (var i = 0; i < 20 && currentLocationButton.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(currentLocationButton, findsOneWidget);
    await tester.tap(currentLocationButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(locationService.positionRequests, 1);
    expect(
      find.text('위치 권한이 차단되어 있어요. 앱 설정에서 허용해 주세요.'),
      findsOneWidget,
    );
    await tester.tap(find.text('앱 설정'));
    await tester.pump();
    expect(locationService.appSettingsRequests, 1);
    expect(find.byTooltip('현재 위치'), findsOneWidget);
  });

  testWidgets('허용된 현재 위치는 국내 지도에 실제 위치 표시 상태를 만든다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final locationService = _FakeMapLocationService(
      position: const MapPosition(latitude: 37.5665, longitude: 126.978),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myProfileProvider.overrideWith((ref) async => profile),
          mapLocationServiceProvider.overrideWithValue(locationService),
          travelCitiesProvider.overrideWith(
            (ref) async => [
              const TravelCity(
                id: 'seoul',
                code: 'SEOUL',
                name: '서울',
                regionGroup: '수도권',
                centerLat: 37.5665,
                centerLng: 126.978,
                sortOrder: 1,
              ),
              const TravelCity(
                id: 'busan',
                code: 'BUSAN',
                name: '부산',
                regionGroup: '영남',
                centerLat: 35.1796,
                centerLng: 129.0756,
                sortOrder: 2,
              ),
            ],
          ),
          travelCityVisitsProvider.overrideWith(
            (ref, coupleId) => Stream.value(const <TravelCityVisit>[]),
          ),
        ],
        child: const MaterialApp(home: TravelMapPage()),
      ),
    );

    final currentLocationButton = find.byTooltip('현재 위치');
    for (var i = 0; i < 20 && currentLocationButton.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(currentLocationButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(locationService.positionRequests, 1);
    expect(find.text('현재 위치를 지도에 표시했어요.'), findsOneWidget);
  });

  testWidgets('공동 사진 삭제 확인은 상대 지도에서도 사라짐을 명시한다', (tester) async {
    bool? confirmed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                confirmed = await confirmSharedMapPhotoDeletion(context);
              },
              child: const Text('사진 삭제 열기'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('사진 삭제 열기'));
    await tester.pumpAndSettle();
    expect(find.text('함께 보관한 사진 삭제'), findsOneWidget);
    expect(find.text('삭제하면 상대방의 여행 지도에서도 이 사진이 사라져요.'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '삭제'));
    await tester.pumpAndSettle();
    expect(confirmed, isTrue);
  });

  testWidgets('장소 탐색기는 최근 여행, 검색, 방문 상태 필터를 실제 목록에 반영한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TravelPlaceExplorerSheet(
            places: [
              TravelMapPlaceItem(
                id: 'seoul',
                title: '서울',
                subtitle: '대한민국 · 수도권',
                visited: true,
                updatedAt: DateTime(2026, 7, 11),
              ),
              const TravelMapPlaceItem(
                id: 'busan',
                title: '부산',
                subtitle: '대한민국 · 영남',
                visited: false,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('최근 여행'), findsOneWidget);
    expect(find.text('전체 장소'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('travel-place-search-field')),
      '부산',
    );
    await tester.pump();
    expect(find.text('검색 결과 1개'), findsOneWidget);
    expect(find.byKey(const ValueKey('travel-place-busan')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('travel-filter-visited')));
    await tester.pump();
    expect(find.text('조건에 맞는 장소가 없어요.'), findsOneWidget);
  });

  testWidgets('공통 지도 헤더는 200퍼센트 글자 크기에서도 핵심 제어를 유지한다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 844),
            textScaler: TextScaler.linear(2),
          ),
          child: Scaffold(
            appBar: TravelMapTopBar(
              section: TravelMapSection.world,
              onBack: () {},
              onSectionSelected: (_) {},
              onMenuSelected: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('여행 지도'), findsOneWidget);
    expect(find.text('국내'), findsOneWidget);
    expect(find.text('세계'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('375pt·200% 국내 지도는 캔버스를 설명하고 44pt 장소 목록을 연다', (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myProfileProvider.overrideWith((ref) async => profile),
          travelCitiesProvider.overrideWith(
            (ref) async => const [
              TravelCity(
                id: 'seoul',
                code: 'METRO_11',
                name: '서울',
                regionGroup: '서울',
                centerLat: 37.5665,
                centerLng: 126.978,
                sortOrder: 1,
              ),
              TravelCity(
                id: 'busan',
                code: 'METRO_21',
                name: '부산',
                regionGroup: '부산',
                centerLat: 35.1796,
                centerLng: 129.0756,
                sortOrder: 2,
              ),
            ],
          ),
          travelCityVisitsProvider.overrideWith(
            (ref, coupleId) => Stream.value(const <TravelCityVisit>[]),
          ),
        ],
        child: const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(375, 812),
              textScaler: TextScaler.linear(2),
            ),
            child: TravelMapPage(),
          ),
        ),
      ),
    );

    const canvasKey = ValueKey('korea-map-canvas-semantics');
    const launcherKey = ValueKey('travel-map-place-list-launcher-semantics');
    await _pumpUntilFound(tester, find.byKey(canvasKey));
    await _pumpUntilFound(tester, find.byKey(launcherKey));

    final canvas = tester.getSemantics(find.byKey(canvasKey));
    expect(canvas.label, contains('시각적 탐색용 캔버스'));
    expect(canvas.hint, contains('장소 목록 열기'));
    expect(canvas.getSemanticsData().flagsCollection.isImage, isTrue);

    final launcher = tester.getSemantics(find.byKey(launcherKey));
    expect(launcher.label, '장소 목록 열기');
    expect(launcher.getSemanticsData().flagsCollection.isButton, isTrue);
    expect(
      launcher.getSemanticsData().hasAction(SemanticsAction.tap),
      isTrue,
    );
    expect(tester.getSize(find.byKey(launcherKey)).height,
        greaterThanOrEqualTo(44));
    expect(
      find.ancestor(
          of: find.byKey(launcherKey), matching: find.byType(SafeArea)),
      findsWidgets,
    );

    final launcherRect = tester.getRect(find.byKey(launcherKey));
    final progressRect = tester.getRect(
      find.byKey(const ValueKey('travel-map-progress-card')),
    );
    final zoomRect = tester.getRect(
      find.byKey(const ValueKey('travel-map-zoom-controls')),
    );
    final editorRect = tester.getRect(
      find.byKey(const ValueKey('travel-map-editor-collapsed')),
    );
    expect(launcherRect.bottom, lessThanOrEqualTo(progressRect.top));
    expect(zoomRect.overlaps(editorRect), isFalse);
    expect(tester.takeException(), isNull);

    await tester.tap(
      find.byKey(const ValueKey('travel-map-search-launcher')),
    );
    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey('travel-place-seoul')),
    );
    expect(find.byKey(const ValueKey('travel-place-seoul')), findsOneWidget);
    expect(find.byKey(const ValueKey('travel-place-busan')), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('가로·200% 세계 지도는 overlay가 겹치지 않고 편집 중에도 장소 목록을 연다',
      (tester) async {
    tester.view.physicalSize = const Size(812, 375);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myProfileProvider.overrideWith((ref) async => profile),
          worldCountriesProvider.overrideWith(
            (ref) async => const [
              WorldCountry(
                code: 'KR',
                iso3: 'KOR',
                nameKo: '대한민국',
                nameEn: 'South Korea',
                centerLat: 36.5,
                centerLng: 127.8,
                sortOrder: 1,
              ),
            ],
          ),
          worldCountryVisitsProvider.overrideWith(
            (ref, coupleId) => Stream.value(const <WorldCountryVisit>[]),
          ),
          worldCountryPhotosProvider.overrideWith(
            (ref, args) => Stream.value(const <WorldCountryPhoto>[]),
          ),
        ],
        child: const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(812, 375),
              textScaler: TextScaler.linear(2),
            ),
            child: WorldMapPage(),
          ),
        ),
      ),
    );

    const canvasKey = ValueKey('world-map-canvas-semantics');
    const launcherKey = ValueKey('travel-map-place-list-launcher-semantics');
    await _pumpUntilFound(tester, find.byKey(canvasKey));
    await _pumpUntilFound(tester, find.byKey(launcherKey));

    final canvas = tester.getSemantics(find.byKey(canvasKey));
    expect(canvas.label, contains('시각적 탐색용 캔버스'));
    expect(canvas.hint, contains('장소 목록 열기'));
    expect(canvas.getSemanticsData().flagsCollection.isImage, isTrue);

    final launcherRect = tester.getRect(find.byKey(launcherKey));
    final progressRect = tester.getRect(
      find.byKey(const ValueKey('travel-map-progress-card')),
    );
    final zoomRect = tester.getRect(
      find.byKey(const ValueKey('travel-map-zoom-controls')),
    );
    expect(launcherRect.right, lessThanOrEqualTo(progressRect.left));
    expect(progressRect.right, lessThanOrEqualTo(zoomRect.left));
    expect(launcherRect.height, greaterThanOrEqualTo(44));
    expect(tester.takeException(), isNull);

    await tester.tap(
      find.byKey(const ValueKey('travel-map-search-launcher')),
    );
    final koreaTile = find.byKey(const ValueKey('travel-place-KR'));
    await _pumpUntilFound(tester, koreaTile);
    await tester.pump(const Duration(milliseconds: 400));
    expect(koreaTile, findsOneWidget);
    await tester.scrollUntilVisible(
      koreaTile,
      280,
      scrollable: find
          .descendant(
            of: find.byType(TravelPlaceExplorerSheet),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(koreaTile);
    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey('travel-map-editor-expanded')),
    );
    expect(
      find.byKey(const ValueKey('travel-map-editor-expanded')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('travel-map-search-launcher')),
    );
    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey('travel-place-KR')),
    );
    expect(find.byKey(const ValueKey('travel-place-KR')), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('세계 여행 저장 실패는 오류를 알리고 저장 버튼을 다시 활성화한다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var saveCalls = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myProfileProvider.overrideWith((ref) async => profile),
          worldCountriesProvider.overrideWith(
            (ref) async => [
              const WorldCountry(
                code: 'KR',
                iso3: 'KOR',
                nameKo: '대한민국',
                nameEn: 'South Korea',
                centerLat: 36.5,
                centerLng: 127.8,
                sortOrder: 1,
              ),
            ],
          ),
          worldCountryVisitsProvider.overrideWith(
            (ref, coupleId) => Stream.value(const <WorldCountryVisit>[]),
          ),
          worldCountryPhotosProvider.overrideWith(
            (ref, args) => Stream.value(const <WorldCountryPhoto>[]),
          ),
          upsertWorldVisitProvider.overrideWithValue(
            ({
              required coupleId,
              required countryCode,
              required colorHex,
              visitedAt,
              memo,
            }) async {
              saveCalls++;
              throw StateError('save failed');
            },
          ),
        ],
        child: const MaterialApp(
          home: WorldMapPage(initialCountryCode: 'KR'),
        ),
      ),
    );
    final saveButton = find.byKey(const ValueKey('travel-map-save-button'));
    for (var i = 0; i < 20 && saveButton.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(saveButton, findsOneWidget);
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(saveCalls, 1);
    expect(
      find.text('요청 처리 중 문제가 발생했어요. 잠시 후 다시 시도해 주세요.'),
      findsOneWidget,
    );
    final button = tester.widget<DearGradientButton>(saveButton);
    expect(button.onPressed, isNotNull);
  });
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 40 && finder.evaluate().isEmpty; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(finder, findsOneWidget);
}

class _FakeMapLocationService implements MapLocationService {
  _FakeMapLocationService({this.position, this.failure});

  final MapPosition? position;
  final MapLocationFailureReason? failure;
  int positionRequests = 0;
  int appSettingsRequests = 0;
  int locationSettingsRequests = 0;

  @override
  Future<MapPosition> currentPosition() async {
    positionRequests++;
    final reason = failure;
    if (reason != null) throw MapLocationException(reason);
    return position!;
  }

  @override
  Future<bool> openAppSettings() async {
    appSettingsRequests++;
    return true;
  }

  @override
  Future<bool> openLocationSettings() async {
    locationSettingsRequests++;
    return true;
  }
}
