package ch.tellbow.alvyo

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContract
import androidx.fragment.app.FragmentActivity
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.PermissionController
import androidx.health.connect.client.contracts.ExerciseRouteRequestContract
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.ExerciseRoute
import androidx.health.connect.client.records.ExerciseRouteResult
import androidx.health.connect.client.records.ExerciseSessionRecord
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import androidx.lifecycle.lifecycleScope
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import java.time.Instant
import java.time.temporal.ChronoUnit

// Hikes from watches on Android (lib/watch/workouts.dart), like Apple Health
// on iOS: Health Connect's exercise sessions and their routes. Not through the
// health plugin, which also needs distance and calories to list workouts.
class HealthConnect(private val activity: FragmentActivity) : MethodChannel.MethodCallHandler {
    private val sessions = HealthPermission.getReadPermission(ExerciseSessionRecord::class)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (HealthConnectClient.getSdkStatus(activity) != HealthConnectClient.SDK_AVAILABLE) {
            return if (call.method == "authorize") result.success(false) else result.error("unavailable", null, null)
        }
        val client = HealthConnectClient.getOrCreate(activity)
        activity.lifecycleScope.launch {
            try {
                when (call.method) {
                    "authorize" -> result.success(authorize(client))
                    "recent" -> result.success(recent(client, call.argument<Int>("days")!!))
                    "route" -> result.success(route(client, call.argument<String>("id")!!, call.argument<Boolean>("ask")!!))
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("health", e.message, null)
            }
        }
    }

    /**
     * True when sessions may be read; asks the first time, with «always
     * allow» for routes (without it, each route is asked for).
     */
    private suspend fun authorize(client: HealthConnectClient): Boolean {
        if (client.permissionController.getGrantedPermissions().contains(sessions)) return true
        val wanted = setOf(sessions, HealthPermission.PERMISSION_READ_EXERCISE_ROUTES)
        return ask(PermissionController.createRequestPermissionResultContract(), wanted).contains(sessions)
    }

    /** Hikes and walks of the last [days]. */
    private suspend fun recent(client: HealthConnectClient, days: Int): List<Map<String, Any?>> {
        val now = Instant.now()
        val sessions = mutableListOf<ExerciseSessionRecord>()
        var token: String? = null
        do {
            val response = client.readRecords(
                ReadRecordsRequest(
                    ExerciseSessionRecord::class,
                    TimeRangeFilter.between(now.minus(days.toLong(), ChronoUnit.DAYS), now),
                    pageToken = token,
                ),
            )
            sessions += response.records
            token = response.pageToken
        } while (token != null)
        return sessions
            .filter { it.exerciseType == ExerciseSessionRecord.EXERCISE_TYPE_HIKING || it.exerciseType == ExerciseSessionRecord.EXERCISE_TYPE_WALKING }
            .map {
                val device = it.metadata.device
                mapOf(
                    "id" to it.metadata.id,
                    "start" to it.startTime.toEpochMilli(),
                    "end" to it.endTime.toEpochMilli(),
                    "hiking" to (it.exerciseType == ExerciseSessionRecord.EXERCISE_TYPE_HIKING),
                    // «Galaxy Watch7»; the writing app's package name means little to people.
                    "source" to listOfNotNull(device?.manufacturer, device?.model).joinToString(" "),
                )
            }
    }

    /**
     * The route of session [id] as [lat, lon, ele, accuracy, time] lists;
     * empty without one. Another app's route needs the user's consent each
     * time unless always allowed: asked for when [ask].
     */
    private suspend fun route(client: HealthConnectClient, id: String, ask: Boolean): List<List<Any?>> {
        val route = when (val r = client.readRecord(ExerciseSessionRecord::class, id).record.exerciseRouteResult) {
            is ExerciseRouteResult.Data -> r.exerciseRoute
            is ExerciseRouteResult.ConsentRequired -> if (ask) ask(ExerciseRouteRequestContract(), id) else null
            else -> null
        }
        return route?.route.orEmpty().map { l: ExerciseRoute.Location ->
            listOf(l.latitude, l.longitude, l.altitude?.inMeters, l.horizontalAccuracy?.inMeters, l.time.toEpochMilli())
        }
    }

    /** Starts [contract] and waits for its answer (a launcher registered for this call only). */
    private suspend fun <I, O> ask(contract: ActivityResultContract<I, O>, input: I): O =
        suspendCancellableCoroutine { done ->
            var launcher: ActivityResultLauncher<I>? = null
            launcher = activity.activityResultRegistry.register("health-${System.nanoTime()}", contract) {
                launcher?.unregister()
                done.resumeWith(Result.success(it))
            }
            launcher.launch(input)
        }
}

/** Health Connect's «privacy policy» link: the website's privacy text. */
class PrivacyActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://alvyo.tellbow.ch/about#privacy")))
        finish()
    }
}
