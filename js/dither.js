// Client-side image dithering: resize an uploaded image and convert it to
// a two-tone orange/white dithered version (Floyd–Steinberg error
// diffusion), matching the CTRLS.zip aesthetic and keeping uploads tiny.
// Colors match css/style.css's --orange / --white.

const ORANGE = [244, 113, 42];
const WHITE = [253, 246, 239];

/**
 * @param {File|Blob} file - the source image
 * @param {number} targetWidth
 * @param {number|null} targetHeight - omit to preserve aspect ratio
 * @returns {Promise<Blob>} a PNG blob of the dithered result
 */
export async function ditherImage(file, targetWidth, targetHeight = null) {
  const bitmap = await createImageBitmap(file);

  const scale = targetWidth / bitmap.width;
  const w = targetWidth;
  const h = targetHeight ?? Math.round(bitmap.height * scale);

  const canvas = document.createElement("canvas");
  canvas.width = w;
  canvas.height = h;
  const ctx = canvas.getContext("2d");
  ctx.drawImage(bitmap, 0, 0, w, h);

  const imageData = ctx.getImageData(0, 0, w, h);
  const gray = new Float32Array(w * h);
  for (let i = 0; i < w * h; i++) {
    const r = imageData.data[i * 4];
    const g = imageData.data[i * 4 + 1];
    const b = imageData.data[i * 4 + 2];
    gray[i] = 0.299 * r + 0.587 * g + 0.114 * b;
  }

  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const i = y * w + x;
      const oldVal = gray[i];
      const isWhite = oldVal > 127;
      const newVal = isWhite ? 255 : 0;
      const err = oldVal - newVal;

      if (x + 1 < w) gray[i + 1] += err * (7 / 16);
      if (y + 1 < h) {
        if (x > 0) gray[i + w - 1] += err * (3 / 16);
        gray[i + w] += err * (5 / 16);
        if (x + 1 < w) gray[i + w + 1] += err * (1 / 16);
      }

      const color = isWhite ? WHITE : ORANGE;
      imageData.data[i * 4] = color[0];
      imageData.data[i * 4 + 1] = color[1];
      imageData.data[i * 4 + 2] = color[2];
      imageData.data[i * 4 + 3] = 255;
    }
  }

  ctx.putImageData(imageData, 0, 0);

  return await new Promise((resolve) => canvas.toBlob(resolve, "image/png"));
}
