# Third-party notices

The release ZIP contains this project's own plugin and scripts, not these runtimes or game assets. Installation downloads upstream packages separately. Their licenses remain in effect; our MIT license does not relicense them.

| Dependency | Purpose | License / upstream |
| --- | --- | --- |
| BepInEx 6.0.0-be.788+5b766a3 | IL2CPP mod loader | [LGPL-2.1](https://github.com/BepInEx/BepInEx/blob/5b766a3/LICENSE); [source](https://github.com/BepInEx/BepInEx/tree/5b766a3) |
| BepInEx bundled components | Doorstop, CoreCLR, Harmony, IL2CPP interop | Each component retains its upstream license; see [BepInEx dependencies](https://github.com/BepInEx/BepInEx/tree/5b766a3) |
| CPython 3.12.15 standalone (Astral build 20261003) | Local table extraction | [PSF license](https://docs.python.org/3.12/license.html); [build source and component licenses](https://github.com/astral-sh/python-build-standalone/tree/20261003) |
| uv 0.12.23 | Install Python dependencies locally | [MIT / Apache-2.0](https://github.com/astral-sh/uv/tree/0.12.23) |
| UnityPy 1.25.4 | Read local Unity bundles | [MIT](https://github.com/K0lb3/UnityPy/blob/master/LICENSE) |
| Python transitive dependencies | Bundle parsing / compression | Package license metadata is retained in local `pydeps`; exact versions are in requirements.txt |
| Microsoft.Net.Compilers.Toolset 4.8.0 | Optional source build only | [NuGet package](https://www.nuget.org/packages/Microsoft.Net.Compilers.Toolset/4.8.0), upstream license retained |

No third-party source code has been copied into the plugin source. The API names referenced by the plugin require game/runtime assemblies supplied locally by the user. Game text, binaries, generated interop and assets are not redistributed.

The Probably Stolen title and other game identifiers belong to their respective owners. This is an unofficial community modification. See the [game modding code of conduct](https://github.com/dragonpan2/probably-stolen-modding/blob/main/CodeOfConduct.md).
