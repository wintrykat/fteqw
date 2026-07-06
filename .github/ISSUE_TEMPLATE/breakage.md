---
name: Breakage report (build / render / plugin / bundle)
about: Something that used to work stopped working — likely an upstream, Homebrew, or macOS change.
title: "[breakage] "
labels: [breakage]
---

<!--
This project is a thin, test-guarded port. Most breakage comes from a moving
upstream part. The fastest fix path is: identify the failing test, then read the
matching section of docs/PORTING.md.
-->

## What broke
<!-- build fails / GL or Vulkan won't init / a plugin won't load / app isn't self-contained / etc. -->

## Failing test(s)
<!-- Output of ./macos/tests/run.sh — especially the FAILURES list. Paste the red lines. -->

```
```

## Environment (what may have changed)

- macOS version (`sw_vers`):
- Chip (`uname -m` / model):
- Homebrew (`brew --version`) and relevant formula versions
  (`brew list --versions sdl2 sdl3 molten-vk vulkan-loader ffmpeg freetype`):
- This repo's commit and upstream merge state (`git log --oneline -5`):

## Relevant PORTING.md section
<!-- Which assumption in docs/PORTING.md looks like it moved? (§1 vk source, §2 engine build,
     §3 MoltenVK, §4 bundling, §5 case-sensitivity, §6 plugins, §7 launcher) -->

## Logs
<!-- Build log, or engine console output (run the binary directly for stdout, or use +condebug). -->

```
```
