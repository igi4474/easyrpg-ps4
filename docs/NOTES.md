# Technical notes

## The crash that took a while: PS4 pthread types (CE-34878-0 on audio init)

The PacBrew musl fork for PS4 (`PacBrew/ps4-openorbis-musl`) does **not** implement
pthreads itself: `src/thread/ps4/*.c` are empty replacements, so every `pthread_*` call
binds to Sony's `libkernel`, which uses the FreeBSD ABI. But musl's headers still declared
musl's own sizes for some of these types:

| type                    | musl default | libkernel (FreeBSD) |
|-------------------------|--------------|---------------------|
| `pthread_mutexattr_t`   | 4 bytes      | 8 (pointer)         |
| `pthread_condattr_t`    | 4 bytes      | 8 (pointer)         |
| `pthread_barrierattr_t` | 4 bytes      | 8 (pointer)         |
| `pthread_spinlock_t`    | 4 bytes      | 8 (pointer)         |
| `pthread_once_t`        | 4 bytes      | 16 (`{int; mutex}`) |

So `pthread_mutexattr_init(&attr)` on a stack variable writes 8 bytes into a 4-byte slot.
With clang 18's stack layout, `SDL_CreateMutex` had the saved `rbx` right after `attr`, so
the low 32 bits of `rbx` got overwritten and the caller (`open_audio_device`) crashed
reading `0x700000008`. Older compilers probably laid the stack out differently and hid it.

Fix: `patches/musl-ps4-pthread-types.patch` (types sized for libkernel, and
`PTHREAD_ONCE_INIT` = `{0, 0}`). Everything that uses these types (libc++/libc++abi, SDL2,
pixman, the app) has to be rebuilt after applying it.

**If you use the official OpenOrbis/PacBrew toolchain instead of building it from source,
check whether it has the same issue** — it is latent and only shows up with some stack layouts.

## Other changes vs. upstream

- `ps4vars.sh`: libc++ include dir must come *before* `$OPENORBIS/include`, otherwise
  `<cmath>` picks up the C `math.h` and fails (`no member named 'abs'`).
- OpenOrbis ships ancient FreeType headers in `include/`; they shadow real FreeType
  (`FT_FONT_FORMATS_H` missing). Moved aside, and `font.cpp` uses `<ft2build.h>` normally.
- SDL2 (PacBrew fork): `-Werror=declaration-after-statement` breaks with newer clang; disabled.
- System library stubs generated with `orbis-lib-gen` from `idc/ps4libdoc` (5.05 branch).
- EasyRPG input on PS4: SDL maps OPTIONS to "back" and the touchpad click to "start".
  Upstream binds back = reset-to-title, which is a bad surprise on a DualShock; both now open
  the settings menu.
- `main.cpp` (debug aid, kept for the testing phase): PS4 notifications at startup steps and
  for every error-level log line; all log levels go to klog.

## Debugging on hardware

- GoldHEN klog server, port 3232. App output lines are prefixed `<EasyRPGPlayer>` / `<ERPG-DBG>`.
- On a crash the kernel prints a backtrace with absolute addresses; `eboot.bin` text is
  mapped at `0x400000`, so `llvm-symbolizer --obj=easyrpg-player <addr - 0x400000>`
  gives the function.
