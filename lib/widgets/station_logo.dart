import 'package:flutter/material.dart';
import 'package:radio_mac/models/radio_station.dart';
import 'package:radio_mac/theme/app_palette.dart';

class StationLogo extends StatelessWidget {
  const StationLogo({
    super.key,
    required this.station,
    this.size = 36,
    this.imageUrl,
  });

  final RadioStation station;
  final double size;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = GenreCatalog.colorFor(station.genre, palette);
    final radius = BorderRadius.circular(8);
    final override = imageUrl?.trim();
    final url = (override != null && override.isNotEmpty)
        ? override
        : (station.hasLogo ? station.logoUrl : null);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: radius,
        border: Border.all(color: palette.line.withValues(alpha: 0.7)),
      ),
      clipBehavior: Clip.antiAlias,
      child: url != null
          ? Image.network(
              url,
              width: size,
              height: size,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, _, _) => _Fallback(color: color, size: size),
            )
          : _Fallback(color: color, size: size),
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Icon(Icons.radio_rounded, size: size * 0.5, color: color),
    );
  }
}
