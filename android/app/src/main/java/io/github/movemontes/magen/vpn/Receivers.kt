package io.github.movemontes.magen.vpn

import android.app.admin.DeviceAdminReceiver
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.VpnService
import io.github.movemontes.magen.Magen
import io.github.movemontes.magen.tr

/** Depois de reiniciar o celular (ou de atualizar o Magen), liga a proteção de novo. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (!Magen.prefs.bool("protecaoLigada", false)) return
        // Só dá para ligar sozinho se a permissão de VPN continua dada.
        if (VpnService.prepare(context) != null) return
        runCatching { MagenVpnService.start(context) }
    }
}

/**
 * "Dificultar a desinstalação". Enquanto isto estiver ativo, o Android não deixa desinstalar o
 * Magen direto: primeiro é preciso desativar aqui. Não impede tudo (quem sabe o caminho desativa),
 * mas tira o "desinstalar em dois toques" de um momento de fraqueza.
 */
class AdminReceiver : DeviceAdminReceiver() {
    override fun onDisableRequested(context: Context, intent: Intent): CharSequence =
        tr("Para remover o Magen, use o botão “Remover” dentro do app, na aba Proteção. Ele pede uma frase, de propósito.")

    companion object {
        fun component(ctx: Context) = ComponentName(ctx, AdminReceiver::class.java)
    }
}
