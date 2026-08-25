import 'package:supabase_flutter/supabase_flutter.dart';

typedef FetchPushToken = Future<String?> Function();
typedef FetchDeviceId = Future<String> Function();
typedef FetchPlatform = Future<String> Function();

class PushRegistrationRequest {
  const PushRegistrationRequest({
    required this.userId,
    required this.deviceId,
    required this.platform,
    required this.token,
  });

  final String userId;
  final String deviceId;
  final String platform;
  final String token;
}

abstract class PushTokenRepository {
  Future<void> upsert(PushRegistrationRequest request);
  Future<void> clearByUserAndDevice(String userId, String deviceId);
}

class SupabasePushTokenRepository implements PushTokenRepository {
  SupabasePushTokenRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  Future<void> upsert(PushRegistrationRequest request) async {
    await _client.from('device_push_tokens').upsert({
      'user_id': request.userId,
      'device_id': request.deviceId,
      'platform': request.platform,
      'push_token': request.token,
    }, onConflict: 'user_id,device_id');
  }

  @override
  Future<void> clearByUserAndDevice(String userId, String deviceId) async {
    await _client
        .from('device_push_tokens')
        .delete()
        .eq('user_id', userId)
        .eq('device_id', deviceId);
  }
}

class PushRegistrationService {
  PushRegistrationService({
    required PushTokenRepository repository,
    required FetchPushToken fetchPushToken,
    required FetchDeviceId fetchDeviceId,
    required FetchPlatform fetchPlatform,
  })  : _repository = repository,
        _fetchPushToken = fetchPushToken,
        _fetchDeviceId = fetchDeviceId,
        _fetchPlatform = fetchPlatform;

  final PushTokenRepository _repository;
  final FetchPushToken _fetchPushToken;
  final FetchDeviceId _fetchDeviceId;
  final FetchPlatform _fetchPlatform;

  String? _lastUserId;
  String? _lastToken;

  Future<void> syncForSession({required String? userId}) async {
    if (userId == null) {
      final previousUserId = _lastUserId;
      _lastUserId = null;
      _lastToken = null;
      if (previousUserId != null) {
        final deviceId = await _fetchDeviceId();
        await _repository.clearByUserAndDevice(previousUserId, deviceId);
      }
      return;
    }

    final token = await _fetchPushToken();
    if (token == null || token.trim().isEmpty) {
      return;
    }

    if (_lastUserId == userId && _lastToken == token) {
      return;
    }

    final deviceId = await _fetchDeviceId();
    final platform = await _fetchPlatform();

    await _repository.upsert(
      PushRegistrationRequest(
        userId: userId,
        deviceId: deviceId,
        platform: platform,
        token: token,
      ),
    );

    _lastUserId = userId;
    _lastToken = token;
  }
}
