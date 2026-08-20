package com.margelo.nitro.glassreactions

import android.app.Activity
import android.app.Dialog
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.util.TypedValue
import android.view.Gravity
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.emoji2.emojipicker.EmojiPickerView

/**
 * The "another reaction" emoji picker: androidx's EmojiPickerView — the
 * platform's own picker UI, the same one Gboard ships — presented as a bottom
 * sheet. A plain Dialog rather than Material's BottomSheetDialog so the
 * library adds no Material dependency.
 */
internal class AnotherReactionSheet {

    private var dialog: Dialog? = null

    /** onPick fires at most once; dismissing without choosing fires nothing. */
    fun present(activity: Activity, onPick: (String) -> Unit) {
        dismiss()

        fun dp(value: Float): Int = TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP, value, activity.resources.displayMetrics
        ).toInt()

        val night = (activity.resources.configuration.uiMode and
            Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES

        val sheet = Dialog(activity)
        val picker = EmojiPickerView(activity)
        picker.setOnEmojiPickedListener { item ->
            dismiss()
            onPick(item.emoji)
        }

        val container = FrameLayout(activity).apply {
            background = GradientDrawable().apply {
                setColor(if (night) Color.rgb(0x1C, 0x1C, 0x1E) else Color.WHITE)
                cornerRadii = floatArrayOf(
                    dp(16f).toFloat(), dp(16f).toFloat(),
                    dp(16f).toFloat(), dp(16f).toFloat(),
                    0f, 0f, 0f, 0f
                )
            }
            clipToOutline = true
            addView(
                picker,
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT, dp(320f)
                )
            )
        }

        sheet.setContentView(container)
        sheet.setCanceledOnTouchOutside(true)
        sheet.window?.apply {
            setGravity(Gravity.BOTTOM)
            setLayout(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
            setBackgroundDrawable(null)
        }
        sheet.setOnDismissListener { if (dialog === sheet) dialog = null }
        dialog = sheet
        sheet.show()
    }

    fun dismiss() {
        dialog?.dismiss()
        dialog = null
    }
}
