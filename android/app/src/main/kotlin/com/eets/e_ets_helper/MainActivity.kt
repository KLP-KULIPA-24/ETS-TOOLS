package com.eets.e_ets_helper

import android.app.Activity
import android.content.ContentResolver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.DocumentsContract
import android.util.Log
import com.topjohnwu.superuser.Shell
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import rikka.shizuku.Shizuku
import java.io.File
import java.io.FileOutputStream

/**
 * 数据提取通道（四模式，与 ETSToolbox 对齐）：
 * - SHIZUKU：借助 Shizuku 获得高级 API，免 root 拷贝 E听说 私有数据
 * - ROOT：libsu 直接以 root 拷贝（权限最高）
 * - DIRECT_READ：部分 ROM / 老版本 Android 上 FUSE 白名单未拦死，可
 *   直接用 Java File API 读取 Android/data（无需任何提权，零依赖）
 * - SAF：存储访问框架授权 Android/data 子目录后经 ContentResolver 遍历拷贝
 *
 * 共同目标：把 E听说 的 Android/data 私有数据拷到本应用可读目录
 */
class MainActivity : FlutterActivity() {

    companion object {
        const val CHANNEL = "eets/shell"
        const val REQ_SAF = 4711
        const val PREF_SAF_URI = "safTreeUri"
        const val ETS_PKG_DIR =
            "/storage/emulated/0/Android/data/com.ets100.secondary"
    }

    private val shizukuListener = Shizuku.OnRequestPermissionResultListener { _, grantResult ->
        // 授权结果由 Dart 侧 probe 再次确认
    }

    private var pendingSafResult: MethodChannel.Result? = null
    private val floating by lazy { FloatingBall(this) }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Shizuku.addRequestPermissionResultListener(shizukuListener)
    }

    override fun onDestroy() {
        Shizuku.removeRequestPermissionResultListener(shizukuListener)
        super.onDestroy()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_SAF) {
            val pr = pendingSafResult
            pendingSafResult = null
            val uri = data?.data
            if (resultCode == Activity.RESULT_OK && uri != null) {
                try {
                    contentResolver.takePersistableUriPermission(
                        uri,
                        Intent.FLAG_GRANT_READ_URI_PERMISSION,
                    )
                } catch (_: Throwable) {
                }
                getSharedPreferences("eets", Context.MODE_PRIVATE)
                    .edit().putString(PREF_SAF_URI, uri.toString()).apply()
                pr?.success("ok")
            } else {
                pr?.success("cancelled")
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // ---- 原生悬浮窗（可拖动的小球，点开展开答案卡）----
                    "floatingShow" -> {
                        val title = call.argument<String>("title") ?: ""
                        val answers = call.argument<String>("answers") ?: ""
                        val size = call.argument<Int>("size") ?: 0
                        val opacity = call.argument<Double>("opacity") ?: 0.95
                        val partsJson = call.argument<String>("parts") ?: ""
                        val theme = call.argument<String>("theme") ?: "follow"
                        val accent = call.argument<Int>("accent") ?: 0xFF4F7CFF.toInt()
                        val darkMode =
                            resources.configuration.uiMode and
                                android.content.res.Configuration.UI_MODE_NIGHT_MASK ==
                                android.content.res.Configuration.UI_MODE_NIGHT_YES
                        runOnUiThread {
                            if (size > 0) {
                                floating.applyStyle(size, opacity, theme, accent)
                            }
                            if (!floating.hasPermission()) {
                                // 未授权：直接拉起系统"显示在其他应用上层"设置页
                                floating.openPermissionSettings()
                                result.success("noPermission")
                            } else {
                                result.success(
                                    if (floating.show(
                                            title,
                                            answers,
                                            partsJson,
                                            theme,
                                            darkMode,
                                            accent,
                                        )
                                    ) "ok"
                                    else "failed",
                                )
                            }
                        }
                    }
                    "floatingUpdate" -> {
                        val title = call.argument<String>("title") ?: ""
                        val answers = call.argument<String>("answers") ?: ""
                        val partsJson = call.argument<String>("parts") ?: ""
                        runOnUiThread {
                            floating.update(title, answers, partsJson)
                            result.success("ok")
                        }
                    }
                    "floatingHide" -> {
                        runOnUiThread {
                            floating.hide()
                            result.success("ok")
                        }
                    }
                    "floatingApply" -> {
                        val w = call.argument<Int>("size") ?: 44
                        val op = call.argument<Double>("opacity") ?: 0.95
                        val theme = call.argument<String>("theme")
                        val accent = call.argument<Int>("accent")
                        runOnUiThread {
                            floating.applyStyle(w, op, theme, accent)
                            result.success("ok")
                        }
                    }
                    "floatingActive" -> {
                        result.success(floating.isShowing)
                    }
                    "probe" -> {
                        Thread {
                            val map = HashMap<String, Any>()
                            map["root"] = try {
                                Shell.getShell().isRoot
                            } catch (_: Throwable) {
                                false
                            }
                            var ping = false
                            var granted = false
                            try {
                                ping = Shizuku.pingBinder()
                                if (ping) {
                                    granted = Shizuku.checkSelfPermission() ==
                                        android.content.pm.PackageManager.PERMISSION_GRANTED
                                }
                            } catch (_: Throwable) {
                            }
                            map["shizuku"] = ping && granted
                            map["shizukuInstalled"] = ping
                            map["directRead"] = directReadReady()
                            map["saf"] = safTreeUri() != null
                            runOnUiThread { result.success(map) }
                        }.start()
                    }
                    "requestShizuku" -> {
                        try {
                            if (Shizuku.pingBinder() &&
                                Shizuku.checkSelfPermission() !=
                                android.content.pm.PackageManager.PERMISSION_GRANTED
                            ) {
                                Shizuku.requestPermission(0)
                                result.success("requested")
                            } else {
                                result.success("ok")
                            }
                        } catch (e: Throwable) {
                            result.success("unavailable")
                        }
                    }
                    "safPick" -> {
                        // SAF 授权：初始目录直接定位到 E听说 的 Android/data
                        try {
                            val i = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
                            i.addFlags(
                                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
                            )
                            try {
                                val initial = DocumentsContract.buildDocumentUri(
                                    "com.android.externalstorage.documents",
                                    "primary:Android/data/com.ets100.secondary",
                                )
                                i.putExtra(DocumentsContract.EXTRA_INITIAL_URI, initial)
                            } catch (_: Throwable) {
                            }
                            pendingSafResult = result
                            startActivityForResult(i, REQ_SAF)
                        } catch (e: Throwable) {
                            result.success("unavailable")
                        }
                    }
                    "directCopy" -> {
                        val dst = call.argument<String>("dst") ?: ""
                        // 同 safCopy：拷贝放后台线程，避免占死 UI 线程
                        Thread {
                            val r = directExtract(dst)
                            runOnUiThread { result.success(r) }
                        }.start()
                    }
                    "safCopy" -> {
                        val dst = call.argument<String>("dst") ?: ""
                        // 拷贝在后台线程算完，只把结果回主线程——
                        // 否则整个 SAF 遍历占死 UI 线程，界面卡住十几秒
                        Thread {
                            val r = safExtract(dst)
                            runOnUiThread { result.success(r) }
                        }.start()
                    }
                    "exec" -> {
                        val cmd = call.argument<String>("cmd") ?: ""
                        Thread {
                            val out = StringBuilder()
                            val err = StringBuilder()
                            var code = -1
                            var via = "none"
                            // 1) Root
                            try {
                                if (Shell.getShell().isRoot) {
                                    val outList = ArrayList<String>()
                                    val errList = ArrayList<String>()
                                    val r = Shell.cmd(cmd).to(outList, errList).exec()
                                    out.append(outList.joinToString("\n"))
                                    err.append(errList.joinToString("\n"))
                                    code = r.code
                                    via = "root"
                                }
                            } catch (_: Throwable) {
                            }
                            // 2) Shizuku（shell 权限）
                            if (code != 0) {
                                try {
                                    if (Shizuku.pingBinder() &&
                                        Shizuku.checkSelfPermission() ==
                                        android.content.pm.PackageManager.PERMISSION_GRANTED
                                    ) {
                                        val p = shizukuProcess(cmd)
                                        if (p != null) {
                                            out.append(p.first)
                                            err.append(p.second)
                                            code = p.third
                                            via = "shizuku"
                                        }
                                    }
                                } catch (_: Throwable) {
                                }
                            }
                            runOnUiThread {
                                result.success(
                                    mapOf(
                                        "exit" to code,
                                        "out" to out.toString(),
                                        "err" to err.toString(),
                                        "via" to via,
                                    )
                                )
                            }
                        }.start()
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** 通过 Shizuku（shell uid）执行命令，反射调用以兼容不同 API 版本 */
    private fun shizukuProcess(cmd: String): Triple<String, String, Int>? {
        return try {
            val m = Shizuku::class.java.getMethod(
                "newProcess",
                Array<String>::class.java,
                Array<String>::class.java,
                String::class.java,
            )
            val p = m.invoke(null, arrayOf("sh", "-c", cmd), null, null) as Process
            val out = p.inputStream.bufferedReader().use { it.readText() }
            val err = p.errorStream.bufferedReader().use { it.readText() }
            Triple(out, err, p.waitFor())
        } catch (_: Throwable) {
            null
        }
    }

    // ---------------- DIRECT_READ（零提权直读） ----------------

    /** 探测能否直接读取 E听说 的 resource 目录（能 list 出内容才算就绪） */
    private fun directReadReady(): Boolean = try {
        val f = File("$ETS_PKG_DIR/files/Download/ETS_secondary/resource")
        f.isDirectory && (f.list()?.isNotEmpty() == true)
    } catch (_: Throwable) {
        false
    }

    /** 直读拷贝：返回 map(ok, files, msg) */
    private fun directExtract(dst: String): Map<String, Any> {
        val src = File("$ETS_PKG_DIR/files/Download/ETS_secondary/resource")
        val srcBase = if (src.isDirectory) src
        else File("$ETS_PKG_DIR/files/Download/ETS_secondary")
        if (!srcBase.isDirectory) {
            return mapOf(
                "ok" to false,
                "files" to 0,
                "msg" to "源目录不可访问（该设备不支持直读，请换 Shizuku/Root/SAF）",
            )
        }
        return try {
            val out = File(dst)
            out.deleteRecursively()
            out.mkdirs()
            val n = directCopyRec(srcBase, out)
            mapOf("ok" to (n > 0), "files" to n, "msg" to "直读拷贝 $n 个文件")
        } catch (e: Throwable) {
            mapOf("ok" to false, "files" to 0, "msg" to "直读失败：${e.message}")
        }
    }

    private fun directCopyRec(src: File, dst: File): Int {
        var n = 0
        if (src.isDirectory) {
            dst.mkdirs()
            src.listFiles()?.forEach { f ->
                val target = File(dst, f.name)
                if (f.isDirectory) {
                    n += directCopyRec(f, target)
                } else {
                    try {
                        f.inputStream().use { i ->
                            FileOutputStream(target).use { o -> i.copyTo(o) }
                        }
                        n++
                    } catch (_: Throwable) {
                    }
                }
            }
        }
        return n
    }

    // ---------------- SAF（存储访问框架） ----------------

    private fun safTreeUri(): Uri? {
        val s = getSharedPreferences("eets", Context.MODE_PRIVATE)
            .getString(PREF_SAF_URI, null) ?: return null
        return try {
            val uri = Uri.parse(s)
            contentResolver.persistedUriPermissions
                .firstOrNull { it.uri == uri && it.isReadPermission }
            uri
        } catch (_: Throwable) {
            null
        }
    }

    /** SAF 拷贝：从已授权 tree 遍历 E听说 目录，返回 map(ok, files, msg) */
    private fun safExtract(dst: String): Map<String, Any> {
        val tree = safTreeUri()
            ?: return mapOf("ok" to false, "files" to 0, "msg" to "尚未授权 SAF 目录")
        return try {
            val out = File(dst)
            out.deleteRecursively()
            out.mkdirs()
            val resolver = contentResolver
            val rootDoc = DocumentsContract.getTreeDocumentId(tree)
            // 用户授权的层级不确定（Android/data、com.ets100.secondary 或更深一层都合法）：
            // 1) 授权目录本身就在 com.ets100.secondary 里 → 整棵授权子树就是 E听说 数据，直接拷；
            //    （往上层走不行——SAF 授权只覆盖所选子树）
            // 2) 授权在其上层 → 按候选路径依次试，哪个能拷到文件用哪个
            val candidates = mutableListOf<String>()
            if (rootDoc.contains("com.ets100.secondary")) {
                candidates.add(rootDoc)
            } else {
                candidates.add("$rootDoc/com.ets100.secondary")
                candidates.add("$rootDoc/Android/data/com.ets100.secondary")
            }
            var n = 0
            var used = rootDoc
            val trace = StringBuilder() // 每个候选的结果轨迹，失败时带回给 UI/日志
            for (c in candidates) {
                val uri = DocumentsContract.buildDocumentUriUsingTree(tree, c)
                val st = try {
                    safCopyStats(resolver, tree, uri, out, 0)
                } catch (e: Throwable) {
                    Log.w("ETSSAF", "候选 $c 查询/拷贝异常", e)
                    trace.append("[$c 异常: ${e.message}] ")
                    null
                }
                Log.d("ETSSAF", "候选 $c → $st")
                if (st != null && st.copied > 0) {
                    n = st.copied
                    used = c
                    break
                }
                if (st != null) {
                    trace.append("[$c 列出 ${st.listed} 拷贝 ${st.copied}${st.err?.let { " 首错: $it" } ?: ""}] ")
                }
            }
            if (n == 0) {
                // 兜底：系统选择器的授权层级五花八门（可能落在合成层级上，
                // 固定候选全部落空）——在授权子树里向下搜 com.ets100.secondary
                val found = findEtsDir(resolver, tree, rootDoc)
                Log.d("ETSSAF", "BFS 找 com.ets100.secondary → $found")
                trace.append("[BFS: ${found ?: "未找到"}] ")
                if (found != null) {
                    used = found
                    val st = safCopyStats(resolver, tree, DocumentsContract.buildDocumentUriUsingTree(tree, found), out, 0)
                    n = st.copied
                    Log.d("ETSSAF", "BFS 目录拷贝 → $st")
                    if (n == 0) {
                        trace.append("[BFS 目录列出 ${st.listed} 拷贝 0${st.err?.let { " 首错: $it" } ?: ""}] ")
                    }
                }
            }
            mapOf(
                "ok" to (n > 0),
                "files" to n,
                "msg" to
                    if (n > 0) "SAF 拷贝 $n 个文件（授权: $used）"
                    else "SAF 没拷到文件（授权: $rootDoc）$trace——请点「重新授权」重选 E听说 的 Android/data",
            )
        } catch (e: Throwable) {
            mapOf("ok" to false, "files" to 0, "msg" to "SAF 拷贝失败：${e.message}")
        }
    }

    /** 在授权子树里向下找 com.ets100.secondary 目录（限深 3 / 限访问 400，防拖死） */
    private fun findEtsDir(
        resolver: ContentResolver,
        tree: Uri,
        rootDoc: String,
    ): String? {
        var frontier = listOf(rootDoc)
        var depth = 0
        var visited = 0
        while (frontier.isNotEmpty() && depth < 4 && visited < 400) {
            val next = mutableListOf<String>()
            for (id in frontier) {
                if (++visited > 400) return null
                val childrenUri =
                    try {
                        DocumentsContract.buildChildDocumentsUriUsingTree(tree, id)
                    } catch (_: Throwable) {
                        continue
                    }
                val c =
                    try {
                        resolver.query(
                            childrenUri,
                            arrayOf(
                                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                                DocumentsContract.Document.COLUMN_MIME_TYPE,
                            ),
                            null,
                            null,
                            null,
                        )
                    } catch (_: Throwable) {
                        null
                    } ?: continue
                c.use {
                    while (it.moveToNext()) {
                        val cid = it.getString(0) ?: continue
                        val name = it.getString(1) ?: continue
                        val mime = it.getString(2)
                        if (mime == DocumentsContract.Document.MIME_TYPE_DIR) {
                            if (name == "com.ets100.secondary") return cid
                            if (depth < 2) next.add(cid)
                        }
                    }
                }
            }
            frontier = next
            depth++
        }
        return null
    }

    private data class SafStats(val listed: Int, val copied: Int, val err: String?)

    /** 递归遍历 SAF document 拷贝到本地文件系统；全程计数+记首个错误（诊断用） */
    private fun safCopyStats(
        resolver: ContentResolver,
        tree: Uri,
        dirUri: Uri,
        dst: File,
        depth: Int,
    ): SafStats {
        if (depth > 15) return SafStats(0, 0, "目录过深")
        var listed = 0
        var copied = 0
        var err: String? = null
        val children =
            try {
                DocumentsContract.buildChildDocumentsUriUsingTree(
                    dirUri,
                    DocumentsContract.getDocumentId(dirUri),
                )
            } catch (e: Throwable) {
                return SafStats(0, 0, "buildChildren: ${e.message}")
            }
        val c =
            try {
                resolver.query(
                    children,
                    arrayOf(
                        DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                        DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                        DocumentsContract.Document.COLUMN_MIME_TYPE,
                    ),
                    null,
                    null,
                    null,
                )
            } catch (e: Throwable) {
                return SafStats(0, 0, "query: ${e.message}")
            } ?: return SafStats(0, 0, "query 返回 null")
        c.use {
            while (it.moveToNext()) {
                listed++
                val id = it.getString(0)
                val name = it.getString(1) ?: continue
                val mime = it.getString(2)
                val childUri =
                    DocumentsContract.buildDocumentUriUsingTree(tree, id)
                if (mime == DocumentsContract.Document.MIME_TYPE_DIR) {
                    val r = safCopyStats(resolver, tree, childUri, File(dst, name), depth + 1)
                    copied += r.copied
                    if (err == null) err = r.err
                } else {
                    try {
                        val target = File(dst, name)
                        // FileOutputStream 不会创建中间父目录：
                        // 不补 mkdirs 的话，除根层外的所有文件都会 ENOENT 失败
                        target.parentFile?.mkdirs()
                        resolver.openInputStream(childUri)?.use { i ->
                            FileOutputStream(target).use { o -> i.copyTo(o) }
                        }
                        copied++
                    } catch (e: Throwable) {
                        Log.d("ETSSAF", "拷贝失败 $name: ${e.message}")
                        if (err == null) err = "拷贝 $name: ${e.message}"
                    }
                }
            }
        }
        return SafStats(listed, copied, err)
    }
}
