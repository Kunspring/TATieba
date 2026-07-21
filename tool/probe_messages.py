#!/usr/bin/env python3
"""探测贴吧消息 API（@ / 回复 / 私信 WebSocket）。用法: python tool/probe_messages.py <BDUSS> [STOKEN]"""
from __future__ import annotations

import asyncio
import sys

import aiotieba as tb
from aiotieba.enums import GroupType


async def main(bduss: str, stoken: str = "") -> None:
    async with tb.Client(bduss, stoken=stoken) as client:
        ats = await client.get_ats(1)
        replies = await client.get_replies(1)
        print(f"@提及: {len(ats)} 条")
        if ats:
            print(f"  示例: {ats[0].text[:40]!r} @ {ats[0].fname}")
        print(f"回复: {len(replies)} 条")
        if replies:
            print(f"  示例: {replies[0].text[:40]!r} @ {replies[0].fname}")

        await client.init_websocket()
        groups = client._ws_core.mid_manager.gid2mid
        priv = [gid for gid, _ in groups.items() if gid]
        print(f"WS 会话组: {len(groups)} 个 (gid keys: {len(priv)})")

        # init 后 mid_manager 已有 group；再拉私信组消息
        from aiotieba.api import init_websocket

        raw_groups = await init_websocket.request(client._ws_core)
        private = [g for g in raw_groups if g.group_type == GroupType.PRIVATE_MSG]
        print(f"私信组 (type=6): {len(private)} 个")
        if private:
            ids = [g.group_id for g in private[:5]]
            msgs = await client.get_group_msg(ids, get_type=1)
            for g in msgs:
                preview = g.messages[0].text[:30] if g.messages else "(空)"
                print(f"  gid={g.group_id} msgs={len(g.messages)} preview={preview!r}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("用法: python tool/probe_messages.py <BDUSS> [STOKEN]")
        sys.exit(1)
    asyncio.run(main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else ""))
