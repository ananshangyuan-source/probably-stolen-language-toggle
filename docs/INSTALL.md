# 安装、卸载与排错

## 普通安装

下载Releases里的Windows x64 ZIP，解压，保存并退出游戏，双击 `Install.cmd`。

安装器按以下顺序工作：

1. 从Steam注册表和 `libraryfolders.vdf` 查找试玩版，包括其他盘上的Steam库。
2. 检查IL2CPP游戏文件、游戏进程、已有加载器和游戏BuildID。
3. 下载固定版本BepInEx、便携Python和uv；对下载归档逐一校验SHA256。
4. 在解压文件夹里安装固定版本UnityPy及依赖，无需系统Python，不设置全局PATH。
5. 从自己的游戏包生成英中对照表，再添加3个加载器文件。
6. 保存本机安装记录；清除本次下载包、uv启动工具和安装缓存。

首次启动由BepInEx生成与本机游戏匹配的互操作程序集。不要在生成时强行退出。以后从Steam或原快捷方式启动即可，无需一直开着安装器。

所有便携运行环境、日志、互操作程序集和本机语言表集中在解压文件夹的 `.runtime`。安装期间的包构建缓存放在Windows临时目录里随机命名的 `psq-install-*` 子目录，成功或失败后都会清除；这样可避免旧版Windows工具的长路径问题。安装记录为 `.installation.json`。这些都不属于公开源码，已加入 `.gitignore`。

首次安装依赖下载约70–100MB；解压及首次启动缓存会占用数百MB，具体由BepInEx生成结果决定。没有额外驻留服务，退出游戏后本MOD不会独立占用CPU/GPU。

## 手动指定位置

在解压目录打开PowerShell：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install.ps1 -GamePath 'D:\SteamLibrary\steamapps\common\Probably Stolen Demo'
```

`ExecutionPolicy Bypass`只作用于这次PowerShell进程，不修改系统执行策略。脚本下载代码来源与哈希都写在 `dependencies.json` 中，可以先自行审查。

若游戏目录权限不足，先确认自己的账号对该Steam库有写权限；也可以在审查脚本后右键 `Install.cmd` 以管理员身份运行。通常无需管理员权限。

未知BuildID默认要求明确确认，自动化运行可使用 `-NoPrompt`。只有接受其他构建可能不兼容时，才添加 `-AllowUntestedBuild`；这不代表其他构建已经通过测试。

## 常见问题

### 找不到游戏

先从Steam安装免费试玩版，或用 `-GamePath` 指定包含 `Probably Stolen.exe` 的目录。暂不保证正式版兼容。

### 提示已有加载器

安装器不会覆盖已有 `winhttp.dll`、`doorstop_config.ini` 或 `.doorstop_version`。用原MOD提供的卸载方式移除它，或保留已有MOD并停止安装本项目。不要为通过检查随意删除来源不明的DLL。

### 下载失败 / 哈希不匹配

检查能否打开BepInEx官方构建站、GitHub及PyPI。网络失败后，安装器会清理本次暂存目录；如果还没有安装成功，不会留下启用状态的加载器。不要用不明来源文件绕过哈希检查。

### 按Q没有反应

检查游戏是否正在进行第一次BepInEx初始化，菜单出现后等待约5秒；确认输入框没有焦点。查看 `.runtime\bepinex\BepInEx\LogOutput.log` 中是否有 `Q is ready`。若游戏更新，请反馈BuildID。分享错误时，只复制相关行，并删除个人路径，不要上传整个日志。

### 物品窗口部分文字没有刷新

关闭后重新打开物品窗口。1.0.3保留原生物品富文本，以避免类别英文消失或排版损坏。

### 中文缺失 / 某些文字仍是英文

本MOD使用游戏已有的语言表，不补翻游戏缺失的中文。部分格式化或缓存文字也可能需要重新进入页面。

### 想移动文件夹 / 游戏更新后重新生成语言表

先关闭游戏并运行 `Uninstall.cmd`，再移动文件夹或重新安装。游戏更新后会重新检查BuildID、提取语言表并生成互操作缓存。

### 卸载提示文件被修改

脚本发现加载器哈希和安装记录不一致时会停止。可能有其他MOD覆盖了加载器；请先查清它的归属，不要强行删除。卸载只会处理本项目添加的3个文件及本项目运行环境。

## 本地下载缓存（维护者 / 测试用途）

可以使用 `-DependencyCache 'D:\verified-downloads'`，其中包含 `bepinex.zip`、`python.tar.gz`、`uv.zip`。仍会校验 `dependencies.json` 中的SHA256，Python包仍从PyPI安装。

安装器不会把API密钥、环境变量、存档或诊断文件发送到维护者。依赖下载和首次BepInEx库下载会像正常网络请求一样访问相应服务器。
