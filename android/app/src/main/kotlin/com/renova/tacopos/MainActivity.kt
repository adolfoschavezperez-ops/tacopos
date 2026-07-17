package com.renova.tacopos

import android.media.MediaPlayer
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val kitchenSoundChannel = "tacopos/kitchen_sound"
    private var kitchenBeepPlayer: MediaPlayer? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, kitchenSoundChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "playKitchenBeep" -> {
                        playKitchenSound("assets/sounds/kitchen_beep.wav")
                        result.success(null)
                    }
                    "playKitchenExpressBeep" -> {
                        playKitchenSound("assets/sounds/kitchen_express_beep.wav")
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun playKitchenSound(assetName: String) {
        val assetPath = FlutterInjector
            .instance()
            .flutterLoader()
            .getLookupKeyForAsset(assetName)

        try {
            kitchenBeepPlayer?.stop()
            kitchenBeepPlayer?.release()

            val assetFileDescriptor = assets.openFd(assetPath)
            kitchenBeepPlayer = MediaPlayer().apply {
                setDataSource(
                    assetFileDescriptor.fileDescriptor,
                    assetFileDescriptor.startOffset,
                    assetFileDescriptor.length,
                )
                setOnCompletionListener {
                    it.release()
                    if (kitchenBeepPlayer === it) {
                        kitchenBeepPlayer = null
                    }
                }
                prepare()
                start()
            }
            assetFileDescriptor.close()
        } catch (error: Exception) {
            kitchenBeepPlayer?.release()
            kitchenBeepPlayer = null
            throw error
        }
    }
}
