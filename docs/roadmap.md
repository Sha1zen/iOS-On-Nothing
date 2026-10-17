# iOS/Darwin XNU on Nothing Phone 3a — Roadmap

**Goal:** boot the Apple XNU kernel (open-source Darwin kernel) on the Nothing
Phone 3a (Qualcomm SM7635 / Snapdragon 7s Gen 3), using QEMU as the development
playground first, then real hardware.

Recommended baseline kernel: **xnu-7195** (Darwin 20.3 / macOS 11.2), `ARM64`,
`DEVELOPMENT` — because the only modern, from-source, non-Apple-silicon port
ecosystem is pinned there (see references).

---

## 1. Key references (surveyed 2026-10-17)

| Project | What it proves | What we reuse |
|---|---|---|
| [anurodhp/xnu-pi3-macos11](https://github.com/anurodhp/xnu-pi3-macos11) + [anurodhp/xnu-iokit-pi3](https://github.com/anurodhp/xnu-iokit-pi3) (active, upd. Oct 2026) | From-source xnu-7195 boots on a *non-Apple SoC* (BCM2837) in QEMU `-M raspi3`, mounts HFS+ root off a real 2-partition SD image, runs real dyld + launchd as PID 1, GNUstep/X11 GUI up to login manager | Entire porting framework: `MACHINE_CONFIG=<board>` in pexpert, `IODTPlatformExpert` subclass, hand-built Apple-format DT (`dtc-appledevicetree`), drivers compiled straight into kernel via `iokit/conf/files` + personality table, userland staging (`userland_staging/`, Csu, libc stubs), u-boot `bootxnu` command, QEMU boot flow |
| [alephsecurity/xnu-qemu-arm64](https://github.com/alephsecurity/xnu-qemu-arm64) | Full iOS 12.1 (iPhone 6s, S8000) boots to bash in a patched QEMU with Apple SoC emulation | Reference for Apple boot_args layout, decompressing iOS IPSW boot artifacts, perl/python2-era tooling. Not our path (Apple-blob based, old QEMU) |
| Khadas VIM3 forum series (lemin9538, 2020, via Minos hypervisor) | Stock iOS kernelcache runs on real non-Apple ARMv8 hardware behind a thin hypervisor shim | List of real-hardware traps: 16K-page FVP support, CPACR_EL1 (0x300000), DC ZVA 64B assumption, SHA-256 crypto extension required, FIQ-based timer ticks |
| [Zhuowei's xnuqemu series](https://worthdoingbadly.com/xnuqemu2/) | Root of the raspi3 loader used above | QEMU Mach-O loader + secondary-core parking patch (fork: `third_party/qemu-zhuowei`, QEMU 2.12.91 + DWC2 backport) |
| [blacktop/darwin-xnu-build](https://github.com/blacktop/darwin-xnu-build) | Builds every macOS xnu release incl. 26.x on macOS | Build environment reference for modern XNU; CI-able |

Local clones of the primary references: `reference/xnu-pi3-macos11`,
`reference/xnu-iokit-pi3`, `reference/qemu-xnu-arm` (gitignored).

## 2. Target hardware facts

Nothing Phone 3a:

- SoC: Qualcomm **SM7635** (Snapdragon 7s Gen 3), ARMv9: Cortex-A715 cluster +
  Cortex-A520 cluster, Adreno 810. ✅ ARMv9 cores support 16 KB granule pages —
  **XNU arm64 needs 16 KB pages**, so this is fine (same as BCM2837's A53 in
  the reference port).
- Bootloader: **officially unlockable** (Nothing provides
  `fastboot flashing unlock`). Unlocked ⇒ unsigned boot images allowed.
- ✅ `fastboot boot <img>` — boot a custom image **without flashing**
  anything. Recovery = power cycle. This is our Phase-3 safety net.
- Serial console: unknown availability on 3a — to research. Fallback for early
  debug: QEMU-emulating phases always have UART; on-device we may rely on
  XBL-resident console UART geometry (mark as Phase-3 risk item).
- Storage: eMMC/UFS — verify (`lsblk` under Android / `/dev/block/bootdevice`).
- PMIC: PON watchdogs/firehose quirks — do **not** flash anything during
  bring-up.

## 3. Strategy

Use the RPi3-port architecture as the skeleton; replace the board-specific
layer (`BCM2837*`) with our own:

1. `QEMUVIRT` board: fork of the reference XNU tree; new `MACHINE_CONFIG`,
   platform expert, Apple-format DT, drivers for what QEMU's `-M virt` models:
   PL011 UART, GICv3 (run virt with `gic-version=3`), architectural timer,
   virtio-blk for storage. This is structurally the same platform class as
   SM7635 (GICv3 + point-to-point UART + arch timer), so the drivers carry
   over.
2. `SM7635` board: new DT (port register bases from the Linux sm7635 device
   tree), QUPv3-Gen3 UART driver, GIC-700 driver (same GICv3 driver, corrected
   MMIO layout), eMMC storage driver. Tested first in QEMU as far as possible
   (virt machine stands in), then for the first real-hardware boot only
   console + timer + GIC need to be right.
3. First stage on-device (`bootstub`): ABL loads an Android boot image whose
   payload is our shim. The shim: unpacks embedded XNU Mach-O + Apple DTB,
   builds an XNU `boot_args` (same layout the QEMU loader produces), installs
   them in RAM, jumps to `start` with `x0=boot_args`. No flashing, no
   TZ/EL2 games — Android hands control at EL1 like it does to Linux.
   (Reference implementation exists: u-boot `bootxnu` in `anurodhp/u-boot`,
   fork of FlorentRevest's; we port the essential 200 lines to a freestanding
   shim instead of dragging u-boot onto SM7635 first.)

## 4. Phases

### Phase 0 — infrastructure (this week)
- [x] Survey references, write roadmap (this file).
- [ ] Decide build host for XNU (needs **macOS + Xcode**: iPhoneOS SDK;
      `SDKROOT=macosx` is a known desync trap). Options: macOS VM via QEMU
      (osx-kvm style) on this box; GitHub Actions `macos-` runner (Xcode 12 for
      kexts); a borrowed Mac.
- [ ] Build Zhuowei-QEMU (2.12 fork) on this Linux box (or port the
      secondary-core-parking patch onto a modern QEMU `raspi3b`).
- [ ] Build reference kernel (their `build_xnu_7195.sh` equivalent) + their
      SD/HFS image, reproduce their `runvm.sh` boot on Linux.

**Milestone R1:** interactive Darwin shell in QEMU `-M raspi3` on this machine.

### Phase 1 — our own QEMU-virt board
- [ ] Fork the reference tree into `platform/` (kernel fork + iokit dir).
- [ ] New `MACHINE_CONFIGS=QEMUVIRT`: `pexpert` board config, concrete
      platform expert, personality table, DT (Apple format, authored with
      dtc-appledevicetree).
- [ ] Drivers: PL011 serial, GICv3 interrupt controller + `IOCPU`, arch timer,
      virtio-mmio + virtio-blk; root mount from a raw image via `-drive`.
- [ ] Boot stub for `-kernel` (EL2 entry → boot_args → XNU).

**Milestone R2:** shell off a virtio-blk root in QEMU `-M virt,gic-version=3`.

### Phase 2 — SM7635 board pre-integration
- [ ] Linux sm7635 device tree reading; map UART (QUPv3 Gen3), GIC, timers,
      eMMC into Apple-format DT.
- [ ] `MACHINE_CONFIGS=SM7635` compiled against QEMU-virt as a stand-in for
      the parts QEMU can't model; Parmaceteriors per-driver unit tests where
      possible (UART in QEMU = same QUPv3 register file as silicon there).

**Milestone R3:** our kernel + our DT boots under QEMU `-M virt` with a *phone
board* build; only QUP/eMMC addresses differ from real hardware.

### Phase 3 — real device bring-up
- [ ] Unlock bootloader **(wipes data!)** — user decision.
- [ ] `mkbootimg` wrapper: bootstub + XNU + DTB; test `fastboot boot` first.
- [ ] Console: check 3a debug UART options; if absent, early console via
      framebuffer (Adreno/display controller bring-up required) — escalation
      path: kernel writes to XBL framebuffer RAM if display init is
      skippable.
- [ ] Bring-up order: entry → MMU/16K → UART → timer → GIC → panic-logging →
      SMP → eMMC → root mount → launchd → shell.
- [ ] Only after stable console-boot: minimize, then consider sparse/naming
      strategy for permanent boot partition.

**Milestone R4:** kernel console output on the phone.
**Milestone R5:** multi-user shell on the phone (Darwin-on-phone).

### Phase 4 — userland parity (opportunistic, parallel-friendly)
- Reuse the reference userland staging stack (dyld, launchd, libc stubs,
  their `userland_staging` scripts) against a proper root on eMMC.
- GNUstep GUI eventually; phone display/touch drivers are a separate project
  and not required for a headless Darwin phone.

## 5. Known swamps (collected from the reference docs)

- XNU arm64 = 16 KB pages; every QEMU model and real silicon involved must
  support them (virt machine: yes; SM7635: yes; FVP historically did not —
  irrelevant here).
- Real interrupts only reach XNU's dispatch through a concrete `IOCPU`
  subclass installing the handler (`IOCPUInterruptController::enableCPUInterrupt()`)
  — trivial but forgotten ⇒ all I/O silently poll-based. The reference port
  hit this; we will not repeat it.
- Generic IOKit reads only the *first cell* of multi-cell `interrupts`
  properties ⇒ author our DTs with pre-flattened single-cell vectors (their
  fix, adopted by us).
- Under TCG: `cpu-factor=10` boot-arg to stop the `INTERRUPT_MASKED_DEBUG`
  watchdog false-panicking; `vm_compressor=0` to avoid the swap-creation spin
  on bare images.
- FIQ vs IRQ: Apple uses FIQ for ticks; we use standard IRQ path via GICv3
  (their BCM2837 work proves the IRQ path is viable end-to-end).
- No opendirectoryd in Apple open source; reference uses a flat-file resolver
  + `pwtool` — copy that.
- Building outside `iPhoneOS` SDK desyncs `CONFIG_EMBEDDED` — never
  `SDKROOT=macosx` for the port kernel.

## 6. Repo layout (planned)

```
docs/            # this
platform/        # fork of xnu-7195 + a (later today) iokit tree, our boards
bootstub/        # Phase-1/3 first stage
userland/        # reference userland staging reuse
emu/             # qemu wrapper scripts + DT sources + disk image recipes
tools/           # build glue, mkbootimg wrapper
third_party/     # gitignored clones (reference repos, zhuowei-qemu, ...)
```
