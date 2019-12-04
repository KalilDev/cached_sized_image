import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'cached_network_image_provider.dart';
import 'package:transparent_image/transparent_image.dart';

typedef Widget ImageWidgetBuilder(
    BuildContext context, ImageProvider imageProvider);
typedef Widget PlaceholderWidgetBuilder(BuildContext context, String url);
typedef Widget LoadingErrorWidgetBuilder(
    BuildContext context, String url, Object error);

class CachedNetworkImage extends StatefulWidget {
  /// The target image that is displayed.
  final String imageUrl;

  /// Optional builder to further customize the display of the image.
  final ImageWidgetBuilder imageBuilder;

  /// Widget displayed while the target [imageUrl] is loading.
  final PlaceholderWidgetBuilder placeholder;

  /// Widget displayed while the target [imageUrl] failed loading.
  final LoadingErrorWidgetBuilder errorWidget;

  /// The duration of the fade-out animation for the [placeholder].
  final Duration fadeOutDuration;

  /// The curve of the fade-out animation for the [placeholder].
  final Curve fadeOutCurve;

  /// The duration of the fade-in animation for the [imageUrl].
  final Duration fadeInDuration;

  /// The curve of the fade-in animation for the [imageUrl].
  final Curve fadeInCurve;

  /// If non-null, require the image to have this width.
  ///
  /// If null, the image will pick a size that best preserves its intrinsic
  /// aspect ratio. This may result in a sudden change if the size of the
  /// placeholder widget does not match that of the target image. The size is
  /// also affected by the scale factor.
  final double width;

  /// If non-null, require the image to have this height.
  ///
  /// If null, the image will pick a size that best preserves its intrinsic
  /// aspect ratio. This may result in a sudden change if the size of the
  /// placeholder widget does not match that of the target image. The size is
  /// also affected by the scale factor.
  final double height;

  /// How to inscribe the image into the space allocated during layout.
  ///
  /// The default varies based on the other fields. See the discussion at
  /// [paintImage].
  final BoxFit fit;

  /// How to align the image within its bounds.
  ///
  /// The alignment aligns the given position in the image to the given position
  /// in the layout bounds. For example, a [Alignment] alignment of (-1.0,
  /// -1.0) aligns the image to the top-left corner of its layout bounds, while a
  /// [Alignment] alignment of (1.0, 1.0) aligns the bottom right of the
  /// image with the bottom right corner of its layout bounds. Similarly, an
  /// alignment of (0.0, 1.0) aligns the bottom middle of the image with the
  /// middle of the bottom edge of its layout bounds.
  ///
  /// If the [alignment] is [TextDirection]-dependent (i.e. if it is a
  /// [AlignmentDirectional]), then an ambient [Directionality] widget
  /// must be in scope.
  ///
  /// Defaults to [Alignment.center].
  ///
  /// See also:
  ///
  ///  * [Alignment], a class with convenient constants typically used to
  ///    specify an [AlignmentGeometry].
  ///  * [AlignmentDirectional], like [Alignment] for specifying alignments
  ///    relative to text direction.
  final AlignmentGeometry alignment;

  /// How to paint any portions of the layout bounds not covered by the image.
  final ImageRepeat repeat;

  /// Whether to paint the image in the direction of the [TextDirection].
  ///
  /// If this is true, then in [TextDirection.ltr] contexts, the image will be
  /// drawn with its origin in the top left (the "normal" painting direction for
  /// children); and in [TextDirection.rtl] contexts, the image will be drawn with
  /// a scaling factor of -1 in the horizontal direction so that the origin is
  /// in the top right.
  ///
  /// This is occasionally used with children in right-to-left environments, for
  /// children that were designed for left-to-right locales. Be careful, when
  /// using this, to not flip children with integral shadows, text, or other
  /// effects that will look incorrect when flipped.
  ///
  /// If this is true, there must be an ambient [Directionality] widget in
  /// scope.
  final bool matchTextDirection;

  // Optional headers for the http request of the image url
  final Map<String, String> httpHeaders;

  CachedNetworkImage({
    Key key,
    @required this.imageUrl,
    this.imageBuilder,
    this.placeholder,
    this.errorWidget,
    this.fadeOutDuration: const Duration(milliseconds: 1000),
    this.fadeOutCurve: Curves.easeOut,
    this.fadeInDuration: const Duration(milliseconds: 500),
    this.fadeInCurve: Curves.easeIn,
    this.width,
    this.height,
    this.fit,
    this.alignment: Alignment.center,
    this.repeat: ImageRepeat.noRepeat,
    this.matchTextDirection: false,
    this.httpHeaders,
  })  : assert(imageUrl != null),
        assert(fadeOutDuration != null),
        assert(fadeOutCurve != null),
        assert(fadeInDuration != null),
        assert(fadeInCurve != null),
        assert(alignment != null),
        assert(repeat != null),
        assert(matchTextDirection != null),
        super(key: key);

  @override
  CachedNetworkImageState createState() {
    return CachedNetworkImageState();
  }
}

class CachedNetworkImageState extends State<CachedNetworkImage>
    with TickerProviderStateMixin {
  @override
  Widget build(BuildContext context) {
    return _animatedWidget();
  }

  _animatedWidget() {
    return LayoutBuilder(builder: (BuildContext context, BoxConstraints constraints) {
      final Size size = Size(widget.width ?? constraints.biggest.width, widget.height ?? constraints.biggest.height);
      var error;
      CachedNetworkImageProvider imgProvider;
      try {
        imgProvider = CachedNetworkImageProvider(
            widget.imageUrl, devicePixelRatio: MediaQuery
            .of(context)
            .devicePixelRatio, size: constraints.biggest, headers: widget.httpHeaders);
      } catch (e) {
        error = e;
      }
      final List<Widget> children = [];
      if (error != null) {
        children.add(Align(alignment: widget.alignment,child: _errorWidget(context,error),));
      } else {
        children.add(Align(alignment: widget.alignment,child: _placeholder(context),));
        children.add(_image(context, imgProvider));
      }

      return SizedBox(height: size.height,width: size.width,child: Stack(fit:StackFit.expand, children: children,));
    });
  }

  _image(BuildContext context, ImageProvider imageProvider) {
    return widget.imageBuilder != null
        ? widget.imageBuilder(context, imageProvider)
        : FadeInImage(
            image: imageProvider,
            fit: widget.fit,
            width: widget.width,
            height: widget.height,
            alignment: widget.alignment,
            repeat: widget.repeat,
            placeholder: MemoryImage(kTransparentImage),
            matchTextDirection: widget.matchTextDirection,
            fadeInCurve: widget.fadeInCurve,
            fadeInDuration: widget.fadeInDuration,
            fadeOutCurve: widget.fadeOutCurve,
            fadeOutDuration: widget.fadeOutDuration,
          );
  }

  _placeholder(BuildContext context) {
    return widget.placeholder != null
        ? widget.placeholder(context, widget.imageUrl)
        : SizedBox(
            width: widget.width,
            height: widget.height,
          );
  }

  _errorWidget(BuildContext context, Object error) {
    return widget.errorWidget != null
        ? widget.errorWidget(context, widget.imageUrl, error)
        : _placeholder(context);
  }
}
