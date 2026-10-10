# 实现与从源码构建

## 实现思路

试玩版采用Unity IL2CPP。BepInEx通过Unity Doorstop加载运行环境，生成当前游戏的互操作程序集，再加载我们自己的 `QuickLanguage.dll`。

本MOD只启用 `CanvasUpdateRegistry.PerformUpdate` 的Harmony后置补丁，每帧只执行一次控制器检查。初始化后，按Q时：

1. 记录当前显示的TMP普通文字。
2. 切换 `LocalizationSettings.SelectedLocale`，更新相关字体和菜单下拉框。
3. 用本机生成的英中对照表替换普通文字；正则匹配避开富文本标签并限制超时。
4. 跳过位于 `TreeNodeRender` 下的物品富文本，交给游戏自己的逻辑处理。
5. 强制更新Canvas，写入仅供本机排查的状态文件。

源码保留了早期 `LocalizationCapture` / `CachedTextRefresh` 的辅助定义，但 `Plugin.Load` **没有注册它们**。不要随意改成 `PatchAll()`：全局文字拦截曾导致物品类别丢失，1.0.3已撤掉这一行为。

文字映射由 `src/extract_languages.py` 在安装时读取玩家自己的Addressables包生成。不调用翻译API，不捆绑语言表。未找到中文时保留游戏的英文回退。

## 项目结构

```text
src/QuickLanguage.cs       已实机验证的1.0.3插件源码
src/extract_languages.py   仅在本机提取英中表
scripts/                  自动安装、停用、卸载、构建和打包
dist/QuickLanguage.dll    本项目自己的插件，非游戏程序集
dependencies.json         固定版本和下载ZIP的SHA256
requirements.txt          固定Python依赖版本
tests/                    安装生命周期、发布内容检查
docs/                     使用和开发说明
```

`.runtime`、`.local-only` 和 `.installation.json` 均仅用于本机，禁止打包发布。游戏DLL、语言表、反编译产物和互操作程序集不在仓库里。

## 编译

需要Windows、已安装且初始化过的BepInEx IL2CPP环境。**从自己拥有的游戏中生成互操作引用**，不得把引用程序集提交到仓库。

安装并启动一次游戏后，在解压目录执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build.ps1 -BepInExPath '.\.runtime\bepinex'
```

构建脚本下载固定版本的官方Roslyn编译器并校验SHA256。引用程序集只从指定的本地BepInEx运行环境读取。输出写到 `.local-only\build\QuickLanguage.dll`，不会自动替换已安装的插件或公开发行版。

也可用 `-CompilerPath` 指定已有的Roslyn `csc.exe`。编译器需要Windows .NET Framework运行环境；普通Windows 10/11系统通常已有。

若修改运行逻辑，应递增插件版本并用自己的游戏验证菜单、物品类别、输入框以及停用恢复。发布时手动更新 `dist/QuickLanguage.dll` 和 `dependencies.json` 的插件版本/哈希，再更新兼容表和CHANGELOG。不要声称未验证的游戏版本已兼容。

## 发布

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Verify-Package.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Package.ps1
```

打包采用明确白名单，不递归复制开发目录。输出ZIP和SHA256位于 `.local-only\releases`，上传到GitHub Releases。仓库中的GitHub Actions只检查公开内容和打包；不会下载游戏，也不会上传本地生成的游戏数据。

## 验证范围

- 插件1.0.3由实际玩家在上述试玩版实机确认Q切换与物品类别显示。
- 发布用安装器通过隔离游戏目录的安装、重复安装、停用、启用、卸载、冲突保护和失败回滚检查。
- 语言提取器对玩家已有游戏执行只读提取，与原1.0.3本机语言表比对。
- 没有为验证安装器替换玩家当前正常使用的加载器或启动第二套游戏运行环境。
