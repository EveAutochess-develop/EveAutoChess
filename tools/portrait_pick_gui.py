# -*- coding: utf-8 -*-
"""Portrait candidate picker — shared pool, copy-on-confirm (non-exclusive).

Each ship folder still shows its shortlist, but you can also browse the shared
icon pool (union of every candidate + optional icons_pool/). Confirm COPIES the
chosen image into chosen/<folder>/; candidates are never moved or deleted, so
the same icon can be assigned to multiple ships.

Usage:
  python portrait_pick_gui.py
  python portrait_pick_gui.py --root ...\\candidates --chosen ...\\chosen
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import tkinter as tk
from pathlib import Path
from tkinter import messagebox, ttk

from PIL import Image, ImageTk

DEFAULT_ROOT = Path(r"H:\game_dev\eveautochess-dev\tools\_portrait_match\candidates")
DEFAULT_CHOSEN = Path(r"H:\game_dev\eveautochess-dev\tools\_portrait_match\chosen")
DEFAULT_POOL = Path(r"H:\game_dev\eveautochess-dev\tools\_portrait_match\icons_pool")
SELECTIONS = Path(r"H:\game_dev\eveautochess-dev\tools\_portrait_match\selections.json")
THUMB = 140
CELL = THUMB + 28  # thumb + padding/label
PAGE_SIZE = 48  # shared-pool page size (avoids loading 1000+ PhotoImages)
IMG_EXTS = {".png", ".jpg", ".jpeg", ".webp", ".bmp", ".gif"}
ICON_ID_RE = re.compile(r"(?:^|_)((?:\d{6,}|(?:\d{9,})))(?:_rgba)?\.png$", re.I)


def extract_icon_id(name: str) -> str | None:
    # filenames like 01_d0.0218_110004009.png or 110004009.png
    m = re.search(r"_(\d{6,})(?:_rgba)?\.png$", name, re.I)
    if m:
        return m.group(1)
    stem = Path(name).stem
    if stem.isdigit() and len(stem) >= 6:
        return stem
    if stem.endswith("_rgba") and stem[: -len("_rgba")].isdigit():
        return stem[: -len("_rgba")]
    return None


class PortraitPicker(tk.Tk):
    def __init__(self, root: Path, chosen: Path, pool: Path) -> None:
        super().__init__()
        self.root_dir = root.resolve()
        self.chosen_dir = chosen.resolve()
        self.pool_dir = pool.resolve()
        self.chosen_dir.mkdir(parents=True, exist_ok=True)

        self.folders: list[Path] = []
        self.folder_idx = 0
        self.mode = tk.StringVar(value="ship")  # ship | pool
        self.images: list[Path] = []  # currently displayed page
        self._all_pool: list[Path] = []
        self._pool_built = False
        self.page_idx = 0
        self.selected: Path | None = None
        self._photo_refs: list[ImageTk.PhotoImage] = []
        self._border_by_path: dict[str, tk.Frame] = {}
        self._last_cols = 0
        self._reflow_job: str | None = None
        self.selections: dict = {}
        if SELECTIONS.exists():
            try:
                self.selections = json.loads(SELECTIONS.read_text(encoding="utf-8"))
            except Exception:
                self.selections = {}

        self.geometry("1100x760")
        self.minsize(720, 520)

        top = ttk.Frame(self, padding=8)
        top.pack(fill=tk.X)
        self.lbl_path = ttk.Label(top, text="", foreground="#666")
        self.lbl_path.pack(anchor=tk.W)
        self.lbl_hint = ttk.Label(
            top,
            text="确认=复制到 chosen/（候选不删不挪，同一张图可分给多艘舰）。可切换「全部共享池」从其它舰的候选里选。",
        )
        self.lbl_hint.pack(anchor=tk.W, pady=(4, 0))

        mode_row = ttk.Frame(self, padding=(8, 0))
        mode_row.pack(fill=tk.X)
        ttk.Radiobutton(
            mode_row, text="本舰候选", variable=self.mode, value="ship", command=self._on_mode_change
        ).pack(side=tk.LEFT)
        ttk.Radiobutton(
            mode_row,
            text="全部共享池（分页，不独占）",
            variable=self.mode,
            value="pool",
            command=self._on_mode_change,
        ).pack(side=tk.LEFT, padx=(12, 0))
        self.btn_prev_page = ttk.Button(mode_row, text="← 上一页", command=self.prev_page)
        self.btn_next_page = ttk.Button(mode_row, text="下一页 →", command=self.next_page)
        self.lbl_page = ttk.Label(mode_row, text="")
        self.btn_prev_page.pack(side=tk.LEFT, padx=(16, 0))
        self.lbl_page.pack(side=tk.LEFT, padx=8)
        self.btn_next_page.pack(side=tk.LEFT)

        mid = ttk.Frame(self)
        mid.pack(fill=tk.BOTH, expand=True, padx=8, pady=4)
        self.canvas = tk.Canvas(mid, highlightthickness=0)
        sb = ttk.Scrollbar(mid, orient=tk.VERTICAL, command=self.canvas.yview)
        self.canvas.configure(yscrollcommand=sb.set)
        sb.pack(side=tk.RIGHT, fill=tk.Y)
        self.canvas.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        self.grid_frame = ttk.Frame(self.canvas)
        self._win = self.canvas.create_window((0, 0), window=self.grid_frame, anchor=tk.NW)
        self.grid_frame.bind("<Configure>", self._on_frame_configure)
        self.canvas.bind("<Configure>", self._on_canvas_configure)
        self.canvas.bind_all("<MouseWheel>", self._on_mousewheel)

        bot = ttk.Frame(self, padding=8)
        bot.pack(fill=tk.X)
        ttk.Button(bot, text="← 上一个文件夹", command=self.prev_folder).pack(side=tk.LEFT)
        ttk.Button(bot, text="下一个文件夹 →", command=self.next_folder).pack(side=tk.LEFT, padx=(8, 0))
        self.lbl_sel = ttk.Label(bot, text="未选中")
        self.lbl_sel.pack(side=tk.LEFT, padx=16)
        ttk.Button(bot, text="确认（复制到 chosen）", command=self.confirm).pack(side=tk.RIGHT)
        ttk.Button(bot, text="无对应图片", command=self.mark_no_match).pack(side=tk.RIGHT, padx=(0, 8))
        ttk.Button(bot, text="刷新", command=self.reload_folders).pack(side=tk.RIGHT, padx=(0, 8))

        self.reload_folders()
        self.after(200, self.refresh_gallery)

    def _on_frame_configure(self, _e=None) -> None:
        self.canvas.configure(scrollregion=self.canvas.bbox("all"))

    def _on_canvas_configure(self, e) -> None:
        self.canvas.itemconfigure(self._win, width=e.width)
        # debounce reflow when column count should change
        if self._reflow_job is not None:
            self.after_cancel(self._reflow_job)
        self._reflow_job = self.after(120, self._maybe_reflow)

    def _grid_cols(self) -> int:
        w = max(
            int(self.canvas.winfo_width() or 0),
            int(self.winfo_width() or 0) - 48,
            900,
        )
        return max(4, w // CELL)

    def _on_mode_change(self) -> None:
        self.page_idx = 0
        self.selected = None
        self.refresh_gallery()

    def prev_page(self) -> None:
        if self.mode.get() != "pool":
            return
        if self.page_idx <= 0:
            return
        self.page_idx -= 1
        self.refresh_gallery()

    def next_page(self) -> None:
        if self.mode.get() != "pool":
            return
        total = len(self._all_pool)
        max_page = max(0, (total - 1) // PAGE_SIZE)
        if self.page_idx >= max_page:
            return
        self.page_idx += 1
        self.refresh_gallery()

    def _update_page_controls(self) -> None:
        pool = self.mode.get() == "pool"
        state = tk.NORMAL if pool else tk.DISABLED
        self.btn_prev_page.configure(state=state)
        self.btn_next_page.configure(state=state)
        if not pool:
            self.lbl_page.configure(text="")
            return
        total = len(self._all_pool)
        pages = max(1, (total + PAGE_SIZE - 1) // PAGE_SIZE)
        self.lbl_page.configure(text=f"第 {self.page_idx + 1}/{pages} 页（共 {total} 张，每页 {PAGE_SIZE}）")

    def _maybe_reflow(self) -> None:
        self._reflow_job = None
        if not self.images:
            return
        cols = self._grid_cols()
        if cols != self._last_cols:
            # only re-grid current page (already in self.images)
            self._render_grid(self.images)

    def _on_mousewheel(self, e) -> None:
        self.canvas.yview_scroll(int(-1 * (e.delta / 120)), "units")

    def reload_folders(self) -> None:
        if not self.root_dir.is_dir():
            messagebox.showerror("错误", f"根目录不存在:\n{self.root_dir}")
            return
        self.folders = sorted(
            [p for p in self.root_dir.iterdir() if p.is_dir() and not p.name.startswith("_")],
            key=lambda p: p.name.lower(),
        )
        self._pool_built = False
        self._all_pool = []
        if not self.folders:
            self.title("（无子文件夹）")
            self._clear_grid()
            messagebox.showinfo("提示", f"没有子文件夹:\n{self.root_dir}")
            return
        self.folder_idx = min(self.folder_idx, len(self.folders) - 1)
        self.refresh_gallery()

    def current_folder(self) -> Path | None:
        if not self.folders:
            return None
        return self.folders[self.folder_idx]

    def prev_folder(self) -> None:
        if not self.folders:
            return
        self.folder_idx = (self.folder_idx - 1) % len(self.folders)
        self.mode.set("ship")
        self.refresh_gallery()

    def next_folder(self) -> None:
        if not self.folders:
            return
        self.folder_idx = (self.folder_idx + 1) % len(self.folders)
        self.mode.set("ship")
        self.refresh_gallery()

    def _clear_grid(self) -> None:
        for w in self.grid_frame.winfo_children():
            w.destroy()
        self._photo_refs.clear()
        self._border_by_path.clear()
        self.images.clear()
        self.selected = None
        self.lbl_sel.configure(text="未选中")

    def _list_preview_images(self, folder: Path) -> list[Path]:
        files = sorted(
            [
                p
                for p in folder.iterdir()
                if p.is_file()
                and p.suffix.lower() in IMG_EXTS
                and not p.name.lower().endswith("_rgba.png")
                and p.name != "无对应图片.txt"
            ],
            key=lambda p: p.name.lower(),
        )
        if not files:
            files = sorted(
                [
                    p
                    for p in folder.iterdir()
                    if p.is_file() and p.suffix.lower() in IMG_EXTS
                ],
                key=lambda p: p.name.lower(),
            )
        return files

    def _ensure_pool(self) -> None:
        if self._pool_built:
            return
        by_id: dict[str, Path] = {}
        # Prefer dedicated pool (preview only, not _rgba) — cheap & complete enough
        if self.pool_dir.is_dir():
            for p in self.pool_dir.iterdir():
                if not p.is_file() or p.suffix.lower() not in IMG_EXTS:
                    continue
                if p.name.lower().endswith("_rgba.png"):
                    continue
                iid = extract_icon_id(p.name) or p.stem
                by_id[iid] = p
        # Supplement with unique previews from ship shortlists (still one path per id)
        if not by_id:
            for folder in self.folders:
                for p in self._list_preview_images(folder):
                    iid = extract_icon_id(p.name)
                    if iid and iid not in by_id:
                        by_id[iid] = p
        self._all_pool = [by_id[k] for k in sorted(by_id.keys())]
        self._pool_built = True

    def refresh_gallery(self) -> None:
        folder = self.current_folder()
        if folder is None:
            return
        self.title(folder.name)
        status = ""
        key = folder.name.split("__", 1)[0]
        if key in self.selections:
            status = f"  |  已选: {self.selections[key].get('icon_id') or self.selections[key].get('status')}"
        mode = self.mode.get()
        if mode == "ship":
            self.lbl_path.configure(
                text=f"{folder}    ({self.folder_idx + 1}/{len(self.folders)})  [本舰候选]{status}"
            )
            files = self._list_preview_images(folder)
        else:
            try:
                self._ensure_pool()
            except Exception as e:
                messagebox.showerror("共享池失败", str(e))
                self.mode.set("ship")
                self.refresh_gallery()
                return
            total = len(self._all_pool)
            max_page = max(0, (total - 1) // PAGE_SIZE) if total else 0
            self.page_idx = min(self.page_idx, max_page)
            start = self.page_idx * PAGE_SIZE
            files = self._all_pool[start : start + PAGE_SIZE]
            self.lbl_path.configure(
                text=f"{folder.name}    ({self.folder_idx + 1}/{len(self.folders)})  [共享池]{status}"
            )
        self._update_page_controls()
        self._render_grid(files)

    def _render_grid(self, files: list[Path]) -> None:
        self._clear_grid()
        self.images = list(files)
        cols = self._grid_cols()
        self._last_cols = cols
        for i, path in enumerate(files):
            cell = ttk.Frame(self.grid_frame, padding=6)
            r, c = divmod(i, cols)
            cell.grid(row=r, column=c, sticky=tk.N)
            try:
                with Image.open(path) as raw:
                    im = raw.convert("RGBA")
                    im.thumbnail((THUMB, THUMB), Image.Resampling.LANCZOS)
                    bg = Image.new("RGB", im.size, (28, 32, 44))
                    bg.paste(im, mask=im.split()[-1])
                    photo = ImageTk.PhotoImage(bg)
                    im.close()
            except Exception as e:
                ttk.Label(cell, text=f"读失败\n{path.name}\n{e}", wraplength=THUMB).pack()
                continue
            self._photo_refs.append(photo)
            border = tk.Frame(cell, bd=3, relief=tk.FLAT, bg="#2a2e3a")
            border.pack()
            self._border_by_path[str(path)] = border
            btn = tk.Label(border, image=photo, cursor="hand2", bg="#2a2e3a")
            btn.pack()
            btn.bind("<Button-1>", lambda _e, p=path: self.select(p))
            iid = extract_icon_id(path.name) or path.name
            label = iid if len(iid) <= 28 else iid[:12] + "…" + iid[-12:]
            ttk.Label(cell, text=label, wraplength=THUMB + 8).pack()
        if not files:
            ttk.Label(self.grid_frame, text="（没有图片）").grid(row=0, column=0)
        # release scroll to top
        self.canvas.yview_moveto(0)

    def select(self, path: Path) -> None:
        self.selected = path
        iid = extract_icon_id(path.name) or path.name
        self.lbl_sel.configure(text=f"已选: {iid}")
        for pth, border in self._border_by_path.items():
            border.configure(bg="#3d8bfd" if pth == str(path) else "#2a2e3a")

    def _resolve_rgba(self, preview: Path) -> Path:
        """Prefer sibling *_rgba.png or icons_pool/{id}_rgba.png / {id}.png."""
        if preview.name.lower().endswith("_rgba.png"):
            return preview
        sibling = preview.with_name(preview.stem + "_rgba.png")
        if sibling.exists():
            return sibling
        iid = extract_icon_id(preview.name)
        if iid:
            for cand in (
                self.pool_dir / f"{iid}_rgba.png",
                self.pool_dir / f"{iid}.png",
                preview.parent / f"{preview.stem}_rgba.png",
            ):
                if cand.exists():
                    return cand
        return preview

    def _save_selections(self) -> None:
        SELECTIONS.write_text(
            json.dumps(self.selections, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )

    def confirm(self) -> None:
        folder = self.current_folder()
        if folder is None:
            return
        if self.selected is None or not self.selected.exists():
            messagebox.showwarning("未选中", "请先点选一张图片（本舰候选或共享池均可）")
            return
        src = self._resolve_rgba(self.selected)
        iid = extract_icon_id(self.selected.name) or self.selected.stem
        dest_dir = self.chosen_dir / folder.name
        dest_dir.mkdir(parents=True, exist_ok=True)
        # clear previous choice files in this chosen folder (keep structure)
        for old in dest_dir.iterdir():
            if old.is_file():
                old.unlink()
        dest = dest_dir / f"{iid}.png"
        shutil.copy2(src, dest)
        # also a stable name
        shutil.copy2(src, dest_dir / "portrait.png")
        key = folder.name.split("__", 1)[0]
        self.selections[key] = {
            "folder": folder.name,
            "icon_id": iid,
            "source": str(src),
            "chosen": str(dest),
            "status": "ok",
        }
        self._save_selections()
        messagebox.showinfo(
            "已复制",
            f"已为【{folder.name}】选定 icon {iid}\n"
            f"复制到:\n  {dest}\n\n"
            f"候选文件夹未改动，其它舰仍可选用同一张图。",
        )
        self.next_folder()

    def mark_no_match(self) -> None:
        folder = self.current_folder()
        if folder is None:
            return
        if not messagebox.askyesno(
            "无对应图片",
            f"文件夹: {folder.name}\n\n"
            f"不删候选。仅在 chosen/ 下写入「无对应图片.txt」占位。",
        ):
            return
        dest_dir = self.chosen_dir / folder.name
        dest_dir.mkdir(parents=True, exist_ok=True)
        for old in dest_dir.iterdir():
            if old.is_file():
                old.unlink()
        note = dest_dir / "无对应图片.txt"
        note.write_text(
            f"无对应图片\n"
            f"========\n"
            f"文件夹: {folder.name}\n"
            f"说明: 共享池/本舰候选中没有正确的手游市场立绘。\n"
            f"候选原文件均保留，未移动。\n",
            encoding="utf-8",
        )
        key = folder.name.split("__", 1)[0]
        self.selections[key] = {
            "folder": folder.name,
            "icon_id": None,
            "status": "no_match",
            "chosen": str(note),
        }
        self._save_selections()
        messagebox.showinfo("完成", f"已留下占位:\n{note}")
        self.next_folder()


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", type=Path, default=DEFAULT_ROOT)
    ap.add_argument("--chosen", type=Path, default=DEFAULT_CHOSEN)
    ap.add_argument("--pool", type=Path, default=DEFAULT_POOL)
    args = ap.parse_args()
    app = PortraitPicker(args.root, args.chosen, args.pool)
    app.mainloop()


if __name__ == "__main__":
    main()
