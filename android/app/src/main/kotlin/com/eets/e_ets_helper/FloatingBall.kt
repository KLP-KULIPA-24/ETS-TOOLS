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
 * 原生悬浮窗（可拖动的小球，点开展开答案卡）。
 *
 * 为什么不用 flutter_overlay_window：那个插件在部分 ROM/新版引擎上悬浮层
 * 起不来——日志里是 `FlutterRenderer: Width is zero`，窗口建出来了但内容
 * 是黑的/看不见（用户反馈"点了没反应"，且会弄乱界面）。原生 WindowManager
 * 视图不依赖第二个 Flutter 引擎，稳定可控。
 */
class FloatingBall(private val context: Context) {

    private val wm = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private val touchSlop = ViewConfiguration.get(context).scaledTouchSlop

    private var card: LinearLayout? = null
    private var params: WindowManager.LayoutParams? = null
    private var titleView: TextView? = null
    private var bodyView: TextView? = null
    private var expanded = false

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

    @SuppressLint("ClickableViewAccessibility")
    private fun buildCard(title: String, answers: String): LinearLayout {
        val pad = (14 * context.resources.displayMetrics.density).toInt()
        val card = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            background = GradientDrawable().apply {
                cornerRadius = pad * 1.6f
                setColor(Color.argb(246, 255, 255, 255))
                setStroke((1 * context.resources.displayMetrics.density).toInt(), Color.argb(40, 20, 24, 40))
            }
            elevation = pad * 0.6f
        }

        // 顶栏：应用图标 + 标题（折叠态只有这一行）
        val head = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        val icon = ImageView(context).apply {
            setImageResource(android.R.drawable.ic_menu_view)
            setColorFilter(Color.argb(235, 31, 58, 140))
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
            rightMargin = dp(4)
        })
        card.addView(head, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT,
            LinearLayout.LayoutParams.WRAP_CONTENT,
        ))

        // 正文（展开才显示）
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
        card.addView(scroll, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            dp(190),
        ).apply { topMargin = dp(8) })
        card.setPadding(pad, pad, pad, pad)

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
        val body = bodyView ?: return
        body.visibility = if (expanded) View.VISIBLE else View.GONE
        (body.parent as? View)?.visibility = if (expanded) View.VISIBLE else View.GONE
        params?.let { p ->
            p.width = if (expanded) dp(280) else dp(150)
            card?.let { c -> wm.updateViewLayout(c, p) }
        }
    }

    private fun dp(v: Int): Int = (v * context.resources.displayMetrics.density).toInt()

    @Synchronized
    fun show(title: String, answers: String): Boolean {
        if (!hasPermission()) return false
        if (card != null) {
            update(title, answers)
            return true
        }
        val p = WindowManager.LayoutParams(
            dp(150),
            WindowManager.LayoutParams.WRAP_CONTENT,
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
    }
}