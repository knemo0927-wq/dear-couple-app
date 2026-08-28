import 'dart:async';
import 'dart:math' as math;

import 'package:couple_chat_app/src/common/dear_design.dart';
import 'package:couple_chat_app/src/common/error_mapper.dart';
import 'package:couple_chat_app/src/features/auth/data/auth_providers.dart';
import 'package:couple_chat_app/src/features/mini_games/data/omok_providers.dart';
import 'package:couple_chat_app/src/features/mini_games/data/omok_repository.dart';
import 'package:couple_chat_app/src/features/mini_games/presentation/omok_history_page.dart';
import 'package:couple_chat_app/src/features/mini_games/presentation/omok_rules_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

enum _GameMenuAction { resign, rematch, rules }

class OmokGamePage extends ConsumerStatefulWidget {
  const OmokGamePage({
    required this.sessionId,
    super.key,
  });

  final String sessionId;

  @override
  ConsumerState<OmokGamePage> createState() => _OmokGamePageState();
}

class _OmokGamePageState extends ConsumerState<OmokGamePage> {
  static const int _boardSize = 15;

  Timer? _clockTimer;
  Timer? _reconnectTimer;
  DateTime _clockNow = DateTime.now();
  DateTime? _activeTurnExpiresAt;
  DateTime? _lastTimeoutSyncAt;
  bool _activeSessionPlaying = false;
  bool _syncingTimeout = false;
  bool _placing = false;
  bool _resigning = false;
  bool _creatingRematch = false;
  final Set<int> _shownNotificationIds = <int>{};
  String? _lastSyncError;

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _tickClock();
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _reconnectTimer?.cancel();
    super.dispose();
  }

  void _tickClock() {
    if (!mounted) return;
    final now = DateTime.now();
    setState(() => _clockNow = now);

    final expiresAt = _activeTurnExpiresAt;
    if (!_activeSessionPlaying ||
        expiresAt == null ||
        now.isBefore(expiresAt) ||
        _lastTimeoutSyncAt == expiresAt ||
        _syncingTimeout) {
      return;
    }

    _lastTimeoutSyncAt = expiresAt;
    unawaited(_syncExpiredTurn());
  }

  Future<void> _syncExpiredTurn() async {
    if (_syncingTimeout) return;
    setState(() => _syncingTimeout = true);
    try {
      await ref.read(syncOmokTurnProvider)(widget.sessionId);
      if (!mounted) return;
      _reconnectTimer?.cancel();
      setState(() => _lastSyncError = null);
    } catch (e) {
      if (!mounted) return;
      setState(() => _lastSyncError = toFriendlyErrorMessage(e));
      _scheduleReconnect();
    } finally {
      if (mounted) setState(() => _syncingTimeout = false);
    }
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 10), () {
      if (!mounted || _lastSyncError == null) return;
      final expiresAt = _activeTurnExpiresAt;
      if (!_activeSessionPlaying ||
          expiresAt == null ||
          DateTime.now().isBefore(expiresAt)) {
        setState(() => _lastSyncError = null);
        return;
      }
      unawaited(_syncExpiredTurn());
    });
  }

  Future<void> _retryRealtime() async {
    _reconnectTimer?.cancel();
    setState(() => _lastSyncError = null);
    ref.invalidate(omokSessionProvider(widget.sessionId));
    ref.invalidate(omokMovesProvider(widget.sessionId));

    final expiresAt = _activeTurnExpiresAt;
    if (_activeSessionPlaying &&
        expiresAt != null &&
        !DateTime.now().isBefore(expiresAt)) {
      _lastTimeoutSyncAt = expiresAt;
      await _syncExpiredTurn();
    }
  }

  Future<bool> _placeStone(
    OmokSessionInfo session,
    int x,
    int y,
    String myUserId,
  ) async {
    if (_placing) return false;
    if (!session.isPlaying) return false;
    if (session.currentTurnUserId != myUserId) return false;

    setState(() => _placing = true);
    try {
      await ref.read(placeOmokMoveProvider)(
        sessionId: widget.sessionId,
        x: x,
        y: y,
      );
      return true;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(toFriendlyErrorMessage(e))),
      );
      return false;
    } finally {
      if (mounted) {
        setState(() => _placing = false);
      }
    }
  }

  Future<void> _showCoordinatePicker({
    required String myUserId,
    required int initialX,
    required int initialY,
  }) async {
    if (_placing || !mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => _OmokCoordinatePickerSheet(
        sessionId: widget.sessionId,
        myUserId: myUserId,
        initialX: initialX,
        initialY: initialY,
        onPlace: (session, x, y) => _placeStone(session, x, y, myUserId),
      ),
    );
  }

  Future<void> _resign(OmokSessionInfo session, String myUserId) async {
    if (_resigning || !session.isPlaying) return;
    if (myUserId != session.blackUserId && myUserId != session.whiteUserId) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('기권할까요?'),
        content: const Text('기권하면 즉시 패배 처리되고 전적에 기록돼요.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('기권')),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _resigning = true);
    try {
      await ref.read(resignOmokGameProvider)(widget.sessionId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(toFriendlyErrorMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _resigning = false);
    }
  }

  Future<void> _createRematch(OmokSessionInfo session, String myUserId) async {
    if (_creatingRematch || session.isPlaying) return;
    if (myUserId != session.blackUserId && myUserId != session.whiteUserId) {
      return;
    }

    setState(() => _creatingRematch = true);
    try {
      final newSessionId =
          await ref.read(createOmokRematchProvider)(session.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('상대에게 재대결 알림을 보냈어요.')),
      );
      context.go('/omok/$newSessionId');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(toFriendlyErrorMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _creatingRematch = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final profileAsync = ref.watch(myProfileProvider);
    final sessionAsync = ref.watch(omokSessionProvider(widget.sessionId));
    final movesAsync = ref.watch(omokMovesProvider(widget.sessionId));
    final currentProfile = profileAsync.valueOrNull;
    final currentSession = sessionAsync.valueOrNull;
    final isCurrentPlayer = currentProfile != null &&
        currentSession != null &&
        (currentProfile.userId == currentSession.blackUserId ||
            currentProfile.userId == currentSession.whiteUserId);

    _activeSessionPlaying = currentSession?.isPlaying ?? false;
    _activeTurnExpiresAt = currentSession?.turnExpiresAt;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          tooltip: '뒤로가기',
          onPressed: () {
            if (context.canPop()) {
              context.pop();
              return;
            }
            context.go('/mini-games');
          },
        ),
        title: const Text('오목'),
        actions: [
          PopupMenuButton<_GameMenuAction>(
            key: const ValueKey('omok-game-overflow'),
            tooltip: '더보기',
            onSelected: (action) {
              switch (action) {
                case _GameMenuAction.resign:
                  if (currentProfile != null && currentSession != null) {
                    _resign(currentSession, currentProfile.userId);
                  }
                case _GameMenuAction.rematch:
                  if (currentProfile != null && currentSession != null) {
                    _createRematch(currentSession, currentProfile.userId);
                  }
                case _GameMenuAction.rules:
                  showOmokRulesSheet(context);
              }
            },
            itemBuilder: (context) => [
              if (isCurrentPlayer && currentSession.isPlaying)
                const PopupMenuItem(
                  value: _GameMenuAction.resign,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.flag_rounded),
                    title: Text('기권하기'),
                  ),
                ),
              if (isCurrentPlayer && !currentSession.isPlaying)
                const PopupMenuItem(
                  value: _GameMenuAction.rematch,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.replay_rounded),
                    title: Text('재대결 신청'),
                  ),
                ),
              const PopupMenuItem(
                value: _GameMenuAction.rules,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.menu_book_rounded),
                  title: Text('오목 규칙'),
                ),
              ),
            ],
            icon: const Icon(Icons.more_horiz_rounded),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: DearBackground(
        child: profileAsync.when(
          loading: () => const _OmokGameSkeleton(),
          error: (error, _) => _OmokGameLoadError(
            message: '프로필을 불러오지 못했어요.\n${toFriendlyErrorMessage(error)}',
            onRetry: () => ref.invalidate(myProfileProvider),
          ),
          data: (profile) {
            if (profile == null) {
              return const Center(child: Text('로그인이 필요합니다.'));
            }

            ref.listen<AsyncValue<List<OmokNotification>>>(
              rematchNotificationsProvider(profile.userId),
              (previous, next) {
                final data = next.valueOrNull;
                if (!mounted || data == null) return;

                final candidate = data.where(
                  (n) =>
                      n.isUnread &&
                      !_shownNotificationIds.contains(n.id) &&
                      n.sessionId != widget.sessionId,
                );
                if (candidate.isEmpty) return;

                final latest = candidate.last;
                _shownNotificationIds.add(latest.id);

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('상대가 새 재대결을 만들었어요!'),
                    action: SnackBarAction(
                      label: '입장',
                      onPressed: () => context.go('/omok/${latest.sessionId}'),
                    ),
                  ),
                );

                unawaited(
                    ref.read(markOmokNotificationsReadProvider)([latest.id]));
              },
            );

            return sessionAsync.when(
              loading: () => const _OmokGameSkeleton(),
              error: (error, _) => _OmokGameLoadError(
                message:
                    '대국 연결을 다시 확인하고 있어요.\n${toFriendlyErrorMessage(error)}',
                onRetry: _retryRealtime,
              ),
              data: (session) {
                if (session == null) {
                  return _OmokGameLoadError(
                    message: '대국을 찾을 수 없어요.',
                    onRetry: _retryRealtime,
                  );
                }

                return movesAsync.when(
                  loading: () => const _OmokGameSkeleton(),
                  error: (error, _) => _OmokGameLoadError(
                    message:
                        '착수 정보를 다시 받고 있어요.\n${toFriendlyErrorMessage(error)}',
                    onRetry: _retryRealtime,
                  ),
                  data: (moves) {
                    final stoneByPosition = <String, String>{};
                    for (final move in moves) {
                      stoneByPosition['${move.x}:${move.y}'] = move.stone;
                    }

                    final OmokMove? lastMove = moves.isEmpty
                        ? null
                        : moves.reduce((a, b) => a.moveNo >= b.moveNo ? a : b);
                    final isMyTurn =
                        session.currentTurnUserId == profile.userId;
                    final isPlayer = profile.userId == session.blackUserId ||
                        profile.userId == session.whiteUserId;
                    final statusLabel =
                        _buildStatusLabel(session, profile.userId, isMyTurn);
                    final secondsLeft = _secondsUntil(session.turnExpiresAt);
                    final boardSummary = _buildBoardSummary(
                      session: session,
                      moves: moves,
                      lastMove: lastMove,
                      statusLabel: statusLabel,
                    );

                    return Column(
                      children: [
                        _OmokConnectionBanner(
                          reconnecting: _lastSyncError != null,
                          detail: _lastSyncError,
                          onRetry: _retryRealtime,
                        ),
                        Semantics(
                          container: true,
                          liveRegion: true,
                          label: '대국 상태. $statusLabel',
                          child: DearCard(
                            margin: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                            padding: const EdgeInsets.all(14),
                            shadowOpacity: 0.55,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _OmokStatusHeader(
                                  title: isPlayer
                                      ? (isMyTurn ? '내 차례' : '상대 차례')
                                      : '관전 모드',
                                  emphasized: isMyTurn,
                                  action: !isPlayer
                                      ? null
                                      : session.isPlaying
                                          ? OutlinedButton(
                                              onPressed: _resigning
                                                  ? null
                                                  : () => _resign(
                                                        session,
                                                        profile.userId,
                                                      ),
                                              child: Text(
                                                _resigning ? '기권 중...' : '기권',
                                              ),
                                            )
                                          : FilledButton(
                                              onPressed: _creatingRematch
                                                  ? null
                                                  : () => _createRematch(
                                                        session,
                                                        profile.userId,
                                                      ),
                                              child: Text(
                                                _creatingRematch
                                                    ? '재대결 생성 중...'
                                                    : '재대결',
                                              ),
                                            ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  statusLabel,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                ),
                                if (session.isPlaying)
                                  Text(
                                    '남은 시간 ${secondsLeft.toString().padLeft(2, '0')}초',
                                    key: const ValueKey('omok-local-countdown'),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w700,
                                          color: secondsLeft <= 5
                                              ? Theme.of(context)
                                                  .colorScheme
                                                  .error
                                              : null,
                                        ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final side = math.min(constraints.maxWidth - 8,
                                  constraints.maxHeight - 8);
                              final boardWidth = side > 0
                                  ? side
                                  : math.min(constraints.maxWidth,
                                          constraints.maxHeight) *
                                      0.95;
                              final boardInset =
                                  math.max(8.0, boardWidth * 0.04);
                              final spacing = (boardWidth - boardInset * 2) /
                                  (_boardSize - 1);
                              final hitSize = math.max(24.0, spacing * 1.4);
                              final stoneSize = math.max(16.0, spacing * 0.82);

                              return Semantics(
                                key: const ValueKey('omok-board-summary'),
                                container: true,
                                liveRegion: true,
                                excludeSemantics: true,
                                label: '오목판 요약',
                                value: boardSummary,
                                hint: isPlayer && session.isPlaying
                                    ? '두 손가락으로 확대하거나 이동할 수 있어요. '
                                        '교차점을 선택해 좌표와 상태를 확인하거나, '
                                        '보드 아래 좌표로 돌 놓기 버튼을 사용하세요.'
                                    : '두 손가락으로 확대하거나 이동해 착수 위치를 확인할 수 있어요.',
                                child: Center(
                                  child: SizedBox(
                                    width: boardWidth,
                                    height: boardWidth,
                                    child: Container(
                                      key: const ValueKey(
                                        'omok-board-surface',
                                      ),
                                      clipBehavior: Clip.antiAlias,
                                      decoration: BoxDecoration(
                                        color: DearColors.board,
                                        borderRadius: BorderRadius.circular(24),
                                        border: Border.all(
                                            color: DearColors.warmLine),
                                        boxShadow: dearSoftShadow(0.55),
                                      ),
                                      child: InteractiveViewer(
                                        key: const ValueKey(
                                            'omok-board-interactive-viewer'),
                                        minScale: 1,
                                        maxScale: 4,
                                        child: Stack(
                                          children: [
                                            Positioned.fill(
                                              child: CustomPaint(
                                                painter: _OmokGridPainter(
                                                  boardSize: _boardSize,
                                                  inset: boardInset,
                                                  color:
                                                      const Color(0xFF8A6337),
                                                ),
                                              ),
                                            ),
                                            ...List.generate(
                                                _boardSize * _boardSize,
                                                (index) {
                                              final x = index % _boardSize;
                                              final y = index ~/ _boardSize;
                                              final key = '$x:$y';
                                              final stone =
                                                  stoneByPosition[key];
                                              final isLastMove =
                                                  lastMove != null &&
                                                      lastMove.x == x &&
                                                      lastMove.y == y;

                                              final left = boardInset +
                                                  x * spacing -
                                                  (hitSize / 2);
                                              final top = boardInset +
                                                  y * spacing -
                                                  (hitSize / 2);

                                              return Positioned(
                                                left: left,
                                                top: top,
                                                child: GestureDetector(
                                                  key: ValueKey(
                                                    'omok-board-cell-row-${y + 1}-column-${x + 1}',
                                                  ),
                                                  behavior: HitTestBehavior
                                                      .translucent,
                                                  onTap: isPlayer &&
                                                          session.isPlaying &&
                                                          !_placing
                                                      ? () =>
                                                          _showCoordinatePicker(
                                                            myUserId:
                                                                profile.userId,
                                                            initialX: x,
                                                            initialY: y,
                                                          )
                                                      : null,
                                                  child: SizedBox(
                                                    width: hitSize,
                                                    height: hitSize,
                                                    child: Center(
                                                      child: stone == null
                                                          ? null
                                                          : SizedBox(
                                                              width:
                                                                  stoneSize + 8,
                                                              height:
                                                                  stoneSize + 8,
                                                              child: Stack(
                                                                alignment:
                                                                    Alignment
                                                                        .center,
                                                                children: [
                                                                  Container(
                                                                    key:
                                                                        ValueKey(
                                                                      'omok-stone-$x-$y',
                                                                    ),
                                                                    width:
                                                                        stoneSize,
                                                                    height:
                                                                        stoneSize,
                                                                    decoration:
                                                                        BoxDecoration(
                                                                      shape: BoxShape
                                                                          .circle,
                                                                      color: stone ==
                                                                              'black'
                                                                          ? Colors
                                                                              .black
                                                                          : Colors
                                                                              .white,
                                                                      border:
                                                                          Border
                                                                              .all(
                                                                        color: stone ==
                                                                                'black'
                                                                            ? Colors.black
                                                                            : Colors.black54,
                                                                        width:
                                                                            1,
                                                                      ),
                                                                    ),
                                                                  ),
                                                                  if (isLastMove)
                                                                    Container(
                                                                      key:
                                                                          const ValueKey(
                                                                        'omok-last-move-marker',
                                                                      ),
                                                                      width:
                                                                          stoneSize +
                                                                              6,
                                                                      height:
                                                                          stoneSize +
                                                                              6,
                                                                      decoration:
                                                                          BoxDecoration(
                                                                        shape: BoxShape
                                                                            .circle,
                                                                        border:
                                                                            Border.all(
                                                                          color:
                                                                              DearColors.coralText,
                                                                          width:
                                                                              2,
                                                                        ),
                                                                      ),
                                                                    ),
                                                                ],
                                                              ),
                                                            ),
                                                    ),
                                                  ),
                                                ),
                                              );
                                            }),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        if (session.isPlaying && isPlayer)
                          SafeArea(
                            top: false,
                            minimum: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                minWidth: double.infinity,
                                minHeight: DearTouchTargets.comfortable,
                              ),
                              child: FilledButton.icon(
                                key: const ValueKey(
                                    'omok-coordinate-place-button'),
                                onPressed: _placing
                                    ? null
                                    : () => _showCoordinatePicker(
                                          myUserId: profile.userId,
                                          initialX: 7,
                                          initialY: 7,
                                        ),
                                icon: const Icon(Icons.pin_drop_outlined),
                                label: Text(
                                  _placing ? '돌 놓는 중...' : '좌표로 돌 놓기',
                                ),
                              ),
                            ),
                          )
                        else
                          const SizedBox(height: 12),
                      ],
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }

  String _buildStatusLabel(
      OmokSessionInfo session, String myUserId, bool isMyTurn) {
    switch (session.status) {
      case 'playing':
        return isMyTurn ? '내 차례예요. 30초 안에 착수해 주세요.' : '상대 차례를 기다리는 중...';
      case 'black_win':
      case 'white_win':
      case 'black_timeout_win':
      case 'white_timeout_win':
      case 'black_resign_win':
      case 'white_resign_win':
        if (session.winnerUserId == myUserId) {
          return '승리! 전적에 기록됐어요.';
        }
        return '패배. 다음 판에서 이겨봐요.';
      case 'draw':
        return '무승부로 종료됐어요.';
      case 'cancelled':
        return '대국이 취소됐어요.';
      default:
        return session.status;
    }
  }

  int _secondsUntil(DateTime? expiresAt) {
    if (expiresAt == null) return 0;
    final milliseconds = expiresAt.difference(_clockNow).inMilliseconds;
    if (milliseconds <= 0) return 0;
    return (milliseconds / Duration.millisecondsPerSecond).ceil();
  }

  String _buildBoardSummary({
    required OmokSessionInfo session,
    required List<OmokMove> moves,
    required OmokMove? lastMove,
    required String statusLabel,
  }) {
    final blackCount = moves.where((move) => move.stone == 'black').length;
    final whiteCount = moves.where((move) => move.stone == 'white').length;
    final lastMoveLabel = lastMove == null
        ? '아직 착수가 없어요.'
        : '마지막 착수는 ${lastMove.y + 1}행 ${lastMove.x + 1}열 '
            '${lastMove.stone == 'black' ? '흑돌' : '백돌'}입니다.';
    final outcome = session.isPlaying ? statusLabel : '대국 종료. $statusLabel';
    return '15 곱하기 15 바둑판, 흑돌 $blackCount개, 백돌 $whiteCount개. '
        '$lastMoveLabel $outcome';
  }
}

class _OmokStatusHeader extends StatelessWidget {
  const _OmokStatusHeader({
    required this.title,
    required this.emphasized,
    this.action,
  });

  final String title;
  final bool emphasized;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget titleWidget() => Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: emphasized ? scheme.primary : scheme.onSurfaceVariant,
                fontWeight: FontWeight.w900,
              ),
        );

    return LayoutBuilder(
      builder: (context, constraints) {
        final reflow = MediaQuery.textScalerOf(context).scale(1) >= 1.6 ||
            constraints.maxWidth < 320;
        final trailing = action;
        if (trailing == null) return titleWidget();
        if (reflow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              titleWidget(),
              const SizedBox(height: DearSpacing.space8),
              SizedBox(width: double.infinity, child: trailing),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: titleWidget()),
            const SizedBox(width: DearSpacing.space8),
            trailing,
          ],
        );
      },
    );
  }
}

typedef _PlaceOmokCoordinate = Future<bool> Function(
  OmokSessionInfo session,
  int x,
  int y,
);

class _OmokCoordinatePickerSheet extends ConsumerStatefulWidget {
  const _OmokCoordinatePickerSheet({
    required this.sessionId,
    required this.myUserId,
    required this.initialX,
    required this.initialY,
    required this.onPlace,
  });

  final String sessionId;
  final String myUserId;
  final int initialX;
  final int initialY;
  final _PlaceOmokCoordinate onPlace;

  @override
  ConsumerState<_OmokCoordinatePickerSheet> createState() =>
      _OmokCoordinatePickerSheetState();
}

class _OmokCoordinatePickerSheetState
    extends ConsumerState<_OmokCoordinatePickerSheet> {
  late int _row;
  late int _column;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _row = math.max(1, math.min(15, widget.initialY + 1));
    _column = math.max(1, math.min(15, widget.initialX + 1));
  }

  Future<void> _confirm(OmokSessionInfo session) async {
    if (_submitting) return;
    setState(() => _submitting = true);
    final placed = await widget.onPlace(session, _column - 1, _row - 1);
    if (!mounted) return;
    if (placed) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sessionAsync = ref.watch(omokSessionProvider(widget.sessionId));
    final movesAsync = ref.watch(omokMovesProvider(widget.sessionId));
    final session = sessionAsync.valueOrNull;
    final moves = movesAsync.valueOrNull;
    String? stone;
    if (moves != null) {
      for (final move in moves) {
        if (move.x == _column - 1 && move.y == _row - 1) {
          stone = move.stone;
          break;
        }
      }
    }
    final dataReady = session != null &&
        moves != null &&
        !sessionAsync.isLoading &&
        !movesAsync.isLoading &&
        !sessionAsync.hasError &&
        !movesAsync.hasError;
    final isMyTurn = session?.currentTurnUserId == widget.myUserId;
    final canConfirm = dataReady &&
        session.isPlaying &&
        isMyTurn &&
        stone == null &&
        !_submitting;
    final status = _selectionStatus(
      sessionAsync: sessionAsync,
      movesAsync: movesAsync,
      session: session,
      stone: stone,
      isMyTurn: isMyTurn,
    );

    Widget coordinateSelector({
      required Key key,
      required String label,
      required int value,
      required ValueChanged<int> onChanged,
    }) {
      return DropdownButtonFormField<int>(
        key: key,
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          helperText: '1~15 중 선택',
        ),
        items: List.generate(
          15,
          (index) => DropdownMenuItem<int>(
            value: index + 1,
            child: Text('${index + 1}'),
          ),
        ),
        onChanged: _submitting
            ? null
            : (next) {
                if (next != null) onChanged(next);
              },
      );
    }

    Widget actionButton({
      required Widget child,
      required Key key,
      required VoidCallback? onPressed,
      required bool primary,
    }) {
      final button = primary
          ? FilledButton(key: key, onPressed: onPressed, child: child)
          : OutlinedButton(key: key, onPressed: onPressed, child: child);
      return ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: DearTouchTargets.comfortable,
        ),
        child: button,
      );
    }

    final cancelButton = actionButton(
      key: const ValueKey('omok-coordinate-cancel'),
      onPressed: _submitting ? null : () => Navigator.of(context).pop(),
      primary: false,
      child: const Text('취소'),
    );
    final confirmButton = actionButton(
      key: const ValueKey('omok-coordinate-confirm'),
      onPressed: canConfirm ? () => _confirm(session) : null,
      primary: true,
      child: Text(_submitting ? '돌 놓는 중...' : '돌 놓기 확인'),
    );
    final textScale = MediaQuery.textScalerOf(context).scale(1);

    return AnimatedPadding(
      key: const ValueKey('omok-coordinate-animated-padding'),
      duration: DearMotion.duration(context, DearMotion.fast),
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          key: const ValueKey('omok-coordinate-sheet'),
          padding: const EdgeInsets.fromLTRB(
            DearSpacing.space20,
            0,
            DearSpacing.space20,
            DearSpacing.space24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '좌표로 돌 놓기',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: DearSpacing.space4),
              Text(
                '행과 열을 선택하고 현재 칸의 상태를 확인한 뒤 돌을 놓아 주세요.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: DearSpacing.space20),
              LayoutBuilder(
                builder: (context, constraints) {
                  final reflow = textScale >= 1.6 || constraints.maxWidth < 340;
                  final rowSelector = coordinateSelector(
                    key: const ValueKey('omok-coordinate-row'),
                    label: '행',
                    value: _row,
                    onChanged: (value) => setState(() => _row = value),
                  );
                  final columnSelector = coordinateSelector(
                    key: const ValueKey('omok-coordinate-column'),
                    label: '열',
                    value: _column,
                    onChanged: (value) => setState(() => _column = value),
                  );
                  if (reflow) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        rowSelector,
                        const SizedBox(height: DearSpacing.space12),
                        columnSelector,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: rowSelector),
                      const SizedBox(width: DearSpacing.space12),
                      Expanded(child: columnSelector),
                    ],
                  );
                },
              ),
              const SizedBox(height: DearSpacing.space16),
              Semantics(
                key: const ValueKey('omok-coordinate-status'),
                container: true,
                liveRegion: true,
                label: status,
                child: ExcludeSemantics(
                  child: Container(
                    padding: const EdgeInsets.all(DearSpacing.space12),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainer,
                      borderRadius: BorderRadius.circular(DearRadii.control),
                      border: Border.all(
                        color: scheme.outlineVariant,
                      ),
                    ),
                    child: Text(
                      status,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            height: 1.45,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: DearSpacing.space20),
              LayoutBuilder(
                builder: (context, constraints) {
                  final reflow = textScale >= 1.6 || constraints.maxWidth < 340;
                  if (reflow) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        cancelButton,
                        const SizedBox(height: DearSpacing.space8),
                        confirmButton,
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: cancelButton),
                      const SizedBox(width: DearSpacing.space12),
                      Expanded(child: confirmButton),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _selectionStatus({
    required AsyncValue<OmokSessionInfo?> sessionAsync,
    required AsyncValue<List<OmokMove>> movesAsync,
    required OmokSessionInfo? session,
    required String? stone,
    required bool isMyTurn,
  }) {
    final coordinate = '$_row행 $_column열';
    if (sessionAsync.hasError) {
      return '$coordinate의 대국 상태를 불러오지 못했어요. 다시 시도해 주세요.';
    }
    if (movesAsync.hasError) {
      return '$coordinate의 돌 상태를 불러오지 못했어요. 다시 시도해 주세요.';
    }
    if (session == null || movesAsync.valueOrNull == null) {
      return '$coordinate의 상태를 확인하는 중입니다.';
    }

    final stoneLabel = switch (stone) {
      'black' => '흑돌',
      'white' => '백돌',
      _ => '빈칸',
    };
    final coordinateStatus = '$coordinate은 $stoneLabel입니다.';
    if (!session.isPlaying) {
      return '$coordinateStatus 대국이 종료됐습니다. '
          '${_omokEndReason(session, widget.myUserId)}';
    }
    if (_submitting) {
      return '$coordinateStatus 현재 내 차례입니다. 돌을 놓는 중입니다.';
    }
    if (isMyTurn) {
      return stone == null
          ? '$coordinateStatus 현재 내 차례입니다. 돌 놓기를 확인할 수 있습니다.'
          : '$coordinateStatus 현재 내 차례이지만 이미 돌이 있어 선택할 수 없습니다.';
    }
    return '$coordinateStatus 현재 상대 차례입니다. 상대 착수를 기다려 주세요.';
  }
}

String _omokEndReason(OmokSessionInfo session, String myUserId) {
  final result = session.winnerUserId == null
      ? ''
      : session.winnerUserId == myUserId
          ? ' 내가 이겼습니다.'
          : ' 상대가 이겼습니다.';
  return switch (session.status) {
    'black_win' || 'white_win' => '종료 이유: 다섯 돌 완성.$result',
    'black_timeout_win' || 'white_timeout_win' => '종료 이유: 시간 초과.$result',
    'black_resign_win' || 'white_resign_win' => '종료 이유: 기권.$result',
    'draw' => '종료 이유: 무승부입니다.',
    'cancelled' => '종료 이유: 대국 취소입니다.',
    _ => '종료 이유: ${session.status}.',
  };
}

class _OmokConnectionBanner extends StatelessWidget {
  const _OmokConnectionBanner({
    required this.reconnecting,
    required this.onRetry,
    this.detail,
  });

  final bool reconnecting;
  final String? detail;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground =
        reconnecting ? scheme.onErrorContainer : scheme.onTertiaryContainer;
    final background =
        reconnecting ? scheme.errorContainer : scheme.tertiaryContainer;
    final border = reconnecting ? scheme.error : scheme.tertiary;
    final label =
        reconnecting ? '연결을 다시 확인하고 있어요' : '실시간 연결됨 · 착수와 턴 상태를 자동으로 받고 있어요';

    return Semantics(
      liveRegion: true,
      label: label,
      child: Container(
        key: const ValueKey('omok-connection-banner'),
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: border),
        ),
        child: Row(
          children: [
            Icon(
              reconnecting ? Icons.sync_rounded : Icons.wifi_rounded,
              color: foreground,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (reconnecting && detail != null)
                    Text(
                      detail!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: foreground, fontSize: 11),
                    ),
                ],
              ),
            ),
            if (reconnecting)
              TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(foregroundColor: foreground),
                child: const Text('다시 시도'),
              ),
          ],
        ),
      ),
    );
  }
}

class _OmokGameSkeleton extends StatelessWidget {
  const _OmokGameSkeleton();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      child: Column(
        children: [
          Container(
            height: 42,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(height: 10),
          const OmokLoadingSkeleton(height: 126),
          const SizedBox(height: 12),
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: Container(
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OmokGameLoadError extends StatelessWidget {
  const _OmokGameLoadError({required this.message, required this.onRetry});

  final String message;
  final FutureOr<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _OmokConnectionBanner(
          reconnecting: true,
          detail: message.replaceAll('\n', ' '),
          onRetry: () async => onRetry(),
        ),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: OmokInlineError(
                message: message,
                onRetry: onRetry,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _OmokGridPainter extends CustomPainter {
  const _OmokGridPainter({
    required this.boardSize,
    required this.inset,
    required this.color,
  });

  final int boardSize;
  final double inset;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7;

    if (boardSize <= 1) return;

    final spacingX = (size.width - inset * 2) / (boardSize - 1);
    final spacingY = (size.height - inset * 2) / (boardSize - 1);

    for (var i = 0; i < boardSize; i++) {
      final x = inset + spacingX * i;
      final y = inset + spacingY * i;

      canvas.drawLine(Offset(inset, y), Offset(size.width - inset, y), paint);
      canvas.drawLine(Offset(x, inset), Offset(x, size.height - inset), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _OmokGridPainter oldDelegate) {
    return oldDelegate.boardSize != boardSize ||
        oldDelegate.inset != inset ||
        oldDelegate.color != color;
  }
}
