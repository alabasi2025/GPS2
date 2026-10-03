package com.pointgps.point_gps

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var gnss: GnssStreamPlugin? = null
    private var updater: UpdateInstallerPlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        gnss = GnssStreamPlugin(applicationContext, flutterEngine.dartExecutor.binaryMessenger).also {
            it.activity = this
        }
        updater = UpdateInstallerPlugin(applicationContext, flutterEngine.dartExecutor.binaryMessenger).also {
            it.activity = this
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (gnss?.onPermissionResult(requestCode, grantResults) == true) return
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    override fun onDestroy() {
        gnss?.dispose()
        gnss = null
        updater?.activity = null
        updater = null
        super.onDestroy()
    }
}
