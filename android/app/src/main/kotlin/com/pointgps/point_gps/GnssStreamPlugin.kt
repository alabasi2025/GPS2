package com.pointgps.point_gps

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import android.content.pm.PackageManager
import android.location.GnssMeasurementsEvent
import android.location.GnssStatus
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * يبث قياسات GNSS الخام إلى Dart.
 *
 * لماذا LocationManager.GPS_PROVIDER وليس FusedLocationProvider؟
 * Fused يدمج Wi-Fi/الخلوي ويطبّق تنعيماً داخلياً غير شفاف؛ لأعلى دقة
 * نحتاج حل GNSS الصافي مع تقديره الأصلي لعدم اليقين، ثم نطبق فلترنا
 * الخاص الذي نعرف خصائصه ونختبره.
 *
 * ثلاث قنوات أحداث:
 *  - fix:     Location (lat, lon, alt, acc, speed, bearing, time, provider)
 *  - status:  GnssStatus لكل قمر (نظام، C/N0، مستخدم في الحل، التردد → L5)
 *  - raw:     GnssMeasurementsEvent (عدد القياسات، ADR متاح، AGC) — للتشخيص
 *
 * كل الاستماع على Looper الرئيسي؛ Flutter EventSink يتطلب الخيط الرئيسي.
 */
class GnssStreamPlugin(private val context: Context, messenger: BinaryMessenger) {

    companion object {
        const val PERMISSION_REQUEST_CODE = 7141
    }

    /** يُضبط من MainActivity لطلب الصلاحية وفتح الإعدادات. */
    var activity: Activity? = null
    private var pendingPermissionResult: MethodChannel.Result? = null

    private val locationManager =
        context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
    private val mainHandler = Handler(Looper.getMainLooper())

    private var fixSink: EventChannel.EventSink? = null
    private var statusSink: EventChannel.EventSink? = null
    private var rawSink: EventChannel.EventSink? = null

    private var listening = false
    private var assistProvider: String? = null
    private var fusedClient: FusedLocationProviderClient? = null

    init {
        EventChannel(messenger, "point_gps/fix").setStreamHandler(sinkHandler { fixSink = it })
        EventChannel(messenger, "point_gps/status").setStreamHandler(sinkHandler { statusSink = it })
        EventChannel(messenger, "point_gps/raw").setStreamHandler(sinkHandler { rawSink = it })
        MethodChannel(messenger, "point_gps/control").setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> result.success(start())
                "stop" -> { stop(); result.success(null) }
                "refresh" -> { refreshNow(); result.success(null) }
                "capabilities" -> result.success(capabilities())
                "requestPermission" -> requestPermission(result)
                "openLocationSettings" -> {
                    activity?.startActivity(Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS))
                    result.success(null)
                }
                "openAppSettings" -> {
                    activity?.startActivity(
                        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${context.packageName}")),
                    )
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun sinkHandler(assign: (EventChannel.EventSink?) -> Unit) =
        object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) = assign(events)
            override fun onCancel(arguments: Any?) = assign(null)
        }

    private fun hasFineLocation(): Boolean =
        ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED

    /** يطلب ACCESS_FINE_LOCATION؛ يعيد "granted" / "denied" / "deniedForever" / "noActivity". */
    private fun requestPermission(result: MethodChannel.Result) {
        if (hasFineLocation()) { result.success("granted"); return }
        val act = activity
        if (act == null) { result.success("noActivity"); return }
        if (pendingPermissionResult != null) { result.success("pending"); return }
        pendingPermissionResult = result
        ActivityCompat.requestPermissions(
            act,
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION),
            PERMISSION_REQUEST_CODE,
        )
    }

    /** تُستدعى من MainActivity.onRequestPermissionsResult. */
    fun onPermissionResult(requestCode: Int, grantResults: IntArray): Boolean {
        if (requestCode != PERMISSION_REQUEST_CODE) return false
        val res = pendingPermissionResult ?: return true
        pendingPermissionResult = null
        val granted = hasFineLocation()
        val act = activity
        val status = when {
            granted -> "granted"
            act != null && !ActivityCompat.shouldShowRequestPermissionRationale(
                act, Manifest.permission.ACCESS_FINE_LOCATION,
            ) -> "deniedForever"
            else -> "denied"
        }
        res.success(status)
        return true
    }

    fun dispose() {
        stop()
        activity = null
    }

    /** يبدأ الاستماع؛ يعيد true إن بدأ، false إن غابت الصلاحية أو GPS معطل. */
    @SuppressLint("MissingPermission")
    private fun start(): Boolean {
        if (listening) return true
        if (!hasFineLocation()) return false
        val gpsOn = locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)
        val anyOn = gpsOn || locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER) ||
            (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && locationManager.isLocationEnabled)
        if (!anyOn) return false

        // أعلى معدل يسمح به النظام (عادة 1 Hz للحل، أسرع للقياسات الخام).
        if (gpsOn) {
            locationManager.requestLocationUpdates(
                LocationManager.GPS_PROVIDER, 0L, 0f, locationListener, Looper.getMainLooper(),
            )
        }
        // آخر حل معروف فوراً (حتى لا تبقى الشاشة فارغة حتى أول حل جديد).
        locationManager.getLastKnownLocation(LocationManager.GPS_PROVIDER)?.let { last ->
            if (System.currentTimeMillis() - last.time < 120_000L) {
                mainHandler.post { fixSink?.success(last.toMap().plus("source" to "gnss")) }
            }
        }
        // مصدر ثانٍ (الأساس): Fused Location Provider من Google Play Services —
        // GPS + Wi-Fi + خلوي + حساسات. هو ما يستخدمه WhatsApp وFind My Device،
        // وهو شبكة الأمان داخل المباني. إن غابت Play Services → NETWORK_PROVIDER.
        startAssist()
        locationManager.registerGnssStatusCallback(statusCallback, mainHandler)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            locationManager.registerGnssMeasurementsCallback(measurementsCallback, mainHandler)
        }
        listening = true
        return true
    }

    private fun stop() {
        if (!listening) return
        locationManager.removeUpdates(locationListener)
        runCatching { locationManager.removeUpdates(assistListener) }
        runCatching { fusedClient?.removeLocationUpdates(fusedCallback) }
        fusedClient = null
        locationManager.unregisterGnssStatusCallback(statusCallback)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            locationManager.unregisterGnssMeasurementsCallback(measurementsCallback)
        }
        listening = false
    }

    private fun capabilities(): Map<String, Any?> {
        val caps = HashMap<String, Any?>()
        caps["sdk"] = Build.VERSION.SDK_INT
        caps["model"] = "${Build.MANUFACTURER} ${Build.MODEL}"
        caps["gpsEnabled"] = locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)
        caps["assistProvider"] = assistProvider
        caps["hasFinePermission"] = hasFineLocation()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            caps["hardwareModelName"] = locationManager.gnssHardwareModelName
            caps["yearOfHardware"] = locationManager.gnssYearOfHardware
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val c = locationManager.gnssCapabilities
            caps["hasMeasurements"] = c.hasMeasurements()
            caps["hasAntennaInfo"] = c.hasAntennaInfo()
        }
        return caps
    }

    private val locationListener = object : LocationListener {
        override fun onLocationChanged(location: Location) {
            fixSink?.success(location.toMap().plus("source" to "gnss"))
        }
        @Deprecated("Deprecated in Java")
        override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) = Unit
        override fun onProviderEnabled(provider: String) = Unit
        override fun onProviderDisabled(provider: String) {
            fixSink?.success(mapOf("event" to "providerDisabled"))
        }
    }

    /** حل واحد طازج عالي الدقة الآن (لزر «حدّث» ولحظة الالتقاط). */
    @SuppressLint("MissingPermission")
    private fun refreshNow() {
        if (!hasFineLocation()) return
        val client = fusedClient ?: run {
            if (GoogleApiAvailability.getInstance().isGooglePlayServicesAvailable(context) != ConnectionResult.SUCCESS) return
            LocationServices.getFusedLocationProviderClient(context)
        }
        client.getCurrentLocation(Priority.PRIORITY_HIGH_ACCURACY, null).addOnSuccessListener { loc ->
            if (loc != null) fixSink?.success(loc.toMap().plus("source" to "assist"))
        }
    }

    @SuppressLint("MissingPermission")
    private fun startAssist() {
        val gms = GoogleApiAvailability.getInstance().isGooglePlayServicesAvailable(context)
        if (gms == ConnectionResult.SUCCESS) {
            assistProvider = "fused(gms)"
            val client = LocationServices.getFusedLocationProviderClient(context)
            fusedClient = client
            val req = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 1000L)
                .setMinUpdateIntervalMillis(500L)
                .setWaitForAccurateLocation(false)
                .build()
            client.requestLocationUpdates(req, fusedCallback, Looper.getMainLooper())
            // آخر موقع معروف فوراً (نفس ما يفعله WhatsApp قبل أول حل جديد).
            client.lastLocation.addOnSuccessListener { last ->
                if (last != null && System.currentTimeMillis() - last.time < 300_000L) {
                    fixSink?.success(last.toMap().plus("source" to "assist"))
                }
            }
            // حل طازج عالي الدقة مرة واحدة لتسريع أول عرض.
            client.getCurrentLocation(Priority.PRIORITY_HIGH_ACCURACY, null).addOnSuccessListener { loc ->
                if (loc != null) fixSink?.success(loc.toMap().plus("source" to "assist"))
            }
            return
        }
        // بديل بلا Google: مزوّد الشبكة (Wi-Fi/خلوي) من النظام.
        if (locationManager.allProviders.contains(LocationManager.NETWORK_PROVIDER)) {
            assistProvider = "network"
            runCatching {
                locationManager.requestLocationUpdates(
                    LocationManager.NETWORK_PROVIDER, 1000L, 0f, assistListener, Looper.getMainLooper(),
                )
                locationManager.getLastKnownLocation(LocationManager.NETWORK_PROVIDER)?.let { last ->
                    if (System.currentTimeMillis() - last.time < 300_000L) {
                        mainHandler.post { fixSink?.success(last.toMap().plus("source" to "assist")) }
                    }
                }
            }
        }
    }

    private val fusedCallback = object : LocationCallback() {
        override fun onLocationResult(result: LocationResult) {
            val loc = result.lastLocation ?: return
            fixSink?.success(loc.toMap().plus("source" to "assist"))
        }
    }

    private val assistListener = object : LocationListener {
        override fun onLocationChanged(location: Location) {
            fixSink?.success(location.toMap().plus("source" to "assist"))
        }
        @Deprecated("Deprecated in Java")
        override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) = Unit
        override fun onProviderEnabled(provider: String) = Unit
        override fun onProviderDisabled(provider: String) = Unit
    }

    private val statusCallback = object : GnssStatus.Callback() {
        override fun onSatelliteStatusChanged(status: GnssStatus) {
            val sats = ArrayList<Map<String, Any?>>(status.satelliteCount)
            var usedInFix = 0
            var l5Used = 0
            for (i in 0 until status.satelliteCount) {
                val used = status.usedInFix(i)
                val freqHz = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && status.hasCarrierFrequencyHz(i))
                    status.getCarrierFrequencyHz(i).toDouble() else null
                val band = bandOf(freqHz)
                if (used) { usedInFix++; if (band == "L5") l5Used++ }
                sats.add(
                    mapOf(
                        "svid" to status.getSvid(i),
                        "constellation" to constellationName(status.getConstellationType(i)),
                        "cn0" to status.getCn0DbHz(i).toDouble(),
                        "elevation" to status.getElevationDegrees(i).toDouble(),
                        "azimuth" to status.getAzimuthDegrees(i).toDouble(),
                        "usedInFix" to used,
                        "band" to band,
                        "hasEphemeris" to status.hasEphemerisData(i),
                    ),
                )
            }
            statusSink?.success(
                mapOf(
                    "count" to status.satelliteCount,
                    "usedInFix" to usedInFix,
                    "l5Used" to l5Used,
                    "satellites" to sats,
                ),
            )
        }
        override fun onFirstFix(ttffMillis: Int) {
            statusSink?.success(mapOf("event" to "firstFix", "ttffMillis" to ttffMillis))
        }
    }

    private val measurementsCallback = object : GnssMeasurementsEvent.Callback() {
        override fun onGnssMeasurementsReceived(event: GnssMeasurementsEvent) {
            var adr = 0
            var agcSum = 0.0
            var agcN = 0
            for (m in event.measurements) {
                if (m.accumulatedDeltaRangeState and android.location.GnssMeasurement.ADR_STATE_VALID != 0) adr++
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && m.hasAutomaticGainControlLevelDb()) {
                    @Suppress("DEPRECATION")
                    agcSum += m.automaticGainControlLevelDb; agcN++
                }
            }
            rawSink?.success(
                mapOf(
                    "measurements" to event.measurements.size,
                    "adrValid" to adr,
                    "agcMeanDb" to if (agcN > 0) agcSum / agcN else null,
                    "clockBiasNs" to if (event.clock.hasBiasNanos()) event.clock.biasNanos else null,
                ),
            )
        }
    }

    private fun Location.toMap(): Map<String, Any?> = mapOf(
        "lat" to latitude,
        "lon" to longitude,
        "alt" to if (hasAltitude()) altitude else null,
        "acc" to if (hasAccuracy()) accuracy.toDouble() else null,
        "vacc" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && hasVerticalAccuracy())
            verticalAccuracyMeters.toDouble() else null,
        "speed" to if (hasSpeed()) speed.toDouble() else null,
        "speedAcc" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && hasSpeedAccuracy())
            speedAccuracyMetersPerSecond.toDouble() else null,
        "bearing" to if (hasBearing()) bearing.toDouble() else null,
        "timeMs" to time,
        "elapsedNs" to elapsedRealtimeNanos,
        "provider" to provider,
        "mock" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) isMock else @Suppress("DEPRECATION") isFromMockProvider,
    )

    private fun bandOf(hz: Double?): String? {
        if (hz == null) return null
        val mhz = hz / 1e6
        return when {
            mhz in 1559.0..1610.0 -> "L1"   // GPS L1 / GAL E1 / GLO G1 / BDS B1
            mhz in 1164.0..1189.0 -> "L5"   // GPS L5 / GAL E5a / BDS B2a / QZSS L5
            mhz in 1189.0..1254.0 -> "L2"   // GPS L2 / GLO G2 / BDS B3
            else -> "other"
        }
    }

    private fun constellationName(type: Int): String = when (type) {
        GnssStatus.CONSTELLATION_GPS -> "GPS"
        GnssStatus.CONSTELLATION_GLONASS -> "GLONASS"
        GnssStatus.CONSTELLATION_GALILEO -> "Galileo"
        GnssStatus.CONSTELLATION_BEIDOU -> "BeiDou"
        GnssStatus.CONSTELLATION_QZSS -> "QZSS"
        GnssStatus.CONSTELLATION_IRNSS -> "NavIC"
        GnssStatus.CONSTELLATION_SBAS -> "SBAS"
        else -> "?"
    }
}
