"""Tworzy pliki ikony aplikacji z logo w design/logo/table-1024px.png.

Wynik w assets/icon:
- icon.png: pełna ikona 1024 px (iOS i starszy Android),
- background.png: sam gradient tła ikony adaptacyjnej Androida,
- foreground.png i monochrome.png: biały znak na przezroczystym tle,
  wpisany w strefę bezpieczną ikony adaptacyjnej.

Potem: dart run flutter_launcher_icons
"""

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "design" / "logo" / "table-1024px.png"
OUT = ROOT / "assets" / "icon"
SIZE = 1024

# Ikona adaptacyjna ma 108 dp, a launcher pokazuje środkowe 72 dp.
VISIBLE = 72 / 108


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    art = Image.open(SOURCE).convert("RGB").resize((SIZE, SIZE), Image.LANCZOS)
    art.save(OUT / "icon.png")

    # Kolor tła w każdym wierszu, z lewego brzegu, gdzie nie ma znaku.
    row_bg = [art.getpixel((8, y)) for y in range(SIZE)]

    background = Image.new("RGB", (SIZE, SIZE))
    for y, color in enumerate(row_bg):
        for x in range(SIZE):
            background.putpixel((x, y), color)
    background.save(OUT / "background.png")

    # Przezroczystość znaku: jak bardzo piksel odbiega od tła w stronę bieli.
    mark = Image.new("L", (SIZE, SIZE))
    for y in range(SIZE):
        bg = row_bg[y][0]
        span = max(255 - bg, 1)
        for x in range(SIZE):
            r = art.getpixel((x, y))[0]
            mark.putpixel((x, y), max(0, min(255, round((r - bg) * 255 / span))))

    inner = round(SIZE * VISIBLE)
    offset = (SIZE - inner) // 2
    alpha = Image.new("L", (SIZE, SIZE))
    alpha.paste(mark.resize((inner, inner), Image.LANCZOS), (offset, offset))

    foreground = Image.new("RGBA", (SIZE, SIZE), (255, 255, 255, 0))
    foreground.putalpha(alpha)
    foreground.save(OUT / "foreground.png")
    foreground.save(OUT / "monochrome.png")

    top, bottom = row_bg[0], row_bg[-1]
    print("gradient", "#%02X%02X%02X" % top, "->", "#%02X%02X%02X" % bottom)


if __name__ == "__main__":
    main()
