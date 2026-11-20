"""Create a double-clickable, offline preview with the actual local release links."""
from pathlib import Path
import re
import shutil

site = Path(__file__).resolve().parent
repo = site.parent
preview = repo / ".build" / "website-preview"
source = site / "dist"
html = (source / "index.html").read_text()
html = re.sub(r'(<meta name="goatcounter-code" content=")[^"]*(">)', r"\1\2", html)
html = re.sub(r'(<p id="metrics-note">).*?(</p>)', r"\1Website analytics are off in this preview.\2", html)
prefix = "https://github.com/Anshumaan-25/Murmur/releases/download/"
links = re.findall(r'href="(' + re.escape(prefix) + r'[^"]+)"', html)
if len(links) != 2:
    raise SystemExit("Expected a DMG and checksum link in the website.")
downloads = preview / "downloads"
downloads.mkdir(parents=True, exist_ok=True)
for url in links:
    name = url.rsplit("/", 1)[1]
    path = repo / "artifacts/releases" / name.split(".dmg")[0] / name
    if not path.is_file():
        raise SystemExit(f"Missing release asset: {path}")
    target = downloads / name
    if not target.exists():
        target.symlink_to(path)
    if target.resolve() != path.resolve():
        raise SystemExit(f"Unexpected preview asset: {target}")
    html = html.replace(url, "downloads/" + name)
shutil.copytree(source, preview, dirs_exist_ok=True)
(preview / "index.html").write_text(html)
print(preview / "index.html")
