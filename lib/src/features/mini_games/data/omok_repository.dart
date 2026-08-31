import 'package:supabase_flutter/supabase_flutter.dart';

class OmokInviteInfo {
  const OmokInviteInfo({
    required this.inviteId,
    required this.inviteCode,
    required this.expiresAt,
  });

  final String inviteId;
  final String inviteCode;
  final DateTime expiresAt;

  factory OmokInviteInfo.fromMap(Map<String, dynamic> map) {
    return OmokInviteInfo(
      inviteId: map['invite_id'] as String,
      inviteCode: map['invite_code'] as String,
      expiresAt: DateTime.parse(map['expires_at'] as String),
    );
  }
}

class OmokPushInviteInfo {
  const OmokPushInviteInfo({
    required this.inviteId,
    required this.recipientUserId,
    required this.expiresAt,
  });

  final String inviteId;
  final String recipientUserId;
  final DateTime expiresAt;

  factory OmokPushInviteInfo.fromMap(Map<String, dynamic> map) {
    return OmokPushInviteInfo(
      inviteId: map['invite_id'] as String,
      recipientUserId: map['recipient_user_id'] as String,
      expiresAt: DateTime.parse(map['expires_at'] as String),
    );
  }
}

class OmokInviteState {
  const OmokInviteState({
    required this.id,
    required this.status,
    required this.sessionId,
    required this.expiresAt,
    required this.inviteType,
    this.senderUserId,
    this.recipientUserId,
    this.createdAt,
  });

  final String id;
  final String status;
  final String? sessionId;
  final DateTime expiresAt;
  final String inviteType;
  final String? senderUserId;
  final String? recipientUserId;
  final DateTime? createdAt;

  bool get isUsed => status == 'used' && sessionId != null;
  bool get isExpired =>
      status == 'expired' || DateTime.now().isAfter(expiresAt);
  bool get isRejected =>
      status == 'rejected' || status == 'declined' || status == 'cancelled';
  bool get isPending => status == 'open' && !isExpired;
  bool get isPushInvite => inviteType == 'push';

  factory OmokInviteState.fromMap(Map<String, dynamic> map) {
    return OmokInviteState(
      id: map['id'] as String,
      status: map['status'] as String,
      sessionId: map['session_id'] as String?,
      expiresAt: DateTime.parse(map['expires_at'] as String),
      inviteType: (map['invite_type'] as String?) ?? 'code',
      senderUserId: map['sender_user_id'] as String?,
      recipientUserId: map['recipient_user_id'] as String?,
      createdAt: map['created_at'] == null
          ? null
          : DateTime.parse(map['created_at'] as String),
    );
  }
}

class OmokSessionInfo {
  const OmokSessionInfo({
    required this.id,
    required this.coupleId,
    required this.blackUserId,
    required this.whiteUserId,
    required this.currentTurnUserId,
    required this.status,
    required this.winnerUserId,
    required this.turnExpiresAt,
    required this.createdAt,
    this.stoneAssignmentReason,
    this.stoneAssignmentSourceSessionId,
  });

  final String id;
  final String coupleId;
  final String blackUserId;
  final String whiteUserId;
  final String? currentTurnUserId;
  final String status;
  final String? winnerUserId;
  final DateTime? turnExpiresAt;
  final DateTime createdAt;
  final String? stoneAssignmentReason;
  final String? stoneAssignmentSourceSessionId;

  bool get isPlaying => status == 'playing';

  factory OmokSessionInfo.fromMap(Map<String, dynamic> map) {
    return OmokSessionInfo(
      id: map['id'] as String,
      coupleId: map['couple_id'] as String,
      blackUserId: map['black_user_id'] as String,
      whiteUserId: map['white_user_id'] as String,
      currentTurnUserId: map['current_turn_user_id'] as String?,
      status: map['status'] as String,
      winnerUserId: map['winner_user_id'] as String?,
      turnExpiresAt: map['turn_expires_at'] == null
          ? null
          : DateTime.parse(map['turn_expires_at'] as String),
      createdAt: DateTime.parse(map['created_at'] as String),
      stoneAssignmentReason: map['stone_assignment_reason'] as String?,
      stoneAssignmentSourceSessionId:
          map['stone_assignment_source_session_id'] as String?,
    );
  }
}

class OmokMove {
  const OmokMove({
    required this.id,
    required this.sessionId,
    required this.moveNo,
    required this.userId,
    required this.stone,
    required this.x,
    required this.y,
    required this.createdAt,
  });

  final int id;
  final String sessionId;
  final int moveNo;
  final String userId;
  final String stone;
  final int x;
  final int y;
  final DateTime createdAt;

  factory OmokMove.fromMap(Map<String, dynamic> map) {
    return OmokMove(
      id: map['id'] as int,
      sessionId: map['session_id'] as String,
      moveNo: map['move_no'] as int,
      userId: map['user_id'] as String,
      stone: map['stone'] as String,
      x: map['x'] as int,
      y: map['y'] as int,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}

class OmokRecord {
  const OmokRecord({
    required this.wins,
    required this.losses,
    required this.draws,
    required this.totalGames,
  });

  final int wins;
  final int losses;
  final int draws;
  final int totalGames;

  factory OmokRecord.fromMap(Map<String, dynamic> map) {
    int parseInt(dynamic value) {
      if (value is int) return value;
      if (value is String) return int.tryParse(value) ?? 0;
      return 0;
    }

    return OmokRecord(
      wins: parseInt(map['wins']),
      losses: parseInt(map['losses']),
      draws: parseInt(map['draws']),
      totalGames: parseInt(map['total_games']),
    );
  }
}

class OmokRecentGame {
  const OmokRecentGame({
    required this.sessionId,
    required this.status,
    required this.result,
    required this.endReason,
    required this.winnerUserId,
    required this.finishedAt,
    required this.createdAt,
  });

  final String sessionId;
  final String status;
  final String result;
  final String endReason;
  final String? winnerUserId;
  final DateTime? finishedAt;
  final DateTime createdAt;

  factory OmokRecentGame.fromMap(Map<String, dynamic> map) {
    return OmokRecentGame(
      sessionId: map['session_id'] as String,
      status: map['status'] as String,
      result: map['result'] as String,
      endReason: map['end_reason'] as String,
      winnerUserId: map['winner_user_id'] as String?,
      finishedAt: map['finished_at'] == null
          ? null
          : DateTime.parse(map['finished_at'] as String),
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}

class OmokNotification {
  const OmokNotification({
    required this.id,
    required this.sessionId,
    required this.notificationType,
    required this.actorUserId,
    required this.createdAt,
    required this.readAt,
  });

  final int id;
  final String sessionId;
  final String notificationType;
  final String actorUserId;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get isUnread => readAt == null;

  factory OmokNotification.fromMap(Map<String, dynamic> map) {
    return OmokNotification(
      id: map['id'] as int,
      sessionId: map['session_id'] as String,
      notificationType: map['notification_type'] as String,
      actorUserId: map['actor_user_id'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      readAt: map['read_at'] == null
          ? null
          : DateTime.parse(map['read_at'] as String),
    );
  }
}

class OmokTurnSync {
  const OmokTurnSync({
    required this.status,
    required this.winnerUserId,
    required this.currentTurnUserId,
    required this.turnExpiresAt,
    required this.secondsLeft,
  });

  final String status;
  final String? winnerUserId;
  final String? currentTurnUserId;
  final DateTime? turnExpiresAt;
  final int secondsLeft;

  factory OmokTurnSync.fromMap(Map<String, dynamic> map) {
    int parseInt(dynamic value) {
      if (value is int) return value;
      if (value is String) return int.tryParse(value) ?? 0;
      return 0;
    }

    return OmokTurnSync(
      status: map['status'] as String,
      winnerUserId: map['winner_user_id'] as String?,
      currentTurnUserId: map['current_turn_user_id'] as String?,
      turnExpiresAt: map['turn_expires_at'] == null
          ? null
          : DateTime.parse(map['turn_expires_at'] as String),
      secondsLeft: parseInt(map['seconds_left']),
    );
  }
}

class OmokMoveResult {
  const OmokMoveResult({
    required this.status,
    required this.nextTurnUserId,
    required this.winnerUserId,
    required this.turnExpiresAt,
  });

  final String status;
  final String? nextTurnUserId;
  final String? winnerUserId;
  final DateTime? turnExpiresAt;

  factory OmokMoveResult.fromMap(Map<String, dynamic> map) {
    return OmokMoveResult(
      status: map['status'] as String,
      nextTurnUserId: map['next_turn_user_id'] as String?,
      winnerUserId: map['winner_user_id'] as String?,
      turnExpiresAt: map['turn_expires_at'] == null
          ? null
          : DateTime.parse(map['turn_expires_at'] as String),
    );
  }
}

class OmokResignResult {
  const OmokResignResult({
    required this.status,
    required this.winnerUserId,
  });

  final String status;
  final String? winnerUserId;

  factory OmokResignResult.fromMap(Map<String, dynamic> map) {
    return OmokResignResult(
      status: map['status'] as String,
      winnerUserId: map['winner_user_id'] as String?,
    );
  }
}

class OmokRepository {
  OmokRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<OmokInviteInfo> createInvite() async {
    final response = await _client.rpc('create_omok_invite');
    final rows = response as List;
    return OmokInviteInfo.fromMap(Map<String, dynamic>.from(rows.first as Map));
  }

  Future<OmokPushInviteInfo> createPushInvite() async {
    final response = await _client.rpc('create_omok_push_invite');
    final rows = response as List;
    return OmokPushInviteInfo.fromMap(
        Map<String, dynamic>.from(rows.first as Map));
  }

  Stream<OmokInviteState?> watchInvite(String inviteId) {
    return _client
        .from('omok_invites')
        .stream(primaryKey: ['id'])
        .eq('id', inviteId)
        .map((rows) {
          if (rows.isEmpty) return null;
          return OmokInviteState.fromMap(Map<String, dynamic>.from(rows.first));
        });
  }

  Stream<OmokInviteState?> watchLatestOutgoingPushInvite(String userId) {
    return _client
        .from('omok_invites')
        .stream(primaryKey: ['id'])
        .eq('sender_user_id', userId)
        .order('created_at', ascending: false)
        .map((rows) {
          final pushRows = rows
              .where((row) => row['invite_type'] == 'push')
              .toList(growable: false);
          if (pushRows.isEmpty) return null;
          final latest = pushRows.reduce((a, b) {
            final aCreated = DateTime.parse(a['created_at'] as String);
            final bCreated = DateTime.parse(b['created_at'] as String);
            return aCreated.isAfter(bCreated) ? a : b;
          });
          return OmokInviteState.fromMap(
            Map<String, dynamic>.from(latest),
          );
        });
  }

  Future<String> joinWithInviteCode(String code) async {
    final normalized = code.trim().toUpperCase();
    if (normalized.isEmpty) {
      throw const AuthException('OMOK_INVITE_CODE_REQUIRED');
    }

    final sessionId = await _client.rpc(
      'join_omok_with_invite_code',
      params: {'target_invite_code': normalized},
    );

    return sessionId as String;
  }

  Future<String> acceptPushInvite(String inviteId) async {
    final sessionId = await _client.rpc(
      'accept_omok_push_invite',
      params: {'target_invite_id': inviteId},
    );
    return sessionId as String;
  }

  Future<void> rejectPushInvite(String inviteId) async {
    await _client.rpc(
      'reject_omok_push_invite',
      params: {'target_invite_id': inviteId},
    );
  }

  Future<void> expireInviteIfNeeded(String inviteId) async {
    await _client.rpc(
      'expire_omok_invite_if_needed',
      params: {'target_invite_id': inviteId},
    );
  }

  Stream<OmokSessionInfo?> watchSession(String sessionId) {
    return _client
        .from('omok_sessions')
        .stream(primaryKey: ['id'])
        .eq('id', sessionId)
        .map((rows) {
          if (rows.isEmpty) return null;
          final row = Map<String, dynamic>.from(rows.first);
          return OmokSessionInfo.fromMap(row);
        });
  }

  Stream<List<OmokMove>> watchMoves(String sessionId) {
    return _client
        .from('omok_moves')
        .stream(primaryKey: ['id'])
        .eq('session_id', sessionId)
        .order('move_no')
        .map(
          (rows) => rows
              .map((row) => OmokMove.fromMap(Map<String, dynamic>.from(row)))
              .toList(growable: false),
        );
  }

  Future<OmokMoveResult> placeMove({
    required String sessionId,
    required int x,
    required int y,
  }) async {
    final response = await _client.rpc(
      'place_omok_move',
      params: {
        'target_session_id': sessionId,
        'p_x': x,
        'p_y': y,
      },
    );

    final rows = response as List;
    return OmokMoveResult.fromMap(Map<String, dynamic>.from(rows.first as Map));
  }

  Future<OmokTurnSync> syncTurnTimeout(String sessionId) async {
    final response = await _client.rpc(
      'sync_omok_turn_timeout',
      params: {'target_session_id': sessionId},
    );
    final rows = response as List;
    return OmokTurnSync.fromMap(Map<String, dynamic>.from(rows.first as Map));
  }

  Future<OmokResignResult> resignGame(String sessionId) async {
    final response = await _client.rpc(
      'resign_omok_game',
      params: {'target_session_id': sessionId},
    );
    final rows = response as List;
    return OmokResignResult.fromMap(
        Map<String, dynamic>.from(rows.first as Map));
  }

  Future<String> createRematch(String sessionId) async {
    final response = await _client.rpc(
      'create_omok_rematch',
      params: {'target_session_id': sessionId},
    );
    return response as String;
  }

  Future<OmokRecord> fetchMyRecord({
    required String coupleId,
    required String userId,
  }) async {
    final response = await _client.rpc(
      'get_omok_record',
      params: {
        'target_couple_id': coupleId,
        'target_user_id': userId,
      },
    );

    final rows = response as List;
    if (rows.isEmpty) {
      return const OmokRecord(wins: 0, losses: 0, draws: 0, totalGames: 0);
    }

    return OmokRecord.fromMap(Map<String, dynamic>.from(rows.first as Map));
  }

  Future<List<OmokRecentGame>> fetchRecentGames({
    required String coupleId,
    required String userId,
    int limit = 10,
  }) async {
    final response = await _client.rpc(
      'get_omok_recent_games',
      params: {
        'target_couple_id': coupleId,
        'target_user_id': userId,
        'p_limit': limit,
      },
    );

    final rows = response as List;
    return rows
        .map((row) =>
            OmokRecentGame.fromMap(Map<String, dynamic>.from(row as Map)))
        .toList(growable: false);
  }

  Future<List<OmokRecentGame>> fetchAllGames({
    required String coupleId,
    required String userId,
  }) async {
    const pageSize = 200;
    final rows = <Map<String, dynamic>>[];
    var offset = 0;

    while (true) {
      final page = await _client
          .from('omok_sessions')
          .select(
            'id,status,winner_user_id,finished_at,created_at',
          )
          .eq('couple_id', coupleId)
          .order('created_at', ascending: false)
          .range(offset, offset + pageSize - 1);
      rows.addAll(page);
      if (page.length < pageSize) break;
      offset += pageSize;
    }

    return rows.where((row) => row['status'] != 'playing').map((row) {
      final status = row['status'] as String;
      final winnerUserId = row['winner_user_id'] as String?;
      final result = switch (status) {
        'draw' => 'draw',
        'cancelled' => 'cancelled',
        _ when winnerUserId == userId => 'win',
        _ => 'loss',
      };
      final endReason = switch (status) {
        'black_timeout_win' || 'white_timeout_win' => 'timeout',
        'black_resign_win' || 'white_resign_win' => 'resign',
        'draw' => 'draw',
        'cancelled' => 'cancelled',
        _ => 'five_in_a_row',
      };

      return OmokRecentGame(
        sessionId: row['id'] as String,
        status: status,
        result: result,
        endReason: endReason,
        winnerUserId: winnerUserId,
        finishedAt: row['finished_at'] == null
            ? null
            : DateTime.parse(row['finished_at'] as String),
        createdAt: DateTime.parse(row['created_at'] as String),
      );
    }).toList(growable: false);
  }

  Stream<List<OmokNotification>> watchRematchNotifications(String userId) {
    return _client
        .from('omok_notifications')
        .stream(primaryKey: ['id'])
        .eq('recipient_user_id', userId)
        .order('created_at')
        .map(
          (rows) => rows
              .where(
                (row) =>
                    row['notification_type'] == 'rechallenge_created' ||
                    row['notification_type'] == 'rematch_created',
              )
              .map((row) =>
                  OmokNotification.fromMap(Map<String, dynamic>.from(row)))
              .toList(growable: false),
        );
  }

  Future<void> markNotificationsRead(List<int> ids) async {
    if (ids.isEmpty) return;
    await _client
        .from('omok_notifications')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()}).inFilter(
            'id', ids);
  }

  Stream<DateTime?> watchLatestGameAt(String coupleId) {
    return _client
        .from('omok_sessions')
        .stream(primaryKey: ['id'])
        .eq('couple_id', coupleId)
        .map((rows) {
          DateTime? latest;
          for (final row in rows) {
            final value = (row['updated_at'] ?? row['created_at']) as String?;
            if (value == null) continue;
            final dt = DateTime.parse(value);
            if (latest == null || dt.isAfter(latest)) {
              latest = dt;
            }
          }
          return latest;
        });
  }
}
