import 'package:flutter/material.dart';

/// "Screen**Next**" wordmark. "Screen" is the on-surface color; "Next" renders
/// the current theme's primary accent with a continuous left-to-right light
/// sweep — a chase-light flourish that reads as forward motion.
///
/// (Originally shipped as "WatchNext" through v0.10.x; renamed to
/// ScreenNext in v0.11.0 after a preliminary trademark search found
/// commercial-use conflicts in the entertainment-software category —
/// see docs/trademark-search-2026-05-24.md. The gradient-sweep
/// treatment on `Next` is intentional and load-bearing for the brand
/// identity — preserve it on any future rebrand.)
class ScreenNextLogo extends StatefulWidget {
  const ScreenNextLogo({
    super.key,
    this.fontSize = 20,
    this.fontWeight = FontWeight.w700,
  });

  final double fontSize;
  final FontWeight fontWeight;

  @override
  State<ScreenNextLogo> createState() => _ScreenNextLogoState();
}

class _ScreenNextLogoState extends State<ScreenNextLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textStyle = TextStyle(
      fontSize: widget.fontSize,
      fontWeight: widget.fontWeight,
      letterSpacing: 0.2,
      height: 1.0,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text('Screen', style: textStyle.copyWith(color: scheme.onSurface)),
        AnimatedBuilder(
          animation: _c,
          builder: (_, _) {
            final t = _c.value;
            // Slide the gradient box from [-2, -1] to [1, 2] in the rect's
            // -1..1 coordinate space; the bright middle stop sweeps through
            // the text. TileMode.clamp leaves the dim accent on the edges
            // when the box is offscreen.
            final accentBright = scheme.primary;
            final accentDim = Color.lerp(scheme.primary, scheme.surface, 0.5)!;
            return ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (bounds) => LinearGradient(
                begin: Alignment(-2.0 + 3 * t, 0),
                end: Alignment(-1.0 + 3 * t, 0),
                colors: [accentDim, accentBright, accentDim],
                stops: const [0.0, 0.5, 1.0],
                tileMode: TileMode.clamp,
              ).createShader(bounds),
              child: Text('Next',
                  style: textStyle.copyWith(color: Colors.white)),
            );
          },
        ),
      ],
    );
  }
}
