String toFriendlyErrorMessage(Object error) {
  final raw = error.toString();

  if (_containsAny(raw, const ['AUTH_REQUIRED'])) {
    return '로그인이 필요해요. 다시 로그인해 주세요.';
  }
  if (_containsAny(raw, const ['PAIRING_CODE_REQUIRED'])) {
    return '페어링 코드를 입력해 주세요.';
  }
  if (_containsAny(raw, const ['NICKNAME_REQUIRED'])) {
    return '닉네임을 입력해 주세요.';
  }
  if (_containsAny(raw, const ['ALREADY_PAIRED'])) {
    return '이미 커플 연결이 완료된 계정이에요.';
  }
  if (_containsAny(raw, const ['INVALID_OR_USED_PAIRING_CODE'])) {
    return '유효하지 않거나 이미 사용된 페어링 코드예요.';
  }
  if (_containsAny(raw, const ['Invalid login credentials'])) {
    return '이메일 또는 비밀번호가 올바르지 않아요.';
  }
  if (_containsAny(raw, const ['Email not confirmed', 'email_not_confirmed'])) {
    return '이메일 인증이 아직 완료되지 않았어요. 메일함에서 인증 후 다시 로그인해 주세요.';
  }
  if (_containsAny(raw, const ['email_provider_disabled'])) {
    return '이메일 로그인 설정이 비활성화되어 있어요. 관리자 설정을 확인해 주세요.';
  }
  if (_containsAny(raw, const ['over_email_send_rate_limit'])) {
    return '요청이 너무 많아요. 잠시 후 다시 시도해 주세요.';
  }
  if (_containsAny(raw, const ['OMOK_INVITE_CODE_REQUIRED'])) {
    return '초대코드를 입력해 주세요.';
  }
  if (_containsAny(raw, const ['INVALID_OR_EXPIRED_INVITE_CODE'])) {
    return '유효하지 않거나 만료된 초대코드예요.';
  }
  if (_containsAny(raw, const ['OMOK_GAME_ALREADY_PLAYING'])) {
    return '이미 진행 중인 대국이 있어요. 미니게임 목록에서 기존 대국으로 들어가 주세요.';
  }
  if (_containsAny(raw, const ['OMOK_SESSION_NOT_FOUND'])) {
    return '대국을 찾을 수 없어요.';
  }
  if (_containsAny(raw, const ['OMOK_NOT_A_PLAYER'])) {
    return '이 대국의 플레이어만 진행할 수 있어요.';
  }
  if (_containsAny(raw, const ['OMOK_DOUBLE_THREE_FORBIDDEN'])) {
    return '3-3 금지 규칙으로 그 자리에 둘 수 없어요.';
  }
  if (_containsAny(raw, const ['MEMORY_ALBUM_COVER_SCHEMA_REQUIRED'])) {
    return '대표 사진 저장을 위한 앨범 DB 업데이트가 필요해요.';
  }
  if (_containsAny(raw, const ['MEMORY_ALBUM_FEATURED_SCHEMA_REQUIRED'])) {
    return '대표 앨범 저장을 위한 앨범 DB 업데이트가 필요해요.';
  }
  if (_containsAny(
      raw, const ['SocketException', 'Failed host lookup', 'timed out'])) {
    return '네트워크 연결이 불안정해요. 인터넷 연결을 확인해 주세요.';
  }
  if (_containsAny(
      raw, const ['WebSocket', 'Realtime', 'channel', 'connection closed'])) {
    return '실시간 연결이 잠시 끊겼어요. 자동으로 다시 연결하고 있어요.';
  }

  if (_containsAny(raw, const [
    'new row violates row-level security policy',
    '42501',
    'permission denied'
  ])) {
    return '권한 문제로 요청이 거부됐어요. 커플 연결 상태를 다시 확인해 주세요.';
  }
  if (_containsAny(
      raw, const ['JWT', 'token is expired', 'session_not_found'])) {
    return '로그인 세션이 만료됐어요. 다시 로그인해 주세요.';
  }
  if (_containsAny(raw, const ['PostgrestException', 'PGRST'])) {
    return '서버 요청 처리에 실패했어요. 네트워크 상태를 확인하고 다시 시도해 주세요.';
  }

  return '요청 처리 중 문제가 발생했어요. 잠시 후 다시 시도해 주세요.';
}

bool _containsAny(String raw, List<String> needles) {
  final lower = raw.toLowerCase();
  return needles.any((needle) => lower.contains(needle.toLowerCase()));
}
