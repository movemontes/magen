package io.github.movemontes.magen.ui

import android.annotation.SuppressLint
import android.content.Context
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.ExperimentalTextApi
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontVariation
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.movemontes.magen.R
import io.github.movemontes.magen.tr

/** Visual da família Treco em vermelho (igual ao Theme.swift do Mac e ao theme.py do Windows). */
object T {
    val CREAM = Color(0xFFFDF9EE)
    val PAPER = Color(0xFFFFFFFF)
    val INK = Color(0xFF0A0A0A)
    val RED = Color(0xFFE10000)
    val HIGHLIGHT = Color(0xFFFFBEBE)
    val HOVER = Color(0xFFFFE8E8)
    val DARK = Color(0xFF3C3C3C)
    val GRAY = Color(0xFF8A8A8A)
    val LINE = 2.dp
    val SHADOW = 4.dp

    lateinit var text: FontFamily
        private set
    lateinit var bold: FontFamily
        private set
    lateinit var wide: FontFamily
        private set

    /** Clash Grotesk se ela foi montada junto (não vai no GitHub); se não, a Archivo. */
    @SuppressLint("DiscouragedApi")
    @OptIn(ExperimentalTextApi::class)
    fun load(ctx: Context) {
        if (::wide.isInitialized) return
        fun archivo(weight: Int, width: Float) = Font(
            R.font.archivo, FontWeight(weight),
            variationSettings = FontVariation.Settings(FontVariation.weight(weight), FontVariation.width(width)))
        wide = FontFamily(archivo(900, 125f))
        val medium = ctx.resources.getIdentifier("clash_medium", "font", ctx.packageName)
        val semi = ctx.resources.getIdentifier("clash_semibold", "font", ctx.packageName)
        text = if (medium != 0) FontFamily(Font(medium, FontWeight.Medium)) else FontFamily(archivo(500, 100f))
        bold = if (semi != 0) FontFamily(Font(semi, FontWeight.SemiBold)) else FontFamily(archivo(700, 100f))
    }

    fun style(size: Float, bold: Boolean = false, color: Color = INK, track: Float = 0f, lineHeight: Float = 1.3f) =
        TextStyle(fontFamily = if (bold) this.bold else text, fontSize = size.sp, color = color,
                  letterSpacing = track.sp, lineHeight = (size * lineHeight).sp)
}

/** Texto do Magen (traduzido pelo tr() quando [translate]). */
@Composable
fun Label(text: String, size: Float = 14f, bold: Boolean = false, color: Color = T.INK, modifier: Modifier = Modifier,
          translate: Boolean = true, track: Float = 0f, align: TextAlign? = null) {
    Text(if (translate) tr(text) else text, modifier = modifier, style = T.style(size, bold, color, track),
         textAlign = align)
}

/** Texto grande na Archivo larga e preta (logo, títulos, números). */
@Composable
fun Wide(text: String, size: Float, color: Color = T.INK, modifier: Modifier = Modifier, lineHeight: Float = 1.05f) {
    Text(text, modifier = modifier, style = TextStyle(fontFamily = T.wide, fontSize = size.sp, color = color,
         lineHeight = (size * lineHeight).sp, fontWeight = FontWeight.Black))
}

/** Título da página com o marca-texto atrás da metade de baixo das letras (como o "Converter" do Treco). */
@Composable
fun PageTitle(text: String, size: Float = 34f) {
    Text(text, style = TextStyle(fontFamily = T.wide, fontSize = size.sp, color = T.INK, fontWeight = FontWeight.Black,
         lineHeight = (size * 1.05f).sp),
         modifier = Modifier.drawBehind {
             drawRect(T.HIGHLIGHT, topLeft = Offset(-4.dp.toPx(), size * 0.48f * density * fontScale),
                      size = Size(this.size.width + 8.dp.toPx(), size * 0.42f * density * fontScale))
         })
}

/** Caixa com borda preta de 2 px e sombra dura. */
@Composable
fun Boxed(modifier: Modifier = Modifier, fill: Color = T.PAPER, border: Color? = T.INK, shadow: Dp = T.SHADOW,
          shadowColor: Color = T.INK, pad: Dp = 14.dp, content: @Composable BoxScope.() -> Unit) {
    Box(modifier
        .padding(end = shadow, bottom = shadow)
        .drawBehind {
            if (shadow > 0.dp) drawRect(shadowColor, topLeft = Offset(shadow.toPx(), shadow.toPx()), size = this.size)
        }
        .background(fill)
        .let { if (border != null) it.border(T.LINE, border) else it }
        .padding(pad), content = content)
}

/** Botão quadrado com sombra dura. Apertar afunda. accent/selected = face preta com sombra vermelha. */
@Composable
fun BoxButton(text: String, onClick: () -> Unit, modifier: Modifier = Modifier, height: Dp = 48.dp,
              size: Float = 13f, accent: Boolean = false, selected: Boolean = false, enabled: Boolean = true,
              icon: ImageVector? = null, translate: Boolean = true) {
    val source = remember { MutableInteractionSource() }
    val pressed by source.collectIsPressedAsState()
    val dark = accent || selected
    val sh = 4.dp
    var face = if (dark) T.INK else if (pressed) T.HOVER else T.PAPER
    var fg = if (dark) T.CREAM else T.INK
    if (!enabled) {
        face = if (dark) Color(0xFF5A5A5A) else Color(0xFFF2EFE6)
        fg = if (dark) Color(0xFFDDDDDD) else T.GRAY
    }
    val off = if (pressed && enabled) sh else 0.dp
    Box(modifier.height(height)) {
        if (off == 0.dp) {
            Box(Modifier.matchParentSize().padding(start = sh, top = sh).background(if (dark) T.RED else T.INK))
        }
        Row(Modifier
            .matchParentSize()
            .padding(end = sh, bottom = sh)
            .offset(off, off)
            .background(face)
            .border(T.LINE, T.INK)
            .clickable(source, null, enabled = enabled, onClick = onClick)
            .padding(horizontal = 10.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.Center) {
            if (icon != null) {
                Icon(icon, null, tint = if (dark) T.CREAM else T.RED, modifier = Modifier.size(20.dp))
                Spacer(Modifier.width(8.dp))
            }
            Text((if (translate) tr(text) else text).uppercase(), style = T.style(size, true, fg, 0.3f),
                 maxLines = 2, textAlign = TextAlign.Center)
        }
    }
}

/** Área tracejada clicável (como "+ ADICIONAR ARQUIVOS" no Treco). */
@Composable
fun DashedButton(text: String, onClick: () -> Unit, modifier: Modifier = Modifier) {
    Box(modifier
        .height(44.dp)
        .drawBehind {
            val w = 2.dp.toPx()
            drawRect(T.INK, topLeft = Offset(w / 2, w / 2), size = Size(size.width - w, size.height - w),
                     style = Stroke(w, pathEffect = PathEffect.dashPathEffect(floatArrayOf(6.dp.toPx(), 4.dp.toPx()))))
        }
        .clickable(onClick = onClick)
        .padding(horizontal = 16.dp), contentAlignment = Alignment.CenterStart) {
        Text("+  " + tr(text).uppercase(), style = T.style(12f, true, T.INK, 0.5f))
    }
}

/** Interruptor quadrado com título e explicação, estilo Treco. */
@Composable
fun CheckRow(title: String, detail: String, on: Boolean, onToggle: (Boolean) -> Unit, modifier: Modifier = Modifier,
             enabled: Boolean = true) {
    Row(modifier.fillMaxWidth().clickable(enabled = enabled) { onToggle(!on) }.padding(vertical = 4.dp)) {
        Canvas(Modifier.size(26.dp)) {
            val w = 2.dp.toPx()
            drawRect(if (on) T.INK else T.PAPER)
            drawRect(T.INK, topLeft = Offset(w / 2, w / 2), size = Size(size.width - w, size.height - w), style = Stroke(w))
            if (on) {
                val p = androidx.compose.ui.graphics.Path().apply {
                    moveTo(size.width * 0.24f, size.height * 0.5f)
                    lineTo(size.width * 0.42f, size.height * 0.7f)
                    lineTo(size.width * 0.78f, size.height * 0.28f)
                }
                drawPath(p, T.RED, style = Stroke(3.dp.toPx()))
            }
        }
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Label(title, 15f, bold = true, color = if (enabled) T.INK else T.GRAY)
            Spacer(Modifier.height(2.dp))
            Label(detail, 13f, color = T.DARK)
        }
    }
}

/** Título de seção em maiúsculas, espaçado. */
@Composable
fun Section(text: String, modifier: Modifier = Modifier) {
    Label(tr(text).uppercase(), 12f, bold = true, color = T.DARK, translate = false, track = 0.6f,
          modifier = modifier.padding(bottom = 8.dp))
}
