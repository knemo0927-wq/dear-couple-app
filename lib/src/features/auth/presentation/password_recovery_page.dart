import 'package:couple_chat_app/src/common/dear_design.dart';
import 'package:couple_chat_app/src/common/error_mapper.dart';
import 'package:couple_chat_app/src/features/auth/data/auth_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class PasswordRecoveryPage extends ConsumerStatefulWidget {
  const PasswordRecoveryPage({super.key});

  @override
  ConsumerState<PasswordRecoveryPage> createState() =>
      _PasswordRecoveryPageState();
}

class _PasswordRecoveryPageState extends ConsumerState<PasswordRecoveryPage> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmationController = TextEditingController();
  bool _passwordVisible = false;
  bool _confirmationVisible = false;
  bool _saving = false;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(authPasswordUpdateProvider)(_passwordController.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('새 비밀번호로 변경했어요.')),
      );
      context.go('/');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(toFriendlyErrorMessage(error))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _validatePassword(String? value) {
    final password = value ?? '';
    if (password.length < 8) return '8자 이상 입력해 주세요.';
    if (!RegExp(r'[A-Za-z]').hasMatch(password) ||
        !RegExp(r'[0-9]').hasMatch(password)) {
      return '영문과 숫자를 함께 사용해 주세요.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('새 비밀번호 설정')),
      body: DearBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 36),
            children: [
              const DearIconBubble(
                icon: Icons.lock_reset_rounded,
                size: 72,
                iconSize: 34,
              ),
              const SizedBox(height: 20),
              Text(
                '새 비밀번호를 입력해 주세요',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                '영문과 숫자를 포함해 8자 이상으로 설정해 주세요.',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 32),
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      key: const ValueKey('new-password-field'),
                      controller: _passwordController,
                      obscureText: !_passwordVisible,
                      autofillHints: const [AutofillHints.newPassword],
                      textInputAction: TextInputAction.next,
                      validator: _validatePassword,
                      decoration: InputDecoration(
                        labelText: '새 비밀번호',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          tooltip: _passwordVisible ? '비밀번호 숨기기' : '비밀번호 보기',
                          onPressed: () => setState(
                            () => _passwordVisible = !_passwordVisible,
                          ),
                          icon: Icon(
                            _passwordVisible
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      key: const ValueKey('confirm-password-field'),
                      controller: _confirmationController,
                      obscureText: !_confirmationVisible,
                      autofillHints: const [AutofillHints.newPassword],
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                      validator: (value) {
                        if (value != _passwordController.text) {
                          return '비밀번호가 서로 같지 않아요.';
                        }
                        return _validatePassword(value);
                      },
                      decoration: InputDecoration(
                        labelText: '새 비밀번호 확인',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          tooltip:
                              _confirmationVisible ? '비밀번호 숨기기' : '비밀번호 보기',
                          onPressed: () => setState(
                            () => _confirmationVisible = !_confirmationVisible,
                          ),
                          icon: Icon(
                            _confirmationVisible
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              DearGradientButton(
                label: _saving ? '변경 중...' : '비밀번호 변경',
                icon: Icons.check_rounded,
                onPressed: _saving ? null : _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
