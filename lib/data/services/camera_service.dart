import 'dart:async';
import 'package:camera/camera.dart';

/// Service that interacts with device camera hardware
class CameraService {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isAvailable = false;
  String _statusMessage = 'Initializing...';
  bool _isInitialized = false;

  CameraController? get controller => _controller;
  List<CameraDescription> get cameras => _cameras;
  bool get isAvailable => _isAvailable;
  String get statusMessage => _statusMessage;
  bool get isInitialized => _isInitialized;

  /// Check permissions and get available cameras
  Future<bool> initialize() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        _statusMessage = 'No cameras found';
        _isAvailable = false;
        return false;
      }

      _isAvailable = true;
      _statusMessage = 'Camera available';
      return true;
    } catch (e) {
      _statusMessage = 'Camera initialization failed: $e';
      _isAvailable = false;
      return false;
    }
  }

  /// Initialize the specific camera controller (usually back camera)
  Future<CameraController?> initController({
    CameraLensDirection direction = CameraLensDirection.back,
    ResolutionPreset preset = ResolutionPreset.medium,
  }) async {
    if (!_isAvailable || _cameras.isEmpty) return null;

    // Dispose old controller if exists
    if (_controller != null) {
      await _controller!.dispose();
      _controller = null;
      _isInitialized = false;
    }

    try {
      final camera = _cameras.firstWhere(
        (cam) => cam.lensDirection == direction,
        orElse: () => _cameras.first,
      );

      _controller = CameraController(
        camera,
        preset,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _controller!.initialize();
      _isInitialized = true;
      _statusMessage = 'Camera active';
      return _controller;
    } catch (e) {
      _statusMessage = 'Camera controller init failed: $e';
      _isInitialized = false;
      return null;
    }
  }

  /// Dispose current camera controller
  Future<void> disposeController() async {
    if (_controller != null) {
      await _controller!.dispose();
      _controller = null;
      _isInitialized = false;
      _statusMessage = 'Camera disposed';
    }
  }

  void dispose() {
    disposeController();
  }
}
