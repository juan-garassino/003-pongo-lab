# Vendored source revisions

Recovered by comparing the vendored PongoOS tree against upstream on 2026-11-03.
All files matched before populating the empty Newlib directory.

- PongoOS: https://github.com/checkra1n/PongoOS/commit/4c9b7541629234147fcc778f0ce4162482aaccef
- Newlib (the submodule commit recorded by that PongoOS revision):
  https://github.com/checkra1n/newlib/commit/feaa8fcf90de497485b74e6f65fd78a58a27b9d7
- Hoolock gaster: https://github.com/HoolockLinux/gaster/commit/2b9d747f2367f8c0860def02ec4fd299e531c52a
  (`make libusb_dyn`; binary SHA-256
  `1c89e31a22eff9858f183a61ffaeb30f57d85c483469ce2c49d066ce4e4d0100`)

Git metadata is omitted from both vendored directories. Build with
`PONGO_VERSION=2.5.1-4c9b7541` so the version identifies the source revision.

## Not stored in this repository

Newlib (`src/pongoOS/newlib/`) and gaster (`src/hoolock/gaster/`) are excluded from
Git because they are pinned public upstreams, listed above. A clean clone cannot build
Pongo modules or gaster until they are fetched again. gaster's local change to
`gaster.c` is kept in `patches/gaster-local.patch`.

Linux research sources are pinned by `scripts/fetch-linux-research-sources.sh`.

## Prebuilt tools

No script downloads these yet, and their download URLs were not recorded. Copies are in
`~/env-snapshots/pongo-lab-tools-2026-11-05/`.

```text
d0ba1cc315523703a7f61e6ba6687ee166e7ac319d36f71b1e79f273180d0738  palera1n/palera1n-v2.1-beta.2
1287243a4eee1edb53e3c8d9c8c9c9d187e0b884b1ed74a161dbc62a9c83b45f  palera1n/checkra1n-0.1337.3-linux-x86_64
8058538d8fdb61b6631cc25221dea96a5b41f33b12bcf92e46045ac2cca7f1ee  checkra1n-official/checkra1n-0.1337.0-linux-x86_64
62908759b06c2f996b5891259583adc50fe0382769bd5d54edc3171c4b01c7fa  checkra1n-official/checkra1n-0.1337.1-linux-x86_64
04c481ce54b9e6b507f5e33dd1574874e0149261485bf507fa47f9bebcc2ae39  checkra1n-official/checkra1n-0.1337.2-linux-x86_64
53154d87594cf67c56659f24547f1b5bb5336f84ea58c2d42f25a7b2df81a964  checkra1n-official/checkra1n-0.1337.3-linux-x86_64
```
