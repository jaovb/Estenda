"""Teste de ponta a ponta do Estenda, com o PC simulado (tela e controle de mentira).

  python testes/e2e.py                        tudo num computador só, pontos de encontro simulados
  python testes/e2e.py --encontros reais      idem, mas usando os pontos de encontro públicos de verdade
  python testes/e2e.py --papel pc --segredo S --senha X --encontros reais --espera 420
  python testes/e2e.py --papel tablet --segredo S --senha X --encontros reais --espera 420
                                              PC e tablet em computadores (e redes) diferentes

O "tablet" é um Chrome sem janela abrindo a mesma página que vai embutida no app Android,
servida em 127.0.0.1:24862 como o app faz."""
import argparse, asyncio, functools, http.server, json, os, shutil, subprocess, sys, tempfile, threading, time, urllib.request
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
SAIDA = Path(__file__).resolve().parent / "saida"
ID_PC = "0123456789abcdef"
SEM_PROXY = urllib.request.build_opener(urllib.request.ProxyHandler({}))
falhas = []


def achar_chrome():
    for c in (os.environ.get("CHROME"), shutil.which("google-chrome"), shutil.which("chromium"),
              "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
              r"C:\Program Files\Google\Chrome\Application\chrome.exe"):
        if c and os.path.isfile(c):
            return c
    raise RuntimeError("Chrome não encontrado (defina CHROME)")


def conferir(cond, nome, detalhe=""):
    print(("ok     " if cond else "FALHOU ") + nome + (f"  [{detalhe}]" if detalhe else ""), flush=True)
    if not cond:
        falhas.append(nome)
    return cond


class Pc:
    """O programa do PC (app.py) em modo simulado, com a ponte de longe de verdade (Chrome sem janela)."""

    def __init__(self, encontros, segredo=None, senha=None):
        self.pasta = Path(tempfile.mkdtemp(prefix="estenda-pc-"))
        if segredo:
            (self.pasta / "longe.json").write_text(json.dumps({"segredo": segredo, "id": ID_PC}))
        if senha:
            (self.pasta / "senha").write_text(senha)
        env = {**os.environ, "PONTE_REMOTA_SIMULAR": "1", "PONTE_REMOTA_CONFIG": str(self.pasta)}
        if encontros:
            env["PONTE_REMOTA_ENCONTROS"] = ",".join(encontros)
        self.proc = subprocess.Popen([sys.executable, str(RAIZ / "app.py"), "--sem-janela"], stdout=subprocess.PIPE,
                                     stderr=subprocess.STDOUT, text=True, env=env)
        while True:
            linha = self.proc.stdout.readline()
            if not linha:
                raise RuntimeError("o programa do PC não abriu")
            if linha.startswith("URL "):
                self.url = linha.split()[1]
                break
        threading.Thread(target=lambda: [None for _ in self.proc.stdout], daemon=True).start()
        self.token = self.url.split("t=")[1]

    def api(self, caminho, corpo=None):
        req = urllib.request.Request(self.url.split("?")[0] + caminho.lstrip("/"),
                                     data=None if corpo is None else json.dumps(corpo).encode(),
                                     headers={"X-Token": self.token, "Content-Type": "application/json"})
        return json.loads(SEM_PROXY.open(req, timeout=10).read())

    def esperar(self, cond, segundos=30):
        fim = time.time() + segundos
        while time.time() < fim:
            e = self.api("/api/estado")
            if cond(e):
                return e
            time.sleep(0.4)
        return None

    def registro(self):
        try:
            return (self.pasta / "registro.txt").read_text(encoding="utf-8")
        except OSError:
            return ""

    def fechar(self):
        self.proc.terminate()
        try:
            self.proc.wait(8)
        except subprocess.TimeoutExpired:
            self.proc.kill()
        shutil.rmtree(self.pasta, ignore_errors=True)


def servir_pagina(porta=24862):
    """A página embutida no app, servida em 127.0.0.1 como o app faz."""
    class Quieto(http.server.SimpleHTTPRequestHandler):
        def log_message(self, *a):
            pass
    srv = http.server.ThreadingHTTPServer(("127.0.0.1", porta), functools.partial(Quieto, directory=str(RAIZ / "interface")))
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return f"http://127.0.0.1:{porta}/remoto.html"


INICIO = "window.__msgs = []; window.EstendaApp = { postMessage: m => window.__msgs.push(JSON.parse(m)) };"


async def abrir(nav, endereco, **par):
    ctx = await nav.new_context(viewport={"width": 1280, "height": 800}, is_mobile=True, has_touch=True,
                                user_agent="Mozilla/5.0 (Linux; Android 14; SM-X710; wv) AppleWebKit/537.36 (KHTML, like Gecko) "
                                           "Version/4.0 Chrome/141.0.0.0 Safari/537.36")
    await ctx.add_init_script(INICIO)
    pg = await ctx.new_page()
    pg.erros = []
    pg.on("pageerror", lambda e: pg.erros.append(str(e)))
    from urllib.parse import urlencode
    await pg.goto(endereco + ("#" + urlencode(par) if par else ""))
    return pg


async def msgs(pg, tipo=None):
    m = await pg.evaluate("window.__msgs || []")
    return [x for x in m if tipo is None or x.get("t") == tipo]


async def esperar_sessao(pg, segundos=40):
    """Espera a tela do PC aparecer e chegarem imagens. Devolve o último estado relatado ao app (ou None)."""
    fim = time.time() + segundos
    while time.time() < fim:
        est = await msgs(pg, "estado")
        if est and est[-1]["sessao"] and est[-1]["quadros"] > 0:
            return est[-1]
        await asyncio.sleep(0.3)
    return None


async def caminho_p2p(pg):
    """Por onde o WebRTC passou (tipos dos endereços escolhidos)."""
    return await pg.evaluate("""(async () => {
      const pc = C.ws && C.ws.pc; if (!pc) return "";
      const st = await pc.getStats(); let par = null;
      st.forEach(r => { if (r.type === "transport" && r.selectedCandidatePairId) par = st.get(r.selectedCandidatePairId); });
      if (!par) return "?";
      const a = st.get(par.localCandidateId), b = st.get(par.remoteCandidateId);
      return (a ? a.candidateType + "/" + a.protocol : "?") + " <-> " + (b ? b.candidateType + "/" + b.protocol : "?");
    })()""")


async def teste_completo(args):
    from playwright.async_api import async_playwright
    SAIDA.mkdir(exist_ok=True)
    sims, encontros = [], None
    if args.encontros == "sim":
        for porta in (28811, 28812):
            p = subprocess.Popen([sys.executable, str(Path(__file__).parent / "mqtt_sim.py"), str(porta)], stdout=subprocess.PIPE, text=True)
            assert p.stdout.readline().startswith("PRONTO")
            p.recados = []
            threading.Thread(target=lambda p=p: [p.recados.append(l) for l in p.stdout], daemon=True).start()
            sims.append(p)
        encontros = ["ws://127.0.0.1:28811", "ws://127.0.0.1:28812"]
    pc = Pc(encontros)
    pagina = servir_pagina()
    try:
        pc.api("/api/ligar", {})
        e = pc.esperar(lambda e: e["enderecos"]["local"] and e["longe"]["sinal"] == "pronto", 45)
        if not conferir(bool(e), "PC: acesso ligado e de longe pronto", json.dumps((e or pc.api("/api/estado"))["longe"])):
            print(pc.registro()[-1500:])
            return
        ip, porta, senha = e["enderecos"]["local"][0], e["porta"], e["senha"]
        alvo = f"{ip}:{porta}"
        conferir(e["longe"]["encontros"] >= 1 and e["apk"] and "github.com" in e["apk"]["url"], "painel: pontos de encontro contados e QR do app",
                 f"{e['longe']['encontros']}/{e['longe']['total']}")
        async with async_playwright() as pw:
            nav = await pw.chromium.launch(executable_path=achar_chrome(), args=["--no-sandbox", "--no-proxy-server",
                                           "--disable-features=WebRtcHideLocalIpsWithMdns"])

            # ---- A. primeira vez, em casa: senha, e o app recebe a chave do aparelho e o segredo de longe
            pg = await abrir(nav, pagina, app="1", pc=alvo, modo="espelho", tema="light")
            await pg.wait_for_selector("#form-senha:not([hidden])", timeout=15000)
            await pg.screenshot(path=str(SAIDA / "a1_entrada_app_claro.png"))
            await pg.fill("#senha", senha)
            await pg.click("#entrar")
            est = await esperar_sessao(pg)
            conferir(bool(est) and est["via"] == "local", "A. em casa: entrou com a senha e chegou imagem", json.dumps(est))
            ap, lg = await msgs(pg, "aparelho"), await msgs(pg, "longe")
            conferir(len(ap) == 1 and len(ap[0]["token"]) > 20, "A. o app recebeu a chave deste tablet")
            conferir(len(lg) == 1 and lg[0]["s"] and lg[0]["pcid"] and lg[0]["e"], "A. o app recebeu o segredo de longe e o id do PC")
            await pg.wait_for_timeout(1500)
            await pg.screenshot(path=str(SAIDA / "a2_sessao_casa.png"))
            for acao, arq in (("tela", "a3_folha_tela.png"), ("teclas", "a4_folha_teclas.png")):
                await pg.click("#puxador") if await pg.is_visible("#puxador") else None
                await pg.click(f'#barra [data-acao="{acao}"]')
                await pg.wait_for_timeout(500)
                await pg.screenshot(path=str(SAIDA / arq))
                await pg.click(f'#barra [data-acao="{acao}"]')
                await pg.wait_for_timeout(300)
            conferir(await pg.is_hidden('#barra [data-acao="cheia"]') and await pg.is_hidden("#tema2"), "A. no app, somem o botão de tela cheia e o de tema")
            if not (ap and lg):
                return
            cred = dict(app="1", pc=alvo, api=ap[0]["id"], apt=ap[0]["token"], ls=lg[0]["s"], le=",".join(lg[0]["e"]), pcid=lg[0]["pcid"])
            # sair pelo botão avisa o app
            await pg.click("#puxador") if await pg.is_visible("#puxador") else None
            await pg.click('#barra [data-acao="sair"]')
            await pg.wait_for_timeout(500)
            conferir(len(await msgs(pg, "sair")) == 1, "A. o botão Sair avisa o app")
            await pg.context.close()

            # ---- B. de novo em casa, com a chave que o app guardou: entra sozinho
            pg = await abrir(nav, pagina, modo="espelho", **cred)
            est = await esperar_sessao(pg)
            conferir(bool(est) and est["via"] == "local", "B. em casa de novo: entrou sozinho, sem senha", json.dumps(est))
            await pg.context.close()

            # ---- C. de longe (forçado): WebRTC direto pelos pontos de encontro
            antes = sum(len(s.recados) for s in sims)
            t0 = time.time()
            pg = await abrir(nav, pagina, modo="espelho", so="longe", **cred)
            est = await esperar_sessao(pg, 60)
            dt = time.time() - t0
            conferir(bool(est) and est["via"] == "p2p", f"C. de longe: conectou direto em {dt:.1f} s e chegou imagem", json.dumps(est))
            print("       caminho:", await caminho_p2p(pg))
            e = pc.api("/api/estado")
            conferir(any(s["tipo"] == "p2p" for s in e["sessoes"]), "C. o PC mostra a sessão como 'de longe'", str([(s["nome"], s["tipo"], s["ip"]) for s in e["sessoes"]]))
            await pg.wait_for_timeout(2500)
            await pg.screenshot(path=str(SAIDA / "c1_sessao_longe.png"))
            if sims:
                recados = sum(len(s.recados) for s in sims) - antes
                await pg.wait_for_timeout(4000)
                depois = sum(len(s.recados) for s in sims) - antes
                conferir(recados <= 12 and depois == recados, "C. pelo encontro passam só os recados do aperto de mão", f"{recados} recados (2 servidores), +{depois - recados} em 4 s de uso")
            # toque de longe: toca no meio e o PC simulado registra o clique
            await pg.touchscreen.tap(640, 400)
            await pg.wait_for_timeout(800)
            # intruso no canal: mesma senha, vínculo errado (ver teste de unidade do servidor) fica no teste antigo
            await pg.context.close()

            # ---- D. fora de casa de verdade: o endereço de casa não responde e o app cai sozinho para "de longe"
            for nome, falso in (("porta fechada", f"{ip}:9"), ("endereço mudo", "10.255.255.1:24860")):
                t0 = time.time()
                pg = await abrir(nav, pagina, modo="espelho", **{**cred, "pc": falso})
                est = await esperar_sessao(pg, 60)
                conferir(bool(est) and est["via"] == "p2p", f"D. {nome}: caiu sozinho para de longe em {time.time() - t0:.1f} s", json.dumps(est))
                await pg.context.close()

            # ---- E. outra rede em que o mesmo endereço é de OUTRO PC: não manda a chave para ele
            pg = await abrir(nav, pagina, modo="espelho", **{**cred, "pcid": "ffffffffffffffff", "ls": ""})
            await pg.wait_for_timeout(4000)
            txt = await pg.inner_text("#pc-texto")
            conferir("outro computador" in txt and not await msgs(pg, "esquecido"), "E. PC diferente no mesmo endereço: recusa e não perde a chave", txt)
            await pg.context.close()

            # ---- F. segundo monitor de longe
            pg = await abrir(nav, pagina, modo="segundo", so="longe", **cred)
            est = await esperar_sessao(pg, 60)
            mon = await pg.evaluate("S.monitor") if est else None
            conferir(bool(est) and mon == 1 and est["tela"].startswith("960x"), "F. segundo monitor de longe: escolheu a tela extra", f"monitor {mon}, {est and est['tela']}")
            await pg.screenshot(path=str(SAIDA / "f1_segundo_monitor_longe.png"))

            # ---- G. um ponto de encontro cai: os outros seguram (só no simulado)
            if sims:
                sims[0].terminate()
                await asyncio.sleep(1)
                pg2 = await abrir(nav, pagina, modo="espelho", so="longe", **cred)
                est = await esperar_sessao(pg2, 60)
                conferir(bool(est) and est["via"] == "p2p", "G. com um ponto de encontro fora do ar, o outro segura", json.dumps(est))
                conferir(bool(await esperar_sessao(pg)), "G. a sessão que já estava aberta nem percebe")
                await pg2.context.close()

            # ---- H. desligar "de longe" no PC derruba quem está de longe e apaga o segredo do tablet ao entrar em casa
            pc.api("/api/config", {"longe": False})
            await pg.wait_for_timeout(2500)
            conferir(await pg.is_visible("#cobertura"), "H. PC desligou o de longe: a sessão de longe cai", (await pg.inner_text("#cob-txt")).strip()[:80])
            await pg.context.close()
            pg = await abrir(nav, pagina, modo="espelho", **cred)
            est = await esperar_sessao(pg)
            lg = await msgs(pg, "longe")
            conferir(bool(est) and est["via"] == "local" and lg and lg[-1]["s"] is None, "H. em casa continua entrando, e o app é avisado de que o de longe foi desligado")
            await pg.context.close()
            pg = await abrir(nav, pagina, modo="espelho", so="longe", **cred)
            await pg.wait_for_selector("#pc-status.mal", timeout=40000)
            conferir("não respondeu" in await pg.inner_text("#pc-texto"), "H. de longe agora diz que o PC não respondeu", await pg.inner_text("#pc-texto"))
            await pg.screenshot(path=str(SAIDA / "h1_sem_pc_escuro.png"))
            await pg.context.close()
            pc.api("/api/config", {"longe": True})

            # ---- I. pelo navegador (sem o app), servido pelo próprio PC: continua funcionando
            pg = await abrir(nav, f"http://{alvo}/")
            await pg.wait_for_selector("#form-senha:not([hidden])", timeout=15000)
            await pg.screenshot(path=str(SAIDA / "i1_entrada_navegador_escuro.png"))
            await pg.fill("#senha", senha)
            await pg.click("#entrar")
            await pg.wait_for_selector("#sessao:not([hidden])", timeout=15000)
            await pg.wait_for_timeout(1500)
            conferir(await pg.evaluate("C.ativo && QUADROS > 0"), "I. navegador comum (sem app): entra com a senha e chega imagem")
            conferir(not pg.erros, "sem erros de JavaScript na página", str(pg.erros[:3]))
            await pg.context.close()
            await nav.close()
    finally:
        reg = pc.registro()
        pc.fechar()
        for s in sims:
            s.terminate()
        print("\n--- registro do PC (fim) ---\n" + "\n".join(reg.strip().split("\n")[-14:]))


async def papel_pc(args):
    pc = Pc(None, segredo=args.segredo, senha=args.senha)
    try:
        pc.api("/api/ligar", {})
        e = pc.esperar(lambda e: e["longe"]["sinal"] == "pronto", 60)
        conferir(bool(e), "PC: de longe pronto", json.dumps((e or pc.api("/api/estado"))["longe"]))
        fim, e = time.time() + args.espera, None
        while time.time() < fim and not e:
            e = pc.esperar(lambda e: any(s["tipo"] == "p2p" and s["fps"] > 0 for s in e["sessoes"]), 30)
            if not e:
                print("       diagnóstico do PC:", json.dumps(pc.api("/api/estado")["longe"].get("diag")), flush=True)
        conferir(bool(e), "PC: um tablet entrou de longe, vindo de outra rede", str(e and [(s["nome"], s["ip"], s["fps"]) for s in e["sessoes"]]))
        if e:
            time.sleep(12)  # deixa o outro lado medir
    finally:
        print("\n--- registro do PC ---\n" + "\n".join(pc.registro().strip().split("\n")[-12:]))
        pc.fechar()


async def papel_tablet(args):
    from playwright.async_api import async_playwright
    SAIDA.mkdir(exist_ok=True)
    pagina = servir_pagina()
    async with async_playwright() as pw:
        nav = await pw.chromium.launch(executable_path=achar_chrome(), args=["--no-sandbox"])
        fim, est, pg, n = time.time() + args.espera, None, None, 0
        while time.time() < fim and not est:
            n += 1
            pg = await abrir(nav, pagina, app="1", pc="10.255.255.1:24860", modo="espelho", so="longe", ls=args.segredo, senha=args.senha, pcid=ID_PC)
            est = await esperar_sessao(pg, 35)
            if not est:
                ult = (await msgs(pg, "estado")) or [{}]
                print(f"tentativa {n}: {await pg.inner_text('#pc-texto')} | diag: {json.dumps(ult[-1].get('diag'))}", flush=True)
                await pg.context.close()
        conferir(bool(est), f"tablet: entrou de longe em outra rede (tentativa {n})", json.dumps(est))
        if est:
            print("       caminho:", await caminho_p2p(pg))
            await pg.wait_for_timeout(5000)
            ult = (await msgs(pg, "estado"))[-1]
            conferir(ult["quadros"] > est["quadros"], "tablet: a imagem continua chegando", json.dumps(ult))
            await pg.screenshot(path=str(SAIDA / "duas_redes.png"))
        await nav.close()


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--papel", default="ambos", choices=["ambos", "pc", "tablet"])
    ap.add_argument("--encontros", default="sim", choices=["sim", "reais"])
    ap.add_argument("--segredo")
    ap.add_argument("--senha", default="teste-teste-teste")
    ap.add_argument("--espera", type=int, default=300)
    ap.add_argument("--informativo", action="store_true", help="não reprova o teste se falhar (rede dos servidores de teste)")
    a = ap.parse_args()
    asyncio.run({"ambos": teste_completo, "pc": papel_pc, "tablet": papel_tablet}[a.papel](a))
    print(f"\n{'TUDO CERTO' if not falhas else str(len(falhas)) + ' FALHA(S): ' + '; '.join(falhas)}")
    sys.exit(1 if falhas and not a.informativo else 0)
