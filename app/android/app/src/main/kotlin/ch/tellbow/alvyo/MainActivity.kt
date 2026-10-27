package ch.tellbow.alvyo

import android.content.Context
import android.graphics.Bitmap
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.view.PixelCopy
import android.view.View
import android.view.ViewGroup
import android.speech.tts.UtteranceProgressListener
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.android.FlutterSurfaceView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.Locale

// A fragment activity: the health plugin asks for permissions through it.
class MainActivity : FlutterFragmentActivity() {
    private var speech: Speech? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Turn-by-turn prompts (lib/navigation/speech.dart).
        val speech = Speech(applicationContext).also { this.speech = it }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "alvyo/speech").setMethodCallHandler { call, result ->
            val text = call.argument<String>("text")
            val language = call.argument<String>("language")
            if (call.method != "say" || text == null || language == null) {
                result.notImplemented()
                return@setMethodCallHandler
            }
            speech.say(text, language) { error ->
                if (error == null) result.success(null) else result.error("speech", error, null)
            }
        }
        // Bug reports (lib/bug_report.dart): the screen as shown, with the
        // maps, which Flutter's own picture leaves empty.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "alvyo/screenshot").setMethodCallHandler { call, result ->
            if (call.method != "window") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            screenshot { jpeg -> runOnUiThread { result.success(jpeg) } }
        }
    }

    /**
     * Flutter's surface as a JPEG at twice its size in dp, as the Flutter
     * picture was; null if the copy fails. Not a PNG: one of a map filling
     * the screen can exceed the 4 MB the API takes (feedback issue 40). Flutter draws into a surface of
     * its own, which a copy of the window leaves out; the maps are drawn
     * into it too (texture layer platform views).
     */
    private fun screenshot(done: (ByteArray?) -> Unit) {
        val view = flutterSurface(window.decorView)
        if (view == null || view.width == 0 || view.height == 0) return done(null)
        val full = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888)
        val thread = HandlerThread("screenshot").apply { start() }
        PixelCopy.request(view, full, { code ->
            val scale = 2 / resources.displayMetrics.density
            val jpeg =
                if (code != PixelCopy.SUCCESS) {
                    null
                } else {
                    val small = Bitmap.createScaledBitmap(full, (full.width * scale).toInt(), (full.height * scale).toInt(), true)
                    ByteArrayOutputStream().also { small.compress(Bitmap.CompressFormat.JPEG, 80, it) }.toByteArray()
                }
            thread.quitSafely()
            done(jpeg)
        }, Handler(thread.looper))
    }

    private fun flutterSurface(view: View): FlutterSurfaceView? = when (view) {
        is FlutterSurfaceView -> view
        is ViewGroup -> (0 until view.childCount).firstNotNullOfOrNull { flutterSurface(view.getChildAt(it)) }
        else -> null
    }

    override fun onDestroy() {
        speech?.shutdown()
        super.onDestroy()
    }
}

// Spoken navigation prompts, like Speech in AppDelegate.swift: other audio
// is turned down while one plays, also with the screen locked.
class Speech(context: Context) : UtteranceProgressListener() {
    private val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val main = Handler(Looper.getMainLooper())
    private val focus =
        AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
            .setAudioAttributes(attributes)
            .build()
    private var ready: Boolean? = null // null while the engine starts
    private val waiting = mutableListOf<() -> Unit>()
    private var count = 0
    private val tts =
        TextToSpeech(context) { status ->
            main.post {
                ready = status == TextToSpeech.SUCCESS
                waiting.forEach { it() }
                waiting.clear()
            }
        }

    init {
        tts.setAudioAttributes(attributes)
        tts.setOnUtteranceProgressListener(this)
    }

    fun say(text: String, language: String, done: (String?) -> Unit) {
        when (ready) {
            null -> waiting += { say(text, language, done) }
            false -> done("no text-to-speech engine")
            true -> {
                // A Swiss voice if there is one, else the language's usual one.
                val usual = mapOf("de" to Locale.GERMANY, "fr" to Locale.FRANCE, "it" to Locale.ITALY)[language] ?: Locale.UK
                val swiss = Locale(language, "CH")
                val locale = if (tts.isLanguageAvailable(swiss) >= TextToSpeech.LANG_COUNTRY_AVAILABLE) swiss else usual
                if (tts.setLanguage(locale) < TextToSpeech.LANG_AVAILABLE) {
                    done("no voice for $locale")
                    return
                }
                audio.requestAudioFocus(focus)
                tts.speak(text, TextToSpeech.QUEUE_ADD, null, "alvyo-${count++}")
                done(null)
            }
        }
    }

    fun shutdown() = tts.shutdown()

    override fun onStart(utteranceId: String?) {}

    override fun onDone(utteranceId: String?) = release()

    @Deprecated("Deprecated in Java")
    override fun onError(utteranceId: String?) = release()

    // Other audio back to full volume once nothing is being said.
    private fun release() {
        main.postDelayed({ if (!tts.isSpeaking) audio.abandonAudioFocusRequest(focus) }, 500)
    }

    private companion object {
        val attributes: AudioAttributes =
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build()
    }
}
