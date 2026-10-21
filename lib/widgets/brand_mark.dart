import 'package:flutter/material.dart';
import 'package:radio_mac/theme/app_palette.dart';

class BrandMark extends StatelessWidget {
  const BrandMark({
    super.key,
    this.iconSize = 28,
    this.fontSize = 18,
    this.showSubtitle,
    this.compact = false,
    this.enableGlitch = true,
  });

  final double iconSize;
  final double fontSize;
  final String? showSubtitle;
  final bool compact;
  final bool enableGlitch;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final title = _BrandTitle(
      fontSize: fontSize,
      enableGlitch: enableGlitch,
      ink: palette.ink,
      accent: palette.accent,
      pink: palette.accentPink,
      cyan: palette.cyan,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        BrandRadioIcon(size: iconSize),
        SizedBox(width: compact ? 8 : 10),
        if (showSubtitle == null)
          title
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              title,
              const SizedBox(height: 2),
              Text(
                showSubtitle!,
                style: TextStyle(
                  fontSize: fontSize * 0.68,
                  color: palette.muted,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _BrandTitle extends StatefulWidget {
  const _BrandTitle({
    required this.fontSize,
    required this.enableGlitch,
    required this.ink,
    required this.accent,
    required this.pink,
    required this.cyan,
  });

  final double fontSize;
  final bool enableGlitch;
  final Color ink;
  final Color accent;
  final Color pink;
  final Color cyan;

  @override
  State<_BrandTitle> createState() => _BrandTitleState();
}

class _BrandTitleState extends State<_BrandTitle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glitch;
  bool _hover = false;

  @override
  void initState() {
    super.initState();
    _glitch = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
  }

  @override
  void dispose() {
    _glitch.dispose();
    super.dispose();
  }

  void _setHover(bool value) {
    if (!widget.enableGlitch || _hover == value) return;
    setState(() => _hover = value);
    if (value) {
      _glitch.repeat();
    } else {
      _glitch
        ..stop()
        ..value = 0;
    }
  }

  TextStyle _base(Color color) => TextStyle(
        fontSize: widget.fontSize,
        fontWeight: FontWeight.w700,
        height: 1.05,
        letterSpacing: -0.03 * widget.fontSize,
        color: color,
      );

  Widget _label({Color? radioColor, Color? macColor}) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: 'Radio', style: _base(radioColor ?? widget.ink)),
          TextSpan(text: 'Mac', style: _base(macColor ?? widget.accent)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = AnimatedBuilder(
      animation: _glitch,
      builder: (context, child) {
        final t = _glitch.value;
        Offset offset = Offset.zero;
        if (_hover) {
          if (t < 0.2) {
            offset = const Offset(-1, 1);
          } else if (t < 0.4) {
            offset = const Offset(1, -1);
          } else if (t < 0.6) {
            offset = const Offset(-1, 0);
          } else if (t < 0.8) {
            offset = const Offset(1, 1);
          }
        }

        return Transform.translate(
          offset: offset,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (_hover) ...[
                Transform.translate(
                  offset: const Offset(2, 0),
                  child: _label(radioColor: widget.pink, macColor: widget.pink),
                ),
                Transform.translate(
                  offset: const Offset(-2, 0),
                  child: _label(radioColor: widget.cyan, macColor: widget.cyan),
                ),
              ],
              _label(),
            ],
          ),
        );
      },
    );

    return MouseRegion(
      onEnter: (_) => _setHover(true),
      onExit: (_) => _setHover(false),
      cursor: SystemMouseCursors.basic,
      child: content,
    );
  }
}

class BrandRadioIcon extends StatelessWidget {
  const BrandRadioIcon({super.key, this.size = 28});

  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RadioMarkPainter(
          accent: palette.accent,
          pink: palette.accentPink,
          bg: palette.bgDeep,
        ),
      ),
    );
  }
}

class _RadioMarkPainter extends CustomPainter {
  _RadioMarkPainter({
    required this.accent,
    required this.pink,
    required this.bg,
  });

  final Color accent;
  final Color pink;
  final Color bg;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.08
      ..strokeCap = StrokeCap.round;
    final fill = Paint()..color = accent;
    final center = Offset(size.width * 0.42, size.height * 0.58);
    canvas.drawCircle(center, size.width * 0.11, fill);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: size.width * 0.26),
      -2.3,
      1.8,
      false,
      stroke,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: size.width * 0.4),
      -2.25,
      1.7,
      false,
      stroke,
    );

    final badge = size.width * 0.4;
    final badgeCenter = Offset(size.width * 0.78, size.height * 0.78);
    canvas.drawCircle(badgeCenter, badge * 0.52, Paint()..color = bg);
    canvas.drawCircle(badgeCenter, badge * 0.42, Paint()..color = accent);
    final plus = Paint()
      ..color = bg
      ..strokeWidth = size.width * 0.07
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(badgeCenter.dx - badge * 0.18, badgeCenter.dy),
      Offset(badgeCenter.dx + badge * 0.18, badgeCenter.dy),
      plus,
    );
    canvas.drawLine(
      Offset(badgeCenter.dx, badgeCenter.dy - badge * 0.18),
      Offset(badgeCenter.dx, badgeCenter.dy + badge * 0.18),
      plus,
    );
  }

  @override
  bool shouldRepaint(covariant _RadioMarkPainter oldDelegate) {
    return oldDelegate.accent != accent || oldDelegate.pink != pink;
  }
}
