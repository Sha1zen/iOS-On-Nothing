# iOS On Nothing

Порт ядра Apple XNU (открытые исходники Darwin, база xnu-7195 / macOS 11.2)
на Nothing Phone 3a (Qualcomm SM7635 / Snapdragon 7s Gen 3).

Путь: сначала QEMU (`-M raspi3` → `-M virt`), потом реальное железо через
`fastboot boot` (без перепрошивки, после разблокировки загрузчика).

## Статус

- [x] Ресёрч: выбрана референс-архитектура (активный проект
  [anurodhp: XNU on RPi3](https://github.com/anurodhp/xnu-iokit-pi3) —
  from-source XNU на не-Apple SoC, QEMU + реальные платы, launchd и GUI).
- [x] План зафиксирован: [docs/roadmap.md](docs/roadmap.md)
- [ ] Фаза 0: сборочная среда (XNU собирается на macOS/iPhoneOS SDK —
  решаем VM-vs-CI), воспроизведение референс-бута в QEMU.

См. также `docs/notes/` — заметки по ходу работы.
