package ch.tellbow.alvyo

import android.app.Activity
import android.content.Intent
import android.os.Bundle

// Hands a sign-in's answer from the browser to the running app and closes the
// browser above it: MainActivity, singleTop, would otherwise start a second time.
class SignInAnswerActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        startActivity(
            Intent(Intent.ACTION_VIEW, intent.data, this, MainActivity::class.java).addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP,
            ),
        )
        finish()
    }
}
