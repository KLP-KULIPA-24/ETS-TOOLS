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
    private var ballView: View? = null
    private var expandedBox: LinearLayout? = null
    private var expanded = false

    /** 球直径（dp，设置页滑杆可调 60~160）与不透明度 */
    private var ballSizeDp = 80
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

    private fun toggleExpanded() {
        expanded = !expanded
        applyExpanded()
    }

    private fun applyExpanded() {
        val c = card ?: return
        ballView?.visibility = if (expanded) View.GONE else View.VISIBLE
        expandedBox?.visibility = if (expanded) View.VISIBLE else View.GONE
        c.alpha = opacity
        // 外壳统一在这里画：折叠=正圆（球），展开=圆角卡片。
        // 之前把外壳分散在 applyStyle 里画，调完尺寸就丢——这里单一来源。
        c.background = if (expanded) {
            GradientDrawable().apply {
                cornerRadius = dp(24).toFloat()
                setColor(Color.argb((246 * opacity).toInt(), 255, 255, 255))
                setStroke(dp(1), Color.argb((40 * opacity).toInt(), 20, 24, 40))
            }
        } else {
            GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.argb((250 * opacity).toInt(), 255, 255, 255))
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
    fun show(title: String, answers: String): Boolean {
        if (!hasPermission()) return false
        if (card != null) {
            update(title, answers)
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
            x = dp(240)
            y = dp(420)
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
    fun update(title: String, answers: String) {
        titleView?.text = title.ifBlank { "E听说助手" }
        bodyView?.text = answers.ifBlank { "（暂无内容）" }
    }

    /** 设置页调整外观：球直径(**屏幕像素**) + 不透明度 */
    @Synchronized
    fun applyStyle(sizePx: Int, opacityValue: Double) {
        val density = context.resources.displayMetrics.density.coerceAtLeast(0.75f)
        ballSizeDp = (sizePx / density).toInt().coerceIn(28, 260)
        opacity = opacityValue.toFloat().coerceIn(0.4f, 1f)
        if (card == null) return
        applyExpanded()
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
