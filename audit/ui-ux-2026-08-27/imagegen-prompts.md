# ImageGen 산출물과 최종 프롬프트

모든 산출물은 API/CLI가 아닌 Codex 내장 ImageGen으로 만들었고, 생성 후 프로젝트의 `audit/ui-ux-2026-08-27/designs/`에 복사했다.

## 1. 홈 개선 시안

파일: `designs/home-redesign-concept.png`

```text
Use case: ui-mockup
Asset type: polished iOS mobile app redesign concept for the Dear home screen
Input images: Image 1 is the current home screen and the layout/content reference; Image 2 is the mascot identity and material-style reference
Primary request: redesign the current Dear home screen so the next useful action is immediately obvious while preserving its warm Korean couple-app identity
Style/medium: realistic, shippable Flutter/iOS product UI; soft flat surfaces with the existing matte clay mascot used only as the emotional accent
Composition/framing: one portrait iPhone screen, same major content order: compact Dear header and notification, greeting/couple avatars, relationship D-day hero, one emphasized continue-chat card, next anniversary, recent memories, four-item bottom tab bar
Hierarchy: make the continue-chat card the clear primary action after the D-day hero; increase secondary-text readability; use consistent 16pt horizontal gutters, 8pt spacing rhythm, 44pt minimum controls, clear safe-area padding, and a quieter shadow system
Color palette: preserve Dear blush pink, coral, ivory, white, and dark charcoal text; use darker coral only for small functional text so contrast is strong
Text (verbatim where rendered): "Dear", "안녕하세요, 우리", "오늘도 좋은 하루 보내세요", "우리의 연애", "D+1097", "2023.08.27부터 함께", "젤라님과 채팅", "그랑", "다음 기념일", "오늘은 3주년이에요", "2026.08.27", "최근 추억", "더보기", "홈", "채팅", "앨범", "더보기"
Constraints: preserve the two mascots' exact proportions, faces, coral-and-ivory identities, and matte clay material; do not add new features; no glassmorphism; no oversized decorative cards; no emoji; no watermark; avoid personal facial detail by using neutral softly blurred photo placeholders for avatars and memory thumbnails; keep every label readable and inside the phone frame
```

## 2. 채팅 개선 시안

최종 파일: `designs/chat-redesign-concept-v2.png`

기본 생성 프롬프트:

```text
Use case: ui-mockup
Asset type: polished iOS mobile chat screen redesign concept for Dear
Input images: Image 1 is the current screen and edit/reference target
Primary request: redesign only the interface chrome, spacing, typography, and interaction hierarchy while preserving the existing Korean conversation and warm blush brand
Style/medium: realistic, shippable Flutter/iOS UI; simple soft surfaces, not concept art
Composition/framing: one portrait iPhone screen. Header uses a 44pt back control, neutral blurred avatar, "젤라" as the main title, "마지막 활동 7월 12일" as readable secondary text, and a single 44pt more button. The relationship-day chip is smaller and lower emphasis. Message list keeps incoming white and outgoing pale blush bubbles, date separators, delivery time, and reactions.
Interaction improvements: group each heart reaction directly under its bubble in a clear compact pill; make metadata at least 12–13pt and darker; maintain generous vertical rhythm. Replace the two ambiguous media icons with one 44pt plus attachment button, a flexible text input, and a 44pt send button. Show clear disabled send state without relying on low contrast alone.
Color palette: existing Dear blush pink, deeper coral for functional labels, ivory-white background, dark charcoal text, subtle rose border
Text (verbatim where rendered): "젤라", "마지막 활동 7월 12일", "D+1097", "2026.05.04", "우리 누나 빠이팅!!", "전송됨 09:25", "빠이팅!", "09:25", "사랑해용ㅎㅎ", "전송됨 10:22", "2026.07.12", "사랑해 젤라❤️", "전송됨 23:32", "그랑", "23:32", "메시지 입력..."
Constraints: keep the same number and order of messages; no phone-call/video-call features; no extra tabs; no glassmorphism; no emoji used as structural icons; no watermark; replace all personal faces with neutral softly blurred circular placeholders; keep all labels legible inside safe areas
```

검수 후 단일 수정 프롬프트:

```text
Use case: precise-object-edit
Asset type: refined Dear chat UI mockup
Input images: Image 1 is the edit target
Primary request: remove only the three reaction pills that display a heart with the number 0. Keep the single heart reaction pill with count 1 under "사랑해 젤라❤️".
Constraints: change only the zero-count reaction pills; preserve every message, text string, avatar placeholder, timestamp, spacing, header, composer, colors, dimensions, typography, safe areas, and all other layout exactly; no extra text or UI; no watermark
```

## 3. 앨범 기본 커버·빈 상태 자산

파일: `designs/album-empty-cover-concept.png`

```text
Use case: stylized-concept
Asset type: reusable 3:2 landscape empty-album cover and empty-state illustration for the Dear mobile app
Input images: Image 1 is the strict character-identity and material-style reference
Primary request: the same two abstract blob mascots gently hold one blank instant-photo frame together, communicating "our memories will go here"
Subject: exactly two characters only — left coral pink, right warm ivory — with the same proportions, dot eyes, small smiles, rounded feet, and friendly relationship as the reference
Style/medium: polished soft matte clay 3D, subtle tactile texture, upper-left diffuse studio light, soft contact shadows
Composition/framing: centered pair in a wide 3:2 composition; full silhouettes and the blank instant-photo frame fully visible; 12–15% safe padding; designed to crop safely inside a rounded album-cover card
Color palette: Dear coral #E85D8B, soft blush #F7A8BD, warm ivory, very pale pink background with enough separation around the ivory character
Constraints: no text, no logos, no watermark, no heart-shaped frame, no extra characters or props, no gendered clothing, no photo inside the instant-photo frame, no glossy resin look, do not change the character faces or proportions
```

