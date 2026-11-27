"""Núcleo do Magen para Windows: configuração, listas, filtro e mensagens DNS.

É a mesma lógica do Mac (Sources/MagenCore), escrita em Python. Os arquivos
config.json e state.json têm o mesmo formato nos dois sistemas.
"""
import array
import bisect
import hashlib
import json
import os
import sys
import threading
from datetime import datetime, timezone

WINDOWS = sys.platform == "win32"

# ---------------------------------------------------------------- pastas

def data_dir():
    """Pasta do serviço (só o administrador escreve; todos leem)."""
    if os.environ.get("MAGEN_DIR"):
        return os.environ["MAGEN_DIR"]
    if WINDOWS:
        return os.path.join(os.environ.get("PROGRAMDATA", r"C:\ProgramData"), "Magen")
    return os.path.expanduser("~/.magen-windows-teste")  # só para testar no Mac


def config_path(d=None): return os.path.join(d or data_dir(), "config.json")
def state_path(d=None): return os.path.join(d or data_dir(), "state.json")
def cache_path(d=None): return os.path.join(d or data_dir(), "blocklist-cache.txt")
def hashes_path(d=None): return os.path.join(d or data_dir(), "blocklist-hashes.bin")
def saved_dns_path(d=None): return os.path.join(d or data_dir(), "dns-anterior.json")
def log_path(d=None): return os.path.join(d or data_dir(), "magen.log")


# Portas locais para o serviço e o app conversarem (no Mac são "notificações Darwin").
DNS_PORT = int(os.environ.get("MAGEN_PORT", "53"))
CONTROL_PORT = int(os.environ.get("MAGEN_CONTROL_PORT", "53530"))  # o serviço ouve: "reload", "update"
APP_PORT = int(os.environ.get("MAGEN_APP_PORT", "53531"))          # o app ouve: "blocked", "show"


def send_local(port, message):
    """Manda um recado curto para outro programa do Magen neste computador."""
    import socket
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.sendto(message.encode(), ("127.0.0.1", port))
        return True
    except OSError:
        return False


# ---------------------------------------------------------------- datas

def now():
    return datetime.now(timezone.utc)


def iso(dt):
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ") if dt else None


def parse_iso(s):
    if not s:
        return None
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00"))
    except ValueError:
        return None


def today_key():
    return datetime.now().strftime("%Y-%m-%d")


# ---------------------------------------------------------------- configuração

DEFAULT_LISTS = [
    "https://nsfw.oisd.nl/domainswild2",
    "https://blocklistproject.github.io/Lists/alt-version/porn-nl.txt",
    "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/porn-only/hosts",
]

DEFAULT_CONFIG = {
    "upstream": ["1.1.1.1", "1.0.0.1", "9.9.9.9"],
    "lists": DEFAULT_LISTS,
    "allow": [],
    "pendingAllow": [],      # [{"domain": "...", "at": "2026-11-27T10:00:00Z"}]
    "block": [],
    "antiBypass": True,
    "blockPrivateRelay": True,  # só existe no Mac; fica para o arquivo ser igual
    "updateEveryHours": 24,
}


def load_config(d=None):
    cfg = json.loads(json.dumps(DEFAULT_CONFIG))
    try:
        with open(config_path(d), encoding="utf-8") as f:
            saved = json.load(f)
        if isinstance(saved, dict):
            for k in cfg:
                if k in saved:
                    cfg[k] = saved[k]
    except (OSError, ValueError):
        pass
    return cfg


def save_config(cfg, d=None):
    write_json(config_path(d), cfg)


def write_json(path, data):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, sort_keys=True, ensure_ascii=False)
    os.replace(tmp, path)


def load_state(d=None):
    try:
        with open(state_path(d), encoding="utf-8") as f:
            s = json.load(f)
            return s if isinstance(s, dict) else {}
    except (OSError, ValueError):
        return {}


# ---------------------------------------------------------------- regras fixas

NEVER_LIST_ENTRIES = {
    # sufixos públicos de várias partes
    "com.br", "net.br", "org.br", "gov.br", "edu.br", "art.br", "blog.br", "co.uk", "org.uk",
    "com.au", "co.jp", "co.nz", "com.mx", "com.ar", "com.pt", "co.za", "co.in", "com.tr",
    # plataformas grandes e hospedagem compartilhada
    "google.com", "google.com.br", "youtube.com", "googlevideo.com", "gstatic.com",
    "googleapis.com", "googleusercontent.com", "ggpht.com", "ytimg.com",
    "apple.com", "icloud.com", "mzstatic.com", "microsoft.com", "live.com", "bing.com",
    "facebook.com", "fbcdn.net", "instagram.com", "cdninstagram.com", "whatsapp.com", "whatsapp.net",
    "twitter.com", "x.com", "twimg.com", "t.co", "reddit.com", "redd.it", "redditmedia.com",
    "tumblr.com", "imgur.com", "discord.com", "discordapp.com", "discord.gg", "tiktok.com",
    "amazon.com", "amazon.com.br", "amazonaws.com", "cloudfront.net", "akamaihd.net",
    "akamaized.net", "fastly.net", "cloudflare.com", "cloudflare.net", "github.com", "github.io",
    "githubusercontent.com", "gitlab.io", "blogspot.com", "blogger.com", "wordpress.com",
    "wp.com", "medium.com", "wikipedia.org", "wikimedia.org", "telegram.org", "t.me",
    "globo.com", "uol.com.br", "netflix.com", "spotify.com", "bit.ly", "linktr.ee",
    "dropbox.com", "vercel.app", "netlify.app", "pages.dev", "herokuapp.com",
    # bloqueados por engano nos 2.000 sites mais visitados (nov. 2026)
    "xiaohongshu.com", "ekstrabladet.dk", "suruga-ya.jp", "character.ai", "gotinder.com",
    "tinder.com", "sslip.io", "nip.io",
    # Windows: endereços que o sistema usa para saber se há internet e para se atualizar
    "msftconnecttest.com", "msftncsi.com", "windowsupdate.com", "windows.com",
}

ANTI_BYPASS_DOMAINS = [
    # Firefox: este domínio "canário" diz para ele não ligar o DNS-over-HTTPS sozinho
    "use-application-dns.net",
    # Servidores comuns de "DNS seguro" (DNS-over-HTTPS / TLS) dos navegadores
    "dns.google", "dns.google.com", "dns64.dns.google",
    "cloudflare-dns.com", "one.one.one.one", "1dot1dot1dot1.cloudflare-dns.com",
    "dns.quad9.net", "dns9.quad9.net", "dns10.quad9.net", "dns11.quad9.net", "dns12.quad9.net",
    "doh.opendns.com", "dns.opendns.com", "doh.familyshield.opendns.com",
    "dns.adguard.com", "dns.adguard-dns.com", "dns-unfiltered.adguard.com",
    "dns.nextdns.io", "doh.cleanbrowsing.org", "doh.mullvad.net", "dns.mullvad.net",
    "doh.dns.sb", "dns.controld.com", "freedns.controld.com", "doh.libredns.gr",
    "dns.alidns.com", "doh.pub", "dns.twnic.tw", "chrome.cloudflare-dns.com",
    "mozilla.cloudflare-dns.com", "doh.xfinity.com", "dns.brahma.world",
]

PRIVATE_RELAY_DOMAINS = ["mask.icloud.com", "mask-h2.icloud.com"]


# ---------------------------------------------------------------- liberar é difícil de propósito

UNBLOCK_DELAY = 60 * 60
UNBLOCK_SENTENCE = {"pt": "este site não é pornográfico", "en": "this site is not pornographic"}
REMOVE_SENTENCE = {"pt": "quero remover a proteção", "en": "i want to remove the protection"}
ADULT_WORDS = ["porn", "xxx", "xvideo", "xnxx", "hentai", "onlyfans", "xhamster", "redtube",
               "youporn", "brazzers", "chaturbate", "spankbang", "stripchat", "camsoda",
               "bongacams", "livejasmin", "fansly", "rule34", "nhentai", "pornhub", "erome"]


def is_obviously_adult(domain):
    d = domain.lower()
    return any(w in d for w in ADULT_WORDS)


def apply_due(cfg, when=None):
    """Passa os sites cuja espera acabou de "pendingAllow" para "allow". Devolve os passados."""
    when = when or now()
    due, keep = [], []
    for p in cfg.get("pendingAllow", []):
        at = parse_iso(p.get("at"))
        (due if at and at <= when else keep).append(p)
    if not due:
        return []
    cfg["pendingAllow"] = keep
    moved = []
    for p in due:
        d = p.get("domain", "")
        if d and d not in cfg["allow"]:
            cfg["allow"].append(d)
        moved.append(d)
    return moved


# ---------------------------------------------------------------- domínios

_OK = set("abcdefghijklmnopqrstuvwxyz0123456789-._")
_HOST_PREFIXES = {"0.0.0.0", "127.0.0.1", "::", "::1", "0", "fe80::1%lo0"}


def normalize(raw):
    """Uma linha de lista (hosts, domínio puro, "*." ou "||dominio^") vira um domínio limpo, ou None."""
    line = raw.split("#", 1)[0].lstrip(" \t")
    if not line or line[0] in "![" or line.startswith("@@"):
        return None
    if line.startswith("||"):
        line = line[2:]
        for i, ch in enumerate(line):
            if ch in "^/$":
                line = line[:i]
                break
    parts = line.split()
    if not parts:
        return None
    token = parts[0]
    if token in _HOST_PREFIXES:
        if len(parts) < 2:
            return None
        token = parts[1]
    d = token.lower()
    while d.startswith("*."):
        d = d[2:]
    d = d.strip(".")
    if "." not in d or len(d) > 253 or not set(d) <= _OK:
        return None
    if all(p.isdigit() for p in d.split(".")):
        return None  # endereço IP
    return d


def clean_site(text):
    """O que a pessoa digitou ("https://www.x.com/pagina") vira "www.x.com", ou None."""
    t = text.strip().lower()
    for p in ("https://", "http://"):
        if t.startswith(p):
            t = t[len(p):]
    t = t.split("/", 1)[0]
    return normalize(t)


def h64(name):
    """Resumo de 64 bits de um nome (rápido, feito em C)."""
    if isinstance(name, str):
        name = name.encode()
    return int.from_bytes(hashlib.blake2b(name, digest_size=8).digest(), "little")


class DomainSet:
    """Conjunto compacto: só os resumos ordenados (8 bytes por site, ~9 MB para 1,1 milhão)."""

    def __init__(self, domains=(), hashes=None):
        if hashes is None:
            hashes = array.array("Q", sorted({h64(d) for d in domains}))
        self.hashes = hashes

    def __len__(self):
        return len(self.hashes)

    def has_hash(self, h):
        a = self.hashes
        i = bisect.bisect_left(a, h)
        return i < len(a) and a[i] == h

    def matches(self, name):
        """True se o nome ou um domínio acima dele (menos o final ".com") está no conjunto."""
        if not self.hashes or not name:
            return False
        while "." in name:
            if self.has_hash(h64(name)):
                return True
            name = name.split(".", 1)[1]
        return False

    def save(self, path):
        tmp = path + ".tmp"
        with open(tmp, "wb") as f:
            self.hashes.tofile(f)
        os.replace(tmp, path)

    @classmethod
    def load(cls, path):
        a = array.array("Q")
        try:
            with open(path, "rb") as f:
                a.frombytes(f.read())
        except OSError:
            pass
        return cls(hashes=a)


def parse_list(text):
    out = []
    for line in text.splitlines():
        d = normalize(line)
        if d:
            out.append(d)
    return out


ALLOWED, BLOCKED, BLOCKED_BYPASS = "allowed", "blocked", "bypass"


class Filter:
    """Decide se um nome está bloqueado. A lista "liberados" da pessoa ganha de tudo."""

    def __init__(self):
        self.lock = threading.Lock()
        self.lists = DomainSet()   # vindo das listas baixadas (pode ser enorme)
        self.extra = DomainSet()   # "bloqueados a mais" da pessoa
        self.allow = DomainSet()
        self.bypass = DomainSet()

    def set_lists(self, ds):
        with self.lock:
            self.lists = ds

    def apply_config(self, cfg):
        extra = DomainSet(filter(None, (normalize(d) for d in cfg.get("block", []))))
        allow = DomainSet(filter(None, (normalize(d) for d in cfg.get("allow", []))))
        bypass = list(ANTI_BYPASS_DOMAINS) if cfg.get("antiBypass", True) else []
        if cfg.get("blockPrivateRelay", True):
            bypass += PRIVATE_RELAY_DOMAINS
        with self.lock:
            self.extra, self.allow, self.bypass = extra, allow, DomainSet(bypass)

    @property
    def count(self):
        with self.lock:
            return len(self.lists) + len(self.extra) + len(self.bypass)

    def verdict(self, name):
        name = name.lower().rstrip(".")
        with self.lock:
            lists, extra, allow, bypass = self.lists, self.extra, self.allow, self.bypass
        if allow.matches(name):
            return ALLOWED
        if bypass.matches(name):
            return BLOCKED_BYPASS
        if extra.matches(name) or lists.matches(name):
            return BLOCKED
        return ALLOWED


def build_list_set(domains):
    """Listas baixadas → conjunto, já sem os domínios que nunca podem vir de uma lista."""
    return DomainSet(d for d in domains if d not in NEVER_LIST_ENTRIES)


# ---------------------------------------------------------------- mensagens DNS

def parse_query(msg):
    """Lê a primeira pergunta de uma consulta DNS. Devolve (nome, tipo, fim) ou None."""
    if len(msg) < 12 or msg[2] & 0x80:  # curta demais, ou é uma resposta
        return None
    if (msg[4] << 8 | msg[5]) < 1:
        return None
    i, labels = 12, []
    while True:
        if i >= len(msg):
            return None
        n = msg[i]
        if n == 0:
            i += 1
            break
        if n & 0xC0 or n > 63 or i + 1 + n > len(msg):
            return None
        labels.append(bytes(msg[i + 1:i + 1 + n]).decode("ascii", "replace").lower())
        i += 1 + n
        if sum(len(x) + 1 for x in labels) > 254:
            return None
    if i + 4 > len(msg):
        return None
    return ".".join(labels), msg[i] << 8 | msg[i + 1], i + 4


def blocked_response(query, end, rcode=3):
    """Resposta "este endereço não existe" (NXDOMAIN; rcode=2 é SERVFAIL)."""
    r = bytearray(query[:end])
    r[2] = 0x80 | (query[2] & 0x78) | (query[2] & 0x01)
    r[3] = 0x80 | rcode
    r[4:12] = b"\x00\x01\x00\x00\x00\x00\x00\x00"
    return bytes(r)


def build_query(name, qid=None, qtype=1):
    import random
    qid = random.randint(1, 65000) if qid is None else qid
    m = bytearray([qid >> 8, qid & 0xFF, 0x01, 0x00, 0, 1, 0, 0, 0, 0, 0, 0])
    for label in name.split("."):
        b = label.encode()
        m.append(len(b))
        m += b
    m += bytes([0, qtype >> 8, qtype & 0xFF, 0, 1])
    return bytes(m)


def rcode(resp):
    return resp[3] & 0x0F if len(resp) >= 4 else None


def answer_count(resp):
    return resp[6] << 8 | resp[7] if len(resp) >= 8 else 0


def dns_check(name, port=None, timeout=4):
    """Pergunta direto ao Magen. True = bloqueado, False = liberado, None = sem resposta."""
    import socket
    q = build_query(name)
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.settimeout(timeout)
            s.sendto(q, ("127.0.0.1", port or DNS_PORT))
            r, _ = s.recvfrom(4096)
    except OSError:
        return None
    return rcode(r) == 3 and answer_count(r) == 0
