import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_ml_kit/google_ml_kit.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  runApp(GymTrainerApp(cameras: cameras));
}

class GymTrainerApp extends StatelessWidget {
  final List<CameraDescription> cameras;
  const GymTrainerApp({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: PoseScreen(cameras: cameras),
    );
  }
}

class PoseScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const PoseScreen({super.key, required this.cameras});

  @override
  State<PoseScreen> createState() => _PoseScreenState();
}

class _PoseScreenState extends State<PoseScreen> {
  late CameraController _cameraController;
  final PoseDetector _poseDetector =
      GoogleMlKit.vision.poseDetector(PoseDetectorOptions(mode: PoseDetectionMode.stream));
  bool _isDetecting = false;
  String _feedback = "Stand in front of camera";

  @override
  void initState() {
    super.initState();
    _cameraController = CameraController(widget.cameras[0], ResolutionPreset.medium);
    _cameraController.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
      _cameraController.startImageStream((CameraImage image) async {
        if (_isDetecting) return;
        _isDetecting = true;

        try {
          final WriteBuffer allBytes = WriteBuffer();
          for (Plane plane in image.planes) {
            allBytes.putUint8List(plane.bytes);
          }
          final bytes = allBytes.done().buffer.asUint8List();

          final Size imageSize = Size(image.width.toDouble(), image.height.toDouble());

          final InputImageRotation imageRotation =
              InputImageRotation.rotation0deg;

          final inputImageFormat =
              InputImageFormatValue.fromRawValue(image.format.raw) ??
                  InputImageFormat.nv21;

          final planeData = image.planes.map(
            (Plane plane) {
              return InputImagePlaneMetadata(
                bytesPerRow: plane.bytesPerRow,
                height: plane.height,
                width: plane.width,
              );
            },
          ).toList();

          final inputImageData = InputImageData(
            size: imageSize,
            imageRotation: imageRotation,
            inputImageFormat: inputImageFormat,
            planeData: planeData,
          );

          final inputImage =
              InputImage.fromBytes(bytes: bytes, inputImageData: inputImageData);

          final poses = await _poseDetector.processImage(inputImage);

          if (poses.isNotEmpty) {
            final pose = poses.first;
            final leftHip = pose.landmarks[PoseLandmarkType.leftHip];
            final leftKnee = pose.landmarks[PoseLandmarkType.leftKnee];
            final leftAnkle = pose.landmarks[PoseLandmarkType.leftAnkle];

            if (leftHip != null && leftKnee != null && leftAnkle != null) {
              double angle = _calculateAngle(
                Offset(leftHip.x, leftHip.y),
                Offset(leftKnee.x, leftKnee.y),
                Offset(leftAnkle.x, leftAnkle.y),
              );

              if (angle > 160) {
                _feedback = "Standing";
              } else if (90 < angle && angle <= 160) {
                _feedback = "Good Squat ✅";
              } else {
                _feedback = "Too Low ⚠️";
              }
            }
          }
        } catch (e) {
          debugPrint("Error: $e");
        }

        setState(() {});
        _isDetecting = false;
      });
    });
  }

  double _calculateAngle(Offset a, Offset b, Offset c) {
    final radians = (c - b).direction - (a - b).direction;
    var angle = radians * 180.0 / 3.141592653589793;
    if (angle < 0) angle += 360.0;
    return angle;
  }

  @override
  void dispose() {
    _cameraController.dispose();
    _poseDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_cameraController.value.isInitialized) {
      return const SizedBox.shrink();
    }
    return Scaffold(
      appBar: AppBar(title: const Text("Gym Trainer PoC")),
      body: Stack(
        children: [
          CameraPreview(_cameraController),
          Positioned(
            bottom: 50,
            left: 20,
            child: Container(
              padding: const EdgeInsets.all(10),
              color: Colors.black54,
              child: Text(
                _feedback,
                style: const TextStyle(color: Colors.white, fontSize: 20),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
