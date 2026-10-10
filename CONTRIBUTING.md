# Contributing

Issues and focused pull requests are welcome. Include the game BuildID, mod version, Windows version, affected screen and minimal reproduction steps.

- Never commit game binaries, localization tables, generated interop assemblies, saves, full logs, credentials or personal paths.
- Keep game data generation local. Respect the game's modding code of conduct.
- Do not add global TMP text hooks without addressing the item category regression.
- Changes to installation/removal must preserve ownership checks and path boundaries.
- Build from local game references; describe which game versions were actually tested.
- Contributions to this project's own code are submitted under its MIT license.

The installer lifecycle is tested using isolated fixtures. Do not point development tests at a real game installation. See docs/DEVELOPMENT.md.
