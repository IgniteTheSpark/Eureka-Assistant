#!/usr/bin/env python3
"""发送 Ureka 打包结果到钉钉机器人。"""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


ROOT = Path(__file__).resolve().parent
CONFIG_FILE = ROOT / ".tokens" / "dingding.json"
MOBILE_RE = re.compile(r"^1[3-9]\d{9}$")


def usage() -> None:
    sys.stderr.write(
        "用法：python3 ding_notify.py <platform> <version> <time> <target> "
        "<build_type> <package_type> <api_base> [description] [download_url] "
        "[install_password] [at]\n"
    )


def load_config() -> dict:
    if not CONFIG_FILE.is_file():
        raise SystemExit(f"缺少钉钉配置：{CONFIG_FILE}")

    try:
        with CONFIG_FILE.open("r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception as exc:
        raise SystemExit(f"钉钉配置 JSON 无效：{exc}") from exc

    webhook_url = str(data.get("webhook_url", "")).strip()
    keyword = str(data.get("keyword", "")).strip()
    if not webhook_url:
        raise SystemExit("dingding.json 缺少 webhook_url")
    if not keyword:
        raise SystemExit("dingding.json 缺少 keyword")
    return data


def sign(timestamp_ms: int, secret: str) -> str:
    string_to_sign = f"{timestamp_ms}\n{secret}"
    digest = hmac.new(
        secret.encode("utf-8"),
        string_to_sign.encode("utf-8"),
        hashlib.sha256,
    ).digest()
    return base64.b64encode(digest).decode("ascii")


def build_at(at_param: str) -> tuple[str, dict]:
    at_param = at_param.strip()
    if at_param.lower() == "all":
        return "@所有人 ", {"isAtAll": True}

    at_mobiles: list[str] = []
    at_dingtalk_ids: list[str] = []
    mentions: list[str] = []
    if at_param:
        for raw in at_param.split(","):
            item = raw.strip()
            if not item:
                continue
            if MOBILE_RE.match(item):
                at_mobiles.append(item)
                mentions.append(f"@{item} ")
            else:
                ding_id = item[9:] if item.startswith("dingtalk:") else item
                at_dingtalk_ids.append(ding_id)
                mentions.append(f"@{ding_id} ")

    at_obj: dict[str, object] = {"isAtAll": False}
    if at_mobiles:
        at_obj["atMobiles"] = at_mobiles
    if at_dingtalk_ids:
        at_obj["atDingtalkIds"] = at_dingtalk_ids
    return "".join(mentions), at_obj


def main() -> None:
    if len(sys.argv) < 8:
        usage()
        raise SystemExit(1)

    config = load_config()
    keyword = str(config["keyword"]).strip()
    webhook_url = str(config["webhook_url"]).strip()
    secret = str(config.get("secret", "")).strip()
    default_at = str(config.get("default_at", "")).strip()

    platform = sys.argv[1]
    version = sys.argv[2]
    timestr = sys.argv[3]
    target = sys.argv[4]
    build_type = sys.argv[5]
    package_type = sys.argv[6]
    api_base = sys.argv[7]
    description = sys.argv[8] if len(sys.argv) > 8 else ""
    download_url = sys.argv[9] if len(sys.argv) > 9 else ""
    install_password = sys.argv[10] if len(sys.argv) > 10 else ""
    at_param = sys.argv[11] if len(sys.argv) > 11 else default_at

    mention_prefix, at_obj = build_at(at_param)
    lines = [
        f"{keyword} {platform.upper()} 新包",
        f"版本：{version}",
        f"时间：{timestr}",
        f"目标：{target}",
        f"构建类型：{build_type}",
        f"产物类型：{package_type}",
        f"API 地址：{api_base}",
    ]
    if download_url:
        lines.append(f"下载地址：{download_url}")
    if install_password:
        lines.append(f"安装密码：{install_password}")
    if description:
        lines.append(f"描述：{description}")

    payload = {
        "msgtype": "text",
        "text": {"content": mention_prefix + "\n".join(lines)},
        "at": at_obj,
    }
    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")

    url = webhook_url
    if secret:
        timestamp_ms = int(time.time() * 1000)
        url += (
            f"&timestamp={timestamp_ms}"
            f"&sign={urllib.parse.quote(sign(timestamp_ms, secret), safe='')}"
        )

    req = urllib.request.Request(
        url,
        data=body,
        headers={"Content-Type": "application/json; charset=utf-8"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            response = resp.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as exc:
        response = exc.read().decode("utf-8", errors="replace")
        sys.stderr.write(f"钉钉通知发送失败：{response}\n")
        raise SystemExit(1) from exc
    except urllib.error.URLError as exc:
        sys.stderr.write(f"钉钉通知发送失败：{exc}\n")
        raise SystemExit(1) from exc

    if '"errcode":0' in response or '"errcode": 0' in response:
        print("钉钉通知发送成功")
        return

    sys.stderr.write(f"钉钉通知发送失败：{response}\n")
    raise SystemExit(1)


if __name__ == "__main__":
    main()
