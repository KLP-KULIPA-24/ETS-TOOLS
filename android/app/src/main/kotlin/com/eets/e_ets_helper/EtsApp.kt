package com.eets.e_ets_helper

import io.flutter.FlutterInjector
import io.flutter.app.FlutterApplication

/**
 * 自定义 Application：
 * FlutterLoader 的初始化默认只在 FlutterActivity.attach 时发生（主进程）。
 * 悬浮窗插件的 OverlayService 运行在独立的 :overlay 进程，该进程里
 * FlutterInjector 的 loader 从未初始化 → findAppBundlePath() 拿不到 assets 路径
 * → 引擎启动时 "Could not resolve main entrypoint function"，悬浮窗永远出不来。
 * 这里在进程启动即初始化（Flutter 3.27+ 惰性初始化 API），所有进程都受益。
 */
class EtsApp : FlutterApplication() {
    override fun onCreate() {
        super.onCreate()
        try {
            FlutterInjector.instance().flutterLoader().let { loader ->
                loader.startInitialization(applicationContext)
                loader.ensureInitializationComplete(applicationContext, null)
            }
        } catch (_: Throwable) {
        }
    }
}