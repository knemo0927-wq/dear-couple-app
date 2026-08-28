import 'package:couple_chat_app/src/common/dear_design.dart';
import 'package:couple_chat_app/src/common/error_mapper.dart';
import 'package:couple_chat_app/src/features/auth/data/auth_providers.dart';
import 'package:couple_chat_app/src/features/travel_map/data/map_location_service.dart';
import 'package:couple_chat_app/src/features/travel_map/presentation/travel_map_filter.dart';
import 'package:couple_chat_app/src/features/travel_map/presentation/widgets/travel_map_controls.dart';
import 'package:couple_chat_app/src/features/travel_map/presentation/widgets/travel_map_explorer.dart';
import 'package:couple_chat_app/src/features/travel_map/presentation/widgets/travel_map_record_editor.dart';
import 'package:couple_chat_app/src/features/travel_map/presentation/widgets/travel_map_top_bar.dart';
import 'package:couple_chat_app/src/features/world_map/data/world_map_providers.dart';
import 'package:couple_chat_app/src/features/world_map/data/world_map_repository.dart';
import 'package:couple_chat_app/src/features/world_map/presentation/widgets/world_globe_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

class WorldMapPage extends ConsumerStatefulWidget {
  const WorldMapPage({this.initialCountryCode, super.key});

  final String? initialCountryCode;

  @override
  ConsumerState<WorldMapPage> createState() => _WorldMapPageState();
}

class _WorldMapPageState extends ConsumerState<WorldMapPage> {
  final TextEditingController _memoController = TextEditingController();

  late Future<List<GlobeCountryShape>> _shapesFuture;
  String? _selectedCode;
  String? _draftCountryCode;
  DateTime? _visitedAt;
  String? _draftColorHex;
  double _centerLat = 20;
  double _centerLng = 127;
  double _zoom = 1;
  bool _editorExpanded = false;
  bool _saving = false;
  bool _deleting = false;
  bool _uploadingPhoto = false;
  bool _locating = false;
  MapPosition? _currentLocation;

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
    _selectedCode = widget.initialCountryCode;
    _editorExpanded = widget.initialCountryCode != null;
    _shapesFuture = loadWorldCountryShapes();
  }

  @override
  void dispose() {
    _memoController.dispose();
    super.dispose();
  }

  void _selectCountry(
    WorldCountry country,
    Map<String, WorldCountryVisit> visitsByCode,
  ) {
    final visit = visitsByCode[country.code];
    final fallbackColor = ref.read(selectedWorldPaletteColorProvider);
    setState(() {
      _selectedCode = country.code;
      _draftCountryCode = country.code;
      _editorExpanded = true;
      _memoController.text = visit?.memo ?? '';
      _visitedAt = visit?.visitedAt;
      _draftColorHex = visit?.colorHex ?? fallbackColor;
      _centerLat = country.centerLat.clamp(-70, 70).toDouble();
      _centerLng = country.centerLng;
      _zoom = _zoom < 1.15 ? 1.15 : _zoom;
    });
  }

  void _initializeRouteSelection(
    WorldCountry country,
    Map<String, WorldCountryVisit> visitsByCode,
  ) {
    if (_draftCountryCode == country.code) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _selectedCode != country.code ||
          _draftCountryCode == country.code) {
        return;
      }
      _selectCountry(country, visitsByCode);
    });
  }

  List<TravelMapPlaceItem> _placeItems(
    List<WorldCountry> countries,
    Map<String, WorldCountryVisit> visitsByCode,
  ) {
    return countries.map((country) {
      final visit = visitsByCode[country.code];
      return TravelMapPlaceItem(
        id: country.code,
        title: country.displayName,
        subtitle: country.nameEn.isEmpty ? '세계' : country.nameEn,
        visited: visit != null,
        updatedAt: visit?.updatedAt,
      );
    }).toList(growable: false);
  }

  Future<void> _openExplorer({
    required List<WorldCountry> countries,
    required Map<String, WorldCountryVisit> visitsByCode,
    TravelPlaceFilter initialFilter = TravelPlaceFilter.all,
  }) async {
    final code = await showTravelPlaceExplorer(
      context: context,
      places: _placeItems(countries, visitsByCode),
      initialFilter: initialFilter,
    );
    if (!mounted || code == null) return;
    for (final country in countries) {
      if (country.code == code) {
        _selectCountry(country, visitsByCode);
        return;
      }
    }
  }

  Future<void> _saveCountry({
    required String coupleId,
    required WorldCountry country,
    required String colorHex,
  }) async {
    if (_saving || _deleting) return;
    setState(() => _saving = true);
    try {
      final memo = _memoController.text.trim();
      await ref.read(upsertWorldVisitProvider)(
        coupleId: coupleId,
        countryCode: country.code,
        colorHex: colorHex,
        visitedAt: _visitedAt,
        memo: memo.isEmpty ? null : memo,
      );
      if (!mounted) return;
      ref.read(selectedWorldPaletteColorProvider.notifier).state = colorHex;
      setState(() => _editorExpanded = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${country.displayName} 여행 기록을 저장했어요.')),
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

  Future<void> _deleteCountry({
    required String coupleId,
    required WorldCountry country,
  }) async {
    if (_saving || _deleting) return;
    setState(() => _deleting = true);
    try {
      await ref.read(deleteWorldVisitProvider)(
        coupleId: coupleId,
        countryCode: country.code,
      );
      if (!mounted) return;
      setState(() {
        _memoController.clear();
        _visitedAt = null;
        _draftColorHex = ref.read(selectedWorldPaletteColorProvider);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${country.displayName} 색칠과 기록을 삭제했어요.')),
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
    required WorldCountry country,
  }) async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
    );
    if (!mounted || picked == null) return;
    setState(() => _uploadingPhoto = true);
    try {
      final memo = _memoController.text.trim();
      await ref.read(uploadWorldCountryPhotoProvider)(
        coupleId: coupleId,
        countryCode: country.code,
        bytes: await picked.readAsBytes(),
        extension:
            picked.name.contains('.') ? picked.name.split('.').last : 'jpg',
        caption: memo.isEmpty ? null : memo,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${country.displayName} 여행 사진을 추가했어요.')),
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

  Future<void> _deletePhoto(WorldCountryPhoto photo) async {
    final confirmed = await confirmSharedMapPhotoDeletion(context);
    if (!mounted || !confirmed) return;
    try {
      await ref.read(deleteWorldCountryPhotoProvider)(photo);
      ref.invalidate(
        worldCountryPhotosProvider((
          coupleId: photo.coupleId,
          countryCode: photo.countryCode,
        )),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(toFriendlyErrorMessage(error))),
      );
    }
  }

  Future<void> _centerOnCurrentLocation() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      final position =
          await ref.read(mapLocationServiceProvider).currentPosition();
      if (!mounted) return;
      setState(() {
        _currentLocation = position;
        _centerLat = position.latitude.clamp(-70, 70).toDouble();
        _centerLng = position.longitude;
        _zoom = _zoom < 1.35 ? 1.35 : _zoom;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('현재 위치를 지도에 표시했어요.')),
      );
    } on MapLocationException catch (error) {
      if (mounted) _showLocationFailure(error);
    } catch (error) {
      if (mounted) {
        _showLocationFailure(
          MapLocationException(MapLocationFailureReason.unavailable, error),
        );
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _showLocationFailure(MapLocationException error) {
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
            onPressed: _centerOnCurrentLocation,
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
      section: TravelMapSection.world,
      onBack: _goBack,
      onSectionSelected: (section) {
        if (section == TravelMapSection.korea) context.replace('/travel-map');
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
        final countriesAsync = ref.watch(worldCountriesProvider);
        return countriesAsync.when(
          loading: () => Scaffold(
            appBar: _topBar(onMenuSelected: _showLoadingMenuMessage),
            body: const TravelMapLoadingState(label: '세계 지도를 불러오고 있어요'),
          ),
          error: (_, __) => Scaffold(
            appBar: _topBar(onMenuSelected: _showLoadingMenuMessage),
            body: TravelMapErrorState(
              message: '국가 정보를 불러오지 못했어요.',
              onRetry: () => ref.invalidate(worldCountriesProvider),
            ),
          ),
          data: (countries) {
            if (countries.isEmpty) {
              return Scaffold(
                appBar: _topBar(onMenuSelected: _showLoadingMenuMessage),
                body: TravelMapErrorState(
                  message: '표시할 국가 정보가 아직 없어요.',
                  onRetry: () => ref.invalidate(worldCountriesProvider),
                ),
              );
            }
            final visitsAsync =
                ref.watch(worldCountryVisitsProvider(profile.coupleId!));
            final cachedVisits = visitsAsync.valueOrNull;
            if (cachedVisits == null) {
              return visitsAsync.when(
                loading: () => Scaffold(
                  appBar: _topBar(onMenuSelected: _showLoadingMenuMessage),
                  body: const TravelMapLoadingState(
                    label: '세계 여행 기록을 불러오고 있어요',
                  ),
                ),
                error: (_, __) => Scaffold(
                  appBar: _topBar(onMenuSelected: _showLoadingMenuMessage),
                  body: TravelMapErrorState(
                    message: '세계 여행 기록을 불러오지 못했어요.',
                    onRetry: () => ref.invalidate(
                      worldCountryVisitsProvider(profile.coupleId!),
                    ),
                  ),
                ),
                data: (_) => const SizedBox.shrink(),
              );
            }
            return _buildMapScaffold(
              coupleId: profile.coupleId!,
              countries: countries,
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
    required List<WorldCountry> countries,
    required List<WorldCountryVisit> visits,
    required bool realtimeError,
  }) {
    final countriesByCode = {
      for (final country in countries) country.code: country
    };
    final visitsByCode = {for (final visit in visits) visit.countryCode: visit};
    final colorsByCode = {
      for (final visit in visits) visit.countryCode: visit.colorHex,
    };
    if (_selectedCode != null && _draftColorHex != null) {
      colorsByCode[_selectedCode!] = _draftColorHex!;
    }
    final selectedCountry =
        _selectedCode == null ? null : countriesByCode[_selectedCode!];
    if (selectedCountry != null) {
      _initializeRouteSelection(selectedCountry, visitsByCode);
    }

    final selectedPhotosAsync = selectedCountry == null
        ? null
        : ref.watch(
            worldCountryPhotosProvider((
              coupleId: coupleId,
              countryCode: selectedCountry.code,
            )),
          );
    final selectedPhotos =
        selectedPhotosAsync?.valueOrNull ?? const <WorldCountryPhoto>[];
    var selectedColor = ref.watch(selectedWorldPaletteColorProvider);
    final existingColor = selectedCountry == null
        ? null
        : visitsByCode[selectedCountry.code]?.colorHex;
    selectedColor = _draftColorHex ?? existingColor ?? selectedColor;

    void handleMenu(TravelMapMenuAction action) {
      switch (action) {
        case TravelMapMenuAction.all:
          _openExplorer(countries: countries, visitsByCode: visitsByCode);
        case TravelMapMenuAction.visited:
          _openExplorer(
            countries: countries,
            visitsByCode: visitsByCode,
            initialFilter: TravelPlaceFilter.visited,
          );
        case TravelMapMenuAction.unvisited:
          _openExplorer(
            countries: countries,
            visitsByCode: visitsByCode,
            initialFilter: TravelPlaceFilter.unvisited,
          );
        case TravelMapMenuAction.help:
          showTravelMapHelp(context);
      }
    }

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      appBar: _topBar(onMenuSelected: handleMenu),
      body: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned.fill(
            child: ColoredBox(
              color: const Color(0xFFEAF3F7),
              child: FutureBuilder<List<GlobeCountryShape>>(
                future: _shapesFuture,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return TravelMapErrorState(
                      message: '세계 지도 도형을 불러오지 못했어요.',
                      onRetry: () => setState(
                        () => _shapesFuture = loadWorldCountryShapes(),
                      ),
                    );
                  }
                  final shapes = snapshot.data;
                  if (shapes == null) return const TravelMapLoadingState();
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(8, 74, 8, 116),
                    child: WorldGlobeCanvas(
                      shapes: shapes,
                      visitColorsByCode: colorsByCode,
                      selectedCode: _selectedCode,
                      centerLat: _centerLat,
                      centerLng: _centerLng,
                      zoom: _zoom,
                      currentLocationLat: _currentLocation?.latitude,
                      currentLocationLng: _currentLocation?.longitude,
                      onChangedView: (lat, lng) => setState(() {
                        _centerLat = lat;
                        _centerLng = lng;
                      }),
                      onCountryTap: (code) {
                        final country = countriesByCode[code];
                        if (country != null) {
                          _selectCountry(country, visitsByCode);
                        }
                      },
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
                  countries: countries,
                  visitsByCode: visitsByCode,
                ),
              ),
              visitedCount: visitsByCode.length,
              totalCount: countries.length,
              placeLabel: '세계',
              realtimeError: realtimeError,
              realtimeSemanticLabel: '실시간 연결 끊김. 마지막 세계 여행 기록 표시 중',
              zoomBottom: selectedCountry == null ? 128 : 136,
              zoomControlsBuilder: _editorExpanded
                  ? null
                  : (horizontal) => TravelMapZoomControls(
                        horizontal: horizontal,
                        canZoomIn: _zoom < 3.2,
                        canZoomOut: _zoom > 0.55,
                        locating: _locating,
                        onZoomIn: () => setState(
                          () =>
                              _zoom = (_zoom * 1.2).clamp(0.55, 3.2).toDouble(),
                        ),
                        onZoomOut: () => setState(
                          () =>
                              _zoom = (_zoom / 1.2).clamp(0.55, 3.2).toDouble(),
                        ),
                        onCurrentLocation: _centerOnCurrentLocation,
                        onReset: () => setState(() {
                          _centerLat = 20;
                          _centerLng = 127;
                          _zoom = 1;
                        }),
                      ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AnimatedSwitcher(
              key: const ValueKey('travel-map-editor-switcher'),
              duration: DearMotion.duration(context, DearMotion.standard),
              child: _editorExpanded && selectedCountry != null
                  ? TravelMapRecordEditor(
                      key: const ValueKey('travel-map-editor-expanded'),
                      placeName: selectedCountry.displayName,
                      regionLabel: selectedCountry.nameEn.isEmpty
                          ? '세계'
                          : selectedCountry.nameEn,
                      palette: _palette,
                      selectedColor: selectedColor,
                      memoController: _memoController,
                      visitedAt: _visitedAt,
                      photos: selectedPhotos
                          .map(
                            (photo) => TravelMapPhotoItem(
                              id: photo.id,
                              url: photo.signedUrl,
                              semanticLabel:
                                  '${selectedCountry.displayName} 여행 사진',
                            ),
                          )
                          .toList(growable: false),
                      photosLoading: selectedPhotosAsync?.isLoading ?? false,
                      photosError: selectedPhotosAsync?.hasError ?? false
                          ? '세계 여행 사진을 불러오지 못했어요. 서버 사진 설정을 확인해 주세요.'
                          : null,
                      saving: _saving,
                      deleting: _deleting,
                      uploadingPhoto: _uploadingPhoto,
                      hasRecord: visitsByCode.containsKey(selectedCountry.code),
                      onCollapse: () => setState(() => _editorExpanded = false),
                      onPickDate: () async {
                        final now = DateTime.now();
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _visitedAt ?? now,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(now.year + 3),
                        );
                        if (!mounted || picked == null) return;
                        setState(() => _visitedAt = picked);
                      },
                      onClearDate: () => setState(() => _visitedAt = null),
                      onSelectColor: (color) =>
                          setState(() => _draftColorHex = color),
                      onSave: () => _saveCountry(
                        coupleId: coupleId,
                        country: selectedCountry,
                        colorHex: selectedColor,
                      ),
                      onDelete: () => _deleteCountry(
                        coupleId: coupleId,
                        country: selectedCountry,
                      ),
                      onAddPhoto: () => _pickAndUploadPhoto(
                        coupleId: coupleId,
                        country: selectedCountry,
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
                      placeName: selectedCountry?.displayName,
                      regionLabel: selectedCountry?.nameEn.isEmpty ?? true
                          ? '세계'
                          : selectedCountry!.nameEn,
                      onExpand: selectedCountry == null
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
