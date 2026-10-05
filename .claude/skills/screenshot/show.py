#!/usr/bin/env python3
"""Shows PNG images with the Kitty graphics protocol (Ghostty): by default
pinned to the top right of the terminal Claude Code runs in, leaving its
bottom rows free for a question box; with --window in a new Ghostty window,
closed with Enter. The shell of a tool call has no terminal of its own, so
the image goes to the first ancestor process that has one.

    show.py shot.png [more.png ...] [--window] [--keep-rows 20]
    show.py --clear      removes the images shown in Claude Code's terminal

Each show first removes the images shown before, so at most one set stays
on the screen. Several images sit side by side, the first on the right.

The terminal reads the images from files (Kitty's t=f): a show is one small
write. Claude Code redraws the same terminal; megabytes of image data
written in pieces got mixed with its output, broke into text and landed in
the wrong place.
"""

import argparse
import base64
import fcntl
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import termios


def terminal() -> str:
    pid = os.getppid()
    while pid > 1:
        ppid, tty = subprocess.check_output(["ps", "-o", "ppid=,tty=", "-p", str(pid)], text=True).split()
        if tty not in ("??", "-"):
            return "/dev/" + tty
        pid = int(ppid)
    raise SystemExit("no terminal found among the parent processes")


def size_of(tty) -> tuple[int, int, float]:
    """Rows, columns, and a cell's height over its width (2 if unknown)."""
    rows, cols, xpix, ypix = struct.unpack("HHHH", fcntl.ioctl(tty.fileno(), termios.TIOCGWINSZ, b"\0" * 8))
    aspect = (ypix / rows) / (xpix / cols) if xpix and ypix else 2.0
    return rows, cols, aspect


def pixels(path: str) -> tuple[int, int]:
    out = subprocess.check_output(["sips", "-g", "pixelWidth", "-g", "pixelHeight", path], text=True).split()
    return int(out[out.index("pixelWidth:") + 1]), int(out[out.index("pixelHeight:") + 1])


def clear(tty) -> None:
    """Deletes every image in the terminal, with its data (Kitty protocol)."""
    tty.write("\x1b_Ga=d,d=A,q=2\x1b\\")


CACHE = os.path.join(tempfile.gettempdir(), "alvyo-show")


def placed(path: str, cols: int, n: int) -> str:
    """The escape sequence that shows path, shrunk into a copy the terminal
    reads itself, cols wide, without moving the cursor."""
    os.makedirs(CACHE, exist_ok=True)
    copy = os.path.join(CACHE, f"{n}.png")
    subprocess.run(["sips", "-Z", "1400", path, "--out", copy], check=True, capture_output=True)
    name = base64.b64encode(copy.encode()).decode()
    return f"\x1b_Gf=100,t=f,a=T,c={cols},C=1,q=2;{name}\x1b\\"


def send(path: str, cols: int, tty, move_cursor: bool = True) -> None:
    # Large screenshots shrunk (sips, macOS): a smaller transfer, same look.
    with tempfile.TemporaryDirectory() as tmp:
        small = os.path.join(tmp, "shot.png")
        subprocess.run(["sips", "-Z", "1400", path, "--out", small], check=True, capture_output=True)
        data = base64.b64encode(open(small, "rb").read()).decode()
    chunks = [data[i : i + 4096] for i in range(0, len(data), 4096)]
    for i, chunk in enumerate(chunks):
        head = f"f=100,a=T,c={cols},q=2,{'' if move_cursor else 'C=1,'}" if i == 0 else ""
        tty.write(f"\x1b_G{head}m={int(i < len(chunks) - 1)};{chunk}\x1b\\")


def pinned(images: list[str], tty, keep_rows: int) -> None:
    """The images at the top right, side by side, at most keep_rows from the
    bottom and half the width; the cursor stays where Claude Code left it."""
    rows, cols, aspect = size_of(tty)
    height = max(5, rows - keep_rows - 1)
    width = max(10, cols // 2) // len(images)
    right = cols
    out = "\x1b_Ga=d,d=A,q=2\x1b\\\x1b7"  # the images before gone; save the cursor
    for n, path in enumerate(images):
        w, h = pixels(path)
        c = max(5, min(width, int(height * aspect * w / h)))
        right -= c
        out += f"\x1b[1;{right + 1}H" + placed(path, c, n)
        right -= 1
    # One write: nothing of Claude Code's comes between moving the cursor
    # and putting it back.
    tty.write(out + "\x1b8")
    tty.flush()


def fitting(path: str, size: os.terminal_size) -> int:
    """The columns that fit the image into a window of [size], a cell being
    about twice as high as wide."""
    w, h = pixels(path)
    return max(10, min(size.columns - 2, int((size.lines - 3) * 2 * w / h)))


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("images", nargs="*")
    p.add_argument("--clear", action="store_true", help="remove the images shown in Claude Code's terminal")
    p.add_argument("--window", action="store_true", help="in a new Ghostty window instead of Claude Code's terminal")
    p.add_argument("--keep-rows", type=int, default=20, help="rows left free at the bottom, for a question box")
    p.add_argument("--here", action="store_true", help=argparse.SUPPRESS)  # inside the new window
    a = p.parse_args()
    if a.clear:
        dev = terminal()
        with open(dev, "w") as tty:
            clear(tty)
        print(f"images removed on {dev}")
        return
    if not a.images:
        p.error("no images")
    images = [os.path.abspath(i) for i in a.images]
    if a.here:
        for path in images:
            print(os.path.basename(path))
            send(path, fitting(path, shutil.get_terminal_size()), sys.stdout)
            print()
        sys.stdout.flush()
        input("Enter closes the window ")
    elif a.window:
        cmd = [sys.executable, os.path.abspath(__file__), "--here", *images]
        subprocess.run(["open", "-na", "Ghostty.app", "--args", "--window-width=170", "--window-height=60", "-e", *cmd], check=True)
        print(f"shown in a new Ghostty window: {', '.join(images)}")
    else:
        dev = terminal()
        with open(dev, "w") as tty:
            pinned(images, tty, a.keep_rows)
        print(f"shown at the top right of {dev}: {', '.join(images)}")


if __name__ == "__main__":
    main()
