import sys
import time
import textwrap
from epd import epd2in13_V4
from PIL import Image, ImageDraw, ImageFont
# Display is 122x250, we rotate 90 so drawing coords are 250 wide x 122 tall
SCREEN_W = 250
SCREEN_H = 122
FONT_SIZE = 12
LINE_SPACING = 14
MAX_LINES = SCREEN_H // LINE_SPACING
CHARS_PER_LINE = 42  # approximate for default font at size 12
epd = epd2in13_V4.EPD()
epd.init()
try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", FONT_SIZE)
except:
    font = ImageFont.load_default()
# Rolling buffer of lines to display
line_buffer = []
def wrap_line(line):
    """Break a long line into multiple lines that fit the screen."""
    return textwrap.wrap(line.rstrip(), width=CHARS_PER_LINE) or ['']
def render():
    image = Image.new('1', (SCREEN_W, SCREEN_H), 255)
    draw = ImageDraw.Draw(image)
    y = 0
    for line in line_buffer[-MAX_LINES:]:
        draw.text((0, y), line, font=font, fill=0)
        y += LINE_SPACING
    return image.rotate(180)
def add_lines(text):
    wrapped = wrap_line(text)
    line_buffer.extend(wrapped)
    # Keep only what fits on screen
    while len(line_buffer) > MAX_LINES:
        line_buffer.pop(0)
def tail(filename, interval=1):
    # Full refresh to set base image
    add_lines("Waiting for output...")
    base_image = render()
    epd.displayPartBaseImage(epd.getbuffer(base_image))
    with open(filename) as f:
        f.seek(0, 2)
        while True:
            line = f.readline()
            if line:
                print(line, end='')
                add_lines(line)
                image = render()
                epd.displayPartial(epd.getbuffer(image))
            else:
                time.sleep(interval)
if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: python3 epd_tail.py <logfile> [interval]")
        sys.exit(1)
    filename = sys.argv[1]
    interval = float(sys.argv[2]) if len(sys.argv) > 2 else 1
    try:
        tail(filename, interval)
    except KeyboardInterrupt:
        epd.sleep()
