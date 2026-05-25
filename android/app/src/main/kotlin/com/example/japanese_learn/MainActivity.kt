package com.example.japanese_learn

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private var pendingDeepLink: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pendingDeepLink = intent?.dataString
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kotabi/word_widget")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "updateWordWidget" -> {
                        val args = call.arguments as? Map<*, *>
                        if (args == null) {
                            result.error("bad_args", "Missing widget payload", null)
                            return@setMethodCallHandler
                        }
                        KotabiWordWidgetProvider.savePayload(this, args)
                        KotabiWordWidgetProvider.updateAll(this)
                        result.success(null)
                    }
                    "consumePendingDeepLink" -> {
                        val link = pendingDeepLink ?: intent?.dataString
                        pendingDeepLink = null
                        intent?.data = null
                        result.success(link)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        pendingDeepLink = intent.dataString
    }
}
