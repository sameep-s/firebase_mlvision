// Copyright 2018 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

part of firebase_mlvision;

/// Indicates the image rotation.
///
/// Rotation is counter-clockwise.
enum ImageRotation { rotation0, rotation90, rotation180, rotation270 }

/// Indicates whether a model is ran on device or in the cloud.
enum ModelType { onDevice, cloud }

/// Indicates direction of selected camera
enum CameraDirection { front, back, external }

/// Indicates selected camera resolution
enum ResolutionSetting { low, medium, high }

const MethodChannel channel = MethodChannel('plugins.flutter.io/firebase_mlvision');

/// Returns the resolution preset as a String.
String serializeResolutionPreset(ResolutionSetting resolutionSetting) {
  switch (resolutionSetting) {
    case ResolutionSetting.high:
      return 'high';
    case ResolutionSetting.medium:
      return 'medium';
    case ResolutionSetting.low:
      return 'low';
  }
  throw ArgumentError('Unknown ResolutionSetting value');
}

CameraDirection _parseCameraDirection(String string) {
  switch (string) {
    case 'front':
      return CameraDirection.front;
    case 'back':
      return CameraDirection.back;
    case 'external':
      return CameraDirection.external;
  }
  throw ArgumentError('Unknown CameraDirection value');
}

/// Completes with a list of available cameras.
///
/// May throw a [FirebaseCameraException].
Future<List<FirebaseCameraDescription>> camerasAvailable() async {
  try {
    final List<Map<dynamic, dynamic>> cameras = await channel
        .invokeListMethod<Map<dynamic, dynamic>>('camerasAvailable');
    return cameras.map((Map<dynamic, dynamic> camera) {
      return FirebaseCameraDescription(
        name: camera['name'],
        lensDirection: _parseCameraDirection(camera['lensFacing']),
        sensorOrientation: camera['sensorOrientation'],
      );
    }).toList();
  } on PlatformException catch (e) {
    throw FirebaseCameraException(e.code, e.message);
  }
}

class FirebaseCameraDescription {
  FirebaseCameraDescription({this.name, this.lensDirection, this.sensorOrientation});

  final String name;
  final CameraDirection lensDirection;

  /// Clockwise angle through which the output image needs to be rotated to be upright on the device screen in its native orientation.
  ///
  /// **Range of valid values:**
  /// 0, 90, 180, 270
  ///
  /// On Android, also defines the direction of rolling shutter readout, which
  /// is from top to bottom in the sensor's coordinate system.
  final int sensorOrientation;

  @override
  bool operator ==(Object o) {
    return o is FirebaseCameraDescription &&
        o.name == name &&
        o.lensDirection == lensDirection;
  }

  @override
  int get hashCode {
    return hashValues(name, lensDirection);
  }

  @override
  String toString() {
    return '$runtimeType($name, $lensDirection, $sensorOrientation)';
  }
}

/// This is thrown when the plugin reports an error.
class FirebaseCameraException implements Exception {
  FirebaseCameraException(this.code, this.description);

  String code;
  String description;

  @override
  String toString() => '$runtimeType($code, $description)';
}

// Build the UI texture view of the video data with textureId.
class FirebaseCameraPreview extends StatelessWidget {
  const FirebaseCameraPreview(this.controller);

  final FirebaseVision controller;

  @override
  Widget build(BuildContext context) {
    return controller.value.isInitialized
        ? Texture(textureId: controller._textureId)
        : Container();
  }
}

/// The state of a [CameraController].
class FirebaseCameraValue {
  const FirebaseCameraValue({
    this.isInitialized,
    this.errorDescription,
    this.previewSize
  });

  const FirebaseCameraValue.uninitialized()
      : this(isInitialized: false);

  /// True after [FirebaseVision.initialize] has completed successfully.
  final bool isInitialized;

  final String errorDescription;

  /// The size of the preview in pixels.
  ///
  /// Is `null` until  [isInitialized] is `true`.
  final Size previewSize;

  /// Convenience getter for `previewSize.height / previewSize.width`.
  ///
  /// Can only be called when [initialize] is done.
  double get aspectRatio => previewSize.height / previewSize.width;

  bool get hasError => errorDescription != null;

  FirebaseCameraValue copyWith({
    bool isInitialized,
    bool isRecordingVideo,
    bool isTakingPicture,
    bool isStreamingImages,
    String errorDescription,
    Size previewSize,
  }) {
    return FirebaseCameraValue(
      isInitialized: isInitialized ?? this.isInitialized,
      errorDescription: errorDescription,
      previewSize: previewSize ?? this.previewSize,
    );
  }

  @override
  String toString() {
    return '$runtimeType('
        'isInitialized: $isInitialized, '
        'errorDescription: $errorDescription, '
        'previewSize: $previewSize )';
  }
}

/// The Firebase machine learning vision API.
///
/// You can get an instance by calling [FirebaseVision.instance] and then get
/// a detector from the instance:
///
/// ```dart
/// TextRecognizer textRecognizer = FirebaseVision.instance.textRecognizer();
/// ```
class FirebaseVision extends ValueNotifier<FirebaseCameraValue> {
  FirebaseVision(
    this.description,
    this.resolutionPreset
  ) : super(const FirebaseCameraValue.uninitialized());

  final FirebaseCameraDescription description;
  final ResolutionSetting resolutionPreset;
  static int nextHandle = 0;

  int _textureId;
  bool _isDisposed = false;
  StreamSubscription<dynamic> _eventSubscription;
  Completer<void> _creatingCompleter;
  BarcodeDetector barcodeDetector;
  FaceDetector faceDetector;
  ImageLabeler cloudImageLabeler;
  ImageLabeler localImageLabeler;
  TextRecognizer textRecognizer;
  VisionEdgeImageLabeler visionEdgeImageLabeler;

  static const MethodChannel channel = MethodChannel('plugins.flutter.io/firebase_mlvision');

  /// Singleton of [FirebaseVision].
  ///
  /// Use this get an instance of a detector:
  ///
  /// ```dart
  /// TextRecognizer textRecognizer = FirebaseVision.instance.textRecognizer();
  /// ```
  // static final FirebaseVision instance = FirebaseVision._();

  /// Initializes the camera on the device.
  ///
  /// Throws a [CameraException] if the initialization fails.
  Future<void> initialize() async {
    if (_isDisposed) {
      return Future<void>.value();
    }
    try {
      _creatingCompleter = Completer<void>();
      final Map<String, dynamic> reply =
          await channel.invokeMapMethod<String, dynamic>(
        'initialize',
        <String, dynamic>{
          'cameraName': description.name,
          'resolutionPreset': serializeResolutionPreset(resolutionPreset)
        },
      );
      _textureId = reply['textureId'];
      value = value.copyWith(
        isInitialized: true,
        previewSize: Size(
          reply['previewWidth'].toDouble(),
          reply['previewHeight'].toDouble(),
        ),
      );
    } on PlatformException catch (e) {
      throw FirebaseCameraException(e.code, e.message);
    }
    _eventSubscription =
        EventChannel('plugins.flutter.io/firebase_mlvision$_textureId')
            .receiveBroadcastStream()
            .listen(_listener);
    _creatingCompleter.complete();
    return _creatingCompleter.future;
  }

  /// Listen to events from the native plugins.
  ///
  /// A "cameraClosing" event is sent when the camera is closed automatically by the system (for example when the app go to background). The plugin will try to reopen the camera automatically but any ongoing recording will end.
  void _listener(dynamic event) {
    final Map<dynamic, dynamic> map = event;
    if (_isDisposed) {
      return;
    }

    switch (map['eventType']) {
      case 'error':
        value = value.copyWith(errorDescription: event['errorDescription']);
        break;
      case 'cameraClosing':
        value = value.copyWith(isRecordingVideo: false);
        break;
    }
  }

  /// Releases the resources of this camera.
  @override
  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    super.dispose();
    if (_creatingCompleter != null) {
      await _creatingCompleter.future;
      await channel.invokeMethod<void>(
        'dispose',
        <String, dynamic>{'textureId': _textureId},
      );
      await _eventSubscription?.cancel();
    }
  }

  /// Creates an instance of [BarcodeDetector].
  Future<Stream<List<Barcode>>> addBarcodeDetector([BarcodeDetectorOptions options]) async {
    barcodeDetector = BarcodeDetector._(options ?? const BarcodeDetectorOptions(),
    nextHandle++,
    );
    await barcodeDetector.startDetection();
    return EventChannel('plugins.flutter.io/firebase_mlvision$_textureId').receiveBroadcastStream().map((convert) {
      dynamic data = convert['data'];
      final List<Barcode> barcodes = <Barcode>[];
      data.forEach((dynamic barcode) {
        barcodes.add(new Barcode._(barcode));
      });
      return barcodes;
    });
  }

  Future<void> removeBarcodeDetector() async {
    await barcodeDetector.close();
  }

  /// Creates an instance of [VisionEdgeImageLabeler].
  Future<Stream<List<VisionEdgeImageLabel>>> addVisionEdgeImageLabeler(
      String dataset, String modelLocation,
      [VisionEdgeImageLabelerOptions options]) async {
    visionEdgeImageLabeler = VisionEdgeImageLabeler._(
        options: options ?? const VisionEdgeImageLabelerOptions(),
        dataset: dataset,
        handle: nextHandle++,
        modelLocation: modelLocation);
    await visionEdgeImageLabeler.startDetection();
    return EventChannel('plugins.flutter.io/firebase_mlvision$_textureId').receiveBroadcastStream().map((convert) {
      dynamic data = convert['data'];
      final List<VisionEdgeImageLabel> labels = <VisionEdgeImageLabel>[];
      data.forEach((dynamic label) {
        labels.add(new VisionEdgeImageLabel._(label));
      });
      return labels;
    });
  }

  Future<void> removeVisionEdgeImageLabeler() async {
    await visionEdgeImageLabeler.close();
  }

  /// Creates an instance of [FaceDetector].
  Future<Stream<List<Face>>> addFaceDetector([FaceDetectorOptions options]) async {
    faceDetector = FaceDetector._(options ?? const FaceDetectorOptions(),
    nextHandle++,
    );
        await faceDetector.startDetection();
    return EventChannel('plugins.flutter.io/firebase_mlvision$_textureId').receiveBroadcastStream().map((convert) {
      dynamic data = convert['data'];
      final List<Face> faces = <Face>[];
      data.forEach((dynamic face) {
        faces.add(new Face._(face));
      });
      return faces;
    });
  }

  Future<void> removeFaceDetector() async {
    await faceDetector.close();
  }

  /// Creates an instance of [ModelManager].
  ModelManager modelManager() {
    return ModelManager._();
  }

  /// Creates an on device instance of [ImageLabeler].
  Future<Stream<List<ImageLabel>>> addImageLabeler([ImageLabelerOptions options]) async {
    localImageLabeler = ImageLabeler._(
      options: options ?? const ImageLabelerOptions(),
      modelType: ModelType.onDevice,
      handle: nextHandle++,
    );
      await localImageLabeler.startDetection();
    return EventChannel('plugins.flutter.io/firebase_mlvision$_textureId').receiveBroadcastStream().map((convert) {
      dynamic data = convert['data'];
      final List<ImageLabel> labels = <ImageLabel>[];
      data.forEach((dynamic label) {
        labels.add(new ImageLabel._(label));
      });  
      return labels;
    });
  }

  Future<void> removeImageLabeler() async {
    await localImageLabeler.close();
  }

  /// Creates an instance of [TextRecognizer].
  Future<Stream<List<VisionText>>> addTextRecognizer([TextRecognizer options]) async {
    textRecognizer = TextRecognizer._(
      modelType: ModelType.onDevice,
      handle: nextHandle++,
  );
  await textRecognizer.startDetection();
  return EventChannel('plugins.flutter.io/firebase_mlvision$_textureId').receiveBroadcastStream().map((convert) {
      dynamic data = convert['data'];
      final List<VisionText> texts = <VisionText>[];
      data.forEach((dynamic text) {
        texts.add(new VisionText._(text));
      });  
      return texts;
    });
  }

  Future<void> removeTextRecognizer() async {
    await textRecognizer.close();
  }

  /// Creates a cloud instance of [ImageLabeler].
  Future<Stream<List<ImageLabel>>> addCloudImageLabeler([CloudImageLabelerOptions options]) async {
    cloudImageLabeler = ImageLabeler._(
      options: options ?? const CloudImageLabelerOptions(),
      modelType: ModelType.cloud,
      handle: nextHandle++,
    );
    await cloudImageLabeler.startDetection();
    return EventChannel('plugins.flutter.io/firebase_mlvision$_textureId').receiveBroadcastStream().map((convert) {
      dynamic data = convert['data'];
      final List<ImageLabel> labels = <ImageLabel>[];
      data.forEach((dynamic label) {
        labels.add(new ImageLabel._(label));
      });  
      return labels;
    });
  }

  Future<void> removeCloudImageLabeler() async {
    await cloudImageLabeler.close();
  }

}

String _enumToString(dynamic enumValue) {
  final String enumString = enumValue.toString();
  return enumString.substring(enumString.indexOf('.') + 1);
}
