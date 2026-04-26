import sys
import time
from epd import epd2in13_V4
from PIL import Image, ImageDraw, ImageFont

epd = epd2in13_V4.EPD()
epd.init()
image = Image.new('1', (epd.height, epd.width), 255)
draw = ImageDraw.Draw(image)

def tail(filename, interval=2):
    with open(filename) as f:
        f.seek(0, 2)
        while True:
            line = f.readline()
            if line:
                print(line, end='')

                try:
                    draw.text((10, 10), line, fill=0)

                    rotated_image = image.rotate(180)

                    epd.display(epd.getbuffer(rotated_image))

                except Exception as e:
                    print(f"Error: {e}")
                else:
                    time.sleep(interval)

if __name__ == '__main__':
    filename = sys.argv[1]
    interval = float(sys.argv[2]) if len(sys.argv) > 2 else 2
    tail(filename, interval)

