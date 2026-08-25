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

  Future<void> _placeStone(
    OmokSessionInfo session,
    int x,
    int y,
    String myUserId,
  ) async {
    if (_placing) return;
    if (!session.isPlaying) return;
    if (session.currentTurnUserId != myUserId) return;

    setState(() => _placing = true);
    try {
      await ref.read(placeOmokMoveProvider)(
        sessionId: widget.sessionId,
        x: x,
        y: y,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(toFriendlyErrorMessage(e))),
      );
    } finally {
      if (mounted) {
        setState(() => _placing = false);
      }
    }
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
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        isPlayer
                                            ? (isMyTurn ? '내 차례' : '상대 차례')
                                            : '관전 모드',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              color: isMyTurn
                                                  ? DearColors.coral
                                                  : DearColors.secondary,
                                              fontWeight: FontWeight.w900,
                                            ),
                                      ),
                                    ),
                                    if (session.isPlaying && isPlayer)
                                      OutlinedButton(
                                        onPressed: _resigning
                                            ? null
                                            : () => _resign(
                                                session, profile.userId),
                                        child:
                                            Text(_resigning ? '기권 중...' : '기권'),
                                      ),
                                    if (!session.isPlaying && isPlayer)
                                      FilledButton(
                                        onPressed: _creatingRematch
                                            ? null
                                            : () => _createRematch(
                                                session, profile.userId),
                                        child: Text(_creatingRematch
                                            ? '재대결 생성 중...'
                                            : '재대결'),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  statusLabel,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(color: DearColors.secondary),
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
                                hint: isMyTurn && session.isPlaying
                                    ? '빈 교차점을 선택해 돌을 놓으세요.'
                                    : null,
                                child: Center(
                                  child: SizedBox(
                                    width: boardWidth,
                                    height: boardWidth,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: DearColors.board,
                                        borderRadius: BorderRadius.circular(24),
                                        border: Border.all(
                                            color: DearColors.warmLine),
                                        boxShadow: dearSoftShadow(0.55),
                                      ),
                                      child: Stack(
                                        children: [
                                          Positioned.fill(
                                            child: CustomPaint(
                                              painter: _OmokGridPainter(
                                                boardSize: _boardSize,
                                                inset: boardInset,
                                                color: const Color(0xFF8A6337),
                                              ),
                                            ),
                                          ),
                                          ...List.generate(
                                              _boardSize * _boardSize, (index) {
                                            final x = index % _boardSize;
                                            final y = index ~/ _boardSize;
                                            final key = '$x:$y';
                                            final stone = stoneByPosition[key];
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
                                                behavior:
                                                    HitTestBehavior.translucent,
                                                onTap: stone == null &&
                                                        isPlayer &&
                                                        isMyTurn
                                                    ? () => _placeStone(
                                                          session,
                                                          x,
                                                          y,
                                                          profile.userId,
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
                                                                          ? Colors
                                                                              .black
                                                                          : Colors
                                                                              .black54,
                                                                      width: 1,
                                                                    ),
                                                                  ),
                                                                ),
                                                                if (isLastMove)
                                                                  Container(
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
                                                                          Border
                                                                              .all(
                                                                        color: const Color(
                                                                            0xFFE678A9),
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
                              );
                            },
                          ),
                        ),
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
    final foreground =
        reconnecting ? const Color(0xFF82551A) : const Color(0xFF28613E);
    final background =
        reconnecting ? const Color(0xFFFFF3D9) : const Color(0xFFEAF7EE);
    final border =
        reconnecting ? const Color(0xFFE8C884) : const Color(0xFFB9DDC4);
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      child: Column(
        children: [
          Container(
            height: 42,
            decoration: BoxDecoration(
              color: DearColors.blushDeep,
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
                    color: DearColors.blushDeep,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: DearColors.line),
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
