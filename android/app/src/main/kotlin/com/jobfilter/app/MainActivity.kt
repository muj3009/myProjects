package com.jobfilter.app

import com.jobfilter.app.automation.AutomationMethodChannelHandler
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Registers the automation method/event channels described in
        // lib/platform/channel_names.dart. Kept as a single handler class
        // rather than scattering channel setup across this activity, per
        // spec section 2's "do not put Android automation logic directly
        // into Flutter widgets" — the inverse also applies here.
        AutomationMethodChannelHandler(this, flutterEngine)
    }
}
