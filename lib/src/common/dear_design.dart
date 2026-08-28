import 'dart:math' as math;

import 'package:flutter/material.dart';

class DearColors {
  static const backgroundTop = Color(0xFFFFFCFD);
  static const blush = Color(0xFFFFF7F9);
  static const blushDeep = Color(0xFFFDE8EF);
  static const card = Color(0xFFFFFFFF);
  static const coral = Color(0xFFE85D8B);
  // Brand coral is reserved for large controls and decorative accents. Small
  // text uses this darker companion so it remains readable on warm-white and
  // blush surfaces at WCAG AA contrast.
  static const coralText = Color(0xFFB53260);
  static const coralLight = Color(0xFFF7A8BD);
  static const coralSoft = Color(0xFFFFEFF4);
  static const accent = Color(0xFFFF8A73);
  static const ink = Color(0xFF2D1F25);
  static const secondary = Color(0xFF6F5963);
  static const muted = Color(0xFF8C6F7A);
  // Placeholder copy is readable as normal-size text and remains distinct from
  // secondary content. Disabled is reserved for genuinely unavailable UI.
  static const placeholder = Color(0xFF876A76);
  static const disabled = Color(0xFF9F8A94);
  static const line = Color(0xFFF2D6DF);
  // Interactive boundaries need stronger contrast than decorative dividers.
  // This color has a 3.09:1 contrast ratio against the white card surface.
  static const outlineStrong = Color(0xFFC47E99);
  static const warmLine = Color(0xFFF0D7D2);
  static const shadow = Color(0xFF2D1F25);
  static const error = Color(0xFFD64545);
  static const warmMap = Color(0xFFFFFCF6);
  static const board = Color(0xFFF3D6A4);
}

class DearGradients {
  static const background = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      DearColors.backgroundTop,
      Color(0xFFFFFBFC),
      Color(0xFFFFF9FB),
    ],
    stops: [0, 0.68, 1],
  );

  static const cta = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFFC13D6B), DearColors.coralText],
  );

  static const softCard = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Colors.white,
      DearColors.blush,
      DearColors.blushDeep,
    ],
  );

  static LinearGradient backgroundFor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        scheme.surfaceContainerLowest,
        scheme.surfaceContainerLow,
        scheme.surfaceContainer,
      ],
      stops: const [0, 0.68, 1],
    );
  }

  static LinearGradient softCardFor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        scheme.surface,
        scheme.surfaceContainerLow,
        scheme.surfaceContainerHigh,
      ],
    );
  }
}

class DearRadii {
  static const chip = 14.0;
  static const control = 18.0;
  static const card = 22.0;
  static const sheet = 30.0;
  static const pill = 999.0;

  // Compatibility aliases for existing feature code. New common components
  // should prefer the semantic names above.
  static const extraSmall = 8.0;
  static const small = chip;
  static const medium = control;
  static const large = card;
  static const extraLarge = sheet;
}

class DearSpacing {
  const DearSpacing._();

  static const space4 = 4.0;
  static const space8 = 8.0;
  static const space12 = 12.0;
  static const space16 = 16.0;
  static const space20 = 20.0;
  static const space24 = 24.0;
  static const space32 = 32.0;
  static const space40 = 40.0;
  static const space48 = 48.0;
}

class DearIconSizes {
  const DearIconSizes._();

  static const small = 20.0;
  static const medium = 24.0;
  static const large = 28.0;
  static const feature = 44.0;
}

class DearTouchTargets {
  const DearTouchTargets._();

  static const minimum = 44.0;
  static const comfortable = 48.0;
  static const spacing = DearSpacing.space8;
}

class DearMotion {
  const DearMotion._();

  static const instant = Duration.zero;
  static const fast = Duration(milliseconds: 120);
  static const standard = Duration(milliseconds: 180);
  static const emphasized = Duration(milliseconds: 260);
  static const exit = Duration(milliseconds: 160);

  static const enterCurve = Curves.easeOutCubic;
  static const exitCurve = Curves.easeInCubic;
  static const emphasizedCurve = Curves.easeOutBack;

  static Duration duration(BuildContext context, Duration preferred) {
    return MediaQuery.disableAnimationsOf(context) ? instant : preferred;
  }
}

class DearTextStyles {
  const DearTextStyles._();

  static const displayDday = TextStyle(
    fontSize: 48,
    height: 56 / 48,
    fontWeight: FontWeight.w800,
  );
  static const title = TextStyle(
    fontSize: 24,
    height: 32 / 24,
    fontWeight: FontWeight.w800,
  );
  static const titleSmall = TextStyle(
    fontSize: 18,
    height: 24 / 18,
    fontWeight: FontWeight.w700,
  );
  static const body = TextStyle(
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w400,
  );
  static const bodySmall = TextStyle(
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w400,
  );
  static const label = TextStyle(
    fontSize: 13,
    height: 18 / 13,
    fontWeight: FontWeight.w600,
  );

  static TextTheme applyTo(
    TextTheme base, {
    required Color primaryColor,
    required Color secondaryColor,
  }) {
    TextStyle merge(
      TextStyle? baseStyle,
      TextStyle token,
      Color color,
    ) {
      return (baseStyle ?? const TextStyle())
          .merge(token)
          .copyWith(color: color);
    }

    return base.copyWith(
      displayMedium: merge(base.displayMedium, displayDday, primaryColor),
      headlineSmall: merge(base.headlineSmall, title, primaryColor),
      titleLarge: merge(base.titleLarge, title, primaryColor),
      titleMedium: merge(base.titleMedium, titleSmall, primaryColor),
      titleSmall: merge(base.titleSmall, titleSmall, primaryColor),
      bodyLarge: merge(base.bodyLarge, body, primaryColor),
      bodyMedium: merge(base.bodyMedium, body, primaryColor),
      bodySmall: merge(base.bodySmall, bodySmall, secondaryColor),
      labelLarge: merge(base.labelLarge, label, primaryColor),
      labelMedium: merge(base.labelMedium, label, primaryColor),
      labelSmall: merge(base.labelSmall, label, secondaryColor),
    );
  }
}

List<BoxShadow> dearSoftShadow([double opacity = 1]) {
  return [
    BoxShadow(
      color: DearColors.shadow.withValues(alpha: 0.07 * opacity),
      blurRadius: 16,
      offset: const Offset(0, 8),
    ),
  ];
}

class DearBackground extends StatelessWidget {
  const DearBackground({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(gradient: DearGradients.backgroundFor(context)),
      child: child,
    );
  }
}

class DearCard extends StatelessWidget {
  const DearCard({
    required this.child,
    this.padding = const EdgeInsets.all(DearSpacing.space16),
    this.margin = EdgeInsets.zero,
    this.radius = DearRadii.card,
    this.gradient,
    this.color,
    this.borderColor,
    this.shadowOpacity = 1,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double radius;
  final Gradient? gradient;
  final Color? color;
  final Color? borderColor;
  final double shadowOpacity;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? color ?? scheme.surface : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor ?? scheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.07 * shadowOpacity),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class DearGradientButton extends StatelessWidget {
  const DearGradientButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.height = 54,
    this.expanded = true,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final double height;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final button = Opacity(
      opacity: onPressed == null ? 0.55 : 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: DearGradients.cta,
          borderRadius: BorderRadius.circular(DearRadii.control),
          boxShadow: [
            BoxShadow(
              color: DearColors.shadow.withValues(alpha: 0.08),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(DearRadii.control),
          child: InkWell(
            borderRadius: BorderRadius.circular(DearRadii.control),
            onTap: onPressed,
            child: SizedBox(
              height: height,
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Icon(
                        icon,
                        color: Colors.white,
                        size: DearIconSizes.small,
                      ),
                      const SizedBox(width: DearSpacing.space8),
                    ],
                    Text(
                      label,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (!expanded) return button;
    return SizedBox(width: double.infinity, child: button);
  }
}

class DearIconBubble extends StatelessWidget {
  const DearIconBubble({
    required this.icon,
    this.size = 54,
    this.iconSize = 27,
    this.background,
    this.color,
    super.key,
  });

  final IconData icon;
  final double size;
  final double iconSize;
  final Color? background;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background ?? scheme.primaryContainer,
        borderRadius: BorderRadius.circular(DearRadii.chip),
      ),
      child:
          Icon(icon, size: iconSize, color: color ?? scheme.onPrimaryContainer),
    );
  }
}

class DearIconButton extends StatelessWidget {
  const DearIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.semanticLabel,
    this.selectedIcon,
    this.selected,
    this.toggled,
    this.targetSize = DearTouchTargets.minimum,
    this.iconSize = DearIconSizes.medium,
    this.color,
    this.disabledColor,
    this.style,
    this.focusNode,
    this.autofocus = false,
    super.key,
  })  : assert(tooltip.length > 0),
        assert(targetSize >= DearTouchTargets.minimum),
        assert(selected == null || toggled == null);

  final Widget icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final String? semanticLabel;
  final Widget? selectedIcon;
  final bool? selected;
  final bool? toggled;
  final double targetSize;
  final double iconSize;
  final Color? color;
  final Color? disabledColor;
  final ButtonStyle? style;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final isSelected = selected ?? toggled;
    return Semantics(
      container: true,
      button: true,
      enabled: onPressed != null,
      label: semanticLabel ?? tooltip,
      selected: selected,
      toggled: toggled,
      onTap: onPressed,
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: targetSize,
        child: IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          icon: icon,
          selectedIcon: selectedIcon,
          isSelected: isSelected,
          iconSize: iconSize,
          color: color,
          disabledColor: disabledColor,
          style: style,
          focusNode: focusNode,
          autofocus: autofocus,
          padding: EdgeInsets.zero,
          constraints: BoxConstraints.tightFor(
            width: targetSize,
            height: targetSize,
          ),
        ),
      ),
    );
  }
}

enum DearAsyncSectionStatus { content, loading, empty, error }

class DearAsyncSection extends StatelessWidget {
  const DearAsyncSection({
    required this.status,
    this.content,
    this.skeleton,
    this.errorMessage,
    this.onRetry,
    this.retrying = false,
    this.loadingLabel = '내용을 불러오는 중',
    this.retryLabel = '다시 시도',
    this.retryingLabel = '다시 불러오는 중',
    this.emptyTitle = '아직 내용이 없어요',
    this.emptyMessage,
    this.emptyIcon = Icons.inbox_outlined,
    this.emptyActionLabel,
    this.onEmptyAction,
    this.statusSpacing = DearSpacing.space12,
    super.key,
  })  : assert(
          status != DearAsyncSectionStatus.error ||
              (errorMessage != null && errorMessage != ''),
        ),
        assert(
          (emptyActionLabel == null && onEmptyAction == null) ||
              (emptyActionLabel != null && onEmptyAction != null),
        ),
        assert(!retrying || status == DearAsyncSectionStatus.error);

  final DearAsyncSectionStatus status;
  final Widget? content;
  final Widget? skeleton;
  final String? errorMessage;
  final VoidCallback? onRetry;
  final bool retrying;
  final String loadingLabel;
  final String retryLabel;
  final String retryingLabel;
  final String emptyTitle;
  final String? emptyMessage;
  final IconData emptyIcon;
  final String? emptyActionLabel;
  final VoidCallback? onEmptyAction;
  final double statusSpacing;

  @override
  Widget build(BuildContext context) {
    if (status == DearAsyncSectionStatus.empty) {
      return DearEmptyState(
        title: emptyTitle,
        message: emptyMessage,
        icon: emptyIcon,
        actionLabel: emptyActionLabel,
        onAction: onEmptyAction,
      );
    }

    final inlineStatus = switch (status) {
      DearAsyncSectionStatus.loading => DearInlineLoading(
          label: loadingLabel,
        ),
      DearAsyncSectionStatus.error => DearInlineError(
          message: errorMessage!,
          onRetry: onRetry,
          retrying: retrying,
          retryLabel: retryLabel,
          retryingLabel: retryingLabel,
        ),
      DearAsyncSectionStatus.content || DearAsyncSectionStatus.empty => null,
    };

    final preservedContent = content;
    if (preservedContent != null) {
      if (inlineStatus == null) return preservedContent;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          inlineStatus,
          SizedBox(height: statusSpacing),
          preservedContent,
        ],
      );
    }

    return switch (status) {
      DearAsyncSectionStatus.loading => DearLoadingState(
          label: loadingLabel,
          skeleton: skeleton,
        ),
      DearAsyncSectionStatus.error => inlineStatus!,
      DearAsyncSectionStatus.content ||
      DearAsyncSectionStatus.empty =>
        const SizedBox.shrink(),
    };
  }
}

class DearInlineError extends StatelessWidget {
  const DearInlineError({
    required this.message,
    this.onRetry,
    this.retrying = false,
    this.retryLabel = '다시 시도',
    this.retryingLabel = '다시 불러오는 중',
    super.key,
  });

  final String message;
  final VoidCallback? onRetry;
  final bool retrying;
  final String retryLabel;
  final String retryingLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final statusLabel = retrying ? '$message. $retryingLabel' : message;
    return Semantics(
      container: true,
      liveRegion: true,
      label: statusLabel,
      child: Material(
        color: scheme.errorContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DearRadii.large),
          side: BorderSide(
            color: scheme.error.withValues(alpha: 0.34),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(DearSpacing.space12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: Icon(
                  Icons.error_outline_rounded,
                  color: scheme.onErrorContainer,
                  size: DearIconSizes.medium,
                ),
              ),
              const SizedBox(width: DearSpacing.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ExcludeSemantics(
                      child: Text(
                        message,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onErrorContainer,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                    if (onRetry != null || retrying) ...[
                      const SizedBox(height: DearSpacing.space4),
                      TextButton.icon(
                        onPressed: retrying ? null : onRetry,
                        style: TextButton.styleFrom(
                          foregroundColor: scheme.onErrorContainer,
                          minimumSize: const Size(
                            DearTouchTargets.minimum,
                            DearTouchTargets.minimum,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: DearSpacing.space8,
                          ),
                        ),
                        icon: retrying
                            ? SizedBox.square(
                                dimension: DearIconSizes.small,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: scheme.onErrorContainer,
                                ),
                              )
                            : const Icon(Icons.refresh_rounded),
                        label: Text(retrying ? retryingLabel : retryLabel),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DearInlineLoading extends StatelessWidget {
  const DearInlineLoading({
    this.label = '내용을 불러오는 중',
    super.key,
  });

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      liveRegion: true,
      label: label,
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainer,
            borderRadius: BorderRadius.circular(DearRadii.large),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(DearSpacing.space12),
            child: Row(
              children: [
                const SizedBox.square(
                  dimension: DearIconSizes.small,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: DearSpacing.space12),
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DearLoadingState extends StatelessWidget {
  const DearLoadingState({
    this.label = '내용을 불러오는 중',
    this.skeleton,
    super.key,
  });

  final String label;
  final Widget? skeleton;

  @override
  Widget build(BuildContext context) {
    final loadingSkeleton = skeleton;
    if (loadingSkeleton != null) {
      return Semantics(
        container: true,
        liveRegion: true,
        label: label,
        child: ExcludeSemantics(child: loadingSkeleton),
      );
    }

    return Semantics(
      container: true,
      liveRegion: true,
      label: label,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.all(DearSpacing.space24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: DearSpacing.space12),
              Text(
                label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DearEmptyState extends StatelessWidget {
  const DearEmptyState({
    required this.title,
    this.message,
    this.icon = Icons.inbox_outlined,
    this.actionLabel,
    this.onAction,
    super.key,
  }) : assert(
          (actionLabel == null && onAction == null) ||
              (actionLabel != null && onAction != null),
        );

  final String title;
  final String? message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.all(DearSpacing.space24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: DearIconBubble(
                icon: icon,
                size: 64,
                iconSize: DearIconSizes.large,
              ),
            ),
            const SizedBox(height: DearSpacing.space12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (message != null) ...[
              const SizedBox(height: DearSpacing.space8),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (onAction != null && actionLabel != null) ...[
              const SizedBox(height: DearSpacing.space16),
              FilledButton(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class DearBottomNav extends StatelessWidget {
  const DearBottomNav({
    required this.currentIndex,
    required this.onTap,
    super.key,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: DearColors.backgroundTop.withValues(alpha: 0.98),
        border: const Border(top: BorderSide(color: DearColors.line)),
      ),
      child: SafeArea(
        top: false,
        child: BottomNavigationBar(
          currentIndex: currentIndex,
          onTap: onTap,
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedItemColor: DearColors.coralText,
          unselectedItemColor: DearColors.secondary,
          selectedLabelStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_rounded),
              label: '홈',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.chat_bubble_outline_rounded),
              label: '채팅',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.image_outlined),
              label: '앨범',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline_rounded),
              label: '더보기',
            ),
          ],
        ),
      ),
    );
  }
}

class DearLogoMark extends StatelessWidget {
  const DearLogoMark({
    this.size = 120,
    super.key,
  });

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.24),
        child: Image.asset(
          'assets/icons/dear_app_icon_1024.png',
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _PaintedLogo(size: size),
        ),
      ),
    );
  }
}

class _PaintedLogo extends StatelessWidget {
  const _PaintedLogo({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _DearLogoPainter()),
    );
  }
}

class _DearLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.09;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke
      ..shader = const LinearGradient(
        colors: [Colors.white, Color(0xFFFFA3B0), DearColors.coral],
      ).createShader(Offset.zero & size);

    final path = Path()
      ..moveTo(size.width * 0.26, size.height * 0.35)
      ..cubicTo(
        size.width * 0.45,
        size.height * 0.10,
        size.width * 0.88,
        size.height * 0.24,
        size.width * 0.78,
        size.height * 0.58,
      )
      ..cubicTo(
        size.width * 0.70,
        size.height * 0.83,
        size.width * 0.28,
        size.height * 0.85,
        size.width * 0.32,
        size.height * 0.56,
      )
      ..cubicTo(
        size.width * 0.36,
        size.height * 0.34,
        size.width * 0.63,
        size.height * 0.38,
        size.width * 0.62,
        size.height * 0.62,
      );

    canvas.drawPath(path, paint);

    final white = Paint()..color = Colors.white;
    final coral = Paint()..color = DearColors.coralLight;
    canvas.drawCircle(
        Offset(size.width * 0.27, size.height * 0.31), stroke * 0.82, white);
    canvas.drawCircle(
        Offset(size.width * 0.73, size.height * 0.61), stroke * 0.78, coral);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class DearAvatarPair extends StatelessWidget {
  const DearAvatarPair({
    this.leftImageUrl,
    this.rightImageUrl,
    this.size = 64,
    super.key,
  });

  final String? leftImageUrl;
  final String? rightImageUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size * 2.45,
      height: size * 1.28,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
              left: 0, child: _DearAvatar(imageUrl: leftImageUrl, size: size)),
          Icon(Icons.favorite_rounded,
              color: DearColors.coral, size: math.max(24, size * 0.42)),
          Positioned(
              right: 0,
              child: _DearAvatar(imageUrl: rightImageUrl, size: size)),
        ],
      ),
    );
  }
}

class _DearAvatar extends StatelessWidget {
  const _DearAvatar({required this.imageUrl, required this.size});

  final String? imageUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl?.trim();
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(4),
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      child: ClipOval(
        child: url == null || url.isEmpty
            ? DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFFFF4F6), Color(0xFFFFD5DF)],
                  ),
                ),
                child: Icon(Icons.person_rounded,
                    color: DearColors.coral, size: size * 0.52),
              )
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.person_rounded, color: DearColors.coral),
              ),
      ),
    );
  }
}
