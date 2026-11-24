"""
Turns a report written in Markdown into a PDF (no extra Python packages needed).

    python docs/md_to_pdf.py docs/milestone2_report.md

Writes <name>.html next to the .md, then prints it to <name>.pdf with headless
Chrome or Edge. Handles the Markdown the reports use: headings, paragraphs, tables,
images (with the caption line under them), bullet and numbered lists (one level of
nesting), bold, italics, inline code and links.
"""
import html
import os
import re
import subprocess
import sys

BROWSERS = [
    r"C:\Program Files\Google\Chrome\Application\chrome.exe",
    r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    "google-chrome", "chromium",
]

CSS = """
@page { size: Letter; margin: 18mm 16mm 18mm 16mm; }
body { font-family: Calibri, 'Segoe UI', Arial, sans-serif; font-size: 10.5pt; line-height: 1.38;
       color: #111; background: #fff; }
h1 { font-size: 20pt; margin: 0 0 10px; }
h2 { font-size: 15pt; margin: 22px 0 6px; border-bottom: 1px solid #bbb; padding-bottom: 2px;
     break-after: avoid; }
h3 { font-size: 12pt; margin: 14px 0 4px; break-after: avoid; }
p { margin: 5px 0; }
table { border-collapse: collapse; width: 100%; margin: 8px 0 10px; font-size: 9pt;
        break-inside: auto; }
tr { break-inside: avoid; }
th, td { border: 1px solid #999; padding: 3px 5px; vertical-align: top; text-align: left; }
th { background: #e8eef7; }
code { font-family: Consolas, monospace; font-size: 9pt; background: #f2f2f2; padding: 0 2px; }
a { color: #1f5fbf; text-decoration: none; }
figure { margin: 10px 0 12px; break-inside: avoid; }
figure img { max-width: 100%; max-height: 165mm; display: block; margin: 0 auto;
             border: 1px solid #ddd; }
figcaption { font-size: 9pt; color: #333; margin-top: 4px; }
figcaption ul { margin: 2px 0 0 16px; padding: 0; }
ul, ol { margin: 4px 0 6px 22px; padding: 0; }
li { margin: 1px 0; }
"""


def inline(text):
    """Escape, then apply code, links, bold and italics."""
    t = text.strip()
    if len(t) > 2 and t.startswith("*") and t.endswith("*") and not t.startswith("**"):
        return "<i>" + inline(t[1:-1]) + "</i>"       # a whole line in italics (captions)
    parts = re.split(r"(`[^`]+`)", text)
    out = []
    for p in parts:
        if p.startswith("`") and p.endswith("`") and len(p) > 1:
            out.append("<code>" + html.escape(p[1:-1]) + "</code>")
            continue
        p = html.escape(p, quote=False).replace("\\|", "|")
        p = re.sub(r"\[([^\]]+)\]\(([^)\s]+)\)", r'<a href="\2">\1</a>', p)
        p = re.sub(r"\*\*([^*]+)\*\*", r"<b>\1</b>", p)
        p = re.sub(r"(?<![\w*])\*([^*\n]+?)\*(?![\w*])", r"<i>\1</i>", p)
        out.append(p)
    return "".join(out)


def split_row(line):
    cells = re.split(r"(?<!\\)\|", line.strip().strip("|"))
    return [c.strip() for c in cells]


def convert(md):
    lines = md.splitlines()
    out, i = [], 0
    while i < len(lines):
        line = lines[i]
        s = line.strip()
        if not s:
            i += 1
            continue
        m = re.match(r"^(#{1,4})\s+(.*)", s)
        if m:
            n = len(m.group(1))
            out.append(f"<h{n}>{inline(m.group(2))}</h{n}>")
            i += 1
            continue
        m = re.match(r"^!\[([^\]]*)\]\(([^)]+)\)$", s)
        if m:                                             # image + caption lines under it
            alt, src = m.groups()
            i += 1
            while i < len(lines) and not lines[i].strip():
                i += 1
            cap = []
            while i < len(lines) and lines[i].strip() and (lines[i].strip().startswith("*")
                                                           or lines[i].strip().startswith("- *")):
                cap.append(lines[i].strip())
                i += 1
                while i < len(lines) and not lines[i].strip() and i + 1 < len(lines) \
                        and lines[i + 1].strip().startswith("*") and not lines[i + 1].strip().startswith("**"):
                    i += 1
            cap_html, bullets = [], []
            for c in cap:
                if c.startswith("- "):
                    bullets.append("<li>" + inline(c[2:]) + "</li>")
                else:
                    if bullets:
                        cap_html.append("<ul>" + "".join(bullets) + "</ul>")
                        bullets = []
                    cap_html.append("<div>" + inline(c) + "</div>")
            if bullets:
                cap_html.append("<ul>" + "".join(bullets) + "</ul>")
            # terminal-style result images print at 75% width so their text matches the body
            style = ' style="max-width:75%"' if re.search(r"(tests|e2e|system_hs1|system_skew)\.png$", src) else ""
            out.append(f'<figure><img src="{src}" alt="{html.escape(alt)}"{style}>'
                       f'<figcaption>{"".join(cap_html)}</figcaption></figure>')
            continue
        if s.startswith("|"):                             # table
            rows = []
            while i < len(lines) and lines[i].strip().startswith("|"):
                rows.append(split_row(lines[i]))
                i += 1
            head, body = rows[0], [r for r in rows[1:] if not all(re.fullmatch(r":?-+:?", c) for c in r)]
            t = ["<table><thead><tr>" + "".join(f"<th>{inline(c)}</th>" for c in head) + "</tr></thead><tbody>"]
            for r in body:
                t.append("<tr>" + "".join(f"<td>{inline(c)}</td>" for c in r) + "</tr>")
            out.append("".join(t) + "</tbody></table>")
            continue
        if re.match(r"^(\s*)([-*]|\d+\.)\s+", line):    # list with one level of nesting
            ordered = bool(re.match(r"^\s*\d+\.", line))
            items = []
            while i < len(lines) and (re.match(r"^\s*([-*]|\d+\.)\s+", lines[i])
                                      or (lines[i].startswith("  ") and lines[i].strip())):
                l = lines[i]
                ind = len(l) - len(l.lstrip())
                txt = re.sub(r"^\s*([-*]|\d+\.)\s+", "", l)
                if ind >= 2 and items:
                    if re.match(r"^\s*([-*]|\d+\.)\s+", l):
                        items[-1][1].append(txt)
                    else:
                        items[-1][0] += " " + txt.strip()
                else:
                    items.append([txt, []])
                i += 1
            tag = "ol" if ordered else "ul"
            h = [f"<{tag}>"]
            for txt, sub in items:
                h.append("<li>" + inline(txt))
                if sub:
                    h.append("<ul>" + "".join("<li>" + inline(x) + "</li>" for x in sub) + "</ul>")
                h.append("</li>")
            out.append("".join(h) + f"</{tag}>")
            continue
        para = [s]                                        # paragraph
        i += 1
        while i < len(lines) and lines[i].strip() and not re.match(r"^(#|\||!\[|\s*[-*]\s|\s*\d+\.\s)", lines[i]):
            para.append(lines[i].strip())
            i += 1
        out.append("<p>" + inline(" ".join(para)) + "</p>")
    return "\n".join(out)


def main():
    src = sys.argv[1]
    base = os.path.splitext(os.path.abspath(src))[0]
    with open(src, encoding="utf-8") as f:
        md = f.read()
    title = re.search(r"^#\s+(.*)", md, re.M).group(1)
    page = (f"<!doctype html><html><head><meta charset='utf-8'><title>{html.escape(title)}</title>"
            f"<style>{CSS}</style></head><body>{convert(md)}</body></html>")
    with open(base + ".html", "w", encoding="utf-8") as f:
        f.write(page)
    browser = next((b for b in BROWSERS if os.path.exists(b)), None)
    if not browser:
        sys.exit("no Chrome or Edge found; open " + base + ".html and print it to PDF")
    url = "file:///" + (base + ".html").replace("\\", "/")
    subprocess.run([browser, "--headless", "--disable-gpu", "--no-pdf-header-footer",
                    "--print-to-pdf=" + base + ".pdf", url], check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print("wrote", base + ".html and", base + ".pdf")


if __name__ == "__main__":
    main()
