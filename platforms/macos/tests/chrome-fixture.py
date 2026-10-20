#!/usr/bin/env python3
"""Create a private offline Chrome page that reports its own state through the tab title.

Chrome does not expose page content to a non-assistive AX client, but the tab title is
readable from AppleScript, so the fixture mirrors the focused element and the textarea
value into the title and the probe only trusts that channel.
"""
import json
import os
from pathlib import Path
import tempfile

PREFIX = "fx"


def create_fixture(parent: Path) -> dict[str, str]:
    directory = Path(tempfile.mkdtemp(prefix="chrome-fixture-", dir=parent))
    title = directory.name
    page = directory / "index.html"
    content = f'''<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; form-action 'none'; base-uri 'none'">
<title>{title}</title></head>
<body>
<label for="fixture-input">萤火虫 Chrome 隔离输入验收</label>
<textarea id="fixture-input" aria-label="{title}" autofocus spellcheck="false" style="width:40em;height:6em"></textarea>
<script>
const field = document.getElementById("fixture-input");
// 标题是探针唯一可信的读取通道：不要在里面放任何输入内容以外的东西。
function report() {{
  document.title = "{PREFIX}|" + "{title}|" + (document.activeElement && document.activeElement.id || "none")
    + "|" + field.value.replace(/\\s/g, " ");
}}
field.addEventListener("input", report);
field.addEventListener("focus", report);
field.addEventListener("blur", report);
window.addEventListener("load", function () {{ field.focus(); report(); }});
report();
</script>
</body></html>
'''
    descriptor = os.open(page, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "w") as stream:
        stream.write(content)
    return {"directory": str(directory), "url": page.as_uri(), "title": title, "prefix": PREFIX}


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("parent", type=Path)
    print(json.dumps(create_fixture(parser.parse_args().parent)))
