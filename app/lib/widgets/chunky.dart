import 'package:flutter/material.dart';

/// The site's palette: loud, flat colors with thick ink outlines.
abstract final class Palette {
  static const blue = Color(0xFF1E5BFF);
  static const ink = Color(0xFF0B1640);
  static const yellow = Color(0xFFFFD60A);
  static const pink = Color(0xFFFF3EA5);
  static const orange = Color(0xFFFF7A00);
  static const green = Color(0xFF00C46A);
  static const sky = Color(0xFFDDE8FF);
  static const white = Colors.white;
}

/// Display type: Lilita One, a heavy rounded face.
TextStyle display(double size, {Color color = Palette.ink}) =>
    TextStyle(fontFamily: 'Lilita', fontSize: size, color: color, height: 1.05);

/// Body type in Nunito at a given weight (it is a variable font).
TextStyle body(double size, {double weight = 700, Color color = Palette.ink}) => TextStyle(
      fontFamily: 'Nunito',
      fontSize: size,
      color: color,
      fontVariations: [FontVariation('wght', weight)],
    );

/// A flat card with a thick outline and a hard offset shadow, like a sticker.
class Chunky extends StatelessWidget {
  const Chunky({
    super.key,
    required this.child,
    this.color = Palette.white,
    this.radius = 18,
    this.padding = const EdgeInsets.all(12),
    this.shadow = 4,
    this.border = 3,
    this.onTap,
  });

  final Widget child;
  final Color color;
  final double radius;
  final EdgeInsetsGeometry padding;
  final double shadow;
  final double border;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: shape,
        border: Border.all(color: Palette.ink, width: border),
        boxShadow: [
          if (shadow > 0) BoxShadow(color: Palette.ink, offset: Offset(shadow, shadow)),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: shape,
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// A pill-shaped choice button; the selected one is filled.
class Pill extends StatelessWidget {
  const Pill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.color = Palette.yellow,
    this.size = 15,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color color;
  final double size;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Chunky(
        color: selected ? color : Palette.white,
        radius: 999,
        shadow: selected ? 3 : 0,
        border: 2.5,
        padding: padding,
        onTap: onTap,
        child: Text(label, style: display(size)),
      );
}

/// Big white text with an ink drop shadow, for headings on the blue page.
class Shout extends StatelessWidget {
  const Shout(this.text, {super.key, this.size = 44, this.color = Palette.white});

  final String text;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: display(size, color: color).copyWith(
          shadows: [Shadow(color: Palette.ink, offset: Offset(size / 14, size / 14))],
        ),
      );
}

/// A slightly tilted label, like a sticker slapped on a wrapper.
class Sticker extends StatelessWidget {
  const Sticker(this.text, {super.key, this.color = Palette.yellow, this.angle = -0.04, this.size = 16});

  final String text;
  final Color color;
  final double angle;
  final double size;

  @override
  Widget build(BuildContext context) => Transform.rotate(
        angle: angle,
        child: Chunky(
          color: color,
          radius: 10,
          shadow: 3,
          border: 2.5,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text(text, style: display(size)),
        ),
      );
}

/// The color of a rank badge: gold, pink and orange for the top three.
Color rankColor(int? rank) => switch (rank) {
      1 => Palette.yellow,
      2 => Palette.pink,
      3 => Palette.orange,
      _ => Palette.sky,
    };
