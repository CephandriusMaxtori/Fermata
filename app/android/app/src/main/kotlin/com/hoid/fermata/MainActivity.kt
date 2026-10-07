package com.hoid.fermata

import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * The app's only platform channel.
 *
 * Deliberately two methods rather than a plugin dependency. Both needs are one
 * call each and neither is worth a package: handing a URI to whichever app owns
 * it, and reading our own installed version. `url_launcher` and
 * `package_info_plus` would each pull in an implementation, a Gradle module and
 * a version constraint to do what these twenty lines do, and the second one
 * exists in the SDK already ([PackageManager]).
 */
class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openUri" -> {
                        val uri = call.argument<String>("uri")
                        if (uri == null) {
                            result.error("bad_args", "openUri needs a 'uri' string", null)
                        } else {
                            result.success(openUri(uri))
                        }
                    }
                    "installedPackage" -> result.success(installedPackage())
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Offers [uri] to the device, reporting whether anything took it.
     *
     * Try-then-catch rather than `resolveActivity`: package visibility from
     * Android 11 hides apps we have not declared in `<queries>`, so
     * `resolveActivity` reports "nothing can handle this" for handlers that are
     * installed and would have opened the URI. A caught
     * [ActivityNotFoundException] is the truth, and it is also the only way to
     * learn that a browser-less device cannot reach `obtainium://`.
     */
    private fun openUri(uri: String): Boolean = try {
        startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(uri)))
        true
    } catch (_: ActivityNotFoundException) {
        false
    }

    /**
     * Our own `versionName` and `versionCode`.
     *
     * Read through [PackageManager] rather than the generated `BuildConfig`
     * because AGP 8 stopped emitting `BuildConfig` unless
     * `buildFeatures.buildConfig` is switched on, and this must not become a
     * second thing that can silently stop compiling.
     *
     * The version is load-bearing, not decoration: Obtainium decides whether an
     * update exists by comparing the source's version string against the
     * installed one, so the app has to be able to show the user which one it is.
     */
    private fun installedPackage(): Map<String, Any> {
        val info = packageManager.getPackageInfo(packageName, 0)
        val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            info.versionCode.toLong()
        }
        return mapOf(
            "versionName" to (info.versionName ?: ""),
            "versionCode" to versionCode,
        )
    }

    private companion object {
        /**
         * Must match the channel name in `platform_bridge.dart`.
         */
        const val CHANNEL = "fermata/platform"
    }
}