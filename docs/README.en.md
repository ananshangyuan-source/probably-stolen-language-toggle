# Probably Stolen — Q Language Toggle

Press **Q** to switch between English and Simplified Chinese in **Probably Stolen Demo**. Useful for reading dialogue and learning languages.

[Download](https://github.com/ananshangyuan-source/probably-stolen-language-toggle/releases/latest) · [Report an issue](https://github.com/ananshangyuan-source/probably-stolen-language-toggle/issues/new/choose) · [中文](../README.md)

## Installation

1. Download `ProbablyStolen-LanguageToggle-v1.0.3-Windows-x64.zip` from Releases.
2. Extract it to a permanent, writable folder and close the game.
3. Double-click `Install.cmd`. Steam libraries are detected automatically; choose the Demo folder if asked.
4. Launch the Demo normally through Steam. After initialization (about five seconds after the menu appears), press Q.

First-time installation requires access to BepInEx, GitHub and PyPI. The first game launch also downloads matching Unity base libraries and generates IL2CPP interop assemblies. It can take longer than a normal launch. The toggle itself runs locally, without API keys or online translation.

**Keep the extracted folder in place after installing.** The loader points to its runtime. To relocate it, uninstall first and reinstall from the new location.

## Compatibility and limitations

Tested with Windows 11 x64, Demo AppID `4349200`, build `25382790` (`049-Rev5-L`), Unity `2021.3.45f2` IL2CPP, and BepInEx `6.0.0-be.788+5b766a3`. The full game, other builds, Windows 10 and combinations with other mods have not been verified.

- Ordinary visible labels and language-dependent fonts are refreshed.
- Some open item panels must be closed and reopened. Native item rich text is deliberately preserved to avoid losing category labels.
- Text missing from the game's Chinese tables remains English. This is not a machine translation mod.
- Not every dynamic/formatted label or special panel can be refreshed immediately.
- Q is fixed and may conflict with another mod. It is ignored while a text input field has focus.

## Disable and uninstall

Close the game first. Use `Disable.cmd` to disable the mod or `Enable.cmd` to enable it again. `Uninstall.cmd` removes the three owned loader files from the game folder and the local runtime, generated tables and caches. Then delete the extracted folder if desired.

The installer adds only `winhttp.dll`, `doorstop_config.ini` and `.doorstop_version` to the game directory. It refuses to overwrite an existing loader. The uninstaller checks ownership/hashes and preserves files changed by another installation. Original game binaries, assets and saves are not edited by these scripts.

## Source and local game data

The repo contains our plugin source/binary, installer scripts, and documentation. It contains **no game binaries, assets, localization tables or generated game interop assemblies**. The installer reads bilingual tables from the user's own game and keeps the output locally. Do not redistribute that output.

The v1.0.3 runtime behavior was verified by a player. Installer lifecycle tests use an isolated fixture and do not claim a fresh runtime launch on every supported system. See [development notes](DEVELOPMENT.md), [changelog](../CHANGELOG.md) and [third-party notices](../THIRD_PARTY_NOTICES.md).

This unofficial community project was developed with Codex assistance and is not affiliated with the game's developers or publisher. Our own code is MIT-licensed; third-party dependencies and game content retain their respective licenses and rights.
