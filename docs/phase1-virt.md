# Phase 1 — board `QEMU_VIRT` (QEMU `-M virt`, GICv3, PL011)

Goal: boot *our own fork* of xnu-7195 on `-M virt` with our new
`MACHINE_CONFIGS=QEMU_VIRT`, reusing the reference project's proven
architecture (PE subclass, DT, personality tables, drivers compiled into
kernel).

## What is board-specific in xnu-7195

Board impact is mostly contained in **pexpert** (reference survey found
`ARM64_BOARD_CONFIG_BCM2837` referenced only in `makedefs/MakeInc.def` +
`pexpert/pexpert/arm64/board_config.h`). The core arm64 kernel adapts at
runtime from the Device Tree. So adding a board = small surface:

1. `makedefs/MakeInc.def`:
   - append to `SUPPORTED_ARM64_MACHINE_CONFIGS`
   - `MACHINE_FLAGS_ARM64_QEMU_VIRT = -DARM64_BOARD_CONFIG_QEMU_VIRT -mcpu=cortex-a53`
     (a53 codegen runs fine on `virt`'s `-cpu max`; revisit if we enable ARMv8.1)
2. `pexpert/pexpert/arm64/board_config.h`: add `#ifdef ... #include <pexpert/arm64/QEMU_VIRT.h> #endif`
3. `pexpert/pexpert/arm64/QEMU_VIRT.h` (new): register map constants + timer
   info; listed in `pexpert/pexpert/arm64/Makefile` header lists.
4. Early console: `pexpert/arm/pe_serial.c` walks DT for a node **named
   `uart0`** and matches its `compatible` against a hardcoded list
   (`uart,16550`, `uart-16550`, `uart,s5i3000`, `uart-1,samsung`, …).
   QEMU virt's PL011 is `arm,pl011` — confirm whether their fork already
   extended pe_serial with PL011 (BCM uses PL011 for BT) else add it.
5. Board IOKit drivers (hub repo `iokit/`, synced into the kernel tree by
   `tools/sync_iokit_drivers.sh` at build time):
   - `QemuVirtPlatformExpert` (concrete `IODTPlatformExpert`, trivial)
   - `QemuVirtArmIO` + personality table
   - `GICv3InterruptController` driver (GICD base `0x08010000`,
     GICR base `0x08014000` per QEMU virt)
   - `PL011Serial` console/sironka + storage `VirtIOBlock` (mmio at
     `0x0a003e00..` region as QEMU places virtio-mmio nodes)
   - `QemuVirtCPU` (concrete IOCPU — the piece that closes the IRQ
     dispatch gap; without it interrupts silently never dispatch)

## Boot loader into `-M virt`

The reference QEMU fork (zhuowei) implements a **generic Mach-O loader**
in `hw/arm/boot.c` producing XNU `boot_args` (Revision 2, Version 2
struct, size 0x2e0) and рacked secondary cores (`hw/arm/raspi.c` has the
`xnu-smp=on` property that moves cores 1..3 into a spin-table stub at EL2
— "the way real firmware leaves them").

Plan: port this loader to a modern QEMU `virt` machine (upstream 10.x) as
a **machine property** (e.g. `virt,xnu-boot=on`):
- `-kernel` = XNU unstripped Mach-O; loader resolves entry, loads image,
  slides, sets up `boot_args` with `DevTree` from `-dtb`
- secondaries parked spin-table (no PSCI into XNU)
- entry at EL2 (start.s handles EL2→EL1) — confirm which EL zhuowei's
  loader enters (start.s branches on currentEL)

Alternative (fuel for `bootstub/` Phase 3): a freestanding ELF loaded as
"linux kernel" by plain upstream QEMU (or ABL on device) that constructs
the same boot_args at runtime. Design so the *same stub core*  serves
both QEMU virt and the phone's ABL (identical memory contracts).

## DT (Apple format)

Authoring via `dtc-AppleDeviceTree` (their `third_party/dtc-appledevicetree`,
formerly by darwin-on-arm). Reference tree: `devicetrees/rpi3.dts`
(466 lines) — copy structural conventions:

- `compatible` strings only for nodes we provide drivers for; **all
  others zeroed** (their practice: prevent stale driver binds)
- node literally named `uart0` = kernel console auto-select
- interrupts: **single-cell pre-flattened vectors** (generic IOKit reads
  only the first cell)
- `memory-map { }` root container hosts `RAMDisk` regions (mockfs /
  initrd mechanism)

For virt DT: root + `cpus` ×  (virtid? qemu `-smp N`), `interrupts` tree
from `virt,gic-version=3` symbols, PL011 console node at
`9000000`-indexed, arch timer node (`interrupts` = virtual PPI 11? and
physical?), memory-map with a candidate `RAMDisk`.

## QEMU command (target shape)

Machine from modern QEMU (not the 2.12 fork) once the property is ported:

```
qemu-system-aarch64 -M virt,xnu-boot=on,gic-version=3 -cpu max -smp 4 -m 4G \
  -kernel build/xnu-latest-build/out/kernel.development.qemuvirt-7195.unstripped \
  -dtb build/qemuvirt.dtb \
  -drive file=root.img,if=none,id=x -device virtio-blk-device,drive=x \
  -serial stdio -display none \
  -append "debug=0x8 kextlog=0xfff -noprogress -v -enable_kprintf_spam rd=disk0s1 serial=3 cpu-factor=10 vm_compressor=0"
```

## Risks / open questions

- Zhwowei fork QEMU 2.12.91 loader pulled `boot_args` fully? (verified in
  reference `hw/arm/boot.c` lines ~1000-1100: boot_args Rev2/V2 + ramdisk
  placement) — reuse verbatim, but *convert* to modern QEMU APIs
  (AddressSpace, MachineState) carefully.
- `-cpu max` on TCG arm64 with our `a53`-coded quirk paces? Runtime `ID
  reg` mismatches: XNU validates CPU features on entry (arm64
  `get_cpu_features`); TCG max CPU exposes plenty. `-unsafe_kernel_text`
  boot-arg may be needed per blacktop's notes for DE patch levels.
- virt machine wants 4K/16K ± but docs said kernel uses 16K — QEMU any
  pages host allocation is fine (CPU granule: `-cpu max` supports 16K).
- Real storage bring-up path: virtio-blk (Phase 1) will be replaced by
  eMMC (Qcom SDHCI) for the phone — keep driver seam so both are
  `IOMedia`-equivalent (IOStorageFamily).
- Keep `vm_compressor=0` + `cpu-factor=10` boot-args (TCG watchdog quirk)
  from their ops-book.
