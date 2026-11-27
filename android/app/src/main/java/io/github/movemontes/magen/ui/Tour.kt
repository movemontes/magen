package io.github.movemontes.magen.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import io.github.movemontes.magen.Magen
import io.github.movemontes.magen.tr

const val TOUR_VERSION = 1 // aumente quando o tour mudar: ele aparece de novo uma vez

class TourStep(val tab: String, val target: String?, val title: String, val text: String)

/** Os 8 passos do tour (os mesmos do Windows, com as palavras do Android). */
val TOUR = listOf(
    TourStep("inicio", null, "Bem-vindo ao Magen",
        "Em poucos passos, você vê como ele protege este celular. Dá para pular quando quiser."),
    TourStep("inicio", "hero", "Está protegendo?",
        "Preto quer dizer protegendo. Vermelho quer dizer desligado: aí aparece o botão “Ligar a proteção”, e o Android pede permissão para a VPN do Magen."),
    TourStep("inicio", "stats", "Os números",
        "Quantos sites adultos foram bloqueados hoje e no total, e quando as listas foram atualizadas. O nome dos sites nunca é guardado."),
    TourStep("inicio", "rail", "As seções",
        "Início, Sites, Versículos, Proteção e Sobre ficam aqui embaixo."),
    TourStep("sites", "sitebox", "Testar, liberar ou bloquear",
        "Digite um site para saber se ele está bloqueado. “Liberar” é só para site que não é adulto: pede uma frase e só vale 1 hora depois."),
    TourStep("versiculos", "panel", "O versículo",
        "Quando um site adulto é bloqueado, a tela fica vermelha com um versículo e só fecha depois de alguns segundos. Aqui você escolhe esse tempo. “Ver como fica” mostra um exemplo."),
    TourStep("protecao", "antiburla", "Contra burla",
        "Deixe isto ligado: assim os navegadores não fogem do Magen pelo “DNS seguro”. Remover o Magen pede uma frase, de propósito."),
    TourStep("inicio", null, "Pronto",
        "Fechar o app não desliga a proteção: o Magen fica na chave da VPN, lá em cima. Para rever este tour, vá em Sobre."),
)

fun tourPending(): Boolean = Magen.prefs.int("tourVisto", 0) < TOUR_VERSION

/** Onde fica cada pedaço que o tour mostra (em coordenadas da tela do app). */
class SpotMap {
    val rects = mutableStateMapOf<String, Rect>()
}

fun Modifier.spot(map: SpotMap, name: String): Modifier = onGloballyPositioned { map.rects[name] = it.boundsInRoot() }

/** Escurece o app, deixa aceso só o pedaço do passo (com borda vermelha) e mostra o balão. */
@Composable
fun TourLayer(a: MainActivity) {
    val step = a.tourStep ?: return
    val s = TOUR[step]
    val density = LocalDensity.current
    val m = with(density) { 6.dp.toPx() }
    val target = s.target?.let { a.spots.rects[it] }?.let { Rect(it.left - m, it.top - m, it.right + m, it.bottom + m) }
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val w = with(density) { maxWidth.toPx() }
        val h = with(density) { maxHeight.toPx() }
        // O escuro: toque nele não faz nada (o balão fica sempre na frente).
        Canvas(Modifier.fillMaxSize()
            .graphicsLayer(compositingStrategy = CompositingStrategy.Offscreen)
            .clickable(remember { MutableInteractionSource() }, null) {}) {
            drawRect(Color(0x8C000000))
            if (target != null) {
                drawRect(Color.Black, topLeft = target.topLeft, size = target.size, blendMode = BlendMode.Clear)
                drawRect(T.RED, topLeft = target.topLeft - Offset(1f, 1f), size = Size(target.width + 2, target.height + 2),
                         style = Stroke(3.dp.toPx()))
            }
        }
        var bsize by remember { mutableStateOf(IntSize.Zero) }
        val gap = with(density) { 14.dp.toPx() }
        val bw = bsize.width.toFloat(); val bh = bsize.height.toFloat()
        var x: Float; var y: Float
        if (target == null) {
            x = (w - bw) / 2; y = (h - bh) / 2
        } else if (h - target.bottom >= bh + gap) { // cabe embaixo
            x = target.left; y = target.bottom + gap
        } else if (target.top >= bh + gap) { // cabe em cima
            x = target.left; y = target.top - gap - bh
        } else { // alvo grande: balão embaixo, por cima do alvo
            x = w - bw - gap; y = h - bh - gap
        }
        x = x.coerceIn(gap, maxOf(gap, w - bw - gap))
        y = y.coerceIn(gap, maxOf(gap, h - bh - gap))
        Box(Modifier
            .offset { IntOffset(x.toInt(), y.toInt()) }
            .widthIn(max = 340.dp)
            .onSizeChanged { bsize = it }
            .graphicsLayer { alpha = if (bsize == IntSize.Zero) 0f else 1f }) {
            Boxed(fill = T.PAPER, shadow = T.SHADOW, shadowColor = T.RED, pad = 16.dp) {
                Column {
                    Label(s.title, 17f, bold = true)
                    Spacer(Modifier.height(6.dp))
                    Label(s.text, 14f, color = T.DARK)
                    Spacer(Modifier.height(14.dp))
                    val last = step == TOUR.size - 1
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Label("${step + 1}/${TOUR.size}", 12f, color = T.GRAY, translate = false)
                        Spacer(Modifier.weight(1f))
                        if (!last) {
                            BoxButton("Pular o tour", a::endTour, Modifier.width(130.dp), height = 42.dp, size = 11f)
                            Spacer(Modifier.width(8.dp))
                        }
                        BoxButton(if (last) "Começar" else "Próximo", a::nextTour, Modifier.width(110.dp), height = 42.dp,
                                  size = 11f, accent = true)
                    }
                }
            }
        }
    }
}
