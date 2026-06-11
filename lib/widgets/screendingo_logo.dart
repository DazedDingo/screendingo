import 'package:flutter/material.dart';

/// "Screen**Dingo**" wordmark. "Screen" is the on-surface color; "Dingo"
/// renders the current theme's primary accent with a continuous left-to-
/// right light sweep — a chase-light flourish that reads as forward motion.
///
/// (Originally shipped as "WatchNext" through v0.10.x; renamed to
/// "ScreenNext" in v0.11.0 after a preliminary trademark search found
/// commercial-use conflicts (Filippe Frulli's Watch Next, Google Android
/// TV); renamed to "ScreenDingo" in v0.12.0 after the same search later
/// found an Austrian word mark on "screennext" by Stefan Lennert.
/// ScreenDingo continues the DazedDingo developer brand — see
/// docs/trademark-search-2026-05-24.md. The gradient-sweep treatment
/// on the second word (originally `Next`, now `Dingo`) is intentional
/// and load-bearing for the brand identity — preserve it on any future
/// rebrand.)
class ScreenDingoLogo extends StatefulWidget {
  const ScreenDingoLogo({
    super.key,
    this.fontSize = 20,
    this.fontWeight = FontWeight.w700,
  });

  final double fontSize;
  final FontWeight fontWeight;

  @override
  State<ScreenDingoLogo> createState() => _ScreenDingoLogoState();
}

class _ScreenDingoLogoState extends State<ScreenDingoLogo>
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
    // Leave `height` unset — `height: 1.0` clips the "g" descender outside
    // ShaderMask.maskRect, so the bottom of the g renders white not gradient.
    final textStyle = TextStyle(
      fontSize: widget.fontSize,
      fontWeight: widget.fontWeight,
      letterSpacing: 0.2,
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
              child: Text('Dingo',
                  style: textStyle.copyWith(color: Colors.white)),
            );
          },
        ),
      ],
    );
  }
}
