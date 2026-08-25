import 'dart:typed_data';
import 'dart:ui';

import 'package:couple_chat_app/src/features/auth/data/auth_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef AuthEmailAction = Future<void> Function({
  required String email,
  required String password,
});
typedef AuthEmailOnlyAction = Future<void> Function(String email);
typedef AuthSignUpAction = Future<AuthSignUpResult> Function({
  required String email,
  required String password,
});
typedef AuthVoidAction = Future<void> Function();
typedef PairWithCodeAction = Future<void> Function(String code);
typedef RotatePairingCodeAction = Future<String> Function();
typedef SharePairingCodeAction = Future<void> Function({
  required String code,
  Rect? sharePositionOrigin,
});
typedef UpdateAvatarAction = Future<void> Function({
  required Uint8List bytes,
  required String extension,
});
typedef UpdateNicknameAction = Future<void> Function(String nickname);
typedef ExportMyDataAction = Future<Map<String, dynamic>> Function();

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(),
);

final authSignInProvider = Provider<AuthEmailAction>((ref) {
  final repository = ref.watch(authRepositoryProvider);
  return ({required email, required password}) =>
      repository.signIn(email: email, password: password);
});

final authSignUpProvider = Provider<AuthSignUpAction>((ref) {
  final repository = ref.watch(authRepositoryProvider);
  return ({required email, required password}) =>
      repository.signUp(email: email, password: password);
});

final authPasswordResetProvider = Provider<AuthEmailOnlyAction>((ref) {
  final repository = ref.watch(authRepositoryProvider);
  return repository.sendPasswordReset;
});

final authPasswordUpdateProvider = Provider<Future<void> Function(String)>(
  (ref) => ref.watch(authRepositoryProvider).updatePassword,
);

final authPasswordRecoveryProvider = StreamProvider<bool>((ref) async* {
  final auth = Supabase.instance.client.auth;
  await for (final state in auth.onAuthStateChange) {
    yield state.event == AuthChangeEvent.passwordRecovery;
  }
});

final authAppleSignInProvider = Provider<AuthVoidAction>((ref) {
  final repository = ref.watch(authRepositoryProvider);
  return repository.signInWithApple;
});

final authSignOutProvider = Provider<AuthVoidAction>((ref) {
  final repository = ref.watch(authRepositoryProvider);
  return repository.signOut;
});

final myAccountEmailProvider = Provider<String?>((ref) {
  return ref.watch(authSessionProvider).valueOrNull?.user.email;
});

final disconnectMyCoupleProvider = Provider<AuthVoidAction>((ref) {
  final repository = ref.watch(authRepositoryProvider);
  return () async {
    await repository.disconnectMyCouple();
    ref.invalidate(myProfileProvider);
    ref.invalidate(myProfileStatsProvider);
    ref.invalidate(myAvatarUrlProvider);
  };
});

final deleteMyAccountProvider = Provider<AuthVoidAction>((ref) {
  final repository = ref.watch(authRepositoryProvider);
  return () async {
    await repository.deleteMyAccount();
    ref.invalidate(myProfileProvider);
    ref.invalidate(myProfileStatsProvider);
    ref.invalidate(myAvatarUrlProvider);
  };
});

final exportMyDataProvider = Provider<ExportMyDataAction>((ref) {
  final repository = ref.watch(authRepositoryProvider);
  return repository.exportMyData;
});

final pairWithCodeProvider = Provider<PairWithCodeAction>((ref) {
  final repository = ref.watch(authRepositoryProvider);
  return (code) async {
    await repository.pairWithCode(code);
    ref.invalidate(myProfileProvider);
  };
});

final rotatePairingCodeProvider = Provider<RotatePairingCodeAction>((ref) {
  final repository = ref.watch(authRepositoryProvider);
  return () async {
    final code = await repository.rotatePairingCode();
    ref.invalidate(myProfileProvider);
    return code;
  };
});

final sharePairingCodeProvider = Provider<SharePairingCodeAction>((ref) {
  return ({required code, sharePositionOrigin}) async {
    await Share.share(
      'Dear에서 둘만의 공간을 연결해요.\n'
      '초대 코드: $code\n'
      '페어링 화면에 4자리 코드를 입력해 주세요.',
      subject: 'Dear 초대 코드',
      sharePositionOrigin: sharePositionOrigin,
    );
  };
});

final authSessionProvider = StreamProvider<Session?>((ref) async* {
  final auth = Supabase.instance.client.auth;
  yield auth.currentSession;
  await for (final state in auth.onAuthStateChange) {
    yield state.session;
  }
});

final hasSessionStateProvider = Provider<AsyncValue<bool>>((ref) {
  return ref.watch(authSessionProvider).whenData((session) => session != null);
});

final myProfileProvider = FutureProvider<ProfileInfo?>((ref) async {
  final session = await ref.watch(authSessionProvider.future);
  if (session == null) {
    return null;
  }

  return ref.watch(authRepositoryProvider).fetchMyProfile();
});

final myProfileStatsProvider = FutureProvider<ProfileStats?>((ref) async {
  final profile = await ref.watch(myProfileProvider.future);
  if (profile == null || !profile.isPaired || profile.coupleId == null) {
    return null;
  }

  final repository = ref.watch(authRepositoryProvider);
  return repository.fetchProfileStats(
    coupleId: profile.coupleId!,
    userId: profile.userId,
  );
});

final myAvatarUrlProvider = FutureProvider<String?>((ref) async {
  final profile = await ref.watch(myProfileProvider.future);
  final path = profile?.avatarPath;
  if (path == null || path.trim().isEmpty) {
    return null;
  }

  return ref.watch(authRepositoryProvider).createSignedAvatarUrl(path);
});

final updateMyNicknameProvider = Provider<UpdateNicknameAction>((ref) {
  final repository = ref.watch(authRepositoryProvider);
  return (nickname) async {
    await repository.updateMyNickname(nickname);
    ref.invalidate(myProfileProvider);
    ref.invalidate(coupleNicknameMapProvider);
  };
});

final updateMyAvatarProvider = Provider<UpdateAvatarAction>((ref) {
  final repository = ref.watch(authRepositoryProvider);
  return ({required bytes, required extension}) async {
    await repository.updateMyAvatar(bytes: bytes, extension: extension);
    ref.invalidate(myProfileProvider);
    ref.invalidate(coupleAvatarUrlMapProvider);
    ref.invalidate(coupleNicknameMapProvider);
  };
});

final clearMyAvatarProvider = Provider<AuthVoidAction>((ref) {
  final repository = ref.watch(authRepositoryProvider);
  return () async {
    await repository.clearMyAvatar();
    ref.invalidate(myProfileProvider);
    ref.invalidate(coupleAvatarUrlMapProvider);
    ref.invalidate(coupleNicknameMapProvider);
  };
});

final coupleNicknameMapProvider =
    StreamProvider.family<Map<String, String>, String>((ref, coupleId) async* {
  final repository = ref.watch(authRepositoryProvider);

  await for (final profiles in repository.watchCoupleAvatars(coupleId)) {
    final result = <String, String>{};
    for (final item in profiles) {
      final nickname = item.nickname.trim();
      if (nickname.isNotEmpty) {
        result[item.userId] = nickname;
      }
    }
    yield result;
  }
});

final coupleAvatarUrlMapProvider =
    StreamProvider.family<Map<String, String>, String>((ref, coupleId) async* {
  final repository = ref.watch(authRepositoryProvider);
  final lastPathByUserId = <String, String>{};
  final signedUrlByUserId = <String, String>{};
  final signedAtByUserId = <String, DateTime>{};
  const signedRefreshInterval = Duration(minutes: 55);

  await for (final profiles in repository.watchCoupleAvatars(coupleId)) {
    final now = DateTime.now();
    final activeUserIds = <String>{};
    final result = <String, String>{};

    for (final item in profiles) {
      final path = item.avatarPath?.trim();
      if (path == null || path.isEmpty) {
        lastPathByUserId.remove(item.userId);
        signedUrlByUserId.remove(item.userId);
        signedAtByUserId.remove(item.userId);
        continue;
      }

      activeUserIds.add(item.userId);
      final previousPath = lastPathByUserId[item.userId];
      final signedAt = signedAtByUserId[item.userId];
      final needsRefresh = previousPath != path ||
          signedUrlByUserId[item.userId] == null ||
          signedAt == null ||
          now.difference(signedAt) >= signedRefreshInterval;

      if (needsRefresh) {
        try {
          final signed = await repository.createSignedAvatarUrl(path);
          lastPathByUserId[item.userId] = path;
          signedUrlByUserId[item.userId] = signed;
          signedAtByUserId[item.userId] = now;
        } catch (_) {
          // Keep default avatar on signed-url failure.
          continue;
        }
      }

      final signedUrl = signedUrlByUserId[item.userId];
      if (signedUrl != null && signedUrl.isNotEmpty) {
        result[item.userId] = signedUrl;
      }
    }

    final staleUserIds = signedUrlByUserId.keys
        .where((userId) => !activeUserIds.contains(userId))
        .toList();
    for (final userId in staleUserIds) {
      lastPathByUserId.remove(userId);
      signedUrlByUserId.remove(userId);
      signedAtByUserId.remove(userId);
    }

    yield result;
  }
});
