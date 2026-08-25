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
  static const disabled = Color(0xFF9F8A94);
  static const line = Color(0xFFF2D6DF);
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
}

class DearRadii {
  static const small = 8.0;
  static const medium = 12.0;
  static const large = 16.0;
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
      decoration: const BoxDecoration(gradient: DearGradients.background),
      child: child,
    );
  }
}

class DearCard extends StatelessWidget {
  const DearCard({
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.margin = EdgeInsets.zero,
    this.radius = DearRadii.medium,
    this.gradient,
    this.color = DearColors.card,
    this.borderColor = DearColors.line,
    this.shadowOpacity = 1,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double radius;
  final Gradient? gradient;
  final Color color;
  final Color borderColor;
  final double shadowOpacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? color : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor),
        boxShadow: dearSoftShadow(shadowOpacity),
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
          borderRadius: BorderRadius.circular(12),
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
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onPressed,
            child: SizedBox(
              height: height,
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, color: Colors.white, size: 20),
                      const SizedBox(width: 8),
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
    this.background = DearColors.coralSoft,
    this.color = DearColors.coral,
    super.key,
  });

  final IconData icon;
  final double size;
  final double iconSize;
  final Color background;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, size: iconSize, color: color),
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
