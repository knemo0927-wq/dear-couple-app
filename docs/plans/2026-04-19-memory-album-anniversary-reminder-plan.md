# Memory Album + Anniversary Reminder Implementation Plan

**Goal:** 채팅 이미지 확대 뷰어를 제공하고, 채팅 목록의 `추억 앨범 알림`/`기념일 리마인더`를 실제 기능 화면으로 연결한다.

## 기능 정의

1. 이미지 확대 뷰어
- 채팅방 이미지 버블 탭 시 전체화면 페이지로 이동
- 핀치 줌/드래그 지원(InteractiveViewer)

2. 추억 앨범
- 채팅 메시지 중 이미지가 있는 항목만 모아 그리드로 표시
- 썸네일 탭 시 전체화면 이미지 뷰어로 이동

3. 기념일 리마인더
- Supabase `anniversaries` 테이블 기반 목록
- 리마인더 추가(제목 + 날짜), 삭제
- 각 항목 D-day 계산 표시

## 라우팅
- `/memory-album`
- `/anniversary-reminders`

## UX 연결
- 채팅 목록 카드
  - `추억 앨범 알림` -> `/memory-album`
  - `기념일 리마인더` -> `/anniversary-reminders`

## 파일
- 생성
  - `lib/src/features/chat/presentation/chat_image_view_page.dart`
  - `lib/src/features/chat/presentation/memory_album_page.dart`
  - `lib/src/features/anniversary/data/anniversary_repository.dart`
  - `lib/src/features/anniversary/data/anniversary_providers.dart`
  - `lib/src/features/anniversary/presentation/anniversary_reminder_page.dart`
- 수정
  - `lib/src/features/chat/presentation/chat_page.dart`
  - `lib/src/features/chat/presentation/chat_list_page.dart`
  - `lib/src/app_router.dart`

## 검증 시나리오
1. 채팅방에서 이미지 탭 -> 전체화면 뷰 열림
2. 채팅 목록 > 추억 앨범 알림 -> 앨범 화면 열림
3. 앨범 썸네일 탭 -> 전체화면 뷰 열림
4. 채팅 목록 > 기념일 리마인더 -> 목록 화면 열림
5. 리마인더 추가 후 즉시 목록 반영
6. 리마인더 삭제 후 목록에서 제거
