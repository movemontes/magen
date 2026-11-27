package io.github.movemontes.magen.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import io.github.movemontes.magen.BuildConfig
import io.github.movemontes.magen.I18n
import io.github.movemontes.magen.Magen
import io.github.movemontes.magen.R
import io.github.movemontes.magen.core.Rules
import io.github.movemontes.magen.core.Store
import io.github.movemontes.magen.tr
import io.github.movemontes.magen.trf
import io.github.movemontes.magen.vpn.MagenVpnService

private val TABS = listOf("inicio" to "Início", "sites" to "Sites", "versiculos" to "Versículos",
                          "protecao" to "Proteção", "sobre" to "Sobre")
private val LEADS = mapOf(
    "inicio" to "Veja se o Magen está protegendo este celular.",
    "sites" to "Teste, libere ou bloqueie um site.",
    "versiculos" to "A tela que aparece quando um site adulto é bloqueado.",
    "protecao" to "Opções contra burla e como o Magen funciona.",
    "sobre" to "Quem fez, créditos e atualizações.",
)

@Composable
fun MagenScreen(a: MainActivity) {
    Box(Modifier.fillMaxSize().background(T.CREAM)) {
        Column(Modifier.fillMaxSize().imePadding()) {
            Column(Modifier.weight(1f).statusBarsPadding()) {
                Header(a)
                Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp)
                    .padding(top = 8.dp, bottom = 20.dp)) {
                    when (a.tab) {
                        "inicio" -> PageHome(a)
                        "sites" -> PageSites(a)
                        "versiculos" -> PageVerses(a)
                        "protecao" -> PageProtection(a)
                        else -> PageAbout(a)
                    }
                }
                BottomBar(a)
            }
            TabBar(a)
        }
        a.versePreview?.let { v -> VerseScreen(v, "Exemplo", minOf(Magen.prefs.int("segundosParaFechar", 5), 3)) { a.versePreview = null } }
        TourLayer(a)
        Dialogs(a)
    }
}

@Composable
private fun Header(a: MainActivity) {
    Column(Modifier.padding(horizontal = 20.dp).padding(top = 10.dp)) {
        val on = a.serviceOn
        val domains = a.state().domains
        val count = if (domains < 1000) tr("baixando as listas…") else trf("%s sites", I18n.num(domains))
        Label(if (on) trf("Protegendo · %s", count) else tr("Desligado"), 12f, bold = !on,
              color = if (on) T.DARK else T.RED, translate = false)
        Spacer(Modifier.height(4.dp))
        PageTitle(tr(TABS.first { it.first == a.tab }.second))
        Spacer(Modifier.height(4.dp))
        Label(LEADS[a.tab]!!, 14f, color = T.DARK)
        Spacer(Modifier.height(8.dp))
    }
}

/** Barra branca de baixo: "Atualizar listas" e o botão principal. */
@Composable
private fun BottomBar(a: MainActivity) {
    val on = a.serviceOn
    Column(Modifier.fillMaxWidth().background(T.PAPER)) {
        Box(Modifier.fillMaxWidth().height(T.LINE).background(T.INK))
        Row(Modifier.padding(horizontal = 16.dp, vertical = 10.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            BoxButton("Atualizar listas", a::requestUpdate, Modifier.weight(1f), enabled = on, icon = Icons.Filled.Refresh, size = 12f)
            BoxButton(if (on) "Ver versículo" else if (a.busy) "Ligando…" else "Ligar a proteção",
                      if (on) a::showVersePreview else a::turnOn, Modifier.weight(1f), accent = true,
                      enabled = on || !a.busy, size = 12f)
        }
    }
}

/** Barra preta com as seções (no Mac e no Windows é o trilho da esquerda). */
@Composable
private fun TabBar(a: MainActivity) {
    Row(Modifier.fillMaxWidth().background(T.INK).navigationBarsPadding().padding(horizontal = 6.dp, vertical = 8.dp)
        .spot(a.spots, "rail"), horizontalArrangement = Arrangement.SpaceEvenly) {
        for ((key, title) in TABS) {
            val sel = key == a.tab
            Box(Modifier.weight(1f).padding(horizontal = 3.dp).height(58.dp).clickable { a.tab = key }) {
                if (sel) {
                    Box(Modifier.fillMaxSize().padding(start = 4.dp, top = 4.dp).background(T.RED))
                    Box(Modifier.fillMaxSize().padding(end = 4.dp, bottom = 4.dp).background(T.PAPER))
                }
                Column(Modifier.fillMaxSize().padding(end = if (sel) 4.dp else 0.dp, bottom = if (sel) 4.dp else 0.dp),
                       horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
                    TabIcon(key, if (sel) T.RED else T.CREAM)
                    Spacer(Modifier.height(3.dp))
                    Label(tr(title).uppercase(), 9.5f, bold = true, color = if (sel) T.INK else T.CREAM,
                          translate = false, track = 0.3f)
                }
            }
        }
    }
}

@Composable
private fun TabIcon(key: String, color: Color) {
    val icon = when (key) {
        "inicio" -> Icons.Filled.Home
        "sites" -> Icons.Filled.Search
        "protecao" -> Icons.Filled.Lock
        "sobre" -> Icons.Filled.Info
        else -> null
    }
    if (icon != null) { Icon(icon, null, tint = color, modifier = Modifier.size(22.dp)); return }
    // Versículos: um livro aberto.
    Canvas(Modifier.size(22.dp)) {
        val w = size.width; val h = size.height; val s = 2.dp.toPx()
        val left = androidx.compose.ui.graphics.Path().apply {
            moveTo(w * 0.5f, h * 0.28f); cubicTo(w * 0.38f, h * 0.18f, w * 0.2f, h * 0.18f, w * 0.08f, h * 0.24f)
            lineTo(w * 0.08f, h * 0.8f); cubicTo(w * 0.2f, h * 0.74f, w * 0.38f, h * 0.74f, w * 0.5f, h * 0.84f)
            cubicTo(w * 0.62f, h * 0.74f, w * 0.8f, h * 0.74f, w * 0.92f, h * 0.8f)
            lineTo(w * 0.92f, h * 0.24f); cubicTo(w * 0.8f, h * 0.18f, w * 0.62f, h * 0.18f, w * 0.5f, h * 0.28f); close()
        }
        drawPath(left, color, style = Stroke(s))
        drawLine(color, Offset(w * 0.5f, h * 0.28f), Offset(w * 0.5f, h * 0.84f), s)
    }
}

// ------------------------------------------------------------ Início

@Composable
private fun PageHome(a: MainActivity) {
    val on = a.serviceOn
    val s = a.state()
    val ctx = LocalContext.current
    Boxed(Modifier.fillMaxWidth().padding(top = 6.dp, bottom = 16.dp).spot(a.spots, "hero"),
          fill = if (on) T.INK else T.RED, border = null, shadow = 6.dp, shadowColor = if (on) T.RED else T.INK, pad = 18.dp) {
        Column {
            Wide(tr(if (on) "PROTEGENDO" else "DESLIGADO"), 26f, color = T.PAPER)
            Spacer(Modifier.height(4.dp))
            val small = when {
                on -> "Sites adultos não abrem neste celular."
                a.busy -> "Ligando… pode levar até 1 minuto."
                else -> "Toque em “Ligar a proteção”. O Android vai pedir para criar uma VPN: ela fica dentro do celular e só olha o nome dos sites."
            }
            Label(small, 14f, color = T.PAPER)
            if (!on) {
                Spacer(Modifier.height(14.dp))
                BoxButton(if (a.busy) "Ligando…" else "Ligar a proteção", a::turnOn, Modifier.fillMaxWidth(), enabled = !a.busy)
            }
        }
    }

    // Avisos que só existem no Android.
    a.privateDnsHost()?.let { host ->
        Warning(trf("O “DNS privado” está ligado (%s)", host),
                "Com ele, o Android tenta perguntar os endereços por fora do Magen: ou a internet para, ou os sites adultos passam. Desligue em Configurações › Rede e internet › DNS privado (escolha “Desativado” ou “Automático”).",
                "Abrir as configurações", a::openPrivateDnsSettings, translateTitle = false)
    }
    if (on && Magen.prefs.bool("versiculos", true) && !VerseOverlay.canDraw(ctx)) {
        Warning("Falta uma permissão para o versículo",
                "Para a tela do versículo aparecer por cima do navegador, deixe o Magen “aparecer sobre outros apps”.",
                "Dar permissão", a::openOverlaySettings)
    }

    val today = Magen.store.blockedTodayNow()
    val domains = s.domains
    val stats = listOf(
        I18n.num(today) to "bloqueios hoje",
        I18n.num(s.blockedTotal) to "bloqueios no total",
        (if (domains < 1000) tr("Baixando…") else I18n.num(domains)) to
            (if (domains < 1000) "as listas chegam em até 1 minuto" else "sites na lista"),
        MainActivity.fmtTime(s.lastUpdate) to "listas atualizadas",
    )
    Column(Modifier.spot(a.spots, "stats")) {
        for (row in stats.chunked(2)) {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                for ((n, label) in row) {
                    Boxed(Modifier.weight(1f).height(90.dp).padding(bottom = 10.dp), shadow = 3.dp, pad = 12.dp) {
                        Column {
                            Wide(n, if (n.length > 9) 15f else 20f, lineHeight = 1.15f)
                            Spacer(Modifier.height(4.dp))
                            Label(label, 12f, color = T.DARK)
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun Warning(title: String, text: String, button: String, action: () -> Unit, translateTitle: Boolean = true) {
    Boxed(Modifier.fillMaxWidth().padding(bottom = 16.dp), border = T.RED, shadowColor = T.RED) {
        Column {
            Label(title, 15f, bold = true, color = T.RED, translate = translateTitle)
            Spacer(Modifier.height(4.dp))
            Label(text, 13f)
            Spacer(Modifier.height(10.dp))
            BoxButton(button, action, Modifier.fillMaxWidth(), accent = true, height = 44.dp, size = 12f)
        }
    }
}

// ------------------------------------------------------------ Sites

@Composable
private fun PageSites(a: MainActivity) {
    Section("Testar, liberar ou bloquear um site")
    Column(Modifier.spot(a.spots, "sitebox")) {
        BasicTextField(
            a.siteText, { a.siteText = it }, singleLine = true,
            textStyle = T.style(17f), cursorBrush = SolidColor(T.INK),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri, imeAction = ImeAction.Search,
                                              capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false),
            keyboardActions = KeyboardActions(onSearch = { a.testSite() }),
            modifier = Modifier.fillMaxWidth().background(T.PAPER).border(T.LINE, T.INK).padding(12.dp),
            decorationBox = { inner ->
                Box { if (a.siteText.isEmpty()) Label("exemplo.com", 17f, color = T.GRAY, translate = false); inner() }
            })
        Spacer(Modifier.height(12.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            BoxButton("Testar", a::testSite, Modifier.weight(1f), size = 12f)
            BoxButton("Liberar", a::unblockSite, Modifier.weight(1f), size = 12f)
            BoxButton("Bloquear", a::blockSite, Modifier.weight(1f), size = 12f)
        }
        Spacer(Modifier.height(10.dp))
        val text = a.siteResult.ifEmpty {
            trf("Liberar é só para site que NÃO é adulto: pede uma frase e só vale %d minutos depois.", Rules.UNBLOCK_DELAY_SECONDS / 60)
        }
        Label(text, 14f, bold = a.siteResult.isNotEmpty(), translate = false,
              color = if (a.siteResult.startsWith("🚫")) T.RED else T.DARK)
    }
    Spacer(Modifier.height(20.dp))

    val cfg = a.config()
    val pending = cfg.pendingAllow.map { trf("⏳ %s — às %s", it.domain, MainActivity.fmtTime(it.at, withDate = false)) to it.domain }
    val allowed = pending + cfg.allow.map { it to it }
    val blocked = cfg.block.map { it to it }
    for ((title, items) in listOf("Liberados por você" to allowed, "Bloqueados a mais" to blocked)) {
        Section(title)
        if (items.isEmpty()) Label("Nenhum", 14f, color = T.GRAY, modifier = Modifier.padding(bottom = 16.dp))
        for ((shown, domain) in items.take(20)) {
            Row(Modifier.fillMaxWidth().padding(bottom = 6.dp).background(T.PAPER).border(T.LINE, T.INK)
                .padding(start = 10.dp, end = 4.dp, top = 4.dp, bottom = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                Label(shown, 14f, translate = false, modifier = Modifier.weight(1f))
                BoxButton("×", { a.undo(domain) }, Modifier.width(44.dp), height = 38.dp, translate = false)
            }
        }
        if (items.size > 20) Label(trf("e mais %d…", items.size - 20), 13f, color = T.DARK, translate = false)
        Spacer(Modifier.height(14.dp))
    }
}

// ------------------------------------------------------------ Versículos

@Composable
private fun PageVerses(a: MainActivity) {
    val ctx = LocalContext.current
    val on = Magen.prefs.bool("versiculos", true)
    Column(Modifier.spot(a.spots, "panel")) {
        CheckRow("Mostrar a tela com versículo quando um site adulto for bloqueado",
                 "Ela cobre a tela, mostra um versículo e só fecha depois de alguns segundos. O nome do site nunca aparece.",
                 on, { Magen.prefs.set("versiculos", it); a.tick++ })
        Spacer(Modifier.height(18.dp))
        if (on && !VerseOverlay.canDraw(ctx)) {
            Warning("Falta uma permissão para o versículo",
                    "Para a tela do versículo aparecer por cima do navegador, deixe o Magen “aparecer sobre outros apps”. Sem isso, o versículo chega como notificação.",
                    "Dar permissão", a::openOverlaySettings)
        }
        Choices(a, "Tempo até poder fechar", "segundosParaFechar", listOf("3 s" to 3, "5 s" to 5, "10 s" to 10, "15 s" to 15), 5, on)
        Choices(a, "Intervalo mínimo entre telas", "minutosEntreJanelas", listOf("1 min" to 1, "5 min" to 5, "15 min" to 15), 1, on)
        BoxButton("Ver como fica", a::showVersePreview, Modifier.fillMaxWidth(), height = 56.dp)
        Spacer(Modifier.height(14.dp))
        Label(Verses.creditLong(ctx), 12f, color = T.DARK, translate = false)
    }
}

@Composable
private fun Choices(a: MainActivity, title: String, key: String, options: List<Pair<String, Int>>, def: Int, enabled: Boolean) {
    Section(title)
    val cur = Magen.prefs.int(key, def)
    Row(Modifier.padding(bottom = 20.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        for ((text, value) in options) {
            BoxButton(text, { Magen.prefs.set(key, value); a.tick++ }, Modifier.weight(1f), height = 44.dp,
                      selected = value == cur, enabled = enabled, translate = false, size = 12f)
        }
    }
}

// ------------------------------------------------------------ Proteção

@Composable
private fun PageProtection(a: MainActivity) {
    val cfg = a.config()
    Box(Modifier.spot(a.spots, "antiburla")) {
        CheckRow("Bloquear o “DNS seguro” dos navegadores",
                 "Chrome, Firefox e outros apps têm uma opção que pergunta os endereços por fora do Android. Com isso ligado, eles voltam a passar pelo Magen.",
                 cfg.antiBypass, a::setAntiBypass)
    }
    Spacer(Modifier.height(16.dp))
    CheckRow("Dificultar a desinstalação",
             "Com isto ativo, o Android não deixa desinstalar o Magen direto: primeiro é preciso desligar aqui, com uma frase.",
             a.adminActive(), a::setAdmin)
    Spacer(Modifier.height(20.dp))

    a.privateDnsHost()?.let { host ->
        Warning(trf("O “DNS privado” está ligado (%s)", host),
                "Com ele, o Android tenta perguntar os endereços por fora do Magen: ou a internet para, ou os sites adultos passam. Desligue em Configurações › Rede e internet › DNS privado (escolha “Desativado” ou “Automático”).",
                "Abrir as configurações", a::openPrivateDnsSettings, translateTitle = false)
    }

    Section("VPN sempre ativa")
    val always = MagenVpnService.alwaysOn()
    val status = when (always) {
        true -> tr("✅ Ligada: o Android liga o Magen sozinho, até depois de reiniciar.")
        false -> tr("Ainda não está ligada.")
        null -> ""
    }
    if (status.isNotEmpty()) Label(status, 14f, bold = true, color = if (always == true) T.INK else T.RED, translate = false)
    Spacer(Modifier.height(4.dp))
    Label("Nas configurações de VPN, toque na engrenagem do Magen e ligue “VPN sempre ativa”. Assim, se o Magen for fechado, o Android liga de novo. Deixe “Bloquear conexões sem VPN” desligado: com ele, a internet para.",
          13f, color = T.DARK)
    Spacer(Modifier.height(10.dp))
    BoxButton("Abrir as configurações de VPN", a::openVpnSettings, Modifier.fillMaxWidth(), height = 48.dp, size = 12f)
    Spacer(Modifier.height(24.dp))

    Section("Como funciona")
    Label(trf("Para sites normais, o Magen pergunta à Cloudflare (%s). Ele só vê o nome do site, nunca o conteúdo das páginas, por isso não deixa a internet lenta.\n\nA VPN do Magen não leva seus dados para lugar nenhum: ela fica dentro do celular e só recebe as perguntas de endereço.\n\nAs listas de sites adultos se atualizam sozinhas a cada %d horas.",
              cfg.upstream.firstOrNull() ?: "1.1.1.1", cfg.updateEveryHours), 14f, translate = false)
    Spacer(Modifier.height(20.dp))
    BoxButton("Remover o Magen deste celular…", a::remove, Modifier.fillMaxWidth(), height = 56.dp, icon = Icons.Filled.Delete)
}

// ------------------------------------------------------------ Sobre

@Composable
private fun PageAbout(a: MainActivity) {
    val ctx = LocalContext.current
    Wide("MAGEN", 40f)
    Label(trf("“escudo” em hebraico · versão %s", BuildConfig.VERSION_NAME), 14f, bold = true, color = T.RED, translate = false,
          modifier = Modifier.padding(top = 2.dp, bottom = 16.dp))
    Label(trf("Feito por %s, de graça, para quem quer vencer essa luta.", MainActivity.AUTHOR), 16f, bold = true, translate = false)
    Spacer(Modifier.height(8.dp))
    val about = if (I18n.isEn())
        "Free adult-site blocker for Android, Windows and Mac. No account, no ads, no data collected.\n\n" +
        "Block lists: OISD NSFW, Block List Project and StevenBlack (downloaded straight from the source).\n" +
        "Verses: World English Bible (public domain) and Bíblia Livre (CC BY 4.0 Brasil). Font: Archivo, SIL Open Font License. Code: MIT license."
    else "Bloqueador grátis de sites adultos para Android, Windows e Mac. Sem conta, sem anúncios, sem coletar nada.\n\n" +
        "Listas de bloqueio: OISD NSFW, Block List Project e StevenBlack (baixadas direto da fonte).\n" +
        "Versículos: Bíblia Livre (BLIVRE), CC BY 4.0 Brasil, e World English Bible (domínio público). Fonte: Archivo, SIL Open Font License. Código: licença MIT."
    Label(about, 13f, color = T.DARK, translate = false)
    Spacer(Modifier.height(16.dp))
    BoxButton(if (I18n.isEn()) "Support Magen" else "Apoie o Magen (Pix)", { a.popup = Popup.Donation }, Modifier.fillMaxWidth(),
              height = 54.dp, accent = true, icon = Icons.Filled.Favorite, translate = false)
    Spacer(Modifier.height(10.dp))
    BoxButton("Procurar atualização", { a.checkUpdates(manual = true) }, Modifier.fillMaxWidth(), height = 54.dp, icon = Icons.Filled.Refresh)
    Spacer(Modifier.height(14.dp))
    CheckRow("Procurar atualização sozinho",
             "Uma vez por dia, o Magen procura uma versão nova no GitHub e avisa. O Android pergunta antes de instalar.",
             Updates.autoCheckOn(), { Magen.prefs.set("atualizarSozinho", it); a.tick++ })
    Spacer(Modifier.height(16.dp))
    Label("Idioma / Language", 12f, bold = true, color = T.DARK, translate = false)
    Spacer(Modifier.height(8.dp))
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        for ((code, name) in listOf("pt" to "Português", "en" to "English")) {
            BoxButton(name, { a.changeLanguage(code) }, Modifier.weight(1f), height = 42.dp, size = 11f,
                      selected = (code == "en") == I18n.isEn(), translate = false)
        }
        BoxButton("Ver o tour", a::startTour, Modifier.weight(1f), height = 42.dp, size = 11f)
    }
}
