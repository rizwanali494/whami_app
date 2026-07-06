// Flutter web plugin registrant file.
//
// Generated file. Do not edit.
//

// @dart = 2.13
// ignore_for_file: type=lint

import 'package:camera_web/camera_web.dart';
import 'package:connectivity_plus/src/connectivity_plus_web.dart';
import 'package:geolocator_web/geolocator_web.dart';
import 'package:maplibre_gl_web/maplibre_gl_web.dart';
import 'package:package_info_plus/src/package_info_plus_web.dart';
import 'package:sensors_plus/src/sensors_plus_web.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

void registerPlugins([final Registrar? pluginRegistrar]) {
  final Registrar registrar = pluginRegistrar ?? webPluginRegistrar;
  CameraPlugin.registerWith(registrar);
  ConnectivityPlusWebPlugin.registerWith(registrar);
  GeolocatorPlugin.registerWith(registrar);
  MapLibreMapPlugin.registerWith(registrar);
  PackageInfoPlusWebPlugin.registerWith(registrar);
  WebSensorsPlugin.registerWith(registrar);
  registrar.registerMessageHandler();
}
