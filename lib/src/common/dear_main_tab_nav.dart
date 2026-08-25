import 'package:couple_chat_app/src/common/dear_design.dart';
import 'package:couple_chat_app/src/features/auth/data/auth_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class DearMainTabBottomNav extends ConsumerWidget {
  const DearMainTabBottomNav({
    required this.currentIndex,
    this.onReselectCurrent,
    this.onTap,
    super.key,
  });

  final int currentIndex;
  final VoidCallback? onReselectCurrent;
  final ValueChanged<int>? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(myProfileProvider).valueOrNull;
    final chatPath = profile?.isPaired == true && profile?.coupleId != null
        ? '/chat/${profile!.coupleId!}'
        : '/';

    return DearBottomNav(
      currentIndex: currentIndex,
      onTap: (index) {
        if (onTap != null) {
          onTap!(index);
          return;
        }

        if (index == currentIndex) {
          onReselectCurrent?.call();
          return;
        }

        switch (index) {
          case 0:
            context.go('/chat-list');
            break;
          case 1:
            context.go(chatPath);
            break;
          case 2:
            context.go('/memory-album');
            break;
          case 3:
            context.go('/profile');
            break;
        }
      },
    );
  }
}

/// Hosts the three persistent root branches (Home, Album, More).
///
/// Chat intentionally is not a branch. It is pushed on the root navigator so
/// the conversation and every other detail screen stay free of the bottom bar.
class DearMainTabShell extends ConsumerWidget {
  const DearMainTabShell({
    required this.navigationShell,
    super.key,
  });

  final StatefulNavigationShell navigationShell;

  int get _bottomNavIndex {
    return switch (navigationShell.currentIndex) {
      0 => 0,
      1 => 2,
      _ => 3,
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: DearMainTabBottomNav(
        currentIndex: _bottomNavIndex,
        onTap: (index) => _handleTap(context, ref, index),
      ),
    );
  }

  void _handleTap(BuildContext context, WidgetRef ref, int index) {
    switch (index) {
      case 0:
        _goBranch(0);
        return;
      case 1:
        final profileAsync = ref.read(myProfileProvider);
        final profile = profileAsync.valueOrNull;
        if (profile?.isPaired == true && profile?.coupleId != null) {
          context.push('/chat/${profile!.coupleId!}');
          return;
        }

        if (profileAsync.isLoading) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('연결 정보를 확인하고 있어요.')),
          );
          return;
        }
        if (profileAsync.hasError) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('연결 정보를 불러오지 못했어요. 다시 시도해 주세요.')),
          );
          return;
        }
        context.go('/');
        return;
      case 2:
        _goBranch(1);
        return;
      case 3:
        _goBranch(2);
        return;
    }
  }

  void _goBranch(int branchIndex) {
    navigationShell.goBranch(
      branchIndex,
      initialLocation: branchIndex == navigationShell.currentIndex,
    );
  }
}
