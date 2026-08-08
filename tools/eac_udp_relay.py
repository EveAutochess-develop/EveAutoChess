#!/usr/bin/env python3
"""EVE自走棋 · 本机 UDP 端口映射（SEMI_ASYNC §7.5 turn_urls 回落）。

把「外口」收到的 UDP 转到本机游戏听口（默认 24567+房号），供跨网段客机
经 turn_urls=可达IP:外口 试连。不是完整 coturn ICE。

Example (host machine, room_code=1 → game port 24568):
  python eac_udp_relay.py --listen 27001 --forward 24568
  # guest net_connectivity.cfg:
  # turn_urls=\"<host-reachable-ip>:27001\"
"""
from __future__ import annotations

import argparse
import select
import socket
import sys
import time


def main() -> int:
    ap = argparse.ArgumentParser(description="UDP port map for EveAutochess ENet")
    ap.add_argument("--listen", type=int, required=True, help="Public/UDP listen port")
    ap.add_argument("--forward", type=int, required=True, help="Local game port (24567+code)")
    ap.add_argument("--bind", default="0.0.0.0", help="Listen bind address")
    ap.add_argument("--dest", default="127.0.0.1", help="Forward destination host")
    args = ap.parse_args()

    ext = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    ext.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    ext.bind((args.bind, args.listen))
    ext.setblocking(False)

    loc = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    loc.setblocking(False)

    client_addr = None  # last remote guest
    game_addr = (args.dest, args.forward)
    print(
        f"[eac_udp_relay] {args.bind}:{args.listen} <-> {args.dest}:{args.forward}",
        flush=True,
    )
    while True:
        r, _, _ = select.select([ext, loc], [], [], 1.0)
        now = time.strftime("%H:%M:%S")
        if ext in r:
            data, addr = ext.recvfrom(65535)
            client_addr = addr
            loc.sendto(data, game_addr)
        if loc in r:
            data, _addr = loc.recvfrom(65535)
            if client_addr is not None:
                ext.sendto(data, client_addr)
            else:
                print(f"[{now}] drop game->ext (no client yet) {len(data)}B", flush=True)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        print("\n[eac_udp_relay] stop", flush=True)
        raise SystemExit(0)
