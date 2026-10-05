package com.eets.e_ets_helper

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowManager
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import kotlin.math.abs

/**
 * 原生悬浮窗：折叠态是一个软件图标的圆形小球，点开展开答案卡，可拖动。
 *
 * 为什么不用 flutter_overlay_window：那个插件在部分 ROM/新版引擎上悬浮层
 * 起不来——日志里是 `FlutterRenderer: Width is zero`，窗口建出来了但内容
 * 是黑的/看不见（用户反馈"点了没反应"，还会把界面搞乱）。原生 WindowManager
 * 视图不依赖第二个 Flutter 引擎，稳定可控。
 */
class FloatingBall(private val context: Context) {

    private val wm = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private val touchSlop = ViewConfiguration.get(context).scaledTouchSlop

    private var card: LinearLayout? = null
    private var params: WindowManager.LayoutParams? = null
    private var titleView: TextView? = null
    private var bodyView: TextView? = null
    private var tabsRow: LinearLayout? = null
    private var partIndex = 0

    /** 分段内容（label + text），A/B/C 一排按钮 */
    private var parts: List<Pair<String, String>> = emptyList()

    /** 配色：follow / light / dark */
    private var theme = "follow"

    private var dark = false

    /** 主题色（ARGB，由 Flutter 侧 accentValue 传入） */
    private var accent = 0xFF4F7CFF.toInt()
    private var ballView: View? = null
    private var expandedBox: LinearLayout? = null
    private var expanded = false

    /** 球直径（dp，设置页滑杆可调 60~160）与不透明度 */
    private var ballSizeDp = 50
    private var opacity = 0.96f

    private fun expandedWidthDp(): Int = (ballSizeDp * 3).coerceIn(220, 420)

    private var downRawX = 0f
    private var downRawY = 0f
    private var startX = 0f
    private var startY = 0f
    private var dragging = false

    val isShowing: Boolean get() = card != null

    fun hasPermission(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(context)

    /** 未授权时直接拉起系统"显示在其他应用上层"设置页 */
    fun openPermissionSettings() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        val intent = Intent(
            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
            Uri.parse("package:${context.packageName}"),
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            context.startActivity(intent)
        } catch (_: Throwable) {
            context.startActivity(
                Intent(Settings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        }
    }

    private fun overlayType(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

    private fun dp(v: Int): Int = (v * context.resources.displayMetrics.density).toInt()

    /**
     * 用 mipmap 的 PNG 图标（不是自适应图标）：
     * 自适应图标会按系统形状遮罩渲染，套进圆形底里会被裁掉一截（用户反馈
     * "图标都没展示完全"）。PNG + FIT_CENTER 能完整显示。
     */
    private fun appIconRes(): Int = R.mipmap.ic_launcher

    @SuppressLint("ClickableViewAccessibility")
    private fun buildCard(title: String, answers: String): LinearLayout {
        val pad = dp(14)
        val card = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            elevation = dp(8).toFloat()
            setPadding(pad, pad, pad, pad)
        }

        // ---- 折叠态：只留软件图标的圆形小球 ----
        val ball = ImageView(context).apply {
            setImageResource(appIconRes())
            scaleType = ImageView.ScaleType.FIT_CENTER
            contentDescription = "E听说助手悬浮窗"
        }
        ballView = ball
        // 图标取球的 ~58%：图标本身是圆角方块，太大会顶出圆壳
        card.addView(
            ball,
            LinearLayout.LayoutParams(
                dp((ballSizeDp * 0.58f).toInt()),
                dp((ballSizeDp * 0.58f).toInt()),
            ),
        )

        // ---- 展开态：图标 + 标题 + 正文 ----
        val box = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
        }
        val head = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        val icon = ImageView(context).apply {
            setImageResource(appIconRes())
            scaleType = ImageView.ScaleType.FIT_CENTER
        }
        head.addView(icon, LinearLayout.LayoutParams(dp(20), dp(20)))
        val t = TextView(context).apply {
            this.text = title.ifBlank { "E听说助手" }
            textSize = 13f
            setTextColor(Color.argb(235, 24, 27, 36))
            maxLines = 1
            ellipsize = android.text.TextUtils.TruncateAt.END
        }
        head.addView(t, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply {
            leftMargin = dp(8)
        })
        box.addView(head)

        // A/B/C 透明按钮条：点哪段看哪段（用户要求）
        val tabs = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        tabsRow = tabs
        box.addView(tabs, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT,
        ).apply { topMargin = dp(8) })

        val scroll = ScrollView(context).apply {
            isVerticalScrollBarEnabled = false
        }
        val body = TextView(context).apply {
            text = answers.ifBlank { "（暂无内容）" }
            textSize = 13f
            setLineSpacing(dp(3).toFloat(), 1f)
            setTextColor(Color.argb(225, 32, 36, 46))
        }
        scroll.addView(
            body,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ),
        )
        box.addView(scroll, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            dp(190),
        ).apply { topMargin = dp(8) })
        card.addView(box, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT,
        ))
        expandedBox = box
        titleView = t
        bodyView = body

        // 拖动 + 点击切换展开
        card.setOnTouchListener { _, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    dragging = false
                    downRawX = event.rawX
                    downRawY = event.rawY
                    startX = (params?.x ?: 0).toFloat()
                    startY = (params?.y ?: 0).toFloat()
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - downRawX
                    val dy = event.rawY - downRawY
                    if (!dragging && (abs(dx) > touchSlop || abs(dy) > touchSlop)) dragging = true
                    if (dragging) {
                        params?.x = (startX + dx).toInt()
                        params?.y = (startY + dy).toInt()
                        card.let { c -> params?.let { p -> wm.updateViewLayout(c, p) } }
                    }
                    true
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    if (!dragging) toggleExpanded()
                    dragging = false
                    true
                }
                else -> false
            }
        }
        return card
    }

    /** 重建 A/B/C 按钮条；单击切换当前段 */
    private fun buildTabs() {
        val row = tabsRow ?: return
        row.removeAllViews()
        if (parts.size < 2) {
            row.visibility = View.GONE
            return
        }
        row.visibility = View.VISIBLE
        for ((i, part) in parts.withIndex()) {
            val active = i == partIndex
            val btn = TextView(context).apply {
                text = part.first
                textSize = 13f
                gravity = Gravity.CENTER
                val tint = accentColor()
                // 未选中＝主题色压淡（原写法 tint and 0x66FFFFFF.inv() 是纯位取反，
                // 结果把 RGB 全掩成 0 = 纯黑，深色底上根本看不见）
                setTextColor(if (active) tint else withAlpha(tint, 150))
                setPadding(dp(10), dp(4), dp(10), dp(4))
                background = GradientDrawable().apply {
                    cornerRadius = dp(14).toFloat()
                    // 透明按钮：选中才给一点主题色底
                    if (active) setColor(withAlpha(accentColor(), 38))
                }
                setOnClickListener {
                    partIndex = i
                    bodyView?.text = part.second.ifBlank { "（暂无内容）" }
                    buildTabs()
                }
            }
            val lp = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT,
            )
            if (i > 0) lp.leftMargin = dp(6)
            row.addView(btn, lp)
        }
    }

    /** 主题色来自 Flutter 侧 accentValue（App 的主题色存放在 Dart 设置里，
     *  Android 资源中并没有 "accent" 这个颜色项，取不到就一直落回旧的硬编码蓝）。 */
    private fun accentColor(): Int = accent

    private fun withAlpha(color: Int, alpha: Int): Int =
        Color.argb(alpha, Color.red(color), Color.green(color), Color.blue(color))

    /** 把 tint 按 ratio 掺进 base（返回不带 alpha 的 RGB，alpha 由调用方自己给） */
    private fun mix(base: Int, tint: Int, ratio: Float): Int {
        val r = Color.red(base) + (Color.red(tint) - Color.red(base)) * ratio
        val g = Color.green(base) + (Color.green(tint) - Color.green(base)) * ratio
        val b = Color.blue(base) + (Color.blue(tint) - Color.blue(base)) * ratio
        return Color.rgb(r.toInt().coerceIn(0, 255), g.toInt().coerceIn(0, 255), b.toInt().coerceIn(0, 255))
    }

    private fun isDarkMode(): Boolean = when (theme) {
        "dark" -> true
        "light" -> false
        else -> dark
    }

    private fun toggleExpanded() {
        expanded = !expanded
        applyExpanded()
        if (expanded) buildTabs()
    }

    private fun applyExpanded() {
        val c = card ?: return
        ballView?.visibility = if (expanded) View.GONE else View.VISIBLE
        expandedBox?.visibility = if (expanded) View.VISIBLE else View.GONE
        c.alpha = opacity
        // 外壳统一在这里画：折叠=正圆（球），展开=圆角卡片。
        // 之前把外壳分散在 applyStyle 里画，调完尺寸就丢——这里单一来源。
        val darkBg = isDarkMode()
        val bgBase = if (darkBg) 0xFF161B24.toInt() else 0xFFFFFFFF.toInt()
        val fg = if (darkBg) 0xFFE8EAF0.toInt() else 0xFF181B24.toInt()
        titleView?.setTextColor(withAlpha(fg, 235))
        bodyView?.setTextColor(withAlpha(fg, 225))
        c.background = if (expanded) {
            GradientDrawable().apply {
                cornerRadius = dp(24).toFloat()
                // 背景带一点主题色调（用户：颜色跟随主题色）。
                // 只掺 14% 主题色，掺多了是 50/50 的浑浊混色，不像"带一点"。
                setColor(withAlpha(mix(bgBase, accentColor(), 0.14f), (246 * opacity).toInt()))
                setStroke(dp(1), Color.argb((40 * opacity).toInt(), 20, 24, 40))
            }
        } else {
            GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                // 与展开卡同一套配色：底色掺一点主题色，深色模式下不再是一颗刺眼的纯白球
                setColor(withAlpha(mix(bgBase, accentColor(), 0.14f), (250 * opacity).toInt()))
                setStroke(dp(1), Color.argb((46 * opacity).toInt(), 20, 24, 40))
            }
        }
        val pad = if (expanded) dp(14) else dp(5)
        c.setPadding(pad, pad, pad, pad)
        // 折叠态要居中（竖向 LinearLayout 默认靠左上，球会偏出去）
        c.gravity = if (expanded) Gravity.START else Gravity.CENTER
        ballView?.let { b ->
            val s = dp((ballSizeDp * 0.58f).toInt())
            b.layoutParams = LinearLayout.LayoutParams(s, s)
        }
        params?.let { p ->
            p.width = if (expanded) dp(expandedWidthDp()) else dp(ballSizeDp)
            p.height = if (expanded) LinearLayout.LayoutParams.WRAP_CONTENT else dp(ballSizeDp)
            try {
                wm.updateViewLayout(c, p)
            } catch (_: Throwable) {
            }
        }
    }

    @Synchronized
    fun show(
        title: String,
        answers: String,
        partsJson: String = "",
        themeMode: String = "follow",
        darkMode: Boolean = false,
        themeAccent: Int = 0xFF4F7CFF.toInt(),
    ): Boolean {
        // 不在开头用 hasPermission() 短路：canDrawOverlays() 在部分 ROM 上会**误报 false**，
        // 一短路就永远走不到 addView，表现为"正式版悬浮窗点了没反应"。
        // 这里直接尝试 addView，失败了再由调用方走授权流程。
        theme = themeMode
        dark = darkMode
        accent = themeAccent
        parseParts(partsJson)
        if (card != null) {
            update(title, answers, partsJson)
            return true
        }
        val p = WindowManager.LayoutParams(
            dp(ballSizeDp),
            dp(ballSizeDp),
            overlayType(),
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            // 默认挂在屏幕右侧中部：避开顶部设置栏（用户反馈球压住顶栏）
            val metrics = context.resources.displayMetrics
            x = metrics.widthPixels - dp(expandedWidthDp()) - dp(12)
            y = (metrics.heightPixels * 0.42f).toInt()
        }
        val view = buildCard(title, answers)
        try {
            wm.addView(view, p)
        } catch (_: Throwable) {
            return false
        }
        card = view
        params = p
        expanded = false
        applyExpanded()
        return true
    }

    @Synchronized
    fun update(title: String, answers: String, partsJson: String = "") {
        if (partsJson.isNotEmpty()) parseParts(partsJson)
        titleView?.text = title.ifBlank { "E听说助手" }
        bodyView?.text =
            if (parts.isNotEmpty()) parts.getOrNull(partIndex)?.second?.ifBlank { "（暂无内容）" }
            else answers.ifBlank { "（暂无内容）" }
        buildTabs()
    }

    /** partsJson: [{"label":"A","text":"..."}, ...] */
    private fun parseParts(json: String) {
        parts = emptyList()
        if (json.isBlank()) return
        try {
            val arr = org.json.JSONArray(json)
            val out = ArrayList<Pair<String, String>>()
            for (i in 0 until arr.length()) {
                val o = arr.optJSONObject(i) ?: continue
                out.add(
                    Pair(
                        o.optString("label", ('A' + i).toString()),
                        o.optString("text", ""),
                    ),
                )
            }
            parts = out
            if (partIndex >= out.size) partIndex = 0
        } catch (_: Throwable) {
        }
    }

    /** 设置页调整外观：球直径(**屏幕像素**) + 不透明度 */
    @Synchronized
    fun applyStyle(
        sizePx: Int,
        opacityValue: Double,
        themeMode: String? = null,
        themeAccent: Int? = null,
    ) {
        val density = context.resources.displayMetrics.density.coerceAtLeast(0.75f)
        ballSizeDp = (sizePx / density).toInt().coerceIn(20, 120)
        opacity = opacityValue.toFloat().coerceIn(0.4f, 1f)
        if (themeMode != null) theme = themeMode
        if (themeAccent != null) accent = themeAccent
        if (card == null) return
        applyExpanded()
        buildTabs()
    }

    @Synchronized
    fun hide() {
        card?.let { c ->
            try {
                wm.removeView(c)
            } catch (_: Throwable) {
            }
        }
        card = null
        params = null
        expanded = false
        ballView = null
        expandedBox = null
    }
}
