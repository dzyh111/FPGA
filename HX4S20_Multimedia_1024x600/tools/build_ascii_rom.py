"""Lossless mechanical conversion of the existing 5x7 font into row ROM."""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
source = (root / 'rtl/font5x7.vh').read_text(encoding='ascii')
glyphs = {int(c): int(bits, 2) for c, bits in
          re.findall(r"8'd(\d+):\s*glyph=35'b([01]{35});", source)}
assert len(glyphs) >= 40
rows = []
for character in range(128):
    value = glyphs.get(character - 32 if 97 <= character <= 122 else character, 0)
    rows.extend((value >> (30 - row * 5)) & 31 if row < 7 else 0 for row in range(8))
assert len(rows) == 1024
(root / 'rtl/ascii_font_rows.hex').write_text(''.join(f'{v:02x}\n' for v in rows), encoding='ascii')
print('Generated lossless ASCII row ROM: 1024 x 5 bits')
