import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Shows the **entire** image (no cropping) inside a fixed rectangle.
///
/// Letterboxing is avoided by drawing a lightly blurred, scaled copy of the same
/// image behind the sharp [BoxFit.contain] layer — works across aspect ratios
/// and resolutions without cutting off faces or edges.
class AdaptiveNetworkPhoto extends StatelessWidget {
  const AdaptiveNetworkPhoto({
    super.key,
    required this.imageUrl,
    this.blurSigma = 18,
    this.backgroundScale = 1.08,
    this.errorBuilder,
    this.loadingBuilder,
  });

  final String imageUrl;
  final double blurSigma;
  final double backgroundScale;
  final ImageErrorWidgetBuilder? errorBuilder;
  final ImageLoadingBuilder? loadingBuilder;

  @override
  Widget build(BuildContext context) {
    Widget err(BuildContext c, Object e, StackTrace? st) {
      if (errorBuilder != null) return errorBuilder!(c, e, st);
      return const SizedBox.shrink();
    }

    Widget load(BuildContext c, Widget child, ImageChunkEvent? progress) {
      if (loadingBuilder != null) return loadingBuilder!(c, child, progress);
      return child;
    }

    // Signed URLs change per session; key the disk cache on the stable path.
    final provider = CachedNetworkImageProvider(
      imageUrl,
      cacheKey: imageUrl.split('?').first,
    );

    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.hardEdge,
      children: [
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: Transform.scale(
            scale: backgroundScale,
            // The backdrop is blurred, so a tiny decode is plenty.
            child: Image(
              image: ResizeImage(provider, width: 120),
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: err,
              loadingBuilder: load,
            ),
          ),
        ),
        Image(
          image: provider,
          fit: BoxFit.contain,
          width: double.infinity,
          height: double.infinity,
          alignment: Alignment.center,
          filterQuality: FilterQuality.medium,
          errorBuilder: err,
          loadingBuilder: load,
        ),
      ],
    );
  }
}
