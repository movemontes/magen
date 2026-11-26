// magen — simple command to see and control the Magen blocker.
import Foundation
import Darwin
import MagenCore

var args = Array(CommandLine.arguments.dropFirst())
var dir = Paths.defaultDir
var port: UInt16 = 53
if let i = args.firstIndex(of: "--dir"), i + 1 < args.count { dir = URL(fileURLWithPath: args[i + 1]); args.removeSubrange(i...(i + 1)) }
if let i = args.firstIndex(of: "--port"), i + 1 < args.count { port = UInt16(args[i + 1]) ?? 53; args.removeSubrange(i...(i + 1)) }

func help() {
    print("""
    Magen — bloqueador de conteúdo adulto

      magen status              mostra se está ligado e quantos sites bloqueia
      magen testar <site>       diz se um site está bloqueado
      magen liberar <site>      desbloqueia um site (bloqueio errado)
      magen desfazer <site>     tira o site da lista de liberados
      magen bloquear <site>     bloqueia um site a mais
      magen atualizar           baixa as listas novas agora

    Os comandos que mudam algo precisam de "sudo" (senha de administrador).
    """)
}

func daemonPID() -> pid_t? {
    guard let s = try? String(contentsOf: Paths.pid(dir), encoding: .utf8),
          let p = pid_t(s.trimmingCharacters(in: .whitespacesAndNewlines)), kill(p, 0) == 0 || errno == EPERM else { return nil }
    return p
}

func signalDaemon(_ sig: Int32) -> Bool {
    guard let p = daemonPID() else { print("O Magen não parece estar rodando."); return false }
    if kill(p, sig) != 0 { print("Não consegui avisar o Magen (use sudo)."); return false }
    return true
}

func cleanSite(_ s: String) -> String? {
    var t = s.lowercased()
    for prefix in ["https://", "http://"] where t.hasPrefix(prefix) { t.removeFirst(prefix.count) }
    if let slash = t.firstIndex(of: "/") { t = String(t[..<slash]) }
    return Domains.normalize(Substring(t))
}

/// Asks the Magen server directly and reads the answer.
func query(_ name: String) -> [UInt8]? {
    let q = DNSMessage.buildQuery(id: UInt16.random(in: 1...65000), name: name)
    var a = sockaddr_in()
    a.sin_len = UInt8(MemoryLayout<sockaddr_in>.size); a.sin_family = sa_family_t(AF_INET); a.sin_port = port.bigEndian
    inet_pton(AF_INET, "127.0.0.1", &a.sin_addr)
    let fd = socket(AF_INET, SOCK_DGRAM, 0); defer { close(fd) }
    var tv = timeval(tv_sec: 4, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    let sent = withUnsafePointer(to: &a) { p in p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sp in
        q.withUnsafeBytes { sendto(fd, $0.baseAddress, q.count, 0, sp, socklen_t(MemoryLayout<sockaddr_in>.size)) } } }
    guard sent == q.count else { return nil }
    var buf = [UInt8](repeating: 0, count: 4096)
    let n = buf.withUnsafeMutableBytes { recv(fd, $0.baseAddress, 4096, 0) }
    return n > 0 ? Array(buf[0..<n]) : nil
}

func editConfig(_ change: (inout MagenConfig) -> Void) {
    var cfg = MagenConfig.load(from: Paths.config(dir))
    change(&cfg)
    do { try cfg.save(to: Paths.config(dir)) } catch {
        print("Não consegui salvar a configuração. Tente com sudo na frente do comando."); exit(1)
    }
    if signalDaemon(SIGHUP) { print("Feito. O Magen já está usando a nova configuração.") }
}

guard let cmd = args.first else { help(); exit(0) }
let site = args.count > 1 ? cleanSite(args[1]) : nil

switch cmd {
case "status":
    let on = daemonPID() != nil
    print(on ? "✅ Magen está LIGADO." : "⚠️  Magen está DESLIGADO.")
    if let d = try? Data(contentsOf: Paths.state(dir)) {
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        if let s = try? dec.decode(MagenState.self, from: d) {
            print("Sites bloqueados na lista: \(s.domains.formatted())")
            if let u = s.lastUpdate { print("Listas atualizadas em: \(u.formatted(date: .abbreviated, time: .shortened))") }
            if on { print("Bloqueios desde que ligou: \(s.blockedSinceStart.formatted())") }
            for l in s.lists { print("  \(l.ok ? "ok " : "erro") \(l.count.formatted()) — \(l.url)") }
        }
    }
case "testar":
    guard let s = site else { print("Diga o site. Exemplo: magen testar exemplo.com"); exit(1) }
    guard let r = query(s) else { print("O Magen não respondeu. Ele está ligado?"); exit(2) }
    switch DNSMessage.rcode(r) {
    case 3 where DNSMessage.answerCount(r) == 0:
        // NXDOMAIN could also be a site that really doesn't exist; check the filter rules too.
        print("🚫 \(s) está BLOQUEADO (ou não existe).")
    case 0: print("✅ \(s) está liberado.")
    default: print("❓ Resposta estranha para \(s) (código \(DNSMessage.rcode(r) ?? -1)).")
    }
case "liberar":
    guard let s = site else { print("Diga o site. Exemplo: magen liberar exemplo.com"); exit(1) }
    editConfig { c in if !c.allow.contains(s) { c.allow.append(s) }; c.block.removeAll { $0 == s } }
case "desfazer":
    guard let s = site else { print("Diga o site."); exit(1) }
    editConfig { c in c.allow.removeAll { $0 == s } }
case "bloquear":
    guard let s = site else { print("Diga o site. Exemplo: magen bloquear exemplo.com"); exit(1) }
    editConfig { c in if !c.block.contains(s) { c.block.append(s) }; c.allow.removeAll { $0 == s } }
case "atualizar":
    if signalDaemon(SIGUSR1) { print("Pedido enviado. As listas novas chegam em 1 ou 2 minutos (veja com: magen status).") }
default:
    help()
}
