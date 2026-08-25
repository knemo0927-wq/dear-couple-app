import 'package:couple_chat_app/src/features/auth/data/auth_providers.dart';
import 'package:couple_chat_app/src/features/chat/presentation/chat_shell_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class ChatAccessGuardPage extends ConsumerWidget {
  const ChatAccessGuardPage({
    required this.coupleId,
    super.key,
  });

  final String coupleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(myProfileProvider);

    return profileAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => Scaffold(
        appBar: AppBar(title: const Text('Dear')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('프로필을 불러오지 못했어요.'),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => context.go('/'),
                child: const Text('페어링 화면으로 이동'),
              ),
            ],
          ),
        ),
      ),
      data: (profile) {
        if (profile == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) context.go('/auth');
          });
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (!profile.isPaired || profile.coupleId == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) context.go('/');
          });
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (profile.coupleId != coupleId) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) context.go('/chat/${profile.coupleId!}');
          });
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return ChatShellPage(coupleId: coupleId);
      },
    );
  }
}
