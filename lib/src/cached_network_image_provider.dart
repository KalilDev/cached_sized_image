import 'dart:async' show Future;
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui show instantiateImageCodec, Codec;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart';
import 'package:path_provider/path_provider.dart' as p;
import 'dart:convert' as c;
import 'resize_isolate.dart';

typedef void ErrorListener();

class CachedNetworkImageProvider
    extends ImageProvider<CachedNetworkImageProvider> {
  /// Creates an ImageProvider which loads an image from the [url], using the [scale].
  /// When the image fails to load [errorListener] is called.
  const CachedNetworkImageProvider(this.url,
      {this.scale: 1.0, this.errorListener, this.headers, @required this.devicePixelRatio, @required this.size})
      : assert(url != null),
        assert(scale != null);

  /// Web url of the image to load
  final String url;

  /// Scale of the image
  final double scale;

  /// Listener to be called when images fails to load.
  final ErrorListener errorListener;

  // Set headers for the image provider, for example for authentication
  final Map<String, String> headers;

  // The device pixel ratio is needed to select the correct image
  final double devicePixelRatio;

  // The desired size for this image
  final Size size;

  @override
  Future<CachedNetworkImageProvider> obtainKey(
      ImageConfiguration configuration) {
    return SynchronousFuture<CachedNetworkImageProvider>(this);
  }

  @override
  ImageStreamCompleter load(
      CachedNetworkImageProvider key, DecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key),
      scale: key.scale,
      informationCollector: () sync* {
        yield DiagnosticsProperty<ImageProvider>(
          'Image provider: $this \n Image key: $key',
          this,
          style: DiagnosticsTreeStyle.errorProperty,
        );
      },
    );
  }

  static const String imgCachePostfix = 'imageCache';

  Future<ui.Codec> _loadAsync(CachedNetworkImageProvider key) async {
    try {
      final Directory cacheDir = await p.getExternalCacheDirectories().then((
          List l) => l.first);
      final Directory imageCacheDir = Directory(
          cacheDir.path + '/' + imgCachePostfix);
      if (!imageCacheDir.existsSync()) {
        imageCacheDir.createSync();
      }
      final File json = File(
          imageCacheDir.path + '/' + imgCachePostfix + '.json');
      if (!json.existsSync())
        json.createSync();

      List<CachedImage> getImagesSync() {
        final String jsonStr = json.readAsStringSync();
        List<dynamic> jsonDoc;
        try {
          jsonDoc = c.jsonDecode(jsonStr);
        } on FormatException catch (e) {
          print(e);
          jsonDoc = [];
        }
        return jsonDoc.map<CachedImage>((
            dynamic v) => CachedImage.fromJson(v as Map)).toList();
      }

      final List<CachedImage> availableImages = getImagesSync();
      final Size normalizedSize = CachedImage.getNormalizedSize(
          size, devicePixelRatio);
      final int idx = availableImages.indexWhere((CachedImage img) =>
      img.url == url);
      final CachedImage img = idx == -1 ? CachedImage(folderName: url
          .split('/')
          .last, availableSizes: [], url: url) : availableImages[idx];
      final Directory dir = Directory(imageCacheDir.path + '/' + img.folderName);
      if (!dir.existsSync()) dir.create();

      final File f = File(
          dir.path + '/' + CachedImage.getSizeName(normalizedSize));
      final File fullSize = File(
          dir.path + '/full');
      final bool requestedFullSized = CachedImage.getSizeName(normalizedSize) == 'full';

      void saveState(CachedImage img) {
        // We need to read the file again and do it synchronously to have a lock
        // on the json. Otherwise, in an async gap, the file could be updated,
        // ruining the changes.
        final List<CachedImage> availableImages = getImagesSync();
        final int idx = availableImages.indexWhere((CachedImage img) =>
          img.url == url);
        final CachedImage newImage = idx == -1 ? null : availableImages[idx];
        if (idx != -1)
          availableImages.removeAt(idx);
        json.writeAsStringSync(c.jsonEncode(availableImages..add(img + newImage),
            toEncodable: (Object o) => (o as CachedImage).toJson()));
      }

      Uint8List bytes;

      if (!fullSize.existsSync()) {
        bytes = await get(url, headers: headers).catchError((_)=>throw ErrorDescription("Couldn't download image")).then((Response r)=>r.bodyBytes);
        fullSize.writeAsBytesSync(bytes);
        if (requestedFullSized) {
          saveState(img);
          return await ui.instantiateImageCodec(bytes);
        }
      }

        // We have the cheese and the knife already
        if (requestedFullSized) {
          return _loadAsyncFromFile(key, fullSize);
        }

        // We need to process the img
        if (!img.availableSizes.contains(normalizedSize)) {
            // We already have a full sized image, we only need to process it.
            // If the bytes aren't empty then there is already an full image,
            // no need to read it again, causing more I/O overhead
            final Operation op = bytes == null ? FileOperation(fullSize, normalizedSize.width, normalizedSize.height) : MemoryOperation(bytes, normalizedSize.width, normalizedSize.height);
            bytes = await IsolateManager.instance.processImage(op);
            // Tell this cache manager that this size was processed already
            saveState(img.copyWithSize(normalizedSize));
            // Store the processed image
            f.writeAsBytes(bytes);
            return await ui.instantiateImageCodec(bytes);
        }


          // The image is already available, just read it
          return await _loadAsyncFromFile(key, f);
    } catch(e) {
      print(e);
      return null;
    }
  }

  Future<ui.Codec> _loadAsyncFromFile(
      CachedNetworkImageProvider key, File file) async {
    assert(key == this);

    final Uint8List bytes = await file.readAsBytes();

    if (bytes.lengthInBytes == 0) {
      if (errorListener != null) errorListener();
      throw Exception("File was empty");
    }

    return await ui.instantiateImageCodec(bytes);
  }

  @override
  bool operator ==(dynamic other) {
    if (other.runtimeType != runtimeType) return false;
    final CachedNetworkImageProvider typedOther = other;
    return url == typedOther.url && scale == typedOther.scale && CachedImage.getNormalizedSize(size, devicePixelRatio) == CachedImage.getNormalizedSize(other.size, other.devicePixelRatio);
  }

  @override
  int get hashCode => hashValues(url, scale, CachedImage.getNormalizedSize(size, devicePixelRatio));

  @override
  String toString() => '$runtimeType("$url", scale: $scale, size: Size(${size?.width}, ${size?.height}), devicePixelRatio: $devicePixelRatio)';
}

class CachedImage {
  const CachedImage({this.folderName, this.availableSizes, this.url});
  factory CachedImage.fromJson(Map<dynamic, dynamic> json) {
    final String folderName = json["name"] as String;
    final String url = json["url"] as String;
    List<Size> availableSizes = [];
    final Iterator i1 = (json["sizesX"] as Iterable).iterator;
    final Iterator i2 = (json["sizesY"] as Iterable).iterator;
    while (i1.moveNext() && i2.moveNext()) {
      availableSizes.add(Size(i1.current as double, i2.current as double));
    }
    return CachedImage(folderName: folderName, availableSizes: availableSizes, url: url);
  }

  final String folderName;
  final List<Size> availableSizes;
  final String url;

  CachedImage copyWithSize(Size s) => CachedImage(folderName: folderName, availableSizes: availableSizes..add(s),url: url);

  static String getSizeName(Size s) => (s == null || (s?.width == null && s?.height == null)) ? "full" : s.width.toString() + 'x' + s.height.toString();
  static Size getNormalizedSize(Size s, double pps) => (s == null || pps == null) ? null : Size((s.width * pps / 100.0).round() * 100.0, (s.height * pps / 100.0).round() * 100.0);

  Map<String, dynamic> toJson() {
    final List<double> sizesX = [];
    final List<double> sizesY = [];
    final Iterator iter = availableSizes.iterator;
    while (iter.moveNext()) {
      final Size current = iter.current;
      sizesX.add(current?.width);
      sizesY.add(current?.height);
    }
    return {
      "name": folderName,
      "url": url,
      "sizesX": sizesX,
      "sizesY": sizesY
    };
  }

  CachedImage operator +(CachedImage other) {
    if (other == null)
      return this;
    return CachedImage(availableSizes: other.availableSizes.followedBy(this.availableSizes).toSet().toList(), folderName: other.folderName, url: other.url);
  }
}
