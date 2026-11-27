"""O "porteiro": responde as perguntas de DNS do computador em 127.0.0.1:53 (e ::1).

Site adulto → "não existe". O resto → pergunta à Cloudflare e devolve a resposta.
Mesmo comportamento do Mac (Sources/magend/Server.swift): cache de 30 s, segunda
tentativa, resposta antiga (até 1 dia) quando a internet falha, e no máximo 48
perguntas ao mesmo tempo.
"""
import socket
import threading
import time
from concurrent.futures import ThreadPoolExecutor

from . import core


def _udp_exchange(query, server, timeout=1.0):
    fam = socket.AF_INET6 if ":" in server else socket.AF_INET
    try:
        with socket.socket(fam, socket.SOCK_DGRAM) as s:
            s.settimeout(timeout)
            s.sendto(query, (server, 53))
            deadline = time.monotonic() + timeout
            while time.monotonic() < deadline:
                r, _ = s.recvfrom(65535)
                if len(r) >= 12 and r[:2] == query[:2]:  # só a resposta da nossa pergunta
                    return r
    except OSError:
        return None
    return None


def _read_exactly(conn, n):
    buf = bytearray()
    while len(buf) < n:
        chunk = conn.recv(n - len(buf))
        if not chunk:
            return None
        buf += chunk
    return bytes(buf)


def _framed(msg):
    return len(msg).to_bytes(2, "big") + msg


def _tcp_exchange(query, server, timeout=4.0):
    fam = socket.AF_INET6 if ":" in server else socket.AF_INET
    try:
        with socket.socket(fam, socket.SOCK_STREAM) as s:
            s.settimeout(timeout)
            s.connect((server, 53))
            s.sendall(_framed(query))
            head = _read_exactly(s, 2)
            return _read_exactly(s, int.from_bytes(head, "big")) if head else None
    except OSError:
        return None


class DNSServer:
    def __init__(self, filt, upstream, on_adult_block=None):
        self.filter = filt
        self.upstream = list(upstream)
        self.on_adult_block = on_adult_block
        self.pool = ThreadPoolExecutor(max_workers=48, thread_name_prefix="dns")
        self.slots = threading.BoundedSemaphore(48)
        self.cache = {}
        self.cache_lock = threading.Lock()
        self.count_lock = threading.Lock()
        self.blocked_count = 0
        self.failures = 0
        self.dropped = 0
        self.sockets = []

    def take_failure_counts(self):
        with self.count_lock:
            r = (self.failures, self.dropped)
            self.failures = self.dropped = 0
            return r

    # ------------------------------------------------------------ resposta

    def answer(self, query, over_tcp):
        q = core.parse_query(query)
        if q is None:
            return self._forward(query, over_tcp)  # pergunta incomum: passa adiante sem mexer
        name, _qtype, end = q
        verdict = self.filter.verdict(name)
        if verdict == core.BLOCKED:
            with self.count_lock:
                self.blocked_count += 1
            if self.on_adult_block:
                self.on_adult_block()
            return core.blocked_response(query, end)
        if verdict == core.BLOCKED_BYPASS:
            return core.blocked_response(query, end)

        key = bytes(query[2:])  # a pergunta sem o número dela
        with self.cache_lock:
            hit = self.cache.get(key)
        if hit and hit[1] > time.time():
            return query[:2] + hit[0][2:]
        # Mais uma volta se todos falharem (pacote perdido é comum no Wi-Fi).
        r = self._forward(query, over_tcp) or self._forward(query, over_tcp)
        if r is None:
            with self.count_lock:
                self.failures += 1
            # Internet soluçou: devolve a última resposta boa (até 1 dia) em vez de "não encontrado".
            if hit and hit[1] + 86400 > time.time():
                return query[:2] + hit[0][2:]
            return core.blocked_response(query, end, rcode=2)
        rc = core.rcode(r)
        if rc in (0, 3) and len(r) > 3 and not (r[2] & 0x02):  # nunca guarda resposta cortada
            with self.cache_lock:
                if len(self.cache) > 50000:
                    self.cache.clear()
                self.cache[key] = (r, time.time() + 30)
        return r

    def _forward(self, query, over_tcp):
        for server in self.upstream:
            r = _tcp_exchange(query, server) if over_tcp else _udp_exchange(query, server)
            if r:
                return r
        return None

    # ------------------------------------------------------------ portas

    @staticmethod
    def _bind(fam, kind, ip, port):
        s = socket.socket(fam, kind)
        if core.WINDOWS:
            # No Windows, SO_REUSEADDR deixaria outro programa "roubar" a porta.
            s.setsockopt(socket.SOL_SOCKET, getattr(socket, "SO_EXCLUSIVEADDRUSE", -5), 1)
        else:
            s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        if fam == socket.AF_INET6:
            s.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 1)
        s.bind((ip, port))
        return s

    def start(self, ip="127.0.0.1", port=53, ipv6=True):
        """Abre UDP e TCP. Devolve os endereços abertos. Erro se nem o IPv4 abrir."""
        opened = []
        targets = [(socket.AF_INET, ip)]
        if ipv6 and socket.has_ipv6:
            targets.append((socket.AF_INET6, "::1"))
        for fam, addr in targets:
            try:
                u = self._bind(fam, socket.SOCK_DGRAM, addr, port)
                t = self._bind(fam, socket.SOCK_STREAM, addr, port)
                t.listen(64)
            except OSError:
                if fam == socket.AF_INET:
                    raise
                continue  # sem IPv6 neste computador: tudo bem
            self.sockets += [u, t]
            threading.Thread(target=self._udp_loop, args=(u,), daemon=True).start()
            threading.Thread(target=self._tcp_loop, args=(t,), daemon=True).start()
            opened.append(f"{addr}:{port}")
        return opened

    def stop(self):
        for s in self.sockets:
            try:
                s.close()
            except OSError:
                pass
        self.sockets = []

    def _udp_loop(self, sock):
        while True:
            try:
                data, client = sock.recvfrom(4096)
            except ConnectionResetError:
                continue  # Windows avisa assim quando um cliente já fechou; ignorar
            except OSError:
                return  # porta fechada (parando)
            if len(data) < 12:
                continue
            # Tudo ocupado (internet lenta): descarta esta em vez de travar; o Windows pergunta de novo.
            if not self.slots.acquire(timeout=0.3):
                with self.count_lock:
                    self.dropped += 1
                continue
            self.pool.submit(self._udp_reply, sock, data, client)

    def _udp_reply(self, sock, data, client):
        try:
            r = self.answer(data, False)
            if r:
                sock.sendto(r, client)
        except OSError:
            pass
        finally:
            self.slots.release()

    def _tcp_loop(self, sock):
        while True:
            try:
                conn, _ = sock.accept()
            except OSError:
                return
            if not self.slots.acquire(timeout=2):
                conn.close()
                continue
            self.pool.submit(self._tcp_client, conn)

    def _tcp_client(self, conn):
        try:
            conn.settimeout(10)
            while True:
                head = _read_exactly(conn, 2)
                if not head:
                    return
                n = int.from_bytes(head, "big")
                q = _read_exactly(conn, n) if n >= 12 else None
                r = self.answer(q, True) if q else None
                if not r:
                    return
                conn.sendall(_framed(r))
        except OSError:
            pass
        finally:
            conn.close()
            self.slots.release()
