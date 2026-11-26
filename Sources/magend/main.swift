// magend — the Magen background service.
// It answers the Mac's DNS questions on 127.0.0.1:53 and says
// "does not exist" for adult sites.
import Foundation
import Darwin
import notify
import MagenCore

setvbuf(stdout, nil, _IOLBF, 0)

func log(_ s: String) {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm:ss"
    print("[\(f.string(from: Date()))] \(s)")
}

// ---------- options ----------
var dir = Paths.defaultDir
var listenIP = "127.0.0.1"
var port: UInt16 = 53
var manageSystemDNS = true
var allowUpdates = true
var it = CommandLine.arguments.dropFirst().makeIterator()
while let a = it.next() {
    switch a {
    case "--dir": dir = URL(fileURLWithPath: it.next() ?? dir.path)
    case "--port": port = UInt16(it.next() ?? "") ?? port
    case "--listen": listenIP = it.next() ?? listenIP
    case "--no-system-dns": manageSystemDNS = false
    case "--no-update": allowUpdates = false
    default: log("Opção desconhecida: \(a)")
    }
}

try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
var config = MagenConfig.load(from: Paths.config(dir))
if !FileManager.default.fileExists(atPath: Paths.config(dir).path) { try? config.save(to: Paths.config(dir)) }

let filter = Filter()
let server = DNSServer(filter: filter, upstream: config.upstream)
var state = MagenState()
state.startedAt = Date()
if let d = try? Data(contentsOf: Paths.state(dir)), let s = try? JSONDecoder.iso.decode(MagenState.self, from: d) {
    state.lastUpdate = s.lastUpdate
    state.lists = s.lists
    state.blockedTotal = s.blockedTotal
    state.blockedToday = s.blockedToday
    state.todayKey = s.todayKey
    state.lastBlockAt = s.lastBlockAt
}

func todayKey() -> String {
    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: Date())
}

// Count adult-site blocks and tell the menu bar icon (at most once per second;
// one page usually asks for several addresses at once).
var lastSignal = Date.distantPast
server.onAdultBlock = {
    stateLock.lock()
    let key = todayKey()
    if state.todayKey != key { state.todayKey = key; state.blockedToday = 0 }
    state.blockedTotal += 1
    state.blockedToday += 1
    state.lastBlockAt = Date()
    let shouldSignal = Date().timeIntervalSince(lastSignal) >= 1
    if shouldSignal { lastSignal = Date() }
    stateLock.unlock()
    if shouldSignal {
        writeState()
        notify_post(Signals.blocked)
    }
}
let stateLock = NSLock()

func writeState() {
    stateLock.lock(); defer { stateLock.unlock() }
    state.domains = filter.count
    state.blockedSinceStart = server.blockedCount
    if let data = try? JSONEncoder.iso.encode(state) { try? data.write(to: Paths.state(dir), options: .atomic) }
}

// ---------- blocklists ----------
/// Domains saved by the last successful update (empty if none yet).
func readCache() -> [String] {
    guard let text = try? String(contentsOf: Paths.cache(dir), encoding: .utf8) else { return [] }
    return text.split(separator: "\n").map(String.init)
}

var hasCache = false
func loadCache() {
    let domains = readCache()
    hasCache = !domains.isEmpty
    filter.rebuild(listDomains: domains, config: config)
    log("Listas carregadas do disco: \(filter.count) domínios bloqueados.")
}

func download(_ url: String) -> String? {
    guard let u = URL(string: url) else { return nil }
    var req = URLRequest(url: u, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 120)
    req.setValue("Magen-blocker/0.1", forHTTPHeaderField: "User-Agent")
    let sem = DispatchSemaphore(value: 0)
    var result: String?
    URLSession.shared.dataTask(with: req) { data, resp, _ in
        if let data, (resp as? HTTPURLResponse)?.statusCode == 200 { result = String(decoding: data, as: UTF8.self) }
        sem.signal()
    }.resume()
    sem.wait()
    return result
}

let updateQueue = DispatchQueue(label: "magen.update")
func updateLists(reason: String) {
    updateQueue.async { doUpdate(reason: reason) }
}

func doUpdate(reason: String) {
    autoreleasepool {
        log("Atualizando listas (\(reason))…")
        var all = Set<String>()
        var results = [MagenState.ListResult]()
        var anyOK = false
        for url in config.lists {
            guard let text = download(url) else {
                log("  falhou: \(url)")
                results.append(MagenState.ListResult(url: url, ok: false, count: 0)); continue
            }
            let domains = Filter.parseList(text)
            // A real list has many thousands of sites. A tiny one is probably an error page.
            if domains.count < 1000 {
                log("  ignorada (só \(domains.count) linhas válidas): \(url)")
                results.append(MagenState.ListResult(url: url, ok: false, count: domains.count)); continue
            }
            anyOK = true
            all.formUnion(domains)
            results.append(MagenState.ListResult(url: url, ok: true, count: domains.count))
            log("  ok: \(domains.count) domínios de \(url)")
        }
        guard anyOK else { log("Nenhuma lista baixou; mantendo as listas antigas."); return }
        let sorted = all.sorted()
        try? (sorted.joined(separator: "\n") + "\n").write(to: Paths.cache(dir), atomically: true, encoding: .utf8)
        hasCache = true
        filter.rebuild(listDomains: sorted, config: config)
        stateLock.lock(); state.lastUpdate = Date(); state.lists = results; stateLock.unlock()
        writeState()
        log("Pronto: \(filter.count) domínios bloqueados.")
    }
}

func listsAreOld() -> Bool {
    guard let last = state.lastUpdate else { return true }
    return Date().timeIntervalSince(last) > config.updateEveryHours * 3600
}

// ---------- start ----------
loadCache()
do {
    try server.startUDP(ip: listenIP, port: port)
    try server.startTCP(ip: listenIP, port: port)
} catch {
    log("Não consegui abrir a porta \(port): \(error.localizedDescription)")
    log("Não mexi no DNS do Mac. Saindo.")
    exit(1)
}
log("Magen ouvindo em \(listenIP):\(port). Servidores de verdade: \(config.upstream.joined(separator: ", "))")
try? "\(getpid())\n".write(to: Paths.pid(dir), atomically: true, encoding: .utf8)

let systemDNS = SystemDNS(savedFile: Paths.savedDNS(dir))
if manageSystemDNS {
    let changed = systemDNS.enforce()
    if !changed.isEmpty { log("DNS do Mac apontado para o Magen em: \(changed.joined(separator: ", "))") }
}
writeState()

// Every 30 s: keep the Mac pointed at Magen, save counters, update lists when old.
let ticker = DispatchSource.makeTimerSource(queue: .global())
ticker.schedule(deadline: .now() + 30, repeating: 30)
var ticks = 0
ticker.setEventHandler {
    // Unblock requests whose 1-hour wait is over.
    updateQueue.async {
        var c = MagenConfig.load(from: Paths.config(dir))
        let moved = Unblock.applyDue(&c)
        guard !moved.isEmpty else { return }
        try? c.save(to: Paths.config(dir))
        config = c
        filter.rebuild(listDomains: readCache(), config: config)
        log("Liberado(s) depois da espera: \(moved.joined(separator: ", "))")
    }
    if manageSystemDNS {
        let changed = systemDNS.enforce()
        if !changed.isEmpty { log("DNS tinha sido mudado; apontei de novo para o Magen em: \(changed.joined(separator: ", "))") }
    }
    writeState()
    let fails = server.takeFailureCounts()
    if fails.failed > 0 || fails.dropped > 0 {
        log("Atenção: nos últimos 30 s, \(fails.failed) perguntas ficaram sem resposta de \(config.upstream.joined(separator: "/")) e \(fails.dropped) foram descartadas por excesso. (Internet fora do ar?)")
    }
    ticks += 1
    if allowUpdates && ticks % 20 == 0 && listsAreOld() { updateLists(reason: "agendada") }
}
ticker.resume()
if allowUpdates && (listsAreOld() || !hasCache) { updateLists(reason: "início") }

// ---------- signals ----------
var sources = [DispatchSourceSignal]()
func onSignal(_ sig: Int32, _ handler: @escaping () -> Void) {
    signal(sig, SIG_IGN)
    let s = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    s.setEventHandler(handler: handler)
    s.resume()
    sources.append(s)
}
// Stop: put the Mac's DNS back, so the internet never breaks with Magen off.
let stop = {
    log("Parando. Devolvendo o DNS original do Mac.")
    if manageSystemDNS { systemDNS.restore() }
    writeState()
    try? FileManager.default.removeItem(at: Paths.pid(dir))
    exit(0)
}
onSignal(SIGTERM, stop)
onSignal(SIGINT, stop)
// Reload settings (after `magen liberar` / `magen bloquear`).
onSignal(SIGHUP) {
    updateQueue.async { // same queue as list updates, so they never clash
        config = MagenConfig.load(from: Paths.config(dir))
        server.upstream = config.upstream
        autoreleasepool { filter.rebuild(listDomains: readCache(), config: config) }
        writeState()
        log("Configuração recarregada: \(filter.count) domínios bloqueados.")
    }
}
// Update lists now (`magen atualizar`).
onSignal(SIGUSR1) { if allowUpdates { updateLists(reason: "pedida") } }
// Same, asked by the menu bar icon. Anyone may ask, so at most once per 5 minutes.
var lastUpdateRequest = Date.distantPast
var updateToken: Int32 = 0
notify_register_dispatch(Signals.updateRequest, &updateToken, DispatchQueue.main) { _ in
    guard allowUpdates, Date().timeIntervalSince(lastUpdateRequest) > 300 else { return }
    lastUpdateRequest = Date()
    updateLists(reason: "pedida pelo ícone")
}

dispatchMain()

extension JSONEncoder {
    static var iso: JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = .prettyPrinted; return e }
}
extension JSONDecoder {
    static var iso: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }
}
