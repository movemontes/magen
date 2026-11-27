"""O serviço do Magen (no Mac é o magend): fica ligado o tempo todo, como SYSTEM.

- abre o porteiro DNS em 127.0.0.1:53 e ::1:53;
- aponta o DNS do Windows para ele e confere a cada 30 s;
- baixa as listas de sites adultos uma vez por dia;
- avisa o app (porta local) quando um site adulto foi bloqueado;
- ao parar, devolve o DNS de antes, para a internet nunca quebrar com o Magen desligado.
"""
import os
import socket
import threading
import time
import urllib.request
from datetime import datetime

from . import core
from .dnsserver import DNSServer
from .version import VERSION

LOG_MAX = 2_000_000


def log(msg):
    line = f"[{datetime.now():%Y-%m-%d %H:%M:%S}] {msg}"
    print(line, flush=True)
    try:
        path = core.log_path()
        if os.path.exists(path) and os.path.getsize(path) > LOG_MAX:
            os.replace(path, path + ".antigo")
        with open(path, "a", encoding="utf-8") as f:
            f.write(line + "\n")
    except OSError:
        pass


def download(url):
    req = urllib.request.Request(url, headers={"User-Agent": f"Magen-blocker/{VERSION}"})
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            if r.status == 200:
                return r.read().decode("utf-8", "replace")
    except Exception:
        pass
    # Plano B: certificados do pacote certifi (Windows sem a cadeia atualizada).
    try:
        import ssl
        import certifi
        ctx = ssl.create_default_context(cafile=certifi.where())
        with urllib.request.urlopen(req, timeout=120, context=ctx) as r:
            return r.read().decode("utf-8", "replace") if r.status == 200 else None
    except Exception:
        return None


class Service:
    def __init__(self, port=None, manage_system_dns=True, allow_updates=True):
        self.port = port or core.DNS_PORT
        self.manage_dns = manage_system_dns and core.WINDOWS
        self.allow_updates = allow_updates
        self.stop_event = threading.Event()
        self.state_lock = threading.Lock()
        self.update_lock = threading.Lock()  # listas e configuração nunca mudam ao mesmo tempo
        self.config = core.load_config()
        self.filter = core.Filter()
        self.server = DNSServer(self.filter, self.config["upstream"], self.on_adult_block)
        self.last_signal = 0.0
        self.last_update_request = 0.0
        old = core.load_state()
        self.state = {k: old.get(k) for k in ("lastUpdate", "lists", "blockedTotal", "blockedToday",
                                               "todayKey", "lastBlockAt")}
        self.state.update({"startedAt": core.iso(core.now()), "version": VERSION})
        for k, v in (("lists", []), ("blockedTotal", 0), ("blockedToday", 0), ("todayKey", "")):
            if self.state.get(k) is None:
                self.state[k] = v

    # ------------------------------------------------------------ estado

    def write_state(self):
        with self.state_lock:
            self.state["domains"] = self.filter.count
            self.state["blockedSinceStart"] = self.server.blocked_count
            data = dict(self.state)
        try:
            core.write_json(core.state_path(), data)
        except OSError as e:
            log(f"Não consegui salvar o estado: {e}")

    def on_adult_block(self):
        """Conta e avisa o app (no máximo uma vez por segundo; uma página pede vários endereços)."""
        with self.state_lock:
            key = core.today_key()
            if self.state["todayKey"] != key:
                self.state["todayKey"], self.state["blockedToday"] = key, 0
            self.state["blockedTotal"] += 1
            self.state["blockedToday"] += 1
            self.state["lastBlockAt"] = core.iso(core.now())
            signal = time.time() - self.last_signal >= 1
            if signal:
                self.last_signal = time.time()
        if signal:
            self.write_state()
            core.send_local(core.APP_PORT, "blocked")

    # ------------------------------------------------------------ listas

    def load_cached_lists(self):
        ds = core.DomainSet.load(core.hashes_path())
        if not len(ds) and os.path.exists(core.cache_path()):
            # Só o texto existe (veio de uma versão antiga ou o .bin se perdeu): refaz.
            with open(core.cache_path(), encoding="utf-8") as f:
                ds = core.build_list_set(f.read().split())
            ds.save(core.hashes_path())
        self.filter.set_lists(ds)
        self.filter.apply_config(self.config)
        log(f"Listas carregadas do disco: {self.filter.count:,} domínios bloqueados.".replace(",", "."))
        return len(ds) > 0

    def update_lists(self, reason):
        threading.Thread(target=self._update, args=(reason,), daemon=True).start()

    def _update(self, reason):
        if not self.update_lock.acquire(blocking=False):
            return  # já está atualizando
        try:
            log(f"Atualizando listas ({reason})…")
            domains, results, any_ok = set(), [], False
            for url in self.config["lists"]:
                text = download(url)
                if text is None:
                    log(f"  falhou: {url}")
                    results.append({"url": url, "ok": False, "count": 0})
                    continue
                found = core.parse_list(text)
                # Uma lista de verdade tem muitos milhares. Uma pequena é provavelmente página de erro.
                if len(found) < 1000:
                    log(f"  ignorada (só {len(found)} linhas válidas): {url}")
                    results.append({"url": url, "ok": False, "count": len(found)})
                    continue
                any_ok = True
                domains.update(found)
                results.append({"url": url, "ok": True, "count": len(found)})
                log(f"  ok: {len(found)} domínios de {url}")
            if not any_ok:
                log("Nenhuma lista baixou; mantendo as listas antigas.")
                return
            ds = core.build_list_set(domains)
            ds.save(core.hashes_path())
            with open(core.cache_path() + ".tmp", "w", encoding="utf-8") as f:
                f.write("\n".join(sorted(domains)) + "\n")
            os.replace(core.cache_path() + ".tmp", core.cache_path())
            self.filter.set_lists(ds)
            with self.state_lock:
                self.state["lastUpdate"] = core.iso(core.now())
                self.state["lists"] = results
            self.write_state()
            log(f"Pronto: {self.filter.count} domínios bloqueados.")
        finally:
            self.update_lock.release()

    def lists_are_old(self):
        last = core.parse_iso(self.state.get("lastUpdate"))
        return last is None or (core.now() - last).total_seconds() > self.config["updateEveryHours"] * 3600

    def reload_config(self):
        with self.update_lock:
            self.config = core.load_config()
            self.server.upstream = list(self.config["upstream"])
            self.filter.apply_config(self.config)
        self.write_state()
        log(f"Configuração recarregada: {self.filter.count} domínios bloqueados.")

    # ------------------------------------------------------------ recados do app

    def control_loop(self):
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            s.bind(("127.0.0.1", core.CONTROL_PORT))
        except OSError as e:
            log(f"Porta de controle {core.CONTROL_PORT} ocupada: {e}")
            return
        s.settimeout(1)
        while not self.stop_event.is_set():
            try:
                data, _ = s.recvfrom(64)
            except (socket.timeout, ConnectionResetError):
                continue
            except OSError:
                break
            cmd = data.decode(errors="replace").strip()
            if cmd == "reload":
                # Só relê o arquivo, que só o administrador consegue mudar.
                self.reload_config()
            elif cmd == "update" and self.allow_updates:
                # Qualquer um pode pedir, então no máximo um pedido a cada 5 minutos.
                if time.time() - self.last_update_request > 300:
                    self.last_update_request = time.time()
                    self.update_lists("pedida pelo app")
        s.close()

    # ------------------------------------------------------------ ciclo

    def tick(self):
        """A cada 30 s: liberações cuja espera acabou, DNS do Windows, estado, listas velhas."""
        cfg = core.load_config()
        moved = core.apply_due(cfg)
        if moved:
            core.save_config(cfg)
            self.reload_config()
            log(f"Liberado(s) depois da espera: {', '.join(moved)}")
        if self.manage_dns:
            from . import systemdns
            changed = systemdns.enforce()
            if changed:
                log(f"DNS tinha sido mudado; apontei de novo para o Magen em: {', '.join(changed)}")
        self.write_state()
        failed, dropped = self.server.take_failure_counts()
        if failed or dropped:
            log(f"Atenção: nos últimos 30 s, {failed} perguntas ficaram sem resposta de "
                f"{'/'.join(self.config['upstream'])} e {dropped} foram descartadas por excesso. "
                "(Internet fora do ar?)")

    def run(self):
        """Roda até stop_event. Devolve 0 se parou bem, 1 se não abriu a porta."""
        os.makedirs(core.data_dir(), exist_ok=True)
        if not os.path.exists(core.config_path()):
            core.save_config(self.config)
        has_cache = self.load_cached_lists()
        try:
            opened = self.server.start(port=self.port)
        except OSError as e:
            log(f"Não consegui abrir a porta {self.port}: {e}. Não mexi no DNS do Windows. Saindo.")
            return 1
        log(f"Magen {VERSION} ouvindo em {', '.join(opened)}. "
            f"Servidores de verdade: {', '.join(self.config['upstream'])}")
        threading.Thread(target=self.control_loop, daemon=True).start()
        if self.manage_dns:
            from . import systemdns
            changed = systemdns.enforce()
            if changed:
                log(f"DNS do Windows apontado para o Magen em: {', '.join(changed)}")
        self.write_state()
        if self.allow_updates and (self.lists_are_old() or not has_cache):
            self.update_lists("início")
        ticks = 0
        while not self.stop_event.wait(30):
            try:
                self.tick()
            except Exception as e:  # nunca deixar o serviço cair por um erro bobo
                log(f"Erro no ciclo: {e!r}")
            ticks += 1
            if self.allow_updates and ticks % 20 == 0 and self.lists_are_old():
                self.update_lists("agendada")
        log("Parando. Devolvendo o DNS original do Windows.")
        if self.manage_dns:
            from . import systemdns
            systemdns.restore()
        self.server.stop()
        self.write_state()
        return 0
