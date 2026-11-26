// Ligar e remover a proteção pelo próprio app (sem Terminal).
// O macOS mostra a janela de senha de administrador dele mesmo.
import AppKit
import MagenCore

enum Service {
    static let daemonPlist = "/Library/LaunchDaemons/io.github.movemontes.magen.plist"
    static var isInstalled: Bool { FileManager.default.fileExists(atPath: daemonPlist) }
    static var busy = false

    private static var scriptsDir: String { (Bundle.main.resourcePath ?? "") + "/servico" }

    /// Text safe inside an AppleScript string literal.
    private static func asString(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// Runs a shell command line as administrator, off the main thread.
    /// `parts` are passed with `quoted form of`, so spaces in paths are fine.
    static func runAsAdmin(_ parts: [String], completion: @escaping (_ ok: Bool, _ canceled: Bool, _ output: String) -> Void) {
        let joined = parts.map { "quoted form of " + asString($0) }.joined(separator: " & \" \" & ")
        let script = "do shell script " + joined + " with administrator privileges"
        busy = true
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = ["-e", script]
            let out = Pipe(), err = Pipe()
            p.standardOutput = out; p.standardError = err
            var ok = false, text = ""
            do {
                try p.run()
                let o = out.fileHandleForReading.readDataToEndOfFile()
                let e = err.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                ok = p.terminationStatus == 0
                text = String(decoding: ok ? o : e, as: UTF8.self)
            } catch { text = error.localizedDescription }
            DispatchQueue.main.async {
                busy = false
                completion(ok, text.contains("-128"), text)
            }
        }
    }

    static func install(completion: @escaping (Bool) -> Void) {
        let pid = String(ProcessInfo.processInfo.processIdentifier)
        runAsAdmin(["/bin/bash", scriptsDir + "/instalar-servico.sh", Bundle.main.bundlePath, "--from-app", pid]) { ok, canceled, out in
            if !ok && !canceled { alert("Não deu para ligar a proteção", out) }
            completion(ok)
        }
    }

    static func uninstall(completion: @escaping (Bool) -> Void) {
        let pid = String(ProcessInfo.processInfo.processIdentifier)
        runAsAdmin(["/bin/bash", scriptsDir + "/desinstalar-servico.sh", "--from-app", pid]) { ok, canceled, out in
            if !ok && !canceled { alert("Não deu para remover", out) }
            completion(ok)
        }
    }

    /// Before turning on: iCloud Private Relay must be off, or some apps lose internet.
    /// Returns false if the person chose to stop.
    static func relayCheckBeforeInstall() -> Bool {
        while PrivateRelay.isOn() == true {
            let a = NSAlert()
            a.alertStyle = .warning
            a.messageText = "Antes, desligue a Retransmissão Privada do iCloud"
            a.informativeText = "Com ela ligada, apps como o Claude e o Gmail podem ficar sem internet quando o Magen está ativo.\n\nDesligue em: " + PrivateRelay.howTo + "\n\nDepois volte aqui e clique em “Já desliguei”."
            a.addButton(withTitle: "Abrir Ajustes")
            a.addButton(withTitle: "Já desliguei")
            a.addButton(withTitle: "Continuar mesmo assim")
            NSApp.activate(ignoringOtherApps: true)
            switch a.runModal() {
            case .alertFirstButtonReturn: PrivateRelay.openSettings()
            case .alertSecondButtonReturn: continue
            default: return true
            }
        }
        return true
    }

    /// Removing the protection is hard on purpose: a sentence + the Mac password.
    static let removeSentence = "quero remover a proteção"
    static func confirmRemoval() -> Bool {
        let a = NSAlert()
        a.alertStyle = .critical
        a.messageText = "Remover o Magen deste Mac?"
        a.informativeText = """
        Sem o Magen, os sites adultos voltam a abrir. Se for um momento de tentação, feche esta janela, respire e faça outra coisa.

        Se tiver certeza, digite exatamente:
        \(removeSentence)
        """
        a.addButton(withTitle: "Desistir")
        a.addButton(withTitle: "Remover")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.placeholderString = removeSentence
        a.accessoryView = field
        a.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        guard a.runModal() == .alertSecondButtonReturn else { return false }
        return field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == removeSentence
    }

    static func alert(_ title: String, _ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.runModal()
    }
}
