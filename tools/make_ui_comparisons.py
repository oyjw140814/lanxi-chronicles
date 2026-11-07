"""Compose before/after renders without changing their contents or aspect ratios."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
root = Path(__file__).resolve().parents[1]
out = root / 'builds/ui-refinement'
font = ImageFont.truetype(str(root / 'assets/fonts/NotoSansSC.ttf'), 26)
for name, before, after in [
    ('desktop', 'before-desktop', '02-desktop'),
    ('mobile', 'before-mobile', '07-mobile'),
    ('recruitment', 'before-recruitment', '03-recruitment'),
    ('title', 'before-title', '01-title'),
]:
    pair = [Image.open(out / f'{stem}.png').convert('RGB') for stem in (before, after)]
    width = 1120
    pair = [im.resize((width, round(im.height * width / im.width)), Image.Resampling.LANCZOS) for im in pair]
    canvas = Image.new('RGB', (width * 2 + 48, max(im.height for im in pair) + 76), '#10272e')
    draw = ImageDraw.Draw(canvas)
    for i, (im, label) in enumerate(zip(pair, ['改前 · 同场景', '改后 · 雾海奇幻'])):
        x = 16 + i * (width + 16)
        draw.text((x + 8, 16), label, font=font, fill='#eee8d7' if i == 0 else '#68cbc1')
        canvas.paste(im, (x, 60))
    canvas.save(out / f'comparison-{name}.png')
print('Wrote four same-scene comparisons')
