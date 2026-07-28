/**
 * converse-shrink — client-side image compression for Converse.js
 *
 * Compresses images in the browser (canvas re-encode) before Converse uploads
 * them via XEP-0363 HTTP File Upload, so recipients get an inline photo
 * instead of a link to a multi-megabyte original. Written for XMPP↔SMS
 * gateways (JMP/Cheogram), where only uploads under the carrier MMS size cap
 * are delivered as real MMS — anything larger falls back to a URL — but it's
 * useful anywhere smaller uploads are preferable.
 *
 * It registers a listener on Converse's official `beforeFileUpload` hook (the
 * same extension point the OMEMO plugin uses to encrypt uploads), so no
 * Converse internals are touched. Verified against Converse.js v14.
 *
 * https://github.com/cwage/converse-shrink — MIT license.
 */

const PLUGIN_NAME = 'converse-shrink';

const DEFAULT_OPTIONS = {
    // Iterate quality/dimensions until the result fits under this many bytes.
    // 500 KiB clears most carriers' MMS caps while still looking decent.
    target_bytes: 500 * 1024,
    // Longest side is scaled down to this many pixels before the first encode.
    max_dimension: 1600,
    // Initial encode quality (0..1), stepped down by 0.1 until min_quality.
    quality: 0.85,
    min_quality: 0.5,
    // When quality bottoms out, dimensions shrink by 25% per step (quality
    // resets) until the longest side would drop below this.
    min_dimension: 480,
    // JPEG is the safe choice for MMS gateways. Transparency is flattened
    // onto white (JPEG has no alpha).
    output_type: 'image/jpeg',
};

const EXTENSIONS = {
    'image/jpeg': 'jpg',
    'image/webp': 'webp',
    'image/png': 'png',
};

function renameForType(name, type) {
    const ext = EXTENSIONS[type] || 'jpg';
    const base = name.includes('.') ? name.slice(0, name.lastIndexOf('.')) : name;
    return `${base}.${ext}`;
}

async function decode(file) {
    // 'from-image' bakes the EXIF orientation into the pixels so portrait
    // phone photos don't come out sideways. Some older browsers throw on the
    // options bag entirely, so fall back to a bare call before giving up.
    try {
        return await createImageBitmap(file, { imageOrientation: 'from-image' });
    } catch {
        return await createImageBitmap(file);
    }
}

async function encode(bitmap, width, height, type, quality) {
    let canvas;
    if (typeof OffscreenCanvas !== 'undefined') {
        canvas = new OffscreenCanvas(width, height);
    } else {
        canvas = document.createElement('canvas');
        canvas.width = width;
        canvas.height = height;
    }
    const ctx = canvas.getContext('2d');
    if (type === 'image/jpeg') {
        // JPEG has no alpha channel; without this, transparent regions
        // composite to black.
        ctx.fillStyle = '#ffffff';
        ctx.fillRect(0, 0, width, height);
    }
    ctx.drawImage(bitmap, 0, 0, width, height);
    if (canvas.convertToBlob) {
        return canvas.convertToBlob({ type, quality });
    }
    return new Promise((resolve, reject) =>
        canvas.toBlob((blob) => (blob ? resolve(blob) : reject(new Error('canvas.toBlob returned null'))), type, quality)
    );
}

/**
 * Compress an image file toward a target byte size. Standalone — no Converse
 * required — so it can be tested (see demo/) or reused directly.
 *
 * Never throws in normal operation: files that can't be decoded (HEIC in most
 * browsers, corrupt data) and results that wouldn't be smaller than the
 * original are returned unchanged.
 *
 * @param {File} file
 * @param {Partial<typeof DEFAULT_OPTIONS>} [options]
 * @returns {Promise<File>} a new, smaller File — or the original, untouched
 */
export async function shrinkImage(file, options = {}) {
    const opts = { ...DEFAULT_OPTIONS, ...options };
    let bitmap;
    try {
        bitmap = await decode(file);
    } catch {
        return file;
    }
    try {
        const { width, height } = bitmap;
        let scale = Math.min(1, opts.max_dimension / Math.max(width, height));
        let quality = opts.quality;
        let best = null;
        for (let attempt = 0; attempt < 12; attempt++) {
            const blob = await encode(
                bitmap,
                Math.max(1, Math.round(width * scale)),
                Math.max(1, Math.round(height * scale)),
                opts.output_type,
                quality
            );
            if (!best || blob.size < best.size) {
                best = blob;
            }
            if (blob.size <= opts.target_bytes) {
                break;
            }
            if (quality - 0.1 >= opts.min_quality - 1e-9) {
                quality = Math.round((quality - 0.1) * 100) / 100;
            } else if (Math.max(width, height) * scale * 0.75 >= opts.min_dimension) {
                scale *= 0.75;
                quality = opts.quality;
            } else {
                break; // floors reached; ship the best attempt
            }
        }
        if (!best || best.size >= file.size) {
            return file;
        }
        return new File([best], renameForType(file.name, opts.output_type), {
            type: opts.output_type,
            lastModified: file.lastModified,
        });
    } catch {
        return file;
    } finally {
        bitmap.close?.();
    }
}

/**
 * Register the plugin on a Converse.js instance. Called automatically against
 * `window.converse` when this module is loaded via a script tag after the
 * Converse bundle; call it yourself when bundling.
 *
 * @param {object} converse the global Converse.js API object
 */
export function registerShrinkPlugin(converse) {
    converse.plugins.add(PLUGIN_NAME, {
        initialize() {
            const { api } = this._converse;
            api.settings.extend({
                shrink_enabled: true,
                shrink_target_bytes: DEFAULT_OPTIONS.target_bytes,
                shrink_max_dimension: DEFAULT_OPTIONS.max_dimension,
                shrink_quality: DEFAULT_OPTIONS.quality,
                shrink_min_quality: DEFAULT_OPTIONS.min_quality,
                shrink_min_dimension: DEFAULT_OPTIONS.min_dimension,
                shrink_output_type: DEFAULT_OPTIONS.output_type,
                // Canvas re-encoding would destroy animation and vectors, so
                // these pass through untouched (and gateways will still turn
                // big ones into links).
                shrink_skip_types: ['image/gif', 'image/svg+xml'],
                shrink_debug: false,
            });

            api.listen.on('beforeFileUpload', async (_chat, file) => {
                try {
                    if (!api.settings.get('shrink_enabled')) return file;
                    if (!(file.type || '').startsWith('image/')) return file;
                    if (api.settings.get('shrink_skip_types').includes(file.type)) return file;
                    const target_bytes = api.settings.get('shrink_target_bytes');
                    if (file.size <= target_bytes) return file;
                    const shrunk = await shrinkImage(file, {
                        target_bytes,
                        max_dimension: api.settings.get('shrink_max_dimension'),
                        quality: api.settings.get('shrink_quality'),
                        min_quality: api.settings.get('shrink_min_quality'),
                        min_dimension: api.settings.get('shrink_min_dimension'),
                        output_type: api.settings.get('shrink_output_type'),
                    });
                    if (api.settings.get('shrink_debug')) {
                        console.debug(
                            `[${PLUGIN_NAME}] ${file.name}: ${file.size} -> ${shrunk.size} bytes` +
                                (shrunk === file ? ' (unchanged)' : ` (${shrunk.name})`)
                        );
                    }
                    return shrunk;
                } catch (e) {
                    // A compression bug must never block sending the file.
                    console.warn(`[${PLUGIN_NAME}] failed, uploading original:`, e);
                    return file;
                }
            });
        },
    });
}

if (typeof window !== 'undefined' && window.converse?.plugins) {
    registerShrinkPlugin(window.converse);
}

export default registerShrinkPlugin;
