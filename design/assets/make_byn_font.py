# Собирает design/assets/BYNSign.ttf — шрифт с одним глифом: знак белорусского рубля (U+20C5, предварительный код Unicode 19.0)
# из официального SVG Нацбанка (design/assets/byn-sign.svg, общественное достояние). Запуск: cd design/assets; python3 make_byn_font.py (нужен fonttools).
import re
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.pens.transformPen import TransformPen
from fontTools.svgLib.path import parse_path
from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.recordingPen import RecordingPen
from fontTools.pens.cu2quPen import Cu2QuPen
d = re.search(r' d="([^"]+)"', open("byn-sign.svg").read()).group(1)
rec = RecordingPen(); parse_path(d, rec)
bp = BoundsPen(None); rec.replay(bp); x0, y0, x1, y1 = bp.bounds
UPM, CAP, SB = 1000, 712, 50          # высота знака ≈ высоте прописных
k = CAP / (y1 - y0)
adv = round((x1 - x0) * k + 2 * SB)
pen = TTGlyphPen(None)
# SVG: y вниз → шрифт: y вверх; знак стоит на базовой линии
rec.replay(TransformPen(Cu2QuPen(pen, max_err=1.0, reverse_direction=True), (k, 0, 0, -k, SB - x0 * k, y1 * k)))
glyph = pen.glyph()
fb = FontBuilder(UPM, isTTF=True)
fb.setupGlyphOrder([".notdef", "byn"])
fb.setupCharacterMap({0x20C5: "byn"})
fb.setupGlyf({".notdef": TTGlyphPen(None).glyph(), "byn": glyph})
fb.setupHorizontalMetrics({".notdef": (500, 0), "byn": (adv, SB)})
fb.setupHorizontalHeader(ascent=950, descent=-250)
fb.setupNameTable({"familyName": "BYN Sign", "styleName": "Regular"})
fb.setupOS2(sTypoAscender=950, sTypoDescender=-250, usWinAscent=950, usWinDescent=250, sCapHeight=CAP)
fb.setupPost()
fb.save("BYNSign.ttf")
print("advance", adv, "bounds", round(x0,3), round(y0,3), round(x1,3), round(y1,3))
