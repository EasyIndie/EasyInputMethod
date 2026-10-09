#!/usr/bin/env python3
"""Generate synthetic capacity data only into a new explicit test file."""
import sys
from pathlib import Path
path = Path(sys.argv[1])
with path.open('x', encoding='utf-8') as output:
    output.write('# lampyris-user-dictionary v1\n')
    for index in range(10000):
        code = 'a' + ''.join(chr(97 + (index // (26 ** power)) % 26) for power in [2, 1, 0])
        output.write(f'wubi\t{code}\t' + '测' * 60 + str(index) + '\t10\n')
print(f'合成容量词库：{path.stat().st_size} 字节 / 10000条，无真实用户数据')
