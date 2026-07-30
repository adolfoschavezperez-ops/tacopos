package com.renova.tacopos

import android.content.Intent
import android.media.MediaPlayer
import android.net.Uri
import android.os.Build
import com.google.android.play.core.appupdate.AppUpdateManager
import com.google.android.play.core.appupdate.AppUpdateManagerFactory
import com.google.android.play.core.appupdate.AppUpdateOptions
import com.google.android.play.core.install.InstallStateUpdatedListener
import com.google.android.play.core.install.model.AppUpdateType
import com.google.android.play.core.install.model.InstallStatus
import com.google.android.play.core.install.model.UpdateAvailability
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val kitchenSoundChannel = "tacopos/kitchen_sound"
    private val appUpdateChannel = "tacopos/app_update"
    private val flexibleUpdateRequestCode = 4201
    private val immediateUpdateRequestCode = 4202
    private var kitchenBeepPlayer: MediaPlayer? = null
    private var appUpdateManager: AppUpdateManager? = null
    private var appUpdateMethodChannel: MethodChannel? = null
    private var installStateListener: InstallStateUpdatedListener? = null

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

        appUpdateManager = AppUpdateManagerFactory.create(this)
        val updateChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            appUpdateChannel,
        )
        appUpdateMethodChannel = updateChannel
        updateChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "versionCode" -> result.success(currentVersionCode())
                "versionName" -> result.success(currentVersionName())
                "installerPackageName" -> result.success(installerPackageName())
                "checkUpdate" -> {
                    checkUpdate(result)
                }
                "startFlexibleUpdate" -> startUpdate(AppUpdateType.FLEXIBLE, result)
                "startImmediateUpdate" -> startUpdate(AppUpdateType.IMMEDIATE, result)
                "completeFlexibleUpdate" -> completeFlexibleUpdate(result)
                "openGooglePlay" -> {
                    openGooglePlay()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onResume() {
        super.onResume()
        appUpdateManager?.appUpdateInfo?.addOnSuccessListener { appUpdateInfo ->
            if (appUpdateInfo.updateAvailability() ==
                UpdateAvailability.DEVELOPER_TRIGGERED_UPDATE_IN_PROGRESS
            ) {
                appUpdateMethodChannel?.invokeMethod("immediateUpdateInProgress", null)
                startUpdate(AppUpdateType.IMMEDIATE, null)
            }
            if (appUpdateInfo.installStatus() == InstallStatus.DOWNLOADED) {
                notifyFlexibleUpdateDownloaded()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == flexibleUpdateRequestCode || requestCode == immediateUpdateRequestCode) {
            appUpdateMethodChannel?.invokeMethod(
                "updateFlowFinished",
                mapOf("requestCode" to requestCode, "resultCode" to resultCode),
            )
        }
    }

    override fun onDestroy() {
        installStateListener?.let { appUpdateManager?.unregisterListener(it) }
        installStateListener = null
        appUpdateManager = null
        appUpdateMethodChannel = null
        super.onDestroy()
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

    private fun checkUpdate(result: MethodChannel.Result) {
        val manager = appUpdateManager
        if (manager == null) {
            result.error("APP_UPDATE_MANAGER_UNAVAILABLE", "Google Play update manager is unavailable.", null)
            return
        }
        manager.appUpdateInfo
            .addOnSuccessListener { appUpdateInfo ->
                val updateCanRun =
                    appUpdateInfo.updateAvailability() == UpdateAvailability.UPDATE_AVAILABLE ||
                        appUpdateInfo.updateAvailability() ==
                        UpdateAvailability.DEVELOPER_TRIGGERED_UPDATE_IN_PROGRESS
                result.success(
                    mapOf(
                        "updateAvailability" to appUpdateInfo.updateAvailability(),
                        "updateAvailable" to updateCanRun,
                        "flexibleAllowed" to appUpdateInfo.isUpdateTypeAllowed(AppUpdateType.FLEXIBLE),
                        "immediateAllowed" to appUpdateInfo.isUpdateTypeAllowed(AppUpdateType.IMMEDIATE),
                        "installStatus" to appUpdateInfo.installStatus(),
                        "availableVersionCode" to appUpdateInfo.availableVersionCode(),
                        "installedFromPlay" to installedFromPlay(),
                        "installerPackageName" to installerPackageName(),
                    ),
                )
            }
            .addOnFailureListener { error ->
                result.error("APP_UPDATE_CHECK_FAILED", error.message, error.javaClass.simpleName)
            }
    }

    private fun startUpdate(updateType: Int, result: MethodChannel.Result?) {
        val manager = appUpdateManager
        if (manager == null) {
            result?.error("APP_UPDATE_MANAGER_UNAVAILABLE", "Google Play update manager is unavailable.", null)
            return
        }
        manager.appUpdateInfo
            .addOnSuccessListener { appUpdateInfo ->
                if (updateType == AppUpdateType.FLEXIBLE &&
                    appUpdateInfo.installStatus() == InstallStatus.DOWNLOADED
                ) {
                    notifyFlexibleUpdateDownloaded()
                    result?.success(mapOf("started" to false, "downloaded" to true))
                    return@addOnSuccessListener
                }
                if (appUpdateInfo.updateAvailability() != UpdateAvailability.UPDATE_AVAILABLE &&
                    appUpdateInfo.updateAvailability() !=
                    UpdateAvailability.DEVELOPER_TRIGGERED_UPDATE_IN_PROGRESS
                ) {
                    result?.error("APP_UPDATE_NOT_AVAILABLE", "No Google Play update is available.", null)
                    return@addOnSuccessListener
                }
                if (!appUpdateInfo.isUpdateTypeAllowed(updateType)) {
                    result?.error("APP_UPDATE_TYPE_NOT_ALLOWED", "This update type is not allowed by Google Play.", null)
                    return@addOnSuccessListener
                }
                if (updateType == AppUpdateType.FLEXIBLE) {
                    registerInstallStateListener()
                }
                val requestCode = if (updateType == AppUpdateType.FLEXIBLE) {
                    flexibleUpdateRequestCode
                } else {
                    immediateUpdateRequestCode
                }
                val started = manager.startUpdateFlowForResult(
                    appUpdateInfo,
                    this,
                    AppUpdateOptions.newBuilder(updateType).build(),
                    requestCode,
                )
                result?.success(mapOf("started" to started, "downloaded" to false))
            }
            .addOnFailureListener { error ->
                result?.error("APP_UPDATE_START_FAILED", error.message, error.javaClass.simpleName)
            }
    }

    private fun completeFlexibleUpdate(result: MethodChannel.Result) {
        val manager = appUpdateManager
        if (manager == null) {
            result.error("APP_UPDATE_MANAGER_UNAVAILABLE", "Google Play update manager is unavailable.", null)
            return
        }
        manager.completeUpdate()
            .addOnSuccessListener { result.success(null) }
            .addOnFailureListener { error ->
                result.error("APP_UPDATE_COMPLETE_FAILED", error.message, error.javaClass.simpleName)
            }
    }

    private fun registerInstallStateListener() {
        if (installStateListener != null) return
        installStateListener = InstallStateUpdatedListener { state ->
            appUpdateMethodChannel?.invokeMethod(
                "flexibleUpdateStatus",
                mapOf(
                    "installStatus" to state.installStatus(),
                    "bytesDownloaded" to state.bytesDownloaded(),
                    "totalBytesToDownload" to state.totalBytesToDownload(),
                ),
            )
            if (state.installStatus() == InstallStatus.DOWNLOADED) {
                notifyFlexibleUpdateDownloaded()
            }
        }
        appUpdateManager?.registerListener(installStateListener!!)
    }

    private fun notifyFlexibleUpdateDownloaded() {
        appUpdateMethodChannel?.invokeMethod("flexibleUpdateDownloaded", null)
    }

    private fun openGooglePlay() {
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

    private fun currentVersionName(): String {
        val packageInfo = packageManager.getPackageInfo(packageName, 0)
        return packageInfo.versionName ?: ""
    }

    private fun installerPackageName(): String {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            packageManager.getInstallSourceInfo(packageName).installingPackageName ?: ""
        } else {
            @Suppress("DEPRECATION")
            packageManager.getInstallerPackageName(packageName) ?: ""
        }
    }

    private fun installedFromPlay(): Boolean {
        return installerPackageName() == "com.android.vending"
    }
}
