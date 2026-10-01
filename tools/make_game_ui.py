"""Build sharp game typography and nine-slice UI textures from existing materials."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageEnhance
import math
import shutil

root = Path(__file__).resolve().parent.parent
assets = root / 'godot/assets'
font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',16)
characters = list(range(32,127)) + list(range(160,256)) + [8211,8212,8226,8230,8592,8594,9654,10005]
atlas = Image.new('RGBA',(512,256))
draw = ImageDraw.Draw(atlas)
lines = ['info face="Enxame Pixel" size=16 bold=1 italic=0 charset="" unicode=1 stretchH=100 smooth=0 aa=1 padding=0,0,0,0 spacing=1,1',
         'common lineHeight=20 base=15 scaleW=512 scaleH=256 pages=1 packed=0',
         'page id=0 file="game_font.png"',f'chars count={len(characters)}']
for i,code in enumerate(characters):
    char = chr(code)
    x = (i%21)*24; y = (i//21)*24
    glyph=Image.new('RGBA',(24,24))
    ImageDraw.Draw(glyph).text((0,0),char,font=font,fill='white')
    glyph.putalpha(glyph.getchannel('A').point(lambda v:255 if v>=100 else 0))
    atlas.alpha_composite(glyph,(x,y))
    box=glyph.getchannel('A').getbbox() or (0,0,0,0)
    advance = max(4,math.ceil(font.getlength(char)))
    lines.append(f'char id={code} x={x+box[0]} y={y+box[1]} width={box[2]-box[0]} height={box[3]-box[1]} xoffset={box[0]} yoffset={box[1]} xadvance={advance} page=0 chnl=15')
alpha = atlas.getchannel('A').point(lambda v:255 if v>=100 else 0)
atlas.putalpha(alpha)
atlas.save(assets/'game_font.png')
(assets/'game_font.fnt').write_text('\n'.join(lines)+'\n')
shutil.copyfile('/usr/share/doc/fonts-dejavu-core/copyright',assets/'GAME-FONT-LICENSE.txt')

metal = Image.open(assets/'metal.png').convert('L').resize((64,64))
for name,base,edge in [('ui_panel',(23,24,20),(115,108,86)),('ui_button',(34,35,28),(92,87,71)),('ui_selected',(59,39,26),(185,139,79))]:
    image=Image.new('RGBA',(64,64))
    px=image.load(); noise=metal.load()
    for y in range(64):
        for x in range(64):
            n=(noise[x,y]-128)*0.055
            px[x,y]=tuple(max(0,min(255,round(c+n))) for c in base)+(249,)
    d=ImageDraw.Draw(image)
    d.rectangle((0,0,63,63),outline=(5,6,4,255),width=2)
    d.line((2,61,2,2,61,2),fill=edge+(255,),width=2)
    d.line((3,60,60,60,60,3),fill=(10,11,8,255),width=3)
    d.line((5,57,5,5,57,5),fill=tuple(int(c*.43) for c in edge)+(255,),width=1)
    image.save(assets/f'{name}.png')
print('game font and nine-slice skins ready')
