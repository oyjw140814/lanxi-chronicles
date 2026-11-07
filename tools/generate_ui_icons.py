"""Deterministic original UI symbols; no third-party icon font dependency."""
from pathlib import Path
out = Path(__file__).resolve().parents[1] / 'assets/ui/icons'
out.mkdir(parents=True, exist_ok=True)
paths = {
'food':'<path d="M14 27 20 6M18 13C9 14 8 8 9 6c6 0 9 3 9 7Zm-2 7c-7 1-10-3-10-6 6-2 9 1 10 6Zm3-6c7 0 9-5 8-8-6 0-9 3-8 8Zm-2 7c7 2 11-2 12-6-6-2-10 1-12 6Z" fill="#c9a96c"/>',
'wood':'<path d="m5 22 5-16 15 5-5 16Z" fill="#72a896"/><path d="m10 6 15 5M8 13l14 5M5 22l15 5M15 9l-4 15"/>',
'crystal':'<path d="m16 3 10 12-10 14L6 15Z" fill="#68cbc1"/><path d="m16 3-3 12 3 14 4-14ZM6 15h20" stroke="#e6efda"/>',
'home':'<path d="m4 15 12-10 12 10M8 13v14h16V13M13 27v-9h6v9"/>',
'pause':'<path d="M11 7v18M21 7v18" stroke-width="4"/>',
'play':'<path d="m10 5 16 11-16 11Z"/>',
'stop':'<rect x="7" y="7" width="18" height="18" rx="2"/>',
'select':'<path d="M12 5H5v7m15-7h7v7M5 20v7h7m15-7v7h-7M11 16l4 4 7-8"/>',
'attack':'<path d="M7 26 26 7l-7-1L7 19m3-9 12 12M5 21l6 6M6 5l20 21M20 27l7-7"/>',
'gather':'<path d="m8 26 12-20M7 12c6-8 12-9 20-4l-8 1M6 24l4 3"/>',
'move':'<path d="M5 25 25 5M12 5h13v13M6 16v10h10"/>',
'close':'<path d="m9 9 14 14M23 9 9 23"/>',
'plus':'<path d="M6 16h20M16 6v20"/>',
'minus':'<path d="M6 16h20"/>',
'compass':'<circle cx="16" cy="16" r="12"/><path d="m21 9-3 10-8 4 3-10Z" fill="#68cbc1"/>',
'map':'<path d="m3 8 8-3 10 4 8-3v20l-8 3-10-4-8 3ZM11 5v20M21 9v20"/>',
'book':'<path d="M16 8C12 4 6 4 3 6v21c4-3 9-3 13 0 4-3 9-3 13 0V6c-4-2-9-2-13 2Zm0 0v19"/>',
'settings':'<path d="M5 8h22M5 16h22M5 24h22M11 4v8M22 12v8M14 20v8"/>',
'save':'<path d="M6 4h17l5 5v19H5V4ZM10 4v8h12V4M10 28V18h13v10"/>',
'load':'<path d="M5 11V5h10l4 5h9v17H5V11Zm11 2v9m-4-4 4 4 4-4"/>',
'restart':'<path d="M6 12a11 11 0 1 1 0 9M6 4v9h9"/>',
'alert':'<path d="m16 4 14 24H2ZM16 12v7M16 23v1" stroke="#d98268"/>',
'info':'<circle cx="16" cy="16" r="12"/><path d="M16 14v10M16 8v2"/>',
'back':'<path d="M27 16H5m9-9-9 9 9 9"/>',
'recruit':'<circle cx="12" cy="10" r="5"/><path d="M3 27v-5c0-8 18-8 18 0v5M26 9v12m-6-6h12"/>',
'build':'<path d="m3 14 13-10 13 10M7 12v16h18V12M12 28V18h8v10M3 28h26"/>',
}
for name, drawing in paths.items():
    svg = f'<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32"><g fill="none" stroke="#eee8d7" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">{drawing}</g></svg>'
    (out / f'{name}.svg').write_text(svg)
print(f'Wrote {len(paths)} original symbols')
