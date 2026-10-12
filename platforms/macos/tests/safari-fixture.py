#!/usr/bin/env python3
"""Create a private offline page without interacting with browser state."""
import json
import os
from pathlib import Path
import tempfile


def create_fixture(parent: Path) -> dict[str, str]:
    directory = Path(tempfile.mkdtemp(prefix="safari-fixture-", dir=parent))
    title = directory.name
    page = directory / "index.html"
    content = f'''<!doctype html>
<html lang="zh-CN"><meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; form-action 'none'; base-uri 'none'">
<title>{title}</title>
<label for="fixture-input">萤火虫隔离输入验收</label>
<textarea id="fixture-input" aria-label="{title}" autofocus spellcheck="false"></textarea>
</html>
'''
    descriptor = os.open(page, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "w") as stream:
        stream.write(content)
    return {"directory": str(directory), "url": page.as_uri(), "title": title}


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("parent", type=Path)
    print(json.dumps(create_fixture(parser.parse_args().parent)))
