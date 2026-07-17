import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class KitchenSoundService {
  KitchenSoundService._();

  static final KitchenSoundService instance = KitchenSoundService._();

  static const MethodChannel _channel = MethodChannel('tacopos/kitchen_sound');

  Future<void> playNewOrderBeep() async {
    try {
      debugPrint('Kitchen sound: nueva comanda normal');
      await _channel.invokeMethod<void>('playKitchenBeep');
    } catch (error, stackTrace) {
      debugPrint('Kitchen beep error: $error');
      debugPrint('$stackTrace');
    }
  }

  Future<void> playExpressOrderBeep() async {
    try {
      debugPrint('Kitchen sound: surtido express');
      await _channel.invokeMethod<void>('playKitchenExpressBeep');
    } catch (error, stackTrace) {
      debugPrint('Kitchen express beep error: $error');
      debugPrint('$stackTrace');
    }
  }
}
