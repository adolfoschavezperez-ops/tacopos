package com.renova.tacopos

import android.content.Intent
import android.media.MediaPlayer
import android.net.Uri
import android.os.Build
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val kitchenSoundChannel = "tacopos/kitchen_sound"
    private val appUpdateChannel = "tacopos/app_update"
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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, appUpdateChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "versionCode" -> result.success(currentVersionCode())
                    "canOpenPlayStore" -> result.success(canOpenPlayStore())
                    "openPlayStore" -> {
                        openPlayStore()
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

    private fun canOpenPlayStore(): Boolean {
        val marketIntent = Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=$packageName"))
        val webIntent = Intent(
            Intent.ACTION_VIEW,
            Uri.parse("https://play.google.com/store/apps/details?id=$packageName"),
        )
        return marketIntent.resolveActivity(packageManager) != null ||
            webIntent.resolveActivity(packageManager) != null
    }

    private fun openPlayStore() {
        val marketIntent = Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=$packageName"))
        marketIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (marketIntent.resolveActivity(packageManager) != null) {
            startActivity(marketIntent)
            return
        }

        val webIntent = Intent(
            Intent.ACTION_VIEW,
            Uri.parse("https://play.google.com/store/apps/details?id=$packageName"),
        )
        webIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(webIntent)
    }

    private fun currentVersionCode(): Long {
        val packageInfo = packageManager.getPackageInfo(packageName, 0)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            packageInfo.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            packageInfo.versionCode.toLong()
        }
    }
}
