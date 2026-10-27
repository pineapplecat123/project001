# project001

基于 **Godot 4.7.2**（2D，GL Compatibility 渲染器）的游戏项目。

- 在线试玩（GitHub Pages）：https://pineapplecat123.github.io/project001/
- 单元测试：[GUT 9.7.1](https://github.com/bitwes/Gut)（已内置在 `addons/gut`）

## 目录结构

```
project.godot          项目配置（主场景 res://scenes/main.tscn）
scenes/main.tscn       主场景（Node2D + 标题 Label）
scripts/main.gd        主场景脚本
tests/                 GUT 测试（文件名以 test_ 开头）
addons/gut/            GUT 测试框架（第三方，MIT）
.gutconfig.json        GUT 命令行配置
export_presets.cfg     导出预设（Web，单线程，输出 build/web/index.html）
.github/workflows/     CI（ci.yml）与 Pages 部署（pages.yml）
```

## 本地运行

1. 安装 [Godot 4.7.2](https://godotengine.org/download/archive/4.7.2-stable/)（标准版，非 .NET）。
2. 用 Godot 打开本目录下的 `project.godot`，按 F5 运行。

命令行运行：

```bash
godot --path . 
```

## 运行测试

```bash
godot --headless --import                         # 首次需导入资源
godot --headless -s addons/gut/gut_cmdln.gd -gexit
```

## Push 前门禁（字符集）

```bash
bash tools/install_git_hooks.sh   # 一次：安装 pre-push hook
bash tools/pre_push_check.sh      # 手动：版本 + UI 字符集覆盖；不绿不得推
```

有玩家可见中文改动时，先 `bash tools/rebuild_ui_font.sh` 再检查。方块字（□）通常是新文案未进字体子集。

也可以在编辑器底部的 **GUT** 面板中运行。新增测试：在 `tests/` 下新建 `test_xxx.gd`，`extends GutTest`，方法名以 `test_` 开头。

## 导出与部署

本地导出 Web（需已安装 4.7.2 导出模板）：

```bash
godot --headless --export-release "Web" build/web/index.html
cd build/web && python3 -m http.server 8000   # 浏览器打开 http://localhost:8000
```

Web 预设关闭了线程支持（`variant/thread_support=false`），因此不需要 COOP/COEP 响应头，可以直接放在 GitHub Pages 上。

自动部署：

- 每次 push / PR，`CI` 工作流会无界面运行 GUT 测试。
- push 到 `main` 时，`Deploy Web to GitHub Pages` 工作流会导出 Web 版并发布到 GitHub Pages（仓库 Settings → Pages 的 Source 为 GitHub Actions）。
