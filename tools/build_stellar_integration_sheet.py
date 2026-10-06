"""Build a labeled comparison from actual production Godot captures."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

root = Path(__file__).resolve().parents[1] / 'docs/reference/stellar-integration'
font_path = '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
font = ImageFont.truetype(font_path, 22)
small = ImageFont.truetype(font_path, 17)
large = ImageFont.truetype(font_path, 35)
sheet = Image.new('RGB', (1980, 1180), '#071019')
draw = ImageDraw.Draw(sheet)
draw.text((28, 22), 'ASTRYX / PRODUCTION STAR RECIPES', fill='#e4edf4', font=large)
draw.text((28, 76), 'Actual Godot cook and automatic detail selection. Optional variants are labeled.', fill='#96aabd', font=small)
samples = [
    ('solar-uv', 'MAIN SEQUENCE / UV SENSOR', 'Gold is an assigned sensor palette.'),
    ('red-giant', 'RED GIANT / VISIBLE LIGHT', 'Broad convection and a diffuse envelope.'),
    ('white-dwarf-disk', 'WHITE DWARF / OPTIONAL DEBRIS', 'Bare remnant supplied separately.'),
    ('pulsar-wind', 'NEUTRON STAR / OPTIONAL X-RAY WIND', 'Authored 45-radius scale demonstration.'),
    ('red-dwarf', 'RED DWARF / VISIBLE LIGHT', 'Temperature-based orange; magnetic loops.'),
    ('brown-dwarf-aurora', 'BROWN DWARF / ENHANCED AURORA', 'Enhanced visible display; optional curtain.'),
]
for i, (file_id, title, note) in enumerate(samples):
    x, y = 20 + (i % 3) * 655, 118 + (i // 3) * 510
    draw.rectangle((x, y, x + 638, y + 492), fill='#09131c', outline='#243644')
    capture = Image.open(root / (file_id + '.png')).convert('RGB')
    capture.thumbnail((630, 420), Image.Resampling.LANCZOS)
    sheet.paste(capture, (x + (638 - capture.width) // 2, y + 48))
    draw.text((x + 12, y + 12), title, fill='#c7dceb', font=small)
    draw.text((x + 12, y + 467), note, fill='#97adbf', font=small)
draw.text((28, 1143), 'Natural-color Sun, bare remnants, unenhanced brown dwarf and astronomical-scale wind are captured separately.', fill='#97adbf', font=small)
sheet.save(root / 'production-sheet.png')
print(root / 'production-sheet.png')
