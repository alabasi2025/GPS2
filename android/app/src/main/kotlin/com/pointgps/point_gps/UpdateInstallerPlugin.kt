package com.pointgps.point_gps

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * جسر تثبيت التحديث.
 *
 * Dart ينزّل الـAPK إلى cache/updates/ ويتحقق من SHA-256، ثم يستدعي install(path).
 * نحن نفتح مثبّت النظام عبر FileProvider — المستخدم يرى شاشة التثبيت القياسية ويوافق.
 * Android 8+: يلزم إذن "تثبيت تطبيقات غير معروفة" لهذا التطبيق تحديداً (مرة واحدة).
 */
class UpdateInstallerPlugin(private val context: Context, messenger: BinaryMessenger) {
    var activity: Activity? = null

    init {
        MethodChannel(messenger, "point_gps/update").setMethodCallHandler { call, result ->
            when (call.method) {
                "canInstall" -> result.success(canInstall())
                "openInstallPermission" -> { openInstallPermission(); result.success(null) }
                "install" -> {
                    val path = call.argument<String>("path")
                    if (path == null) { result.error("ARG", "path required", null); return@setMethodCallHandler }
                    result.success(install(File(path)))
                }
                "versionCode" -> result.success(currentVersionCode())
                "cacheDir" -> result.success(File(context.cacheDir, "updates").apply { mkdirs() }.absolutePath)
                else -> result.notImplemented()
            }
        }
    }

    private fun canInstall(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.O || context.packageManager.canRequestPackageInstalls()

    private fun openInstallPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val i = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${context.packageName}"))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        (activity ?: context).startActivity(i)
    }

    private fun install(file: File): Boolean {
        if (!file.exists() || file.length() < 1_000_000) return false
        val uri: Uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
        val i = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, "application/vnd.android.package-archive")
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        return runCatching { (activity ?: context).startActivity(i); true }.getOrDefault(false)
    }

    private fun currentVersionCode(): Long {
        val info = context.packageManager.getPackageInfo(context.packageName, 0)
        @Suppress("DEPRECATION")
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) info.longVersionCode else info.versionCode.toLong()
    }
}
