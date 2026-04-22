# GTK4 Video Rendering Notes

This project uses a local `media-kit` override to make Linux GTK4 rendering work with Flutter.

## Why rebind exists

At startup, media-kit can be created before a stable Flutter EGL context is available. In that phase it may initialize with a fallback EGL display/config.

Once texture population runs on Flutter's render path, we "rebind" mpv to Flutter's active EGL display/context so both sides operate in compatible GL/EGL state.

Without rebind, texture sharing may fail or crash.

## Why pbuffer is tried first

Rebind needs a current EGL context to render frames from mpv. A tiny pbuffer surface is preferred first because it is:

- Offscreen and isolated from Flutter's window surface.
- Less likely to interfere with Flutter/Skia GL state.
- A common EGL path on many drivers.

So priority is:

1. `eglCreatePbufferSurface` (isolated offscreen surface)
2. Surfaceless fallback (`eglMakeCurrent(..., EGL_NO_SURFACE, ...)`)
3. Borrow Flutter draw/read surface (last resort)

## Why not "direct only"

"Direct" in this code means direct shared texture path (skip EGLImage bridge) in GTK4.

That still requires a valid current EGL context for mpv rendering. Rebind handles this requirement; direct texture sharing alone is not enough.

Current behavior:

- Rebind to Flutter EGL context.
- Use direct shared texture path on GTK4.
- Avoid EGLImage bridge when direct path is active.

## Log hints

Healthy GTK4 path should include:

- `Rebind ...`
- `Rebind using surfaceless EGL context fallback.` or `Rebind using Flutter EGL surface fallback.`
- `TextureGL: Using direct shared texture path (GTK4).`

If you still see:

- `TextureGL: GL error ... populate.egl_image_bridge`

then GTK4 compile defines were likely not propagated, or rebind/direct path was bypassed.
