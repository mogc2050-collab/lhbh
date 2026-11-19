package com.ibetoo.ibetoo_media

import android.app.Activity
import android.app.AlertDialog
import android.widget.EditText
import org.mozilla.geckoview.GeckoResult
import org.mozilla.geckoview.GeckoSession
import org.mozilla.geckoview.GeckoSession.PromptDelegate
import org.mozilla.geckoview.GeckoSession.PromptDelegate.PromptResponse

/** alert / confirm / prompt dialogs. File pickers and permissions come next. */
class GeckoPrompts(private val activity: () -> Activity?) : PromptDelegate {

    override fun onAlertPrompt(
        session: GeckoSession, prompt: PromptDelegate.AlertPrompt,
    ): GeckoResult<PromptResponse>? {
        val act = activity() ?: return GeckoResult.fromValue(prompt.dismiss())
        val result = GeckoResult<PromptResponse>()
        AlertDialog.Builder(act)
            .setTitle(prompt.title)
            .setMessage(prompt.message)
            .setPositiveButton(android.R.string.ok) { _, _ -> result.complete(prompt.dismiss()) }
            .setOnCancelListener { result.complete(prompt.dismiss()) }
            .show()
        return result
    }

    override fun onButtonPrompt(
        session: GeckoSession, prompt: PromptDelegate.ButtonPrompt,
    ): GeckoResult<PromptResponse>? {
        val act = activity() ?: return GeckoResult.fromValue(prompt.dismiss())
        val result = GeckoResult<PromptResponse>()
        AlertDialog.Builder(act)
            .setTitle(prompt.title)
            .setMessage(prompt.message)
            .setPositiveButton(android.R.string.ok) { _, _ ->
                result.complete(prompt.confirm(PromptDelegate.ButtonPrompt.Type.POSITIVE))
            }
            .setNegativeButton(android.R.string.cancel) { _, _ ->
                result.complete(prompt.confirm(PromptDelegate.ButtonPrompt.Type.NEGATIVE))
            }
            .setOnCancelListener { result.complete(prompt.dismiss()) }
            .show()
        return result
    }

    override fun onTextPrompt(
        session: GeckoSession, prompt: PromptDelegate.TextPrompt,
    ): GeckoResult<PromptResponse>? {
        val act = activity() ?: return GeckoResult.fromValue(prompt.dismiss())
        val result = GeckoResult<PromptResponse>()
        val input = EditText(act)
        input.setText(prompt.defaultValue ?: "")
        AlertDialog.Builder(act)
            .setTitle(prompt.title)
            .setMessage(prompt.message)
            .setView(input)
            .setPositiveButton(android.R.string.ok) { _, _ ->
                result.complete(prompt.confirm(input.text.toString()))
            }
            .setNegativeButton(android.R.string.cancel) { _, _ -> result.complete(prompt.dismiss()) }
            .setOnCancelListener { result.complete(prompt.dismiss()) }
            .show()
        return result
    }
}
