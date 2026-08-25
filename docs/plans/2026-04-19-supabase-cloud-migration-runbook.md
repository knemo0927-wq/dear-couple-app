# Supabase Cloud 전환 런북

## 목표
로컬 Supabase(`http://<맥IP>:54321`) 의존을 제거하고, LTE/외부망에서도 앱이 동작하도록 Supabase Cloud로 전환한다.

## 사전 준비
- Supabase Cloud 프로젝트 생성 (지역: ap-northeast-2 권장)
- Dashboard > Project Settings > API에서 값 확보
  - `SUPABASE_URL` = `https://<project-ref>.supabase.co`
  - `SUPABASE_ANON_KEY` = `sb_publishable_...`
- Dashboard > Project Settings > Database에서 DB 비밀번호 확인
- https://supabase.com/dashboard/account/tokens 에서 personal access token 생성

필수 환경변수:
- `SUPABASE_ACCESS_TOKEN`
- `SUPABASE_PROJECT_REF`
- `SUPABASE_DB_PASSWORD`
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`

## 1) Cloud DB 마이그레이션 + 스모크 테스트
레포 루트에서:

```bash
export SUPABASE_ACCESS_TOKEN='<pat>'
export SUPABASE_PROJECT_REF='<project-ref>'
export SUPABASE_DB_PASSWORD='<db-password>'
export SUPABASE_URL='https://<project-ref>.supabase.co'
export SUPABASE_ANON_KEY='<sb_publishable_xxx>'

./scripts/migrate_supabase_to_cloud.sh
```

성공 기준:
- `supabase db push` 성공
- `scripts/supabase_e2e_smoke.py` 결과 `"ok": true`

## 2) 앱 실행(Cloud 키 주입)
### Android
```bash
cd app
SUPABASE_URL='https://<project-ref>.supabase.co' SUPABASE_ANON_KEY='<sb_publishable_xxx>' ./scripts/run_android_cloud.sh
```

### iOS 실기기
```bash
cd app
SUPABASE_URL='https://<project-ref>.supabase.co' SUPABASE_ANON_KEY='<sb_publishable_xxx>' IOS_DEVICE_ID='<ios-device-udid>' ./scripts/run_ios_cloud.sh
```

## 3) 검증 체크리스트
- 회원가입/로그인 성공
- 페어링 코드 연결 성공
- 텍스트 메시지 송수신
- 이미지 업로드 + 추억 앨범 노출
- 기념일 리마인더 CRUD
- (옵션) 푸시 토큰 등록 및 push_events 적재

## 4) 전환 후 권장 정리
- Android Studio Run Configuration에 Cloud dart-define 값 반영
- 기존 로컬 URL(`10.0.2.2`, `host.docker.internal`, `<맥IP>:54321`) 사용 스크립트는 보조 용도로만 유지
