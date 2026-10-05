#!/usr/bin/env python3
"""Shows PNG images with the Kitty graphics protocol (Ghostty): by default
in the terminal Claude Code runs in, where its prompts may be drawn over
or under them; with --window in a new Ghostty window, closed with Enter.
The shell of a tool call has no terminal of its own, so the image goes to
the first ancestor process that has one.

    show.py shot.png [more.png ...] [--window] [--cols 80]
"""

import argparse
import base64
import os
import shutil
import subprocess
import sys
import tempfile


def terminal() -> str:
    pid = os.getppid()
    while pid > 1:
        ppid, tty = subprocess.check_output(["ps", "-o", "ppid=,tty=", "-p", str(pid)], text=True).split()
        if tty not in ("??", "-"):
            return "/dev/" + tty
        pid = int(ppid)
    raise SystemExit("no terminal found among the parent processes")


def fitting(path: str, size: os.terminal_size, most: int) -> int:
    """The columns (at most [most]) that fit the image into a terminal of
    [size], a cell being about twice as high as wide."""
    out = subprocess.check_output(["sips", "-g", "pixelWidth", "-g", "pixelHeight", path], text=True).split()
    w, h = int(out[out.index("pixelWidth:") + 1]), int(out[out.index("pixelHeight:") + 1])
    return max(10, min(most, size.columns - 2, int((size.lines - 3) * 2 * w / h)))


def show(path: str, cols: int, tty) -> None:
    # Large screenshots shrunk (sips, macOS): a smaller transfer, same look.
    with tempfile.TemporaryDirectory() as tmp:
        small = os.path.join(tmp, "shot.png")
        subprocess.run(["sips", "-Z", "1400", path, "--out", small], check=True, capture_output=True)
        data = base64.b64encode(open(small, "rb").read()).decode()
    chunks = [data[i : i + 4096] for i in range(0, len(data), 4096)]
    tty.write("\r\n")
    for i, chunk in enumerate(chunks):
        head = f"f=100,a=T,c={cols},q=2," if i == 0 else ""
        tty.write(f"\x1b_G{head}m={int(i < len(chunks) - 1)};{chunk}\x1b\\")
    tty.write("\r\n")


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("images", nargs="+")
    p.add_argument("--cols", type=int, default=0, help="width in terminal columns (default: the window's)")
    p.add_argument("--window", action="store_true", help="in a new Ghostty window instead of Claude Code's terminal")
    p.add_argument("--here", action="store_true", help=argparse.SUPPRESS)  # inside the new window
    a = p.parse_args()
    images = [os.path.abspath(i) for i in a.images]
    if a.here:
        for path in images:
            print(os.path.basename(path))
            show(path, a.cols or fitting(path, shutil.get_terminal_size(), 400), sys.stdout)
        sys.stdout.flush()
        input("Enter closes the window ")
    elif not a.window:
        dev = terminal()
        rows, cols = map(int, subprocess.check_output(["stty", "-f", dev, "size"], text=True).split())
        with open(dev, "w") as tty:
            for path in images:
                show(path, a.cols or fitting(path, os.terminal_size((cols, rows)), 100), tty)
        print(f"shown on {dev}: {', '.join(images)}")
    else:
        cmd = [sys.executable, os.path.abspath(__file__), "--here", *images]
        if a.cols:
            cmd += ["--cols", str(a.cols)]
        subprocess.run(["open", "-na", "Ghostty.app", "--args", "--window-width=170", "--window-height=60", "-e", *cmd], check=True)
        print(f"shown in a new Ghostty window: {', '.join(images)}")


if __name__ == "__main__":
    main()
