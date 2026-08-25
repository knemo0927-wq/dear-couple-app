import 'package:couple_chat_app/src/common/error_mapper.dart';
import 'package:couple_chat_app/src/common/dear_design.dart';
import 'package:couple_chat_app/src/features/auth/data/auth_providers.dart';
import 'package:couple_chat_app/src/features/auth/data/auth_repository.dart';
import 'package:couple_chat_app/src/routing/route_guard.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class AuthPage extends ConsumerStatefulWidget {
  const AuthPage({super.key});

  @override
  ConsumerState<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends ConsumerState<AuthPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _submitting = false;
  bool _isSignIn = true;
  bool _obscurePassword = true;
  bool _emailTouched = false;
  bool _passwordTouched = false;
  bool _emailVerificationPending = false;
  String? _message;

  AuthEmailAction get _signIn => ref.read(authSignInProvider);
  AuthSignUpAction get _signUp => ref.read(authSignUpProvider);
  AuthEmailOnlyAction get _sendPasswordReset =>
      ref.read(authPasswordResetProvider);
  AuthVoidAction get _signInWithApple => ref.read(authAppleSignInProvider);

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String? _validateEmail(String value) {
    final email = value.trim();
    if (email.isEmpty) return '이메일을 입력해 주세요.';

    final emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    if (!emailPattern.hasMatch(email)) {
      return '올바른 이메일 형식을 입력해 주세요.';
    }
    return null;
  }

  String? _validatePassword(String value) {
    if (value.isEmpty) return '비밀번호를 입력해 주세요.';
    if (!_isSignIn && value.length < 6) {
      return '비밀번호는 6자 이상 입력해 주세요.';
    }
    return null;
  }

  bool get _hasValidCredentials =>
      _validateEmail(_emailController.text) == null &&
      _validatePassword(_passwordController.text) == null;

  Future<bool> _run(
    Future<void> Function() action, {
    String? successMessage,
  }) async {
    if (_submitting) return false;
    setState(() {
      _submitting = true;
      _message = null;
    });

    try {
      await action();
      if (!mounted) return false;
      if (successMessage != null) {
        setState(() => _message = successMessage);
      }
      return true;
    } catch (e) {
      if (!mounted) return false;
      setState(() => _message = toFriendlyErrorMessage(e));
      return false;
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    setState(() {
      _emailTouched = true;
      _passwordTouched = true;
      _message = null;
    });
    if (!_hasValidCredentials) {
      return;
    }

    if (_isSignIn) {
      final succeeded = await _run(
        () => _signIn(email: email, password: password),
        successMessage: '로그인 성공',
      );
      if (!succeeded || !mounted) return;
      final from = GoRouterState.of(context).uri.queryParameters['from'];
      context.go(resolvePostLoginDestination(from));
      return;
    }

    AuthSignUpResult? result;
    final succeeded = await _run(() async {
      result = await _signUp(email: email, password: password);
    });
    if (!succeeded || !mounted || result == null) return;

    _passwordController.clear();
    if (result!.emailVerificationPending) {
      setState(() {
        _emailVerificationPending = true;
        _passwordTouched = false;
        _message = null;
      });
      return;
    }

    final from = GoRouterState.of(context).uri.queryParameters['from'];
    context.go(resolvePostLoginDestination(from));
  }

  Future<void> _resetPassword() async {
    setState(() {
      _emailTouched = true;
      _message = null;
    });
    final email = _emailController.text.trim();
    if (_validateEmail(email) != null) return;

    await _run(
      () => _sendPasswordReset(email),
      successMessage: '비밀번호 재설정 메일을 보냈어요.',
    );
  }

  Future<void> _startAppleSignIn() async {
    await _run(
      _signInWithApple,
      successMessage: 'Apple 로그인 화면을 열었어요.',
    );
  }

  void _returnToSignIn() {
    setState(() {
      _emailVerificationPending = false;
      _isSignIn = true;
      _passwordTouched = false;
      _message = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCompactHeight = MediaQuery.sizeOf(context).height < 700;
    final logoSize = isCompactHeight ? 86.0 : 148.0;
    final topGap = isCompactHeight ? 12.0 : 70.0;
    final logoTitleGap = isCompactHeight ? 6.0 : 14.0;
    final headlineGap = isCompactHeight ? 14.0 : 48.0;
    final formGap = isCompactHeight ? 20.0 : 54.0;
    final fieldGap = isCompactHeight ? 10.0 : 14.0;
    final buttonGap = isCompactHeight ? 14.0 : 28.0;

    return Scaffold(
      body: DearBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                20,
                isCompactHeight ? 8 : 10,
                20,
                16,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: topGap),
                    Center(child: DearLogoMark(size: logoSize)),
                    SizedBox(height: logoTitleGap),
                    Text(
                      'Dear',
                      textAlign: TextAlign.center,
                      style: (isCompactHeight
                              ? theme.textTheme.displaySmall
                              : theme.textTheme.displayMedium)
                          ?.copyWith(
                        color: DearColors.coralText,
                        fontWeight: FontWeight.w300,
                        letterSpacing: 0,
                      ),
                    ),
                    SizedBox(height: headlineGap),
                    Text(
                      '둘만의 공간',
                      textAlign: TextAlign.center,
                      style: (isCompactHeight
                              ? theme.textTheme.titleLarge
                              : theme.textTheme.headlineSmall)
                          ?.copyWith(
                        color: DearColors.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: isCompactHeight ? 4 : 8),
                    Text(
                      '함께 나누고, 함께 쌓아가는 우리 이야기',
                      textAlign: TextAlign.center,
                      style: (isCompactHeight
                              ? theme.textTheme.bodyMedium
                              : theme.textTheme.bodyLarge)
                          ?.copyWith(
                        color: DearColors.muted,
                      ),
                    ),
                    SizedBox(height: formGap),
                    if (_emailVerificationPending)
                      _EmailVerificationPendingCard(
                        email: _emailController.text.trim(),
                        onReturnToSignIn: _returnToSignIn,
                      )
                    else ...[
                      const ExcludeSemantics(
                        child: Opacity(
                          opacity: 0,
                          child: Text(
                            '로그인 / 회원가입',
                            style: TextStyle(fontSize: 0, height: 0),
                          ),
                        ),
                      ),
                      _AuthModeTabs(
                        isSignIn: _isSignIn,
                        enabled: !_submitting,
                        onChanged: (value) {
                          setState(() {
                            _isSignIn = value;
                            _passwordTouched =
                                _passwordController.text.isNotEmpty;
                            _message = null;
                          });
                        },
                      ),
                      SizedBox(height: isCompactHeight ? 16 : 26),
                      TextField(
                        key: const Key('auth-email-field'),
                        controller: _emailController,
                        enabled: !_submitting,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        autofillHints: const [AutofillHints.email],
                        onChanged: (_) => setState(() {
                          _emailTouched = true;
                          _message = null;
                        }),
                        decoration: InputDecoration(
                          hintText: '이메일',
                          prefixIcon: const Icon(Icons.mail_outline_rounded),
                          errorText: _emailTouched
                              ? _validateEmail(_emailController.text)
                              : null,
                        ),
                      ),
                      SizedBox(height: fieldGap),
                      TextField(
                        key: const Key('auth-password-field'),
                        controller: _passwordController,
                        enabled: !_submitting,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.done,
                        autofillHints: [
                          _isSignIn
                              ? AutofillHints.password
                              : AutofillHints.newPassword,
                        ],
                        onChanged: (_) => setState(() {
                          _passwordTouched = true;
                          _message = null;
                        }),
                        onSubmitted: (_) {
                          if (!_submitting) _submit();
                        },
                        decoration: InputDecoration(
                          hintText: '비밀번호',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          errorText: _passwordTouched
                              ? _validatePassword(_passwordController.text)
                              : null,
                          suffixIcon: IconButton(
                            key: const Key('password-visibility-toggle'),
                            tooltip: _obscurePassword ? '비밀번호 표시' : '비밀번호 숨기기',
                            onPressed: _submitting
                                ? null
                                : () => setState(() {
                                      _obscurePassword = !_obscurePassword;
                                    }),
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: isCompactHeight ? 8 : 12),
                      if (_isSignIn)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: _submitting ? null : _resetPassword,
                            style: TextButton.styleFrom(
                              foregroundColor: DearColors.secondary,
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(44, 44),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text('비밀번호를 잊으셨나요?'),
                          ),
                        )
                      else
                        Text(
                          '6자 이상의 비밀번호를 사용해 주세요.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: DearColors.secondary,
                          ),
                        ),
                      SizedBox(height: buttonGap),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: DearGradients.cta,
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: dearSoftShadow(0.85),
                        ),
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            disabledBackgroundColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          onPressed: _submitting ? null : _submit,
                          child: SizedBox(
                            height: 56,
                            child: Center(
                              child: _submitting
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Text(_isSignIn ? '로그인' : '회원가입'),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: isCompactHeight ? 20 : 28),
                      Row(
                        children: [
                          const Expanded(
                            child: Divider(color: DearColors.line),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Text(
                              '또는',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: DearColors.disabled,
                              ),
                            ),
                          ),
                          const Expanded(
                            child: Divider(color: DearColors.line),
                          ),
                        ],
                      ),
                      SizedBox(height: isCompactHeight ? 16 : 22),
                      OutlinedButton.icon(
                        key: const Key('apple-sign-in-button'),
                        onPressed: _submitting ? null : _startAppleSignIn,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: DearColors.ink,
                          backgroundColor: Colors.white.withValues(alpha: 0.9),
                          side: const BorderSide(color: DearColors.line),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                          minimumSize: const Size.fromHeight(56),
                        ),
                        icon: const Icon(Icons.apple),
                        label: const Text('Apple로 계속하기'),
                      ),
                      SizedBox(height: isCompactHeight ? 20 : 36),
                      TextButton.icon(
                        onPressed: _submitting
                            ? null
                            : () => context.push('/onboarding'),
                        icon: const Icon(Icons.menu_book_outlined),
                        label: const Text('앱 소개 보기'),
                      ),
                      if (_message != null) ...[
                        const SizedBox(height: 14),
                        _InlineStatusMessage(message: _message!),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmailVerificationPendingCard extends StatelessWidget {
  const _EmailVerificationPendingCard({
    required this.email,
    required this.onReturnToSignIn,
  });

  final String email;
  final VoidCallback onReturnToSignIn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DearCard(
      padding: const EdgeInsets.all(24),
      radius: DearRadii.large,
      child: Column(
        children: [
          const DearIconBubble(
            icon: Icons.mark_email_unread_outlined,
            size: 72,
            iconSize: 34,
          ),
          const SizedBox(height: 20),
          Text(
            '이메일을 확인해 주세요',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: DearColors.ink,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            email,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: DearColors.coralText,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '보내드린 인증 링크를 누른 뒤 로그인해 주세요.\n메일이 보이지 않으면 스팸함도 확인해 주세요.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: DearColors.secondary,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 24),
          DearGradientButton(
            label: '로그인으로 돌아가기',
            onPressed: onReturnToSignIn,
            height: 56,
          ),
        ],
      ),
    );
  }
}

class _AuthModeTabs extends StatelessWidget {
  const _AuthModeTabs({
    required this.isSignIn,
    required this.enabled,
    required this.onChanged,
  });

  final bool isSignIn;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.36),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: DearColors.line),
      ),
      child: Row(
        children: [
          _AuthModeTab(
            label: '로그인',
            selected: isSignIn,
            enabled: enabled,
            onTap: () => onChanged(true),
          ),
          _AuthModeTab(
            label: '회원가입',
            selected: !isSignIn,
            enabled: enabled,
            onTap: () => onChanged(false),
          ),
        ],
      ),
    );
  }
}

class _AuthModeTab extends StatelessWidget {
  const _AuthModeTab({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 54,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? Colors.white.withValues(alpha: 0.94)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            boxShadow: selected ? dearSoftShadow(0.35) : null,
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: selected ? DearColors.coral : DearColors.muted,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
      ),
    );
  }
}

class PairingPage extends ConsumerStatefulWidget {
  const PairingPage({super.key});

  @override
  ConsumerState<PairingPage> createState() => _PairingPageState();
}

class _PairingPageState extends ConsumerState<PairingPage> {
  final _pairingCodeController = TextEditingController();
  bool _submitting = false;
  bool _rotatingCode = false;
  bool _sharingCode = false;
  String? _message;
  String? _invitationMessage;
  String? _rotatedPairingCode;

  PairWithCodeAction get _pairWithCode => ref.read(pairWithCodeProvider);
  RotatePairingCodeAction get _rotatePairingCode =>
      ref.read(rotatePairingCodeProvider);
  SharePairingCodeAction get _sharePairingCode =>
      ref.read(sharePairingCodeProvider);
  AuthVoidAction get _signOut => ref.read(authSignOutProvider);

  @override
  void dispose() {
    _pairingCodeController.dispose();
    super.dispose();
  }

  Future<void> _pair() async {
    if (_submitting) return;

    final code = _pairingCodeController.text.trim().toUpperCase();
    if (code.length != 4) {
      setState(() => _message = '4자리 초대 코드를 모두 입력해 주세요.');
      return;
    }

    setState(() {
      _submitting = true;
      _message = null;
    });
    try {
      await _pairWithCode(code);
      if (!mounted) return;
      setState(() => _message = '커플 연결 완료');
      context.go('/');
    } catch (e) {
      if (!mounted) return;
      setState(() => _message = toFriendlyErrorMessage(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _confirmAndRotatePairingCode() async {
    if (_rotatingCode) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('새 초대 코드를 만들까요?'),
        content: const Text(
          '새 코드를 만들면 기존 코드는 더 이상 사용할 수 없어요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            key: const Key('confirm-pairing-code-rotation'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('새 코드 만들기'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _rotatingCode) return;

    setState(() {
      _rotatingCode = true;
      _invitationMessage = null;
    });
    try {
      final code = await _rotatePairingCode();
      if (!mounted) return;
      setState(() {
        _rotatedPairingCode = code;
        _invitationMessage = '새 초대 코드를 만들었어요.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _invitationMessage = toFriendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _rotatingCode = false);
    }
  }

  Future<void> _shareCode(String code, BuildContext shareContext) async {
    if (_sharingCode || code.isEmpty) return;

    Rect? sharePositionOrigin;
    final renderObject = shareContext.findRenderObject();
    if (renderObject is RenderBox && renderObject.hasSize) {
      sharePositionOrigin =
          renderObject.localToGlobal(Offset.zero) & renderObject.size;
    }

    setState(() {
      _sharingCode = true;
      _invitationMessage = null;
    });
    try {
      await _sharePairingCode(
        code: code,
        sharePositionOrigin: sharePositionOrigin,
      );
      if (!mounted) return;
      setState(() => _invitationMessage = '공유 화면을 열었어요.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _invitationMessage = toFriendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _sharingCode = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(myProfileProvider);

    return profileAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(title: const Text('Dear')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(toFriendlyErrorMessage(error)),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => ref.invalidate(myProfileProvider),
                child: const Text('다시 시도'),
              ),
            ],
          ),
        ),
      ),
      data: (profile) {
        if (profile == null) {
          return const Scaffold(
            body: Center(child: Text('로그인이 필요합니다.')),
          );
        }

        if (profile.isPaired) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            context.go('/chat-list');
          });
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final theme = Theme.of(context);
        final invitationCode =
            (_rotatedPairingCode ?? profile.pairingCode).trim().toUpperCase();

        return Scaffold(
          appBar: AppBar(
            title: const Text('페어링'),
            leading: IconButton(
              tooltip: '뒤로가기',
              onPressed: () => context.go('/auth'),
              icon: const Icon(Icons.arrow_back_ios_new_rounded),
            ),
            actions: [
              IconButton(
                tooltip: '로그아웃',
                onPressed: () async {
                  await _signOut();
                  if (context.mounted) context.go('/auth');
                },
                icon: const Icon(Icons.logout),
              ),
            ],
          ),
          body: DearBackground(
            child: SafeArea(
              top: false,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
                children: [
                  Center(
                    child: Column(
                      children: [
                        const DearLogoMark(size: 118),
                        const SizedBox(height: 28),
                        Text(
                          '둘이 연결되면\n우리만의 공간이 열려요',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: DearColors.ink,
                            fontWeight: FontWeight.w800,
                            height: 1.28,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '초대 코드를 공유하고 서로 연결해 보세요',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: DearColors.secondary,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  DearCard(
                    padding: const EdgeInsets.all(18),
                    radius: DearRadii.large,
                    color: Colors.white.withValues(alpha: 0.9),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const DearIconBubble(
                              icon: Icons.person_outline_rounded,
                              size: 48,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '내 초대 코드',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: DearColors.ink,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            OutlinedButton.icon(
                              key: const Key('rotate-pairing-code-button'),
                              onPressed: _rotatingCode || _sharingCode
                                  ? null
                                  : _confirmAndRotatePairingCode,
                              icon: _rotatingCode
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.refresh_rounded,
                                      size: 18,
                                    ),
                              label: Text(
                                _rotatingCode ? '생성 중...' : '새 코드 생성',
                              ),
                            ),
                          ],
                        ),
                        if (_invitationMessage != null) ...[
                          const SizedBox(height: 12),
                          _InlineStatusMessage(message: _invitationMessage!),
                        ],
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 26,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.78),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: DearColors.line),
                          ),
                          child: Column(
                            children: [
                              SelectableText(
                                invitationCode,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.displayMedium?.copyWith(
                                  letterSpacing: 7,
                                  fontWeight: FontWeight.w900,
                                  color: DearColors.coralText,
                                  height: 1,
                                ),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                '이 코드를 상대방에게 공유해 주세요',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: DearColors.secondary,
                                ),
                              ),
                              const SizedBox(height: 22),
                              const Divider(color: DearColors.line),
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: _rotatingCode ||
                                              invitationCode.isEmpty
                                          ? null
                                          : () async {
                                              await Clipboard.setData(
                                                ClipboardData(
                                                  text: invitationCode,
                                                ),
                                              );
                                              if (!context.mounted) return;
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                const SnackBar(
                                                  content:
                                                      Text('초대 코드를 복사했어요.'),
                                                ),
                                              );
                                            },
                                      icon: const Icon(Icons.copy_rounded),
                                      label: const Text('복사'),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Builder(
                                      builder: (shareContext) =>
                                          OutlinedButton.icon(
                                        key: const Key(
                                          'share-pairing-code-button',
                                        ),
                                        onPressed: _sharingCode ||
                                                _rotatingCode ||
                                                invitationCode.isEmpty
                                            ? null
                                            : () => _shareCode(
                                                  invitationCode,
                                                  shareContext,
                                                ),
                                        icon: _sharingCode
                                            ? const SizedBox(
                                                width: 18,
                                                height: 18,
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                ),
                                              )
                                            : const Icon(
                                                Icons.ios_share_rounded,
                                              ),
                                        label: Text(
                                          _sharingCode ? '공유 중...' : '공유하기',
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  DearCard(
                    padding: const EdgeInsets.all(18),
                    radius: DearRadii.large,
                    color: Colors.white.withValues(alpha: 0.9),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const DearIconBubble(
                              icon: Icons.person_outline_rounded,
                              size: 48,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '상대 코드 입력',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: DearColors.ink,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '상대방이 보여주는 코드를 입력해 주세요',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: DearColors.secondary,
                          ),
                        ),
                        const SizedBox(height: 18),
                        _PairingCodeInput(
                          controller: _pairingCodeController,
                          enabled: !_submitting,
                          onChanged: (_) {
                            if (_message != null) {
                              setState(() => _message = null);
                            }
                          },
                          onSubmitted: _pair,
                        ),
                        const SizedBox(height: 18),
                        DearGradientButton(
                          onPressed: _submitting ? null : _pair,
                          label: _submitting ? '연결 중...' : '연결하기',
                        ),
                        if (_message != null) ...[
                          const SizedBox(height: 12),
                          _InlineStatusMessage(message: _message!),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  DearCard(
                    padding: const EdgeInsets.all(18),
                    radius: DearRadii.large,
                    color: DearColors.blush.withValues(alpha: 0.9),
                    shadowOpacity: 0.35,
                    child: Row(
                      children: [
                        const DearLogoMark(size: 72),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '연결 대기 중',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: DearColors.ink,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '상대방이 코드를 입력하면 연결이 완료돼요',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: DearColors.secondary,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.8),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.circle,
                            color: DearColors.coral,
                            size: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  DearCard(
                    padding: const EdgeInsets.all(16),
                    shadowOpacity: 0.25,
                    child: Row(
                      children: [
                        const DearIconBubble(
                          icon: Icons.info_outline_rounded,
                          size: 48,
                          background: DearColors.blushDeep,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            '초대 코드는 상대방을 확인한 뒤 직접 전달해 주세요.\n'
                            '코드는 24시간 뒤 만료되며, 새 코드를 만들거나 연결하면 기존 코드는 사용할 수 없어요.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: DearColors.ink,
                              fontWeight: FontWeight.w700,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PairingCodeInput extends StatelessWidget {
  const _PairingCodeInput({
    required this.controller,
    required this.enabled,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      child: Stack(
        children: [
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              final chars = value.text.toUpperCase().split('');
              return Row(
                children: List.generate(4, (index) {
                  final active =
                      chars.length >= 4 ? index == 3 : index == chars.length;
                  final char = index < chars.length ? chars[index] : '';
                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(right: index == 3 ? 0 : 8),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.86),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: active ? DearColors.coral : DearColors.line,
                            width: active ? 1.6 : 1,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            char,
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(
                                  color: DearColors.coralText,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              );
            },
          ),
          Positioned.fill(
            child: TextField(
              key: const Key('pairing-code-field'),
              controller: controller,
              enabled: enabled,
              autofocus: false,
              textCapitalization: TextCapitalization.characters,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.done,
              autocorrect: false,
              enableSuggestions: false,
              inputFormatters: const [_PairingCodeFormatter()],
              onChanged: onChanged,
              onSubmitted: (_) => onSubmitted(),
              style: const TextStyle(color: Colors.transparent),
              cursorColor: DearColors.coral,
              decoration: const InputDecoration(
                counterText: '',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PairingCodeFormatter extends TextInputFormatter {
  const _PairingCodeFormatter();

  static final _unsupportedCharacters = RegExp('[^A-Z0-9]');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final normalized =
        newValue.text.toUpperCase().replaceAll(_unsupportedCharacters, '');
    final text =
        normalized.length <= 4 ? normalized : normalized.substring(0, 4);

    final rawCursor = newValue.selection.extentOffset;
    final safeCursor = rawCursor.clamp(0, newValue.text.length).toInt();
    final normalizedBeforeCursor = newValue.text
        .substring(0, safeCursor)
        .toUpperCase()
        .replaceAll(_unsupportedCharacters, '');
    final cursor = normalizedBeforeCursor.length.clamp(0, text.length).toInt();

    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: cursor),
    );
  }
}

class _InlineStatusMessage extends StatelessWidget {
  const _InlineStatusMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isError = message.contains('오류') ||
        message.contains('실패') ||
        message.contains('입력') ||
        message.contains('필요') ||
        message.contains('문제') ||
        message.contains('올바르지') ||
        message.contains('불안정') ||
        message.contains('거부') ||
        message.contains('만료');

    final bg = isError ? scheme.errorContainer : scheme.primaryContainer;
    final fg = isError ? scheme.onErrorContainer : scheme.onPrimaryContainer;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Text(
          message,
          style: TextStyle(color: fg),
        ),
      ),
    );
  }
}
