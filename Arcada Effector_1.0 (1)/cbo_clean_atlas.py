# Post-process exported atlases: fade every cell to transparent near its borders and drop
# near-zero haze, so additive drawing never shows the cell rectangle.
import sys, os, json, glob
import numpy as np
from PIL import Image
src, dst = sys.argv[1], sys.argv[2]
os.makedirs(dst, exist_ok=True)
for f in sorted(glob.glob(os.path.join(src, '*.png'))):
    info = json.load(open(f[:-4] + '.json'))
    im = np.array(Image.open(f).convert('RGBA')).astype(np.float32)
    fw, fh = info['frameWidth'], info['frameHeight']
    yy, xx = np.mgrid[0:fh, 0:fw].astype(np.float32)
    d = np.minimum(np.minimum(xx + 0.5, fw - 0.5 - xx), np.minimum(yy + 0.5, fh - 0.5 - yy))
    margin = 0.14 * min(fw, fh)
    t = np.clip(d / margin, 0, 1)
    mask = t * t * (3 - 2 * t)
    tiled = np.tile(mask, (im.shape[0] // fh, im.shape[1] // fw))
    a = im[..., 3] * tiled
    a[a < 4] = 0
    im[..., 3] = a
    Image.fromarray(im.clip(0, 255).astype(np.uint8)).save(os.path.join(dst, os.path.basename(f)), optimize=True)
    with open(os.path.join(dst, os.path.basename(f)[:-4] + '.json'), 'w') as o:
        json.dump(info, o)
print('cleaned')
