import 'package:couple_chat_app/src/common/dear_design.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _controller = PageController();
  int _index = 0;

  final _items = const [
    _OnboardingItem(
      eyebrow: 'CHAT',
      icon: Icons.chat_bubble_rounded,
      title: '둘만의 대화',
      subtitle: '메시지와 사진으로 오늘의 마음을 가장 가까이에서 나눠요.',
    ),
    _OnboardingItem(
      eyebrow: 'ALBUM',
      icon: Icons.photo_library_rounded,
      title: '함께 쌓는 추억 앨범',
      subtitle: '소중한 사진을 앨범별로 모으고 우리만의 추억을 오래 간직해요.',
    ),
    _OnboardingItem(
      eyebrow: 'ANNIVERSARY',
      icon: Icons.favorite_rounded,
      title: '다가오는 기념일',
      subtitle: '100일과 주년, 직접 만든 특별한 날까지 한곳에서 확인해요.',
    ),
    _OnboardingItem(
      eyebrow: 'TRAVEL MAP',
      icon: Icons.map_rounded,
      title: '함께 채우는 여행 지도',
      subtitle: '국내 도시와 세계 곳곳의 방문 기록을 색칠하며 여행 이야기를 남겨요.',
    ),
    _OnboardingItem(
      eyebrow: 'NOTIFICATION',
      icon: Icons.notifications_active_rounded,
      title: '중요한 순간을 놓치지 않게',
      subtitle: '새 메시지와 기념일, 둘만의 소식을 필요한 때 알려드려요.',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: DearBackground(
        child: Stack(
          children: [
            const Positioned(top: 90, left: -30, child: _PetalBlob(size: 120)),
            const Positioned(
              top: 210,
              right: -25,
              child: _PetalBlob(size: 100),
            ),
            const Positioned(
                bottom: 180, left: 22, child: _PetalBlob(size: 64)),
            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
                    child: Row(
                      children: [
                        const DearLogoMark(size: 42),
                        const SizedBox(width: 8),
                        Text(
                          'Dear',
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    color: scheme.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => context.go('/auth'),
                          style: TextButton.styleFrom(
                            foregroundColor: scheme.onSurfaceVariant,
                            minimumSize: const Size(44, 44),
                          ),
                          child: const Text('건너뛰기'),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: PageView.builder(
                      key: const Key('onboarding-pages'),
                      controller: _controller,
                      itemCount: _items.length,
                      onPageChanged: (value) => setState(() => _index = value),
                      itemBuilder: (context, i) {
                        final item = _items[i];
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
                          child: DearCard(
                            key: ValueKey('onboarding-card-$i'),
                            padding: const EdgeInsets.all(24),
                            radius: DearRadii.large,
                            color: scheme.surface.withValues(alpha: 0.92),
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                return SingleChildScrollView(
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      minHeight: constraints.maxHeight,
                                    ),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Container(
                                          width: 136,
                                          height: 136,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            gradient: DearGradients.softCardFor(
                                                context),
                                            border: Border.all(
                                              color: scheme.outlineVariant,
                                            ),
                                          ),
                                          child: Icon(
                                            item.icon,
                                            size: 60,
                                            color: scheme.primary,
                                          ),
                                        ),
                                        const SizedBox(height: 24),
                                        Text(
                                          item.eyebrow,
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelMedium
                                              ?.copyWith(
                                                color: scheme.primary,
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: 1.4,
                                              ),
                                          textAlign: TextAlign.center,
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          item.title,
                                          style: Theme.of(context)
                                              .textTheme
                                              .headlineSmall
                                              ?.copyWith(
                                                color: scheme.onSurface,
                                                fontWeight: FontWeight.w800,
                                              ),
                                          textAlign: TextAlign.center,
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          item.subtitle,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyLarge
                                              ?.copyWith(
                                                color: scheme.onSurfaceVariant,
                                                height: 1.5,
                                              ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Semantics(
                    label: '${_index + 1} / ${_items.length} 페이지',
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        _items.length,
                        (i) => AnimatedContainer(
                          duration: DearMotion.duration(
                            context,
                            DearMotion.standard,
                          ),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: _index == i ? 20 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            color: _index == i
                                ? scheme.primary
                                : scheme.outlineVariant,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                    child: DearGradientButton(
                      key: const Key('onboarding-next-button'),
                      height: 56,
                      onPressed: () {
                        if (_index < _items.length - 1) {
                          if (MediaQuery.disableAnimationsOf(context)) {
                            _controller.jumpToPage(_index + 1);
                          } else {
                            _controller.nextPage(
                              duration: DearMotion.emphasized,
                              curve: DearMotion.enterCurve,
                            );
                          }
                        } else {
                          context.go('/auth');
                        }
                      },
                      label: _index == _items.length - 1 ? '시작하기' : '다음',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PetalBlob extends StatelessWidget {
  const _PetalBlob({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Opacity(
      opacity: 0.34,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: scheme.primaryContainer,
        ),
      ),
    );
  }
}

class _OnboardingItem {
  const _OnboardingItem({
    required this.eyebrow,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final String eyebrow;
  final IconData icon;
  final String title;
  final String subtitle;
}
