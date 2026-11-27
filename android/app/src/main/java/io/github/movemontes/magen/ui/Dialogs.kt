package io.github.movemontes.magen.ui

import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.runtime.LaunchedEffect
import io.github.movemontes.magen.BuildConfig
import io.github.movemontes.magen.I18n
import io.github.movemontes.magen.Magen
import io.github.movemontes.magen.tr
import io.github.movemontes.magen.trf

/** Abre a janelinha que estiver em [MainActivity.popup]. */
@Composable
fun Dialogs(a: MainActivity) {
    val p = a.popup ?: return
    fun close() { a.popup = null; a.popupClosed(p) }
    when (p) {
        is Popup.Message -> Frame(::close) {
            Heading(p.title, T.INK)
            Body(p.text)
            Buttons(listOf(Triple("OK", ::close, true)))
        }
        is Popup.Ask -> Frame(::close) {
            Heading(p.title, T.INK)
            Body(p.text)
            Buttons(listOf(Triple("Desistir", ::close, false), Triple(p.yes, { close(); p.onYes() }, true)))
        }
        is Popup.Sentence -> SentenceDialog(p, ::close)
        is Popup.Donation -> Donation(a, ::close)
        is Popup.Update -> Frame(::close) {
            Heading(trf("Magen %s chegou", p.release.version), T.RED)
            Body(trf("Você está com a %s.", BuildConfig.VERSION_NAME), color = T.DARK)
            if (p.release.notes.isNotEmpty()) Body(p.release.notes.take(900))
            Buttons(listOf(Triple("Pular esta versão", { Updates.skip(p.release.version); close() }, false),
                           Triple("Depois", ::close, false)))
            Spacer(Modifier.height(10.dp))
            BoxButton("Atualizar agora", { close(); a.installUpdate(p.release) }, Modifier.fillMaxWidth(), accent = true)
        }
    }
}

/** Janela creme com borda e sombra dura, no meio da tela. */
@Composable
private fun Frame(onDismiss: () -> Unit, content: @Composable () -> Unit) {
    Dialog(onDismiss, DialogProperties(usePlatformDefaultWidth = false)) {
        Boxed(Modifier.padding(18.dp).widthIn(max = 520.dp), fill = T.CREAM, shadow = 6.dp, pad = 22.dp) {
            Column(Modifier.verticalScroll(rememberScrollState())) { content() }
        }
    }
}

@Composable
private fun Heading(text: String, color: Color, size: Float = 20f) {
    Wide(tr(text), size, color = color, lineHeight = 1.12f)
    Spacer(Modifier.height(12.dp))
}

@Composable
private fun Body(text: String, bold: Boolean = false, color: Color = T.INK, size: Float = 14f) {
    Label(text, size, bold = bold, color = color)
    Spacer(Modifier.height(10.dp))
}

@Composable
private fun Buttons(items: List<Triple<String, () -> Unit, Boolean>>) {
    Spacer(Modifier.height(6.dp))
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        for ((text, action, accent) in items) {
            BoxButton(text, action, Modifier.weight(1f), accent = accent, size = 12f)
        }
    }
}

/** A pessoa precisa digitar a frase exata (sem diferença de maiúsculas). */
@Composable
private fun SentenceDialog(p: Popup.Sentence, close: () -> Unit) {
    var typed by remember { mutableStateOf("") }
    val focus = remember { FocusRequester() }
    Frame(close) {
        Heading(p.title, T.RED)
        Body(p.text)
        Label(p.sentence, 16f, bold = true, color = T.RED, translate = false)
        Spacer(Modifier.height(8.dp))
        BasicTextField(typed, { typed = it }, singleLine = true, textStyle = T.style(17f), cursorBrush = SolidColor(T.INK),
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false),
            modifier = Modifier.fillMaxWidth().background(T.PAPER).border(T.LINE, T.INK).padding(12.dp).focusRequester(focus))
        LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }
        Spacer(Modifier.height(8.dp))
        Buttons(listOf(Triple("Desistir", close, false), Triple(p.yes, {
            val ok = typed.trim().lowercase() == p.sentence
            close()
            p.onResult(ok)
        }, true)))
    }
}

/** Pedido de doação (como o welcome.py do Treco). Pix só em português. */
@Composable
private fun Donation(a: MainActivity, close: () -> Unit) {
    Magen.prefs.set("doacaoVista", true)
    var copied by remember { mutableStateOf(false) }
    Frame(close) {
        Heading("ME AJUDA: TENHO 5 BOCAS PRA ALIMENTAR", T.RED, size = 21f)
        Body("e fiz esse app de graça pra você.", bold = true)
        Body(trf("Oi, eu sou o %s. O Magen não tem anúncio, não pede conta e não manda nada seu pra internet.", MainActivity.AUTHOR))
        if (I18n.isEn()) {
            Body("Se ele te ajudar nessa luta, o melhor apoio é mostrar o Magen para alguém que precisa. Obrigado de coração!")
            Signature()
            Buttons(listOf(Triple("Bora usar", close, true)))
        } else {
            Body("Se ele te ajudar nessa luta, qualquer valor ajuda muito aqui em casa. Obrigado de coração!")
            Signature()
            Body("Pix (chave aleatória, PicPay):", bold = true)
            Label(MainActivity.PIX, 14f, color = T.RED, translate = false)
            Spacer(Modifier.height(10.dp))
            Buttons(listOf(Triple("Bora usar", close, false),
                           Triple(if (copied) "Copiado!" else "Copiar chave Pix", { a.copyPix(); copied = true }, true)))
        }
    }
}

/** Foto redonda pequena, "Mateus" em negrito e a frase em vermelho. */
@Composable
private fun Signature() {
    val ctx = LocalContext.current
    val photo = remember {
        runCatching { ctx.assets.open("mateus.png").use { BitmapFactory.decodeStream(it) }.asImageBitmap() }.getOrNull()
    }
    Row(Modifier.padding(top = 2.dp, bottom = 12.dp), verticalAlignment = Alignment.CenterVertically) {
        if (photo != null) {
            Image(photo, null, Modifier.size(40.dp).clip(CircleShape))
            Spacer(Modifier.width(10.dp))
        }
        Column {
            Label(MainActivity.AUTHOR, 14f, bold = true, translate = false)
            Label("Tudo para honra e glória do Senhor!", 14f, color = T.RED)
        }
    }
}
