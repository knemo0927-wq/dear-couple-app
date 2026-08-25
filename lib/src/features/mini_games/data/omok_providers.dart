import 'package:couple_chat_app/src/features/mini_games/data/omok_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef CreateOmokInviteAction = Future<OmokInviteInfo> Function();
typedef CreateOmokPushInviteAction = Future<OmokPushInviteInfo> Function();
typedef WatchOmokInviteStream = Stream<OmokInviteState?> Function(
    String inviteId);
typedef JoinOmokWithCodeAction = Future<String> Function(String code);
typedef AcceptOmokPushInviteAction = Future<String> Function(String inviteId);
typedef RejectOmokPushInviteAction = Future<void> Function(String inviteId);
typedef ExpireOmokInviteAction = Future<void> Function(String inviteId);
typedef PlaceOmokMoveAction = Future<OmokMoveResult> Function({
  required String sessionId,
  required int x,
  required int y,
});
typedef SyncOmokTurnAction = Future<OmokTurnSync> Function(String sessionId);
typedef ResignOmokGameAction = Future<OmokResignResult> Function(
    String sessionId);
typedef CreateOmokRematchAction = Future<String> Function(String sessionId);
typedef MarkOmokNotificationsReadAction = Future<void> Function(List<int> ids);

final omokRepositoryProvider = Provider<OmokRepository>(
  (ref) => OmokRepository(),
);

final createOmokInviteProvider = Provider<CreateOmokInviteAction>((ref) {
  return ref.read(omokRepositoryProvider).createInvite;
});

final createOmokPushInviteProvider =
    Provider<CreateOmokPushInviteAction>((ref) {
  return ref.read(omokRepositoryProvider).createPushInvite;
});

final watchOmokInviteProvider = Provider<WatchOmokInviteStream>((ref) {
  return ref.read(omokRepositoryProvider).watchInvite;
});

final latestOutgoingOmokInviteProvider =
    StreamProvider.family<OmokInviteState?, String>((ref, userId) {
  return ref
      .watch(omokRepositoryProvider)
      .watchLatestOutgoingPushInvite(userId);
});

final joinOmokWithCodeProvider = Provider<JoinOmokWithCodeAction>((ref) {
  return ref.read(omokRepositoryProvider).joinWithInviteCode;
});

final acceptOmokPushInviteProvider =
    Provider<AcceptOmokPushInviteAction>((ref) {
  return ref.read(omokRepositoryProvider).acceptPushInvite;
});

final rejectOmokPushInviteProvider =
    Provider<RejectOmokPushInviteAction>((ref) {
  return ref.read(omokRepositoryProvider).rejectPushInvite;
});

final expireOmokInviteProvider = Provider<ExpireOmokInviteAction>((ref) {
  return ref.read(omokRepositoryProvider).expireInviteIfNeeded;
});

final placeOmokMoveProvider = Provider<PlaceOmokMoveAction>((ref) {
  return ({required sessionId, required x, required y}) {
    return ref.read(omokRepositoryProvider).placeMove(
          sessionId: sessionId,
          x: x,
          y: y,
        );
  };
});

final syncOmokTurnProvider = Provider<SyncOmokTurnAction>((ref) {
  return ref.read(omokRepositoryProvider).syncTurnTimeout;
});

final resignOmokGameProvider = Provider<ResignOmokGameAction>((ref) {
  return ref.read(omokRepositoryProvider).resignGame;
});

final createOmokRematchProvider = Provider<CreateOmokRematchAction>((ref) {
  return ref.read(omokRepositoryProvider).createRematch;
});

final markOmokNotificationsReadProvider =
    Provider<MarkOmokNotificationsReadAction>((ref) {
  return ref.read(omokRepositoryProvider).markNotificationsRead;
});

final omokSessionProvider =
    StreamProvider.family<OmokSessionInfo?, String>((ref, sessionId) {
  return ref.watch(omokRepositoryProvider).watchSession(sessionId);
});

final omokMovesProvider =
    StreamProvider.family<List<OmokMove>, String>((ref, sessionId) {
  return ref.watch(omokRepositoryProvider).watchMoves(sessionId);
});

final omokRecordProvider = FutureProvider.autoDispose
    .family<OmokRecord, ({String coupleId, String userId})>((ref, args) {
  return ref.watch(omokRepositoryProvider).fetchMyRecord(
        coupleId: args.coupleId,
        userId: args.userId,
      );
});

final omokRecentGamesProvider = FutureProvider.autoDispose.family<
    List<OmokRecentGame>,
    ({String coupleId, String userId, int limit})>((ref, args) {
  return ref.watch(omokRepositoryProvider).fetchRecentGames(
        coupleId: args.coupleId,
        userId: args.userId,
        limit: args.limit,
      );
});

final omokAllGamesProvider = FutureProvider.autoDispose
    .family<List<OmokRecentGame>, ({String coupleId, String userId})>(
        (ref, args) {
  return ref.watch(omokRepositoryProvider).fetchAllGames(
        coupleId: args.coupleId,
        userId: args.userId,
      );
});

final rematchNotificationsProvider =
    StreamProvider.family<List<OmokNotification>, String>((ref, userId) {
  return ref.watch(omokRepositoryProvider).watchRematchNotifications(userId);
});

final latestOmokActivityAtProvider =
    StreamProvider.family<DateTime?, String>((ref, coupleId) {
  return ref.watch(omokRepositoryProvider).watchLatestGameAt(coupleId);
});
