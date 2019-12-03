import 'dart:io'; // for exit();
import 'dart:async';
import 'dart:isolate';
import 'package:image/image.dart' as img;
import 'dart:typed_data';
import 'package:tuple/tuple.dart';
import 'package:meta/meta.dart';

void myIsolate(SendPort mainSink) {
  ReceivePort isolateSink = ReceivePort();
  mainSink.send(isolateSink.sendPort);

  isolateSink.listen((d) { // This is where the data will be handled
    Operation data = d;
    Uint8List imageBytes;
    if (data is FileOperation) {
      imageBytes = data.file.readAsBytesSync();
    }
    if (data is MemoryOperation) {
      imageBytes = data.bytes;
    }

    final img.Image image = img.decodeImage(imageBytes);
    final int x = image.width;
    final int y = image.height;

    final double tgtAspectRatio = data.xSize / data.ySize;
    final double currentAspectRatio = x/y;

    final double unit = tgtAspectRatio > currentAspectRatio ? x/data.xSize : y/data.ySize;
    final double tgtX = unit*data.xSize;
    final double tgtY = unit*data.ySize;
    // Crop the image to the biggest possible size matching the target aspect
    // ratio, and then resize the image to the exact target size.
    mainSink.send(img.encodePng(img.copyResize(img.copyCrop(image, 0, 0, tgtX.round(), tgtY.round()), width: data.xSize.round(), height: data.ySize.round())));
  });
}

class IsolateManager {
  IsolateManager._();
  static IsolateManager _instance;

  static IsolateManager get instance {
    if (_instance == null) {
      _instance = IsolateManager._();
      _instance.spawnIsolate();
    }
    return _instance;
  }

  List<Tuple2<Operation, Completer<Uint8List>>> _ops = []; // Will be completed in a fifo manner

  Isolate isolate;
  ReceivePort isolateStream;
  SendPort isolateSink;

  Future<SendPort> spawnIsolate() async {
    final Completer completer = Completer<SendPort>();
    isolateStream = ReceivePort();

    isolateStream.listen((data) {
      // This setups the Isolate communication
      if (data is SendPort) {
        isolateSink = data;
        completer.complete(isolateSink);
        processNext();
      } else {
        // This is an image, lets send it to who requested it
        handleProcessedImage(data as Uint8List);
      }
    });

    isolate = await Isolate.spawn(myIsolate, isolateStream.sendPort);
    return completer.future;
  }

  Future<Uint8List> processImage(Operation op) async {
    final Completer<Uint8List> completer = Completer<Uint8List>();
    _ops.add(Tuple2(op, completer));
    return completer.future;
  }

  void processNext() {
    if (_ops.isEmpty) {
      // Ok, nothing more to do, kill the isolate, along with the manager
      isolate.kill(priority: Isolate.immediate);
      return _instance = null;
    }
    isolateSink.send(_ops.first.item1);
  }

  void handleProcessedImage(Uint8List bytes) {
    final Completer<Uint8List> completer = _ops.first.item2;
    completer.complete(bytes);
    _ops.removeAt(0);
    processNext();
  }
}

@immutable
abstract class Operation {
  const Operation(this.xSize, this.ySize);
  final double xSize;
  final double ySize;
}

class FileOperation extends Operation {
  const FileOperation(this.file, double x, double y) : super(x,y);
  final File file;
}

class MemoryOperation extends Operation {
  const MemoryOperation(this.bytes, double x, double y) : super(x,y);
  final Uint8List bytes;
}