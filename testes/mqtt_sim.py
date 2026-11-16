"""Servidor de recados MQTT (3.1.1 sobre WebSocket) de mentira, para testar o encontro sem internet.
Uso: python mqtt_sim.py PORTA   (imprime PRONTO e, a cada recado, RECADO <tópico> <bytes>)"""
import asyncio, base64, hashlib, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from remoto import WebSocket, GUID_WS

assinantes: dict[str, set] = {}


def varint(n: int) -> bytes:
    out = bytearray()
    while True:
        b, n = n % 128, n // 128
        out.append(b | 128 if n else b)
        if not n:
            return bytes(out)


async def cliente(ws: WebSocket) -> None:
    buf, meus = b"", set()
    try:
        while True:
            dados = await ws.receber()
            if dados is None:
                break
            if isinstance(dados, str):
                continue
            buf += dados
            while len(buf) >= 2:
                tam, mult, i = 0, 1, 1
                while True:
                    if i >= len(buf):
                        tam = None
                        break
                    tam += (buf[i] & 127) * mult
                    mult *= 128
                    i += 1
                    if not buf[i - 1] & 128:
                        break
                if tam is None or len(buf) < i + tam:
                    break
                cab, corpo, buf = buf[0], buf[i:i + tam], buf[i + tam:]
                tipo = cab >> 4
                if tipo == 1:      # CONNECT -> CONNACK
                    await ws.enviar(bytes([0x20, 2, 0, 0]))
                elif tipo == 8:    # SUBSCRIBE -> SUBACK
                    pid, n = corpo[:2], int.from_bytes(corpo[2:4], "big")
                    topico = corpo[4:4 + n].decode()
                    assinantes.setdefault(topico, set()).add(ws)
                    meus.add(topico)
                    await ws.enviar(bytes([0x90, 3]) + pid + b"\0")
                elif tipo == 3:    # PUBLISH -> repassa
                    n = int.from_bytes(corpo[:2], "big")
                    topico = corpo[2:2 + n].decode()
                    print("RECADO", topico, len(corpo) - 2 - n, flush=True)
                    pacote = bytes([0x30]) + varint(len(corpo)) + corpo
                    for outro in list(assinantes.get(topico, ())):
                        try:
                            await outro.enviar(pacote)
                        except Exception:
                            pass
                elif tipo == 12:   # PINGREQ -> PINGRESP
                    await ws.enviar(bytes([0xD0, 0]))
                elif tipo == 14:   # DISCONNECT
                    return
    finally:
        for t in meus:
            assinantes.get(t, set()).discard(ws)


async def conexao(reader, writer):
    try:
        cab = (await reader.readuntil(b"\r\n\r\n")).decode("latin-1").split("\r\n")
        h = {k.strip().lower(): v.strip() for k, v in (l.split(":", 1) for l in cab[1:] if ":" in l)}
        aceite = base64.b64encode(hashlib.sha1((h["sec-websocket-key"] + GUID_WS).encode()).digest()).decode()
        writer.write(("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                      f"Sec-WebSocket-Accept: {aceite}\r\nSec-WebSocket-Protocol: mqtt\r\n\r\n").encode())
        await writer.drain()
        await cliente(WebSocket(reader, writer))
    except Exception:
        pass
    finally:
        try:
            writer.close()
        except Exception:
            pass


async def main(porta: int):
    srv = await asyncio.start_server(conexao, "127.0.0.1", porta)
    print("PRONTO", flush=True)
    async with srv:
        await srv.serve_forever()


if __name__ == "__main__":
    asyncio.run(main(int(sys.argv[1])))
