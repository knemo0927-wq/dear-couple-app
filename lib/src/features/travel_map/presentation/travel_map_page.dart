import 'package:couple_chat_app/src/common/dear_design.dart';
import 'package:couple_chat_app/src/common/error_mapper.dart';
import 'package:couple_chat_app/src/features/auth/data/auth_providers.dart';
import 'package:couple_chat_app/src/features/travel_map/data/map_location_service.dart';
import 'package:couple_chat_app/src/features/travel_map/data/travel_map_providers.dart';
import 'package:couple_chat_app/src/features/travel_map/data/travel_map_repository.dart';
import 'package:couple_chat_app/src/features/travel_map/presentation/travel_map_filter.dart';
import 'package:couple_chat_app/src/features/travel_map/presentation/widgets/korea_city_map_canvas.dart';
import 'package:couple_chat_app/src/features/travel_map/presentation/widgets/travel_map_controls.dart';
import 'package:couple_chat_app/src/features/travel_map/presentation/widgets/travel_map_explorer.dart';
import 'package:couple_chat_app/src/features/travel_map/presentation/widgets/travel_map_record_editor.dart';
import 'package:couple_chat_app/src/features/travel_map/presentation/widgets/travel_map_top_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

class TravelMapPage extends ConsumerStatefulWidget {
  const TravelMapPage({this.initialCityId, super.key});

  final String? initialCityId;

  @override
  ConsumerState<TravelMapPage> createState() => _TravelMapPageState();
}

class _TravelMapPageState extends ConsumerState<TravelMapPage>
    with SingleTickerProviderStateMixin {
  final TextEditingController _memoController = TextEditingController();
  final TransformationController _mapTransformationController =
      TransformationController();

  late final AnimationController _mapAnimationController;
  Animation<Matrix4>? _mapAnimation;
  String? _selectedCityId;
  String? _draftCityId;
  DateTime? _selectedVisitedAt;
  String? _selectedDraftColorHex;
  bool _saving = false;
  bool _deleting = false;
  bool _uploadingPhoto = false;
  bool _locating = false;
  bool _mapInitialTransformApplied = false;
  bool _editorExpanded = false;
  MapPosition? _currentLocation;
  double _currentMapScale = 1;
  Size _mapViewportSize = Size.zero;

  static const double _minMapScale = 0.34;
  static const double _maxMapScale = 3.8;
  static const _palette = <String>[
    '#EF6F89',
    '#FDBB85',
    '#F9D89B',
    '#A9DBC9',
    '#BBD7F1',
    '#C9A7E1',
  ];

  @override
  void initState() {
    super.initState();
    _selectedCityId = widget.initialCityId;
    _editorExpanded = widget.initialCityId != null;
    _mapAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    )..addListener(() {
        final animation = _mapAnimation;
        if (animation != null) {
          _mapTransformationController.value = animation.value;
        }
      });
    _mapTransformationController.addListener(_handleMapTransformChanged);
  }

  @override
  void dispose() {
    _mapTransformationController.removeListener(_handleMapTransformChanged);
    _mapAnimationController.dispose();
    _mapTransformationController.dispose();
    _memoController.dispose();
    super.dispose();
  }

  void _handleMapTransformChanged() {
    final nextScale = _mapScaleFrom(_mapTransformationController.value);
    if (!mounted || (nextScale - _currentMapScale).abs() < 0.015) return;
    setState(() => _currentMapScale = nextScale);
  }

  double _mapScaleFrom(Matrix4 matrix) => matrix.storage[0].abs();

  void _animateMapTo(Matrix4 value) {
    _mapAnimationController.stop();
    _mapAnimation = Matrix4Tween(
      begin: _mapTransformationController.value.clone(),
      end: value,
    ).animate(
      CurvedAnimation(
        parent: _mapAnimationController,
        curve: Curves.easeOutCubic,
      ),
    );
    _mapAnimationController.forward(from: 0);
  }

  void _applyInitialMapFocus({
    required BoxConstraints viewportConstraints,
    required Size contentSize,
  }) {
    if (_mapInitialTransformApplied) return;
    final viewportSize = Size(
      viewportConstraints.maxWidth,
      viewportConstraints.maxHeight,
    );
    if (!viewportSize.width.isFinite ||
        !viewportSize.height.isFinite ||
        viewportSize.isEmpty) {
      return;
    }
    _focusMapOverview(viewportSize: viewportSize, contentSize: contentSize);
    _mapInitialTransformApplied = true;
  }

  void _focusMapOverview({
    required Size viewportSize,
    required Size contentSize,
  }) {
    if (viewportSize.isEmpty || contentSize.isEmpty) return;
    final fitScale = (viewportSize.width / contentSize.width)
        .clamp(_minMapScale, _maxMapScale)
        .toDouble();
    final scale = (fitScale * 1.2).clamp(_minMapScale, _maxMapScale).toDouble();
    final contentCenter = contentSize.center(Offset.zero);
    final targetCenter = Offset(
      viewportSize.width * 0.5,
      viewportSize.height * 0.49,
    );
    final value = Matrix4.identity()
      ..translateByDouble(
        targetCenter.dx - contentCenter.dx * scale,
        targetCenter.dy - contentCenter.dy * scale,
        0,
        1,
      )
      ..scaleByDouble(scale, scale, 1, 1);
    if (_mapInitialTransformApplied) {
      _animateMapTo(value);
    } else {
      _mapTransformationController.value = value;
    }
  }

  void _zoomMap(double factor) {
    final viewportSize = _mapViewportSize;
    if (viewportSize.isEmpty) return;
    final matrix = _mapTransformationController.value;
    final currentScale = _mapScaleFrom(matrix);
    final nextScale =
        (currentScale * factor).clamp(_minMapScale, _maxMapScale).toDouble();
    if ((nextScale - currentScale).abs() < 0.001) return;

    final translation = matrix.getTranslation();
    final viewportCenter = viewportSize.center(Offset.zero);
    final pointAtCenter = Offset(
      (viewportCenter.dx - translation.x) / currentScale,
      (viewportCenter.dy - translation.y) / currentScale,
    );
    _animateMapTo(
      Matrix4.identity()
        ..translateByDouble(
          viewportCenter.dx - pointAtCenter.dx * nextScale,
          viewportCenter.dy - pointAtCenter.dy * nextScale,
          0,
          1,
        )
        ..scaleByDouble(nextScale, nextScale, 1, 1),
    );
  }

  Future<void> _centerOnCurrentLocation(List<TravelCity> cities) async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      final position =
          await ref.read(mapLocationServiceProvider).currentPosition();
      if (!mounted) return;
      if (!isWithinKoreaMapBounds(
        latitude: position.latitude,
        longitude: position.longitude,
      )) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('현재 위치가 국내 지도 범위를 벗어났어요. 세계 지도를 이용해 주세요.'),
          ),
        );
        return;
      }

      final contentSize = Size(
        _mapViewportSize.width * 1.92,
        _mapViewportSize.height * 1.92,
      );
      final locationPoint = projectKoreaLocationToCanvas(
        size: contentSize,
        cities: cities,
        latitude: position.latitude,
        longitude: position.longitude,
      );
      final scale = _currentMapScale < 1.15 ? 1.15 : _currentMapScale;
      final target = Offset(
        _mapViewportSize.width * 0.5,
        _mapViewportSize.height * 0.48,
      );
      setState(() => _currentLocation = position);
      _animateMapTo(
        Matrix4.identity()
          ..translateByDouble(
            target.dx - locationPoint.dx * scale,
            target.dy - locationPoint.dy * scale,
            0,
            1,
          )
          ..scaleByDouble(scale, scale, 1, 1),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('현재 위치를 지도에 표시했어요.')),
      );
    } on MapLocationException catch (error) {
      if (mounted) _showLocationFailure(error, cities);
    } catch (error) {
      if (mounted) {
        _showLocationFailure(
          MapLocationException(MapLocationFailureReason.unavailable, error),
          cities,
        );
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _showLocationFailure(
    MapLocationException error,
    List<TravelCity> cities,
  ) {
    final service = ref.read(mapLocationServiceProvider);
    final (message, action) = switch (error.reason) {
      MapLocationFailureReason.servicesDisabled => (
          '기기의 위치 서비스가 꺼져 있어요.',
          SnackBarAction(
            label: '위치 설정',
            onPressed: () => service.openLocationSettings(),
          ),
        ),
      MapLocationFailureReason.permissionDenied => (
          '현재 위치를 표시하려면 위치 권한이 필요해요.',
          SnackBarAction(
            label: '다시 요청',
            onPressed: () => _centerOnCurrentLocation(cities),
          ),
        ),
      MapLocationFailureReason.permissionDeniedForever => (
          '위치 권한이 차단되어 있어요. 앱 설정에서 허용해 주세요.',
          SnackBarAction(
            label: '앱 설정',
            onPressed: () => service.openAppSettings(),
          ),
        ),
      MapLocationFailureReason.unavailable => (
          '현재 위치를 확인하지 못했어요. 잠시 후 다시 시도해 주세요.',
          null,
        ),
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), action: action),
    );
  }

  void _selectCity(
    TravelCity city,
    Map<String, TravelCityVisit> visitsByCityId,
  ) {
    final visit = visitsByCityId[city.id];
    final fallbackColor = ref.read(selectedTravelPaletteColorProvider);
    setState(() {
      _selectedCityId = city.id;
      _draftCityId = city.id;
      _editorExpanded = true;
      _memoController.text = visit?.memo ?? '';
      _selectedVisitedAt = visit?.visitedAt;
      _selectedDraftColorHex = visit?.colorHex ?? fallbackColor;
    });
  }

  void _initializeRouteSelection(
    TravelCity city,
    Map<String, TravelCityVisit> visitsByCityId,
  ) {
    if (_draftCityId == city.id) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _selectedCityId != city.id || _draftCityId == city.id) {
        return;
      }
      _selectCity(city, visitsByCityId);
    });
  }

  List<TravelMapPlaceItem> _placeItems(
    List<TravelCity> cities,
    Map<String, TravelCityVisit> visitsByCityId,
  ) {
    return cities.map((city) {
      final visit = visitsByCityId[city.id];
      return TravelMapPlaceItem(
        id: city.id,
        title: city.name,
        subtitle:
            city.regionGroup.isEmpty ? '대한민국' : '대한민국 · ${city.regionGroup}',
        visited: visit != null,
        updatedAt: visit?.updatedAt,
      );
    }).toList(growable: false);
  }

  Future<void> _openExplorer({
    required List<TravelCity> cities,
    required Map<String, TravelCityVisit> visitsByCityId,
    TravelPlaceFilter initialFilter = TravelPlaceFilter.all,
  }) async {
    final cityId = await showTravelPlaceExplorer(
      context: context,
      places: _placeItems(cities, visitsByCityId),
      initialFilter: initialFilter,
    );
    if (!mounted || cityId == null) return;
    for (final city in cities) {
      if (city.id == cityId) {
        _selectCity(city, visitsByCityId);
        return;
      }
    }
  }

  Future<void> _saveCity({
    required String coupleId,
    required TravelCity city,
    required String colorHex,
  }) async {
    if (_saving || _deleting) return;
    setState(() => _saving = true);
    try {
      final memo = _memoController.text.trim();
      await ref.read(upsertTravelVisitProvider)(
        coupleId: coupleId,
        cityId: city.id,
        colorHex: colorHex,
        visitedAt: _selectedVisitedAt,
        memo: memo.isEmpty ? null : memo,
      );
      if (!mounted) return;
      ref.read(selectedTravelPaletteColorProvider.notifier).state = colorHex;
      setState(() => _editorExpanded = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${city.name} 여행 기록을 저장했어요.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(toFriendlyErrorMessage(error))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteCity({
    required String coupleId,
    required TravelCity city,
  }) async {
    if (_saving || _deleting) return;
    setState(() => _deleting = true);
    try {
      await ref.read(deleteTravelVisitProvider)(
        coupleId: coupleId,
        cityId: city.id,
      );
      if (!mounted) return;
      setState(() {
        _memoController.clear();
        _selectedVisitedAt = null;
        _selectedDraftColorHex = ref.read(selectedTravelPaletteColorProvider);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${city.name} 색칠과 기록을 삭제했어요.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(toFriendlyErrorMessage(error))),
      );
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future<void> _pickAndUploadPhoto({
    required String coupleId,
    required TravelCity city,
  }) async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
    );
    if (!mounted || picked == null) return;
    setState(() => _uploadingPhoto = true);
    try {
      final memo = _memoController.text.trim();
      await ref.read(uploadTravelCityPhotoProvider)(
        coupleId: coupleId,
        cityId: city.id,
        bytes: await picked.readAsBytes(),
        extension:
            picked.name.contains('.') ? picked.name.split('.').last : 'jpg',
        caption: memo.isEmpty ? null : memo,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${city.name} 여행 사진을 추가했어요.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(toFriendlyErrorMessage(error))),
      );
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _deletePhoto(TravelCityPhoto photo) async {
    final confirmed = await confirmSharedMapPhotoDeletion(context);
    if (!mounted || !confirmed) return;
    try {
      await ref.read(deleteTravelCityPhotoProvider)(photo);
      ref.invalidate(
        travelCityPhotosProvider((
          coupleId: photo.coupleId,
          cityId: photo.cityId,
        )),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(toFriendlyErrorMessage(error))),
      );
    }
  }

  void _goBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  void _showLoadingMenuMessage(TravelMapMenuAction action) {
    if (action == TravelMapMenuAction.help) {
      showTravelMapHelp(context);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('장소 데이터를 불러오고 있어요.')),
    );
  }

  PreferredSizeWidget _topBar({
    required ValueChanged<TravelMapMenuAction> onMenuSelected,
  }) {
    return TravelMapTopBar(
      section: TravelMapSection.korea,
      onBack: _goBack,
      onSectionSelected: (section) {
        if (section == TravelMapSection.world) context.replace('/world-map');
      },
      onMenuSelected: onMenuSelected,
    );
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(myProfileProvider);
    return profileAsync.when(
      loading: () => Scaffold(
        appBar: _topBar(onMenuSelected: _showLoadingMenuMessage),
        body: const TravelMapLoadingState(),
      ),
      error: (_, __) => Scaffold(
        appBar: _topBar(onMenuSelected: _showLoadingMenuMessage),
        body: TravelMapErrorState(
          message: '프로필을 불러오지 못했어요.',
          onRetry: () => ref.invalidate(myProfileProvider),
        ),
      ),
      data: (profile) {
        if (profile == null || !profile.isPaired || profile.coupleId == null) {
          return Scaffold(
            appBar: _topBar(onMenuSelected: _showLoadingMenuMessage),
            body: const Center(child: Text('커플 연결 후 사용할 수 있어요.')),
          );
        }
        final citiesAsync = ref.watch(travelCitiesProvider);
        return citiesAsync.when(
          loading: () => Scaffold(
            appBar: _topBar(onMenuSelected: _showLoadingMenuMessage),
            body: const TravelMapLoadingState(),
          ),
          error: (_, __) => Scaffold(
            appBar: _topBar(onMenuSelected: _showLoadingMenuMessage),
            body: TravelMapErrorState(
              message: '지역 정보를 불러오지 못했어요.',
              onRetry: () => ref.invalidate(travelCitiesProvider),
            ),
          ),
          data: (cities) {
            if (cities.isEmpty) {
              return Scaffold(
                appBar: _topBar(onMenuSelected: _showLoadingMenuMessage),
                body: TravelMapErrorState(
                  message: '표시할 지역 정보가 아직 없어요.',
                  onRetry: () => ref.invalidate(travelCitiesProvider),
                ),
              );
            }
            final visitsAsync =
                ref.watch(travelCityVisitsProvider(profile.coupleId!));
            final cachedVisits = visitsAsync.valueOrNull;
            if (cachedVisits == null) {
              return visitsAsync.when(
                loading: () => Scaffold(
                  appBar: _topBar(onMenuSelected: _showLoadingMenuMessage),
                  body: const TravelMapLoadingState(),
                ),
                error: (_, __) => Scaffold(
                  appBar: _topBar(onMenuSelected: _showLoadingMenuMessage),
                  body: TravelMapErrorState(
                    message: '여행 기록을 불러오지 못했어요.',
                    onRetry: () => ref.invalidate(
                      travelCityVisitsProvider(profile.coupleId!),
                    ),
                  ),
                ),
                data: (_) => const SizedBox.shrink(),
              );
            }
            return _buildMapScaffold(
              coupleId: profile.coupleId!,
              cities: cities,
              visits: cachedVisits,
              realtimeError: visitsAsync.hasError,
            );
          },
        );
      },
    );
  }

  Widget _buildMapScaffold({
    required String coupleId,
    required List<TravelCity> cities,
    required List<TravelCityVisit> visits,
    required bool realtimeError,
  }) {
    final visitsByCityId = {for (final visit in visits) visit.cityId: visit};
    final colorsByCityId = {
      for (final visit in visits) visit.cityId: visit.colorHex,
    };
    if (_selectedCityId != null && _selectedDraftColorHex != null) {
      colorsByCityId[_selectedCityId!] = _selectedDraftColorHex!;
    }

    TravelCity? selectedCity;
    for (final city in cities) {
      if (city.id == _selectedCityId) {
        selectedCity = city;
        break;
      }
    }
    if (selectedCity != null) {
      _initializeRouteSelection(selectedCity, visitsByCityId);
    }

    final selectedPhotosAsync = selectedCity == null
        ? null
        : ref.watch(
            travelCityPhotosProvider((
              coupleId: coupleId,
              cityId: selectedCity.id,
            )),
          );
    final selectedPhotos =
        selectedPhotosAsync?.valueOrNull ?? const <TravelCityPhoto>[];
    var selectedColor = ref.watch(selectedTravelPaletteColorProvider);
    final existingColor =
        selectedCity == null ? null : visitsByCityId[selectedCity.id]?.colorHex;
    selectedColor = _selectedDraftColorHex ?? existingColor ?? selectedColor;

    void handleMenu(TravelMapMenuAction action) {
      switch (action) {
        case TravelMapMenuAction.all:
          _openExplorer(cities: cities, visitsByCityId: visitsByCityId);
        case TravelMapMenuAction.visited:
          _openExplorer(
            cities: cities,
            visitsByCityId: visitsByCityId,
            initialFilter: TravelPlaceFilter.visited,
          );
        case TravelMapMenuAction.unvisited:
          _openExplorer(
            cities: cities,
            visitsByCityId: visitsByCityId,
            initialFilter: TravelPlaceFilter.unvisited,
          );
        case TravelMapMenuAction.help:
          showTravelMapHelp(context);
      }
    }

    return Scaffold(
      backgroundColor: DearColors.backgroundTop,
      appBar: _topBar(onMenuSelected: handleMenu),
      body: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned.fill(
            child: ColoredBox(
              color: const Color(0xFFEAF3F7),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  _mapViewportSize = constraints.biggest;
                  final contentSize = Size(
                    constraints.maxWidth * 1.92,
                    constraints.maxHeight * 1.92,
                  );
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      _applyInitialMapFocus(
                        viewportConstraints: constraints,
                        contentSize: contentSize,
                      );
                    }
                  });
                  return InteractiveViewer(
                    transformationController: _mapTransformationController,
                    constrained: false,
                    minScale: _minMapScale,
                    maxScale: _maxMapScale,
                    boundaryMargin: const EdgeInsets.all(900),
                    panEnabled: true,
                    scaleEnabled: true,
                    clipBehavior: Clip.none,
                    child: SizedBox(
                      width: contentSize.width,
                      height: contentSize.height,
                      child: KoreaCityMapCanvas(
                        cities: cities,
                        colorByCityId: colorsByCityId,
                        selectedCityId: _selectedCityId,
                        labelScaleFactor: 1 /
                            _currentMapScale.clamp(1, _maxMapScale).toDouble(),
                        currentLocationLngLat: _currentLocation == null
                            ? null
                            : Offset(
                                _currentLocation!.longitude,
                                _currentLocation!.latitude,
                              ),
                        onTapCity: (city) => _selectCity(city, visitsByCityId),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          if (_editorExpanded)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () {
                  FocusScope.of(context).unfocus();
                  setState(() => _editorExpanded = false);
                },
              ),
            ),
          Positioned.fill(
            child: TravelMapAccessibleOverlay(
              placeListLauncher: TravelMapSearchLauncher(
                onTap: () => _openExplorer(
                  cities: cities,
                  visitsByCityId: visitsByCityId,
                ),
              ),
              visitedCount: visitsByCityId.length,
              totalCount: cities.length,
              placeLabel: '대한민국',
              realtimeError: realtimeError,
              realtimeSemanticLabel: '실시간 연결 끊김. 마지막 여행 기록 표시 중',
              zoomBottom: selectedCity == null ? 128 : 136,
              zoomControlsBuilder: _editorExpanded
                  ? null
                  : (horizontal) => TravelMapZoomControls(
                        horizontal: horizontal,
                        canZoomIn: _currentMapScale < _maxMapScale - 0.01,
                        canZoomOut: _currentMapScale > _minMapScale + 0.01,
                        locating: _locating,
                        onZoomIn: () => _zoomMap(1.12),
                        onZoomOut: () => _zoomMap(0.89),
                        onCurrentLocation: () =>
                            _centerOnCurrentLocation(cities),
                        onReset: () => _focusMapOverview(
                          viewportSize: _mapViewportSize,
                          contentSize: Size(
                            _mapViewportSize.width * 1.92,
                            _mapViewportSize.height * 1.92,
                          ),
                        ),
                      ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: _editorExpanded && selectedCity != null
                  ? TravelMapRecordEditor(
                      key: const ValueKey('travel-map-editor-expanded'),
                      placeName: selectedCity.name,
                      regionLabel: selectedCity.regionGroup.isEmpty
                          ? '대한민국'
                          : '대한민국 · ${selectedCity.regionGroup}',
                      palette: _palette,
                      selectedColor: selectedColor,
                      memoController: _memoController,
                      visitedAt: _selectedVisitedAt,
                      photos: selectedPhotos
                          .map(
                            (photo) => TravelMapPhotoItem(
                              id: photo.id,
                              url: photo.signedUrl,
                              semanticLabel: '${selectedCity!.name} 여행 사진',
                            ),
                          )
                          .toList(growable: false),
                      photosLoading: selectedPhotosAsync?.isLoading ?? false,
                      photosError: selectedPhotosAsync?.hasError ?? false
                          ? '사진을 불러오지 못했어요. 실시간 연결을 확인해 주세요.'
                          : null,
                      saving: _saving,
                      deleting: _deleting,
                      uploadingPhoto: _uploadingPhoto,
                      hasRecord: visitsByCityId.containsKey(selectedCity.id),
                      onCollapse: () => setState(() => _editorExpanded = false),
                      onPickDate: () async {
                        final now = DateTime.now();
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _selectedVisitedAt ?? now,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(now.year + 3),
                        );
                        if (!mounted || picked == null) return;
                        setState(() => _selectedVisitedAt = picked);
                      },
                      onClearDate: () =>
                          setState(() => _selectedVisitedAt = null),
                      onSelectColor: (color) => setState(
                        () => _selectedDraftColorHex = color,
                      ),
                      onSave: () => _saveCity(
                        coupleId: coupleId,
                        city: selectedCity!,
                        colorHex: selectedColor,
                      ),
                      onDelete: () => _deleteCity(
                        coupleId: coupleId,
                        city: selectedCity!,
                      ),
                      onAddPhoto: () => _pickAndUploadPhoto(
                        coupleId: coupleId,
                        city: selectedCity!,
                      ),
                      onDeletePhoto: (photoId) {
                        for (final photo in selectedPhotos) {
                          if (photo.id == photoId) {
                            _deletePhoto(photo);
                            return;
                          }
                        }
                      },
                    )
                  : TravelMapCollapsedEditor(
                      key: const ValueKey('travel-map-editor-collapsed'),
                      placeName: selectedCity?.name,
                      regionLabel: selectedCity?.regionGroup.isEmpty ?? true
                          ? '대한민국'
                          : '대한민국 · ${selectedCity!.regionGroup}',
                      onExpand: selectedCity == null
                          ? null
                          : () => setState(() => _editorExpanded = true),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
