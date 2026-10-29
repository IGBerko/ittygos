# ittyGOS

**ittyGOS** (ittyGamesOS) is a gaming-oriented Linux distribution: **Debian 13 (trixie)** with a slim
**KDE Plasma** desktop, **Steam + Proton**, Wine, **Java 25 + 21**, Python 3 and system tuning for games.
It is built from a chroot with plain `debootstrap`, in the same spirit as [ittyOS](https://github.com/IGBerko/ittyos).

> Status: **0.1.0, first draft.** The build scripts are written but have not been run on a real
> machine yet. Expect to fix a few package names on the first build (the build tells you exactly which).

## What is inside

| Part | What |
|---|---|
| Base | Debian 13 trixie, kernel `linux-image-amd64`, systemd, NetworkManager, PipeWire, non-free firmware and microcode |
| Desktop | KDE Plasma 6 (X11 and Wayland), SDDM, Dolphin, Konsole, Kate, Firefox ESR. No Discover, no PIM, no office, no KDE games |
| Games | Steam (`steam-installer`, downloads Steam on first start; Proton comes from Steam), Wine, Lutris, GameMode, MangoHud, Gamescope (when Debian 13 has it), 32-bit graphics libraries |
| Proton-GE | `ittygos-proton install` adds the community Proton-GE builds (checksum verified) |
| Languages | Java 25 (`openjdk-25-jdk`, default) and Java 21 (`openjdk-21-jdk`, for Minecraft), Python 3 (Debian 13 ships 3.13), pip, venv, pipx |
| Tuning | `vm.max_map_count` for games, zram swap (zstd), I/O scheduler per disk type, higher file limits, BBR, Baloo indexing off, faster boot |
| Installer | Calamares (from the live session) |
| NVIDIA | optional proprietary driver: `WITH_NVIDIA=1 ./build.sh configure` (off by default) |

## Build (WSL2 Ubuntu or Debian)

Needs about 20 GB of free disk space and a few hours at the first run. Keep the folder in the WSL home
(`~/ittygos`), **not** under `/mnt/c`.

```sh
git clone https://github.com/IGBerko/ittygos && cd ittygos
sudo ./build.sh setup        # build tools
sudo ./build.sh all          # debootstrap + packages + ISO
# result: out/ittyGOS-0.1.0.iso  (and a .sha256 file)
cp out/ittyGOS-0.1.0.iso /mnt/c/WSL/
```

Step by step: `bootstrap` (base system), `configure` (packages, hooks, overlay; re-runnable),
`shell` (enter the chroot and change things by hand), `iso`. `DRY_RUN=1 ./build.sh all` only prints
the plan. `SQUASH_LEVEL=5 ./build.sh iso` makes a test ISO much faster (larger file).

Change the system by editing:

- `config/packages-*.txt`: package lists (a wrong name is reported before anything is installed),
- `hooks/NN-*.sh`: steps that run inside the chroot, in order,
- `overlay/`: files copied into `/` of the system (sysctl, udev, scripts, defaults).

## Testing

A VirtualBox virtual machine (4+ GB RAM, 3D acceleration on, EFI on or off, both work) is enough to check that the
ISO boots and the desktop starts. Games need real hardware or GPU passthrough.
Live user: `gamer`, password `live` (if the name is not accepted: `user` / `live`), sudo allowed.

## Commands in the system

`ittygos-help` shows everything; `ittygos-proton list|install|remove`; Steam launch options:
`gamemoderun %command%`, `mangohud %command%`.

## License

MIT for the ittyGOS scripts and configuration. Debian and the packages keep their own licences;
Steam and the NVIDIA driver are non-free software that is installed from Debian's `contrib`/`non-free`
and is not changed by this project.
