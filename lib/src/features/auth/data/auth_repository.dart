import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileInfo {
  const ProfileInfo({
    required this.userId,
    required this.nickname,
    required this.pairingCode,
    required this.coupleId,
    required this.avatarPath,
  });

  final String userId;
  final String nickname;
  final String pairingCode;
  final String? coupleId;
  final String? avatarPath;

  bool get isPaired => coupleId != null && coupleId!.isNotEmpty;

  factory ProfileInfo.fromMap(Map<String, dynamic> map) {
    return ProfileInfo(
      userId: map['user_id'] as String,
      nickname: ((map['nickname'] as String?) ?? '').trim(),
      pairingCode: (map['pairing_code'] as String?) ?? '',
      coupleId: map['couple_id'] as String?,
      avatarPath: map['avatar_path'] as String?,
    );
  }
}

class ProfileStats {
  const ProfileStats({
    required this.consecutiveDays,
    required this.sentPhotos,
    required this.receivedLikes,
  });

  final int consecutiveDays;
  final int sentPhotos;
  final int receivedLikes;

  factory ProfileStats.fromMap(Map<String, dynamic> map) {
    int parseInt(dynamic value) {
      if (value is int) return value;
      if (value is String) return int.tryParse(value) ?? 0;
      return 0;
    }

    return ProfileStats(
      consecutiveDays: parseInt(map['consecutive_days']),
      sentPhotos: parseInt(map['sent_photos']),
      receivedLikes: parseInt(map['received_likes']),
    );
  }
}

class CoupleAvatarInfo {
  const CoupleAvatarInfo({
    required this.userId,
    required this.avatarPath,
    required this.nickname,
  });

  final String userId;
  final String? avatarPath;
  final String nickname;

  factory CoupleAvatarInfo.fromMap(Map<String, dynamic> map) {
    return CoupleAvatarInfo(
      userId: map['user_id'] as String,
      avatarPath: map['avatar_path'] as String?,
      nickname: ((map['nickname'] as String?) ?? '').trim(),
    );
  }
}

class AuthSignUpResult {
  const AuthSignUpResult({required this.emailVerificationPending});

  final bool emailVerificationPending;
}

class AuthRepository {
  AuthRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Session? get currentSession => _client.auth.currentSession;

  Future<void> signIn({required String email, required String password}) async {
    await _client.auth.signInWithPassword(email: email, password: password);
  }

  Future<AuthSignUpResult> signUp({
    required String email,
    required String password,
  }) async {
    final response = await _client.auth.signUp(
      email: email,
      password: password,
      emailRedirectTo: 'io.supabase.flutter://login-callback',
    );
    return AuthSignUpResult(
      emailVerificationPending: response.session == null,
    );
  }

  Future<void> sendPasswordReset(String email) async {
    final normalized = email.trim();
    if (normalized.isEmpty) {
      throw const AuthException('EMAIL_REQUIRED');
    }
    await _client.auth.resetPasswordForEmail(
      normalized,
      redirectTo: 'io.supabase.flutter://reset-password',
    );
  }

  Future<void> updatePassword(String password) async {
    if (_client.auth.currentSession == null) {
      throw const AuthException('RECOVERY_SESSION_REQUIRED');
    }
    final normalized = password.trim();
    if (normalized.length < 8) {
      throw const AuthException('PASSWORD_TOO_SHORT');
    }
    await _client.auth.updateUser(UserAttributes(password: normalized));
  }

  Future<void> signInWithApple() async {
    final launched = await _client.auth.signInWithOAuth(
      OAuthProvider.apple,
      redirectTo: 'io.supabase.flutter://login-callback',
    );
    if (!launched) {
      throw StateError('APPLE_SIGN_IN_LAUNCH_FAILED');
    }
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  /// Disconnects both profiles from their current relationship on the server.
  ///
  /// This must be implemented as a security-definer database RPC so both sides
  /// are updated atomically and relationship-owned data can be handled by the
  /// backend policy in one transaction.
  Future<void> disconnectMyCouple() async {
    if (_client.auth.currentUser == null) {
      throw const AuthException('AUTH_REQUIRED');
    }
    await _client.rpc('disconnect_my_couple');
  }

  /// Permanently deletes the authenticated account through a privileged RPC.
  Future<void> deleteMyAccount() async {
    if (_client.auth.currentUser == null) {
      throw const AuthException('AUTH_REQUIRED');
    }
    final response = await _client.functions.invoke('delete-account');
    if (response.status < 200 || response.status >= 300) {
      throw StateError('ACCOUNT_DELETE_FAILED');
    }
    await _client.auth.signOut();
  }

  /// Returns a portable JSON-compatible snapshot of data visible to the user.
  ///
  /// Storage binaries are represented by their storage paths. This avoids
  /// creating a huge in-memory archive while still making every media reference
  /// discoverable in the export.
  Future<Map<String, dynamic>> exportMyData() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('AUTH_REQUIRED');
    }

    final profile = await fetchMyProfile();
    final userSections = <String, Future<List<Map<String, dynamic>>>>{
      'profiles': _selectRows('profiles', 'user_id', user.id),
      'notification_preferences':
          _selectRows('notification_preferences', 'user_id', user.id),
      'device_push_tokens':
          _selectRows('device_push_tokens', 'user_id', user.id),
      'conversation_reads':
          _selectRows('conversation_reads', 'user_id', user.id),
      'notification_jobs': _selectRows('notification_jobs', 'user_id', user.id),
      'message_reactions': _selectRows('message_reactions', 'user_id', user.id),
      'omok_notifications':
          _selectRows('omok_notifications', 'recipient_user_id', user.id),
    };
    final data = <String, dynamic>{};
    await Future.wait(
      userSections.entries.map((entry) async {
        data[entry.key] = await entry.value;
      }),
    );

    final coupleId = profile.coupleId;
    if (coupleId != null && coupleId.isNotEmpty) {
      final coupleSections = <String, Future<List<Map<String, dynamic>>>>{
        'couples': _selectRows('couples', 'id', coupleId),
        'messages': _selectRows('messages', 'couple_id', coupleId),
        'anniversaries': _selectRows('anniversaries', 'couple_id', coupleId),
        'memory_albums': _selectRows('memory_albums', 'couple_id', coupleId),
        'memory_album_photos':
            _selectRows('memory_album_photos', 'couple_id', coupleId),
        'travel_city_visits':
            _selectRows('travel_city_visits', 'couple_id', coupleId),
        'travel_city_photos':
            _selectRows('travel_city_photos', 'couple_id', coupleId),
        'world_country_visits':
            _selectRows('world_country_visits', 'couple_id', coupleId),
        'world_country_photos':
            _selectRows('world_country_photos', 'couple_id', coupleId),
        'omok_sessions': _selectRows('omok_sessions', 'couple_id', coupleId),
      };
      await Future.wait(
        coupleSections.entries.map((entry) async {
          data[entry.key] = await entry.value;
        }),
      );

      final sessionIds = (data['omok_sessions'] as List<dynamic>)
          .map((row) => (row as Map<String, dynamic>)['id'])
          .whereType<String>()
          .toList(growable: false);
      data['omok_moves'] = sessionIds.isEmpty
          ? <Map<String, dynamic>>[]
          : await _selectRowsIn('omok_moves', 'session_id', sessionIds);
    }

    return {
      'format': 'dear-data-export-v1',
      'generated_at': DateTime.now().toUtc().toIso8601String(),
      'account': {
        'user_id': user.id,
        'email': user.email,
        'created_at': user.createdAt,
      },
      'data': data,
    };
  }

  Future<ProfileInfo> fetchMyProfile() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('AUTH_REQUIRED');
    }

    final row = await _client
        .from('profiles')
        .select('user_id, nickname, pairing_code, couple_id, avatar_path')
        .eq('user_id', user.id)
        .single();

    return ProfileInfo.fromMap(row);
  }

  Future<void> pairWithCode(String code) async {
    final normalized = code.trim().toUpperCase();
    if (normalized.isEmpty) {
      throw const AuthException('PAIRING_CODE_REQUIRED');
    }

    await _client.rpc('pair_with_code', params: {
      'target_pairing_code': normalized,
    });
  }

  Future<String> rotatePairingCode() async {
    final response = await _client.rpc('rotate_my_pairing_code');
    final code = response?.toString().trim().toUpperCase() ?? '';
    if (code.isEmpty) {
      throw StateError('PAIRING_CODE_ROTATION_FAILED');
    }
    return code;
  }

  Future<void> updateMyNickname(String nickname) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('AUTH_REQUIRED');
    }

    final normalized = nickname.trim();
    if (normalized.isEmpty) {
      throw const AuthException('NICKNAME_REQUIRED');
    }

    await _client
        .from('profiles')
        .update({'nickname': normalized}).eq('user_id', user.id);
  }

  Future<ProfileStats> fetchProfileStats({
    required String coupleId,
    required String userId,
  }) async {
    final rows = await _client.rpc('get_profile_stats', params: {
      'target_couple_id': coupleId,
      'target_user_id': userId,
    });

    if (rows is List && rows.isNotEmpty) {
      return ProfileStats.fromMap(Map<String, dynamic>.from(rows.first as Map));
    }
    if (rows is Map) {
      return ProfileStats.fromMap(Map<String, dynamic>.from(rows));
    }

    return const ProfileStats(
        consecutiveDays: 0, sentPhotos: 0, receivedLikes: 0);
  }

  Future<String> updateMyAvatar({
    required Uint8List bytes,
    required String extension,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('AUTH_REQUIRED');
    }

    final ext = extension.trim().toLowerCase().replaceAll('.', '');
    final imagePath =
        '${user.id}/avatar_${DateTime.now().millisecondsSinceEpoch}.$ext';

    await _client.storage.from('profile-images').uploadBinary(
          imagePath,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );

    await _client
        .from('profiles')
        .update({'avatar_path': imagePath}).eq('user_id', user.id);

    return imagePath;
  }

  Future<void> clearMyAvatar() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('AUTH_REQUIRED');
    }

    await _client
        .from('profiles')
        .update({'avatar_path': null}).eq('user_id', user.id);
  }

  Future<List<CoupleAvatarInfo>> fetchCoupleAvatars(String coupleId) async {
    final rows = await _client
        .from('profiles')
        .select('user_id, avatar_path, nickname')
        .eq('couple_id', coupleId);
    return rows.map<CoupleAvatarInfo>(CoupleAvatarInfo.fromMap).toList();
  }

  Stream<List<CoupleAvatarInfo>> watchCoupleAvatars(String coupleId) {
    return _client
        .from('profiles')
        .stream(primaryKey: ['user_id'])
        .eq('couple_id', coupleId)
        .map(
          (rows) => rows
              .map<CoupleAvatarInfo>(
                (row) => CoupleAvatarInfo.fromMap(
                  Map<String, dynamic>.from(row),
                ),
              )
              .toList(),
        );
  }

  Future<String> createSignedAvatarUrl(String avatarPath) {
    return _client.storage
        .from('profile-images')
        .createSignedUrl(avatarPath, 3600);
  }

  Future<List<Map<String, dynamic>>> _selectRows(
    String table,
    String column,
    Object value,
  ) async {
    final rows = await _client.from(table).select().eq(column, value);
    return rows
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> _selectRowsIn(
    String table,
    String column,
    List<Object> values,
  ) async {
    final rows = await _client.from(table).select().inFilter(column, values);
    return rows
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }
}
