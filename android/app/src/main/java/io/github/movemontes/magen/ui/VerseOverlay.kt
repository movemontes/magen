package io.github.movemontes.magen.ui

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.os.Build
import android.provider.Settings
import android.view.Gravity
import android.view.KeyEvent
import android.view.WindowManager
import android.widget.FrameLayout
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import androidx.lifecycle.setViewTreeLifecycleOwner
import androidx.savedstate.SavedStateRegistry
import androidx.savedstate.SavedStateRegistryController
import androidx.savedstate.SavedStateRegistryOwner
import androidx.savedstate.setViewTreeSavedStateRegistryOwner
import io.github.movemontes.magen.I18n
import io.github.movemontes.magen.Magen
import io.github.movemontes.magen.R
import io.github.movemontes.magen.tr
import io.github.movemontes.magen.trf
import kotlinx.coroutines.delay
import org.json.JSONObject

data class Verse(val title: String, val text: String, val ref: String)

object Verses {
    private var all: Map<String, List<Verse>> = emptyMap()
    private var last = -1

    fun list(ctx: Context): List<Verse> {
        if (all.isEmpty()) {
            val j = JSONObject(ctx.assets.open("versiculos.json").bufferedReader().readText())
            all = listOf("pt", "en").associateWith { lang ->
                val a = j.getJSONArray(lang)
                (0 until a.length()).map { a.getJSONObject(it).let { o -> Verse(o.getString("title"), o.getString("text"), o.getString("ref")) } }
            }
        }
        return all[if (I18n.isEn()) "en" else "pt"]!!
    }

    fun random(ctx: Context): Verse {
        val vs = list(ctx)
        var i = vs.indices.random()
        if (vs.size > 1 && i == last) i = (i + 1) % vs.size
        last = i
        return vs[i]
    }

    fun creditLong(ctx: Context): String = if (I18n.isEn())
        "${list(ctx).size} verses from the World English Bible (public domain). The titles above each verse are Magen's."
    else "${list(ctx).size} versículos da Bíblia Livre (BLIVRE), Copyright © Diego Santos, Mario Sérgio e Marco Teles, " +
        "fevereiro de 2018. Licença Creative Commons Atribuição 4.0 Brasil. Os títulos acima de cada versículo são do Magen."
}

/**
 * A tela vermelha com o versículo (como o VerseAlert do Mac). Cobre tudo, por cima dos outros apps,
 * e só fecha depois da contagem "Respire… 5". Precisa da permissão "Aparecer sobre outros apps".
 * O nome do site nunca aparece.
 */
object VerseOverlay {
    private var view: FrameLayout? = null
    private var lastShown = 0L

    val showing get() = view != null

    fun canDraw(ctx: Context) = Settings.canDrawOverlays(ctx)

    /** O porteiro avisou que bloqueou um site adulto. */
    fun siteBlocked(ctx: Context) {
        val p = Magen.prefs
        if (!p.bool("versiculos", true) || showing) return
        val gap = p.int("minutosEntreJanelas", 1) * 60_000L
        if (System.currentTimeMillis() - lastShown < gap) return
        lastShown = System.currentTimeMillis()
        val lock = p.int("segundosParaFechar", 5)
        if (canDraw(ctx)) show(ctx, Verses.random(ctx), "Site bloqueado", lock)
        else notifyInstead(ctx, Verses.random(ctx))
    }

    /** "Ver como fica". Devolve false se falta a permissão (aí o app mostra dentro dele mesmo). */
    fun preview(ctx: Context): Boolean {
        if (!canDraw(ctx)) return false
        show(ctx, Verses.random(ctx), "Exemplo", minOf(Magen.prefs.int("segundosParaFechar", 5), 3))
        return true
    }

    fun show(ctx: Context, verse: Verse, heading: String, lockSeconds: Int) {
        close(ctx)
        val app = ctx.applicationContext
        T.load(app)
        val owner = OverlayOwner()
        var remaining = lockSeconds
        val frame = object : FrameLayout(app) {
            override fun dispatchKeyEvent(event: KeyEvent): Boolean {
                if (event.keyCode == KeyEvent.KEYCODE_BACK) {
                    if (event.action == KeyEvent.ACTION_UP && remaining <= 0) close(app)
                    return true // "voltar" não fecha antes da contagem
                }
                return super.dispatchKeyEvent(event)
            }
        }
        val compose = ComposeView(app).apply {
            setContent {
                VerseScreen(verse, heading, lockSeconds, onTick = { remaining = it }, onClose = { close(app) })
            }
        }
        frame.addView(compose)
        frame.setViewTreeLifecycleOwner(owner)
        frame.setViewTreeSavedStateRegistryOwner(owner)
        @Suppress("DEPRECATION")
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT, WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_FULLSCREEN,
            PixelFormat.OPAQUE)
        params.gravity = Gravity.TOP or Gravity.START
        if (Build.VERSION.SDK_INT >= 28) {
            params.layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        }
        try {
            app.getSystemService(WindowManager::class.java).addView(frame, params)
            owner.start()
            view = frame
            frame.requestFocus()
        } catch (e: Exception) {
            Magen.log("Não consegui mostrar o versículo: $e")
        }
    }

    fun close(ctx: Context) {
        val v = view ?: return
        view = null
        runCatching { ctx.applicationContext.getSystemService(WindowManager::class.java).removeView(v) }
    }

    /** Sem a permissão de aparecer por cima: um aviso com o versículo. */
    private fun notifyInstead(ctx: Context, v: Verse) {
        val nm = ctx.getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel("avisos", tr("Avisos do Magen"), NotificationManager.IMPORTANCE_HIGH))
        val open = PendingIntent.getActivity(ctx, 1, Intent(ctx, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        val n = android.app.Notification.Builder(ctx, "avisos")
            .setSmallIcon(R.drawable.ic_notificacao)
            .setContentTitle(v.title)
            .setContentText("“${v.text}” ${v.ref}")
            .setStyle(android.app.Notification.BigTextStyle().bigText("“${v.text}”\n${v.ref}"))
            .setContentIntent(open)
            .setAutoCancel(true)
            .build()
        runCatching { nm.notify(3, n) }
    }

    /** O Compose precisa de um "dono" com ciclo de vida, mesmo fora de uma tela do app. */
    private class OverlayOwner : LifecycleOwner, SavedStateRegistryOwner {
        private val registry = LifecycleRegistry(this)
        private val saved = SavedStateRegistryController.create(this)
        override val lifecycle: Lifecycle get() = registry
        override val savedStateRegistry: SavedStateRegistry get() = saved.savedStateRegistry
        init { saved.performRestore(null) }
        fun start() {
            registry.currentState = Lifecycle.State.CREATED
            registry.currentState = Lifecycle.State.RESUMED
        }
    }
}

/** O desenho da tela do versículo (usado por cima dos apps e, sem permissão, dentro do Magen). */
@Composable
fun VerseScreen(v: Verse, heading: String, lockSeconds: Int, onTick: (Int) -> Unit = {}, onClose: () -> Unit) {
    var remaining by remember { mutableIntStateOf(lockSeconds) }
    LaunchedEffect(Unit) {
        while (remaining > 0) {
            delay(1000)
            remaining--
            onTick(remaining)
        }
    }
    Box(Modifier
        .fillMaxSize()
        .background(T.RED)
        .clickable(remember { MutableInteractionSource() }, null) {} // toque no vermelho não faz nada
        .systemBarsPadding()
        .verticalScroll(rememberScrollState())
        .padding(18.dp),
        contentAlignment = Alignment.Center) {
        Boxed(Modifier.widthIn(max = 560.dp), fill = T.PAPER, shadow = 8.dp, shadowColor = T.INK, pad = 22.dp) {
            Column {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Wide("MAGEN", 22f)
                    Spacer(Modifier.weight(1f))
                    Label(tr(heading).uppercase(), 12f, bold = true, color = T.RED, translate = false, track = 0.6f)
                }
                Box(Modifier.padding(top = 12.dp, bottom = 20.dp).fillMaxWidth().height(2.dp).background(T.INK))
                Wide(v.title, 26f, color = T.RED)
                Spacer(Modifier.height(14.dp))
                Label("“${v.text}”", 19f, translate = false)
                Spacer(Modifier.height(12.dp))
                val source = if (I18n.isEn()) "WORLD ENGLISH BIBLE" else "BÍBLIA LIVRE"
                Label("${v.ref.uppercase()}  ·  $source", 12f, bold = true, color = T.DARK, translate = false, track = 0.6f)
                Spacer(Modifier.height(18.dp))
                Label("Feche o navegador por alguns minutos. Levante, beba água, fale com alguém.", 13f, color = T.DARK)
                Spacer(Modifier.height(16.dp))
                if (remaining > 0) {
                    BoxButton(trf("Respire… %d", remaining), {}, Modifier.fillMaxWidth(), height = 56.dp, size = 15f,
                              enabled = false, translate = false)
                } else {
                    BoxButton("Entendi", onClose, Modifier.fillMaxWidth(), height = 56.dp, size = 15f, accent = true)
                }
            }
        }
    }
}
