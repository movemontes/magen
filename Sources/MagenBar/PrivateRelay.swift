// Detecta se a Retransmissão Privada do iCloud está ligada.
// Com ela ligada, o Magen bloqueia o caminho dela (para o Safari não passar
// por fora), e aí os apps do Mac (Claude, Grok…) podem ficar sem internet até
// a pessoa responder um aviso do macOS. O certo é desligá-la nos Ajustes.
import AppKit

enum PrivateRelay {
    /// true = ligada, false = desligada, nil = não deu para saber.
    /// Lê a preferência do macOS "com.apple.networkserviceproxy" (só leitura).
    static func isOn() -> Bool? {
        guard let data = CFPreferencesCopyAppValue("NSPServiceStatusManagerInfo" as CFString,
                                                   "com.apple.networkserviceproxy" as CFString) as? Data,
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let objects = plist["$objects"] as? [Any] else { return nil }
        // The main status object is the one that also lists the networks.
        for case let obj as [String: Any] in objects where obj["PrivacyProxyNetworkStatuses"] != nil {
            if let status = obj["PrivacyProxyServiceStatus"] as? Int { return status == 1 }
        }
        return nil
    }

    /// Opens System Settings on the Apple Account page (iCloud is inside it).
    static func openSettings() {
        let urls = ["x-apple.systempreferences:com.apple.systempreferences.AppleIDSettings:icloud",
                    "x-apple.systempreferences:com.apple.systempreferences.AppleIDSettings"]
        for u in urls {
            if let url = URL(string: u), NSWorkspace.shared.open(url) { return }
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }

    static var howTo: String { tr("Ajustes do Sistema › (seu nome) › iCloud › Retransmissão Privada › Desligar.") }
}
