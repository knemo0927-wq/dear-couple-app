import 'package:couple_chat_app/src/features/travel_map/presentation/widgets/travel_map_record_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('사진 로드 오류는 다시 시도 액션을 노출하고 callback을 실행한다', (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var retryCalls = 0;
    final memoController = TextEditingController();
    addTearDown(memoController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(375, 812),
            textScaler: TextScaler.linear(2),
          ),
          child: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: TravelMapRecordEditor(
                placeName: '광명',
                regionLabel: '대한민국 · 경기',
                palette: const ['#EF6F89'],
                selectedColor: '#EF6F89',
                memoController: memoController,
                visitedAt: null,
                photos: const [],
                photosLoading: false,
                photosError: '사진을 불러오지 못했어요.',
                saving: false,
                deleting: false,
                uploadingPhoto: false,
                hasRecord: false,
                onCollapse: () {},
                onPickDate: () {},
                onClearDate: () {},
                onSelectColor: (_) {},
                onSave: () {},
                onDelete: null,
                onAddPhoto: null,
                onDeletePhoto: (_) {},
                onRetryPhotos: () => retryCalls++,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('사진을 불러오지 못했어요.'), findsOneWidget);
    final retryButton = find.byKey(
      const ValueKey('travel-map-photo-retry-button'),
    );
    expect(retryButton, findsOneWidget);
    expect(
      find.descendant(of: retryButton, matching: find.text('다시 시도')),
      findsOneWidget,
    );
    final retrySize = tester.getSize(retryButton);
    expect(retrySize.width, greaterThanOrEqualTo(44));
    expect(retrySize.height, greaterThanOrEqualTo(44));
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(retryButton);
    await tester.tap(retryButton);

    expect(retryCalls, 1);
  });

  testWidgets('서명 URL이 실패한 사진도 자리와 삭제 동작을 유지한다', (tester) async {
    String? deletedPhotoId;
    final memoController = TextEditingController();
    addTearDown(memoController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: TravelMapRecordEditor(
              placeName: '광명',
              regionLabel: '대한민국 · 경기',
              palette: const ['#EF6F89'],
              selectedColor: '#EF6F89',
              memoController: memoController,
              visitedAt: null,
              photos: const [
                TravelMapPhotoItem(
                  id: 'photo-1',
                  url: null,
                  semanticLabel: '광명 여행 사진, 미리보기를 불러오지 못함',
                ),
              ],
              photosLoading: false,
              photosError: '1장의 사진 미리보기를 불러오지 못했어요.',
              saving: false,
              deleting: false,
              uploadingPhoto: false,
              hasRecord: false,
              onCollapse: () {},
              onPickDate: () {},
              onClearDate: () {},
              onSelectColor: (_) {},
              onSave: () {},
              onDelete: null,
              onAddPhoto: null,
              onDeletePhoto: (photoId) => deletedPhotoId = photoId,
              onRetryPhotos: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    expect(
      find.bySemanticsLabel('광명 여행 사진, 미리보기를 불러오지 못함'),
      findsOneWidget,
    );

    await tester.ensureVisible(find.byTooltip('함께 보관한 사진 삭제'));
    await tester.tap(find.byTooltip('함께 보관한 사진 삭제'));
    expect(deletedPhotoId, 'photo-1');
  });
}
