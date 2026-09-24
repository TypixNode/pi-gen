#!/usr/bin/env python3
"""（vendored from eggfly/TypixDeck: scripts/cn_mirror/sync_release.py —— 改动请先改那边再同步过来）

把 TypixNode/pi-gen 的 GitHub Release 镜像同步到国内存储，并生成国内版 Imager 内容仓库。

pi-gen 的 CI 已经在每个 Release 里发了一份 `os_list.json`（Imager v4 格式，
四个哈希/大小字段都齐了），所以国内站**不需要重算哈希**，只要：

1. 拉每个 Release 的 `os_list.json`（几 KB）；
2. 把里面的 `url`、`icon` 改写成国内地址，多个 flavor / 多个版本合并成一份 repo.json；
3. 把 `.img.xz` 从 Release 搬到国内存储（下载后用 CI 给的 image_download_sha256 校验）；
4. 生成 publish/（repo.json + index.html + images/ + icons/），交给 --upload-cmd 推上去。

Imager 写卡时校验 extract_sha256，国内副本必须与 Release 逐字节一致；
本脚本下载后立刻核对压缩包 sha256，不一致直接跳过，不会发布坏文件。
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
USER_AGENT = "typixdeck-cn-mirror/1.0"

# CI 的 tag 形如 typixdeck-slim-build-20260918-b7c54cf / typixdeck-build-20260821-7e6dc79
TAG_RE = re.compile(r"^typixdeck-(?P<flavor>.*?)-?build-(?P<date>\d{8})-(?P<sha>[0-9a-f]+)$")


# ---------------------------------------------------------------- GitHub 侧

def gh_json(path: str) -> Any:
    """优先用 gh CLI（带鉴权、不吃匿名限流），没有就裸 API。"""
    if shutil.which("gh"):
        out = subprocess.run(["gh", "api", path], capture_output=True, text=True)
        if out.returncode == 0:
            return json.loads(out.stdout)
        print(f"[warn] gh api {path} 失败，改用匿名 API：{out.stderr.strip()[:160]}", file=sys.stderr)
    req = urllib.request.Request(f"https://api.github.com{path}",
                                 headers={"User-Agent": USER_AGENT,
                                          "Accept": "application/vnd.github+json"})
    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.load(resp)


def fetch_url(url: str, dest: Path, expect_size: int | None = None, quiet: bool = False) -> bool:
    dest.parent.mkdir(parents=True, exist_ok=True)
    if expect_size and dest.exists() and dest.stat().st_size == expect_size:
        return True
    progress = ["-sS"] if quiet else ["--progress-bar"]
    rc = subprocess.run(["curl", "-fL", "--retry", "3", "--retry-delay", "2", "-C", "-",
                         *progress, "-o", str(dest), url]).returncode
    return rc == 0


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        while chunk := fh.read(8 << 20):
            h.update(chunk)
    return h.hexdigest()


def head_ok(url: str, timeout: int = 25) -> bool:
    req = urllib.request.Request(url, method="HEAD", headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return 200 <= resp.status < 400
    except Exception:      # noqa: BLE001 - HTTP 错误和网络错误一样都算"不可用"
        return False


def flavor_of(tag: str, asset_name: str) -> str:
    m = TAG_RE.match(tag)
    if m:
        return m.group("flavor") or "base"
    # 不是 CI 标准 tag（早期构建、Android 版等）：退回用镜像文件名区分
    return re.sub(r"^raspios-\w+-\w+-typixdeck-?|\.img\.xz$", "", asset_name) or asset_name


# ---------------------------------------------------------------- 改写

def localize_icon(icon: str, icons_dir: Path, base_url: str, cache: dict[str, str]) -> str:
    """把 icon 下载到本地并改写成国内 URL（raw.githubusercontent.com 在国内基本打不开）。"""
    if not icon or not icon.startswith(("http://", "https://")):
        return icon
    if icon in cache:
        return cache[icon]
    name = Path(urllib.parse.unquote(urllib.parse.urlsplit(icon).path)).name or "icon.png"
    name = re.sub(r"[^\w.\-]", "_", name)
    dest = icons_dir / name
    if dest.exists() or fetch_url(icon, dest, quiet=True):
        cache[icon] = f"{base_url}/icons/{name}"
    else:
        print(f"[warn] 图标下载失败，保留原地址：{icon}", file=sys.stderr)
        cache[icon] = icon
    return cache[icon]


# ---------------------------------------------------------------- main

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--config", type=Path, default=HERE / "typixdeck.config.json")
    ap.add_argument("--base-url", help="国内站点根 URL，覆盖配置里的 base_url")
    ap.add_argument("--repo", help="GitHub 仓库，覆盖配置里的 github_repo")
    ap.add_argument("--tag", action="append", default=[], help="只同步这些 tag（可多次给）")
    ap.add_argument("--flavors", nargs="*", help="只要这些 flavor（如 slim plasma-mobile），默认全要")
    ap.add_argument("--per-flavor", type=int, default=2, help="每个 flavor 保留最近几个版本（默认 2）")
    ap.add_argument("--all-tags", action="store_true",
                    help="连非 typixdeck-*-build-* 的 release 也收（默认只收 TypixDeck 自己的构建）")
    ap.add_argument("--scan", type=int, default=30, help="往回扫多少个 release（默认 30）")
    ap.add_argument("--staging", type=Path, default=Path.home() / ".cache" / "typixdeck-mirror",
                    help="镜像下载缓存目录")
    ap.add_argument("--out", type=Path, default=HERE / "publish", help="待上传目录")
    ap.add_argument("--proxy-prefix",
                    help="白嫖模式：不搬文件，把 url 改写成 <前缀>+GitHub 原始 URL。"
                         "可逗号分隔给多条线路（第一条为主，其余给最新版生成「线路 N」备用条目），"
                         "例如 https://cdn.gh-proxy.com/,https://gh-proxy.com/"
                         "（用 bench_mirrors.py 挑最快的）")
    ap.add_argument("--no-images", action="store_true",
                    help="只出 repo.json / index.html / icons，不搬镜像（镜像由 CI 直传国内存储时用）")
    ap.add_argument("--copy-images", action="store_true", help="复制而不是硬链接到 publish/")
    ap.add_argument("--max-total-gb", type=float, default=9.0,
                    help="发布的镜像总大小上限（GB），从新到旧累加，超了就不再收更旧的版本。"
                         "默认 9.0，给 R2 的 10 GB 免费额度留余量")
    ap.add_argument("--verify-urls", action="store_true",
                    help="生成前对每条改写后的 url 发 HEAD；不存在的条目回退到 GitHub 原始链接，"
                         "绝不给用户留 404")
    ap.add_argument("--upload-cmd", help="上传命令，{dir} 替换成 publish 目录")
    args = ap.parse_args()

    cfg = json.loads(args.config.read_text(encoding="utf-8"))
    base_url = (args.base_url or cfg["base_url"]).rstrip("/")
    repo = args.repo or cfg["github_repo"]
    if "REPLACE-ME" in base_url and not args.proxy_prefix:
        ap.error("先把 typixdeck.config.json 里的 base_url 改成你的国内站点地址（或用 --base-url）")

    proxies = [x.rstrip("/") + "/" for x in (args.proxy_prefix or "").split(",") if x.strip()]
    proxy = proxies[0] if proxies else None
    if proxy:
        args.no_images = True                    # 文件留在 GitHub，只改 URL

    out: Path = args.out
    (out / "icons").mkdir(parents=True, exist_ok=True)
    args.staging.mkdir(parents=True, exist_ok=True)

    # ---- 挑 release
    if args.tag:
        releases = [gh_json(f"/repos/{repo}/releases/tags/{t}") for t in args.tag]
    else:
        releases = [r for r in gh_json(f"/repos/{repo}/releases?per_page={args.scan}")
                    if not r.get("draft")]
        # ⚠️ /releases 的返回顺序**不是**按时间倒序（实测 2026-09-24：同一个 flavor
        # 的 797ff04(published 05:55) 排在 7123232(published 06:42) 前面）。
        # 不自己排序就会把旧版本当成最新版发布出去。
        releases.sort(key=lambda r: r.get("published_at") or r.get("created_at") or "",
                      reverse=True)
        picked: dict[str, list[dict[str, Any]]] = {}
        for rel in releases:
            img = next((a for a in rel.get("assets", []) if a["name"].endswith(".img.xz")), None)
            if not img:
                continue
            if not args.all_tags and not TAG_RE.match(rel["tag_name"]):
                continue                         # 只发 TypixDeck 自己的镜像
            fl = flavor_of(rel["tag_name"], img["name"])
            if args.flavors and fl not in args.flavors:
                continue
            if len(picked.setdefault(fl, [])) < args.per_flavor:
                picked[fl].append(rel)
        releases = [r for rels in picked.values() for r in rels]
        print(f"[plan] {repo}: flavor {', '.join(sorted(picked))} → {len(releases)} 个 release",
              file=sys.stderr)

    entries: list[dict[str, Any]] = []
    spares: list[dict[str, Any]] = []            # 备用线路条目，排在正常条目后面
    seen_flavors: set[str] = set()
    devices: list[dict[str, Any]] | None = None
    icon_cache: dict[str, str] = {}
    failed = 0
    total_bytes = 0

    for rel in sorted(releases, key=lambda r: r.get("published_at", ""), reverse=True):
        tag = rel["tag_name"]
        assets = {a["name"]: a for a in rel.get("assets", [])}
        if "os_list.json" not in assets:
            print(f"  - {tag}: 没有 os_list.json（老 CI 构建？），跳过", file=sys.stderr)
            continue

        meta_path = args.staging / tag / "os_list.json"
        if not fetch_url(assets["os_list.json"]["browser_download_url"], meta_path, quiet=True):
            print(f"  ✗ {tag}: os_list.json 拉取失败", file=sys.stderr)
            failed += 1
            continue
        doc = json.loads(meta_path.read_text(encoding="utf-8"))

        if devices is None and doc.get("imager", {}).get("devices"):
            devices = doc["imager"]["devices"]
            for dev in devices:
                if dev.get("icon"):
                    dev["icon"] = (proxy + dev["icon"] if proxy else
                                   localize_icon(dev["icon"], out / "icons", base_url, icon_cache))

        for entry in doc.get("os_list", []):
            fname = Path(urllib.parse.urlsplit(entry["url"]).path).name
            asset = assets.get(fname)
            if not asset:
                print(f"  ✗ {tag}: os_list.json 指向 {fname}，但 Release 里没有", file=sys.stderr)
                failed += 1
                continue

            # 从新到旧累加，超过额度就不再收更旧的版本（R2 免费额度 10 GB）
            if total_bytes + asset["size"] > args.max_total_gb * 1e9:
                print(f"  ⏭  {tag}/{fname} 超出 {args.max_total_gb} GB 上限，跳过（更旧的版本同理）",
                      file=sys.stderr)
                continue
            total_bytes += asset["size"]

            if not args.no_images:
                local = args.staging / tag / fname
                print(f"  ↓ {tag}/{fname} ({asset['size'] / 1e6:.0f} MB)", file=sys.stderr)
                if not fetch_url(asset["browser_download_url"], local, asset["size"]):
                    print(f"  ✗ {tag}/{fname} 下载失败", file=sys.stderr)
                    failed += 1
                    continue
                want = entry.get("image_download_sha256")
                got = sha256_file(local)
                if want and got != want:
                    print(f"  ✗ {tag}/{fname} sha256 不符（{got[:16]}… != {want[:16]}…），不发布",
                          file=sys.stderr)
                    failed += 1
                    continue
                dest = out / "images" / tag / fname
                dest.parent.mkdir(parents=True, exist_ok=True)
                if not dest.exists():
                    (shutil.copy2 if args.copy_images else os.link)(local, dest)
                print(f"  ✓ {tag}/{fname} sha256 OK", file=sys.stderr)

            if proxy:
                github_url = asset["browser_download_url"]
                entry["url"] = proxy + github_url
                # 主线路挂了用户还有得选：Imager 不支持一个条目多个 URL，
                # 只能把备用线路做成额外条目，且只给每个 flavor 最新的那一版做。
                fl = flavor_of(tag, fname)
                if fl not in seen_flavors:
                    for n, alt in enumerate(proxies[1:], start=2):
                        spare = dict(entry)
                        spare["url"] = alt + github_url
                        spare["name"] = f"{entry['name']}［线路 {n}］"
                        spares.append(spare)
                seen_flavors.add(fl)
            else:
                entry["url"] = f"{base_url}/images/{tag}/{fname}"
            entry["_github_url"] = asset["browser_download_url"]
            if entry.get("icon"):
                entry["icon"] = (proxy + entry["icon"] if proxy else
                                 localize_icon(entry["icon"], out / "icons", base_url, icon_cache))
            entries.append(entry)

    if not entries:
        print("[error] 没有可发布的镜像", file=sys.stderr)
        return 1

    entries.sort(key=lambda e: (e.get("release_date", ""), e.get("name", "")), reverse=True)
    entries += spares

    if args.verify_urls:
        # 绝不给用户留 404：镜像还没传上去（或被滚动删掉）的条目，
        # 回退到 GitHub 原始链接——慢，但一定下得动。
        print(f"[verify] HEAD 校验 {len(entries)} 条下载地址 …", file=sys.stderr)
        with ThreadPoolExecutor(max_workers=8) as pool:
            oks = list(pool.map(lambda e: head_ok(e["url"]), entries))
        for entry, ok in zip(entries, oks):
            if ok:
                continue
            fallback = entry.get("_github_url")
            if fallback:
                print(f"[verify] ✗ {entry['url'].rsplit('/', 1)[-1]} 不在镜像站上，"
                      f"回退 GitHub 原始链接", file=sys.stderr)
                entry["url"] = fallback
            else:
                print(f"[verify] ✗ {entry.get('name')} 无可用地址，剔除", file=sys.stderr)
                entry["_drop"] = True
        entries = [e for e in entries if not e.pop("_drop", False)]

    for entry in entries:
        entry.pop("_github_url", None)

    doc = {"imager": {"devices": devices or []}, "os_list": entries}
    (out / "repo.json").write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n",
                                   encoding="utf-8")

    tpl = (HERE / "site" / "index.html").read_text(encoding="utf-8")
    (out / "index.html").write_text(
        tpl.replace("{{SITE_TITLE}}", cfg.get("site_title", "TypixDeck 镜像站"))
           .replace("{{SITE_NOTE}}", cfg.get("site_note", ""))
           .replace("{{REPO_URL}}", f"{base_url}/repo.json"), encoding="utf-8")

    total = sum(e.get("image_download_size", 0) for e in entries)
    print(f"[done] publish/ 就绪：{len(entries)} 个镜像"
          f"{'（未搬文件）' if args.no_images else f'（{total / 1e9:.1f} GB）'}"
          f" + repo.json + index.html\n"
          f"       Imager 内容仓库地址：{base_url}/repo.json", file=sys.stderr)
    if failed:
        print(f"[warn] {failed} 项失败，已从列表中剔除", file=sys.stderr)

    if args.upload_cmd:
        cmd = args.upload_cmd.replace("{dir}", str(out))
        print(f"[upload] {cmd}", file=sys.stderr)
        return subprocess.run(cmd, shell=True).returncode
    print(f"[next] 把 {out}/ 整个推到国内存储（各家命令见 README）", file=sys.stderr)
    return 1 if failed and not entries else 0


if __name__ == "__main__":
    raise SystemExit(main())
