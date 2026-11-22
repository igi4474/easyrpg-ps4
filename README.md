# EasyRPG Player for PS4 (homebrew)

> ⚠️ **Status: testing.** This is an early test build. It has been tried on one console only
> and **bugs may occur** — crashes, missing sound, broken text, lost saves. Back up your saves
> and use it at your own risk.

Play **RPG Maker 2000 / 2003** games on a jailbroken PS4 with the DualShock 4, using
[EasyRPG Player](https://github.com/EasyRPG/Player) (a free, open-source reimplementation
of the RPG Maker 2000/2003 engine).

EasyRPG already contains PS4 platform code upstream (thanks to the original PS4 porter in
EasyRPG/Player#3466); this repository provides a working build setup, a fix for a crash
in the PS4 C library, controller tweaks and step-by-step install instructions.

## Tested so far

| Console | Firmware | HEN | Game | Result |
|---|---|---|---|---|
| PS4 Pro | 11.02 | GoldHEN | Yume Nikki (Steam version, RM2003) | boots, controller works, game playable |

Please open an issue with your console/firmware/game and what happened.

## Known limitations

- **Text encoding:** since v0.2-test the build includes ICU, so Japanese (Shift-JIS), Polish
  and other Central-European, Cyrillic, Greek, Korean and Chinese games should display
  correctly — **not yet confirmed on hardware**. If a game shows garbled text, set its encoding
  in the game's `RPG_RT.ini`: `[EasyRPG]` → `Encoding=1250` (Polish), `932` (Japanese), `1251` (Russian).
- This is a **debug-flavoured build**: it shows PS4 notifications during startup and when an
  error happens. That's intentional while testing.
- RPG Maker XP / VX / VX Ace / MV / MZ games are **not** supported (different engines).

## Install

1. **Get the package folder** — from the [Releases](../../releases) page, or build it yourself
   (see below).
2. **Make the .pkg (Windows):** download [LibOrbisPkg v0.2](https://github.com/maxton/LibOrbisPkg/releases),
   put `PkgTool.exe` + its `.dll` files next to `tools/build-pkg.bat` and the `EasyRPG` folder,
   and run `build-pkg.bat`.
3. **Install:** copy the `.pkg` to a USB stick (exFAT/FAT32) → *Settings → Debug Settings →
   Game → Package Installer*. (Delete an older version first.)
4. **Copy games over FTP** (GoldHEN FTP server, port `2121`): each game in its own folder
   under `/data/easyrpg-player/`, e.g. `/data/easyrpg-player/YumeNikki/RPG_RT.ldb`.
   If a game needs the RTP: `/data/easyrpg-player/rtp/2000/` or `/data/easyrpg-player/rtp/2003/`.

## Controls (DualShock 4)

| Button | Action |
|---|---|
| ✕ | Confirm |
| ○ / □ | Cancel / menu |
| △ | Run (Shift) |
| D-pad / left stick | Move |
| OPTIONS or touchpad click | EasyRPG settings menu |
| R1 | Toggle FPS display |
| R2 (hold) | Fast forward |
| PS | Back to the PS4 home screen |

## Reporting a crash

Run the klog capture before launching (PowerShell, put your PS4's IP in):

```powershell
$c=New-Object Net.Sockets.TcpClient('YOUR_PS4_IP',3232);$r=New-Object IO.StreamReader($c.GetStream());while(($l=$r.ReadLine()) -ne $null){$l;Add-Content klog.txt $l}
```

and attach `klog.txt` to the issue (or use `tools/klog.ps1`).

## Building from source (Linux)

Needs clang/lld (tested with 18), cmake, ninja, make, git, Go, Python 3, pkg-config.

```bash
sudo mkdir -p /opt/pacbrew && sudo chown $USER /opt/pacbrew
./scripts/build-toolchain.sh   # PS4 toolchain from source (musl, libc++, stubs, create-fself)
./scripts/build-deps.sh        # zlib, libpng, freetype, SDL2 (PacBrew), pixman, fmt, ...
./scripts/build-easyrpg.sh     # liblcf + EasyRPG Player -> out/EasyRPG (package folder)
```

Then pack `out/EasyRPG` with `tools/build-pkg.bat` on Windows. All sources are pinned to the
exact commits used for the tested build. See [docs/NOTES.md](docs/NOTES.md) for the technical
details (including the pthread type bug and how to read crash backtraces).

## Credits

- [EasyRPG](https://easyrpg.org/) team — EasyRPG Player & liblcf, and the upstream PS4 port
- [OpenOrbis](https://github.com/OpenOrbis) — PS4 toolchain, create-fself, create-gp4, orbis-lib-gen
- [PacBrew](https://github.com/PacBrew) (cpasjuste) — PS4 musl, SDL2 port, toolchain recipes
- [LibOrbisPkg](https://github.com/maxton/LibOrbisPkg) — open-source PKG tools
- idc — ps4libdoc

## License

GPL-3.0, same as EasyRPG Player (see [LICENSE](LICENSE)). Not affiliated with Sony,
Kadokawa or the EasyRPG project.
