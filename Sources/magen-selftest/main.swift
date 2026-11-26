// Quick self-test of the blocking rules (no network, no root needed).
import Foundation
import MagenCore

var failures = 0
func check(_ cond: Bool, _ msg: String) {
    print((cond ? "ok   " : "FALHA ") + msg)
    if !cond { failures += 1 }
}

// List parsing
check(Domains.normalize("0.0.0.0 Example.COM # c") == "example.com", "linha de hosts")
check(Domains.normalize("*.adult.test") == "adult.test", "curinga *.")
check(Domains.normalize("||ads.adult.test^") == "ads.adult.test", "estilo adblock")
check(Domains.normalize("# comentário") == nil, "comentário ignorado")
check(Domains.normalize("localhost") == nil, "localhost ignorado")
check(Domains.normalize("127.0.0.1 localhost") == nil, "linha localhost ignorada")
check(Domains.normalize("1.2.3.4") == nil, "IP ignorado")

// Matching
var cfg = MagenConfig()
cfg.allow = ["liberado.adult.test"]
cfg.block = ["extra.test"]
let f = Filter()
f.rebuild(listDomains: ["adult.test", "com.br", "google.com", "blog.tumblr.com"], config: cfg)
check(f.isBlocked("adult.test"), "domínio da lista")
check(f.isBlocked("www.cdn.adult.test"), "subdomínio da lista")
check(!f.isBlocked("notadult.test"), "nome parecido não é bloqueado")
check(!f.isBlocked("liberado.adult.test"), "liberado pela pessoa")
check(f.isBlocked("extra.test"), "bloqueio extra da pessoa")
check(!f.isBlocked("globo.com.br"), "entrada perigosa com.br ignorada")
check(!f.isBlocked("www.google.com"), "google.com nunca vira bloqueio")
check(f.isBlocked("blog.tumblr.com"), "subdomínio adulto de site grande é bloqueado")
check(!f.isBlocked("www.tumblr.com"), "resto do site grande funciona")
check(f.isBlocked("use-application-dns.net"), "anti-burla Firefox")
check(f.isBlocked("mask.icloud.com"), "anti-burla Retransmissão Privada")
check(!f.isBlocked("www.icloud.com"), "iCloud normal funciona")
check(f.isBlocked("ADULT.TEST."), "maiúsculas e ponto final")

// DNS messages
let q = DNSMessage.buildQuery(id: 0x1234, name: "Www.Adult.Test")
let pq = DNSMessage.parseQuery(q)
check(pq?.nameString == "www.adult.test" && pq?.qtype == 1, "lê a pergunta DNS")
if let pq {
    let r = DNSMessage.blockedResponse(query: q, question: pq)
    check(r[0] == 0x12 && r[1] == 0x34 && DNSMessage.rcode(r) == 3 && r[2] & 0x80 != 0, "resposta NXDOMAIN")
}
check(DNSMessage.parseQuery([0, 1, 2]) == nil, "mensagem quebrada ignorada")

print(failures == 0 ? "\nTudo certo." : "\n\(failures) falha(s).")
exit(failures == 0 ? 0 : 1)
