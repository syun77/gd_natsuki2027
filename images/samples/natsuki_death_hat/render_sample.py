"""Render the review animation; source bitmap remains unchanged. Requires Pillow."""
from pathlib import Path
import math
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent
FPS = 25
FALL_SPEED_SCALE = 0.25
DURATION = 13.44
SIZE = (320, 288)


def pose(t):
    fall = max(0.0, t - 0.32)
    phase = 2 * math.pi * fall / 1.25
    amplitude = 42 * min(1, fall / 0.45)
    x = 160 + amplitude * math.sin(phase)
    descent = fall * FALL_SPEED_SCALE
    y = 65 - 12 * math.sin(min(t / 0.32, 1) * math.pi / 2) + 62 * descent + 10 * descent * descent
    tilt = -24 * math.cos(phase) * min(1, fall / 0.35)
    return x, y, tilt, 0.88 + 0.12 * math.cos(phase * 2)


def main():
    source = Image.open(ROOT / 'hat_source.png').convert('RGBA')
    source = source.crop(source.getbbox())
    hat = source.resize((72, round(source.height * 72 / source.width)), Image.Resampling.NEAREST)
    frames = []
    contact = Image.new('RGB', (320 * 4, 288), '#47615f')
    sample_indices = (0, 100, 180, 260)
    for i in range(round(FPS * DURATION)):
        t = i / FPS
        frame = Image.new('RGBA', SIZE, '#47615f')
        draw = ImageDraw.Draw(frame)
        for y in range(16, SIZE[1], 32):
            draw.line((0, y, SIZE[0], y), fill='#506a68')
        x, y, angle, pitch = pose(t)
        sprite = hat.resize((hat.width, round(hat.height * pitch)), Image.Resampling.NEAREST)
        sprite = sprite.rotate(angle, Image.Resampling.NEAREST, expand=True)
        frame.alpha_composite(sprite, (round(x - sprite.width / 2), round(y - sprite.height / 2)))
        frames.append(frame.convert('RGB').resize((640, 576), Image.Resampling.NEAREST))
        if i in sample_indices:
            contact.paste(frame.convert('RGB'), (sample_indices.index(i) * 320, 0))
    frames[0].save(ROOT / 'preview.gif', save_all=True, append_images=frames[1:], duration=40, loop=0, disposal=2, optimize=False)
    contact.save(ROOT / 'contact_sheet.png')
    with Image.open(ROOT / 'preview.gif') as check:
        assert check.size == (640, 576)
        duration = 0
        for index in range(check.n_frames):
            check.seek(index)
            duration += check.info['duration']
        assert duration == round(DURATION * 1000)
    print(f'PASS: {round(FPS * DURATION)} source frames, {FPS}fps, total {DURATION} seconds')


if __name__ == '__main__':
    main()
