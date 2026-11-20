#!/usr/bin/env python3
"""Terminal output with ANSI colors → an SVG terminal window in the style of docs/images.

ansi2svg.py TITLE COMMAND INPUT OUTPUT [--until TEXT] [--cursor] [--keep N]
  --until TEXT  stop after the first line that contains TEXT
  --cursor      draw a block cursor at the end of the last line (a prompt waiting for input)
  --keep N      drop lines from the top, keeping the last N (the first line, macup's own, stays)
"""
import argparse, html, re, unicodedata

BG, BORDER, BAR, TITLE = "#17181c", "#33353c", "#26272d", "#9a9ea8"
NORMAL, BOLD, DIM, PROMPT = "#d6d8de", "#f2f3f5", "#7d818c", "#c792ea"
COLORS = {31: "#ff6b6b", 32: "#5fd38d", 33: "#e8c468", 35: "#c792ea", 36: "#5cc8dc", 37: "#ffffff"}
CW, LH, X0, Y0 = 7.8, 20, 22.0, 64   # char width, line height, left margin, baseline of the first line
MONO = "ui-monospace, 'SF Mono', SFMono-Regular, Menlo, Monaco, Consolas, 'Liberation Mono', monospace"
SANS = "-apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif"
SGR = re.compile(r"\x1b\[([0-9;?]*)([A-Za-z])")


def width(ch):
    return 2 if unicodedata.east_asian_width(ch) in "WF" else 1


def emulate(raw):
    """\\r returns to the line start and \\x1b[K clears the rest, as the terminal did; lines of [char, style]."""
    out, line, col, style = [], [], 0, (False, False, None)
    i = 0
    while i < len(raw):
        c = raw[i]
        m = SGR.match(raw, i) if c == "\x1b" else None
        if m:
            codes, cmd = m.group(1), m.group(2)
            if cmd == "m":
                bold, dim, color = style
                for n in [int(x) for x in codes.split(";") if x.isdigit()] or [0]:
                    if n == 0: bold, dim, color = False, False, None
                    elif n == 1: bold = True
                    elif n == 2: dim = True
                    elif n in COLORS: color = n
                    elif n == 39: color = None
                style = (bold, dim, color)
            elif cmd == "K":
                del line[col:]
            i = m.end(); continue
        if c == "\r": col = 0
        elif c == "\n": out.append(line); line, col = [], 0
        elif c == "\x1b": pass
        else:
            if col < len(line): line[col] = [c, style]
            else: line.append([c, style])
            col += 1
        i += 1
    if line: out.append(line)
    return out


def runs(line):
    """[char, style] → (column, text, style) runs; spaces end a run so every word lands on its own grid column."""
    col, cur, start, res = 0, None, 0, []
    for ch, st in line:
        key = None if ch == " " else st
        if key != cur or ch == " ":
            if cur is not None and buf: res.append((start, "".join(buf), cur))
            buf, cur, start = [], key, col
        if ch != " ": buf.append(ch)
        col += width(ch)
    if cur is not None and buf: res.append((start, "".join(buf), cur))
    return res, col


def fill(st):
    bold, dim, color = st
    if dim and color is None: return DIM, False
    if color is not None: return COLORS[color], bold
    return (BOLD if bold else NORMAL), bold


def svg(title, command, lines, cursor):
    body = [[["❯", (True, False, 35)], [" ", (False, False, None)]] + [[c, (True, False, 37)] for c in command]] + lines
    cols = max([runs(l)[1] for l in body] + [80])
    w = round(X0 * 2 + cols * CW)
    h = Y0 + (len(body) - 1) * LH + 26
    o = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}" role="img" aria-label="{html.escape(title)}">',
         f"<title>{html.escape(title)}</title>",
         f'<rect width="{w}" height="{h}" rx="10" fill="{BG}"/>',
         f'<rect x="0.5" y="0.5" width="{w - 1}" height="{h - 1}" rx="10" fill="none" stroke="{BORDER}"/>',
         f'<path d="M10.5 0.5h{w - 21}a10 10 0 0 1 10 10v23h-{w - 1}v-23a10 10 0 0 1 10-10z" fill="{BAR}"/>',
         '<circle cx="22" cy="17" r="6" fill="#ff5f57"/><circle cx="42" cy="17" r="6" fill="#febc2e"/><circle cx="62" cy="17" r="6" fill="#28c840"/>',
         f'<text x="{w / 2:.1f}" y="21.5" text-anchor="middle" font-family="{SANS}" font-size="12.5" fill="{TITLE}">{html.escape(title)}</text>',
         f'<g font-family="{MONO}" font-size="13" xml:space="preserve">']
    for n, line in enumerate(body):
        y = Y0 + n * LH
        rs, end = runs(line)
        for col, text, st in rs:
            color, bold = fill(st)
            if n == 0 and text == "❯": color = PROMPT
            ln = sum(width(c) for c in text)
            attrs = f' font-weight="bold"' if bold else ""
            if ln > 1: attrs += f' textLength="{ln * CW:.1f}" lengthAdjust="spacing"'
            o.append(f'<text x="{X0 + col * CW:.1f}" y="{y}" fill="{color}"{attrs}>{html.escape(text)}</text>')
        if cursor and n == len(body) - 1:
            o.append(f'<rect x="{X0 + (end + 1) * CW:.1f}" y="{y - 12}" width="{CW:.1f}" height="16" fill="{NORMAL}" opacity="0.8"/>')
    o += ["</g>", "</svg>"]
    return "\n".join(o) + "\n"


def main():
    a = argparse.ArgumentParser()
    a.add_argument("title"); a.add_argument("command"); a.add_argument("input"); a.add_argument("output")
    a.add_argument("--until"); a.add_argument("--cursor", action="store_true"); a.add_argument("--keep", type=int)
    p = a.parse_args()
    lines = emulate(open(p.input, encoding="utf-8", errors="replace", newline="").read())   # \r is the terminal's, not a line end
    text = lambda l: "".join(c for c, _ in l)
    while lines and not text(lines[0]).strip(): lines.pop(0)
    if p.until:
        for i, l in enumerate(lines):
            if p.until in text(l): lines = lines[: i + 1]; break
    while lines and not text(lines[-1]).strip(): lines.pop()
    if p.keep and len(lines) > p.keep: lines = lines[:1] + [[]] + lines[-(p.keep - 2):]
    # two blank lines in a row are one
    lines = [l for i, l in enumerate(lines) if text(l).strip() or i == 0 or text(lines[i - 1]).strip()]
    open(p.output, "w", encoding="utf-8").write(svg(p.title, p.command, lines, p.cursor))


if __name__ == "__main__":
    main()
