import 'dart:async';
import 'package:background_locator_2/location_dto.dart';
import 'package:flutter/foundation.dart';

@pragma('vm:entry-point')
class LocationCallbackHandler {
  @pragma('vm:entry-point')
  static Future<void> initCallback(Map<dynamic, dynamic> params) async {
    debugPrint('BG initCallback: $params');
  }

  @pragma('vm:entry-point')
  static Future<void> callback(LocationDto locationDto) async {
    debugPrint(
      'BG callback -> '
      'lat=${locationDto.latitude}, '
      'lon=${locationDto.longitude}, '
      'accuracy=${locationDto.accuracy}, '
      'time=${locationDto.time}',
    );
  }

  @pragma('vm:entry-point')
  static Future<void> disposeCallback() async {
    debugPrint('BG disposeCallback');
  }
}