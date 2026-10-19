# 点觅 · Dotmi

**简体中文** | [English](README.en.md)

原生 macOS 文件名搜索工具：按关键词查找本机文件，按类型筛选，在 Finder 中定位结果。

目前为个人项目预览版。现有本地构建使用临时签名，尚未提供经过 Developer ID 签名与 Apple 公证的正式安装包。

## 功能

- 搜索文件名，支持空格分隔多个关键词，可选匹配完整路径。
- 搜索整台 Mac 可访问且未排除的位置，或限定某个文件夹及其子文件夹。
- 按文档、图片、视频、音频、文件夹、压缩包、代码等类型筛选。
- 保存常用文件夹，切换范围时复用已有索引。
- 在 Finder 中显示选中文件、打开文件、快速预览、复制路径。
- 搜索框焦点、文件名关键词高亮与悬停反馈；复制路径、收藏和切换范围后显示短提示，轻量动效遵循系统减少动态效果设置。
- 搜索无结果时区分当前范围离线、无法访问、被排除、索引未完成和筛选限制，提供对应入口。
- 本地 SQLite 文件信息索引与字符检索索引；通过 FSEvents 增量更新。
- 默认收起常见隐藏文件与程序数据，可手动显示已索引的这些项目。
- 支持相关性、名称及修改时间排序；查询完成后预选首项，方向键导航时自动滚动跟随。
- 结果列表按空格打开独立预览，空格或 Esc 关闭，上下键切换；搜索框中的空格仍用于分隔关键词。
- 空搜索提供常用位置和可清除的最近定位 / 打开记录；记住排序与各风格窗口位置。
- 首批加载 200 项，可继续加载；过时查询支持执行中取消，分类计数继续覆盖全部匹配结果。
- 排序面板聚焦当前排序并支持键盘导航；全局快捷键提供三个可选组合及注册失败提示。
- 设置中的响应诊断分解调度 / 排队、查询执行与主线程等待；统计截至结果发布，不代表最终屏幕绘制。

当前不提供文件正文全文搜索、OCR、拼音检索、语义搜索或自动更新下载。

## 演示

[![点觅 1.21 搜索与类型筛选，全部为合成演示文件](docs/点觅-搜索与类型筛选-codex-2026-10-19-v1.0.png)](docs/点觅-搜索与类型筛选-codex-2026-10-19-v1.0.png)

1.21 使用顶部类型按钮筛选，不再按类型分组。切换类型后自动回到第一条结果；继续加载保留当前选择。截图为 2 倍分辨率的合成数据演示，未扫描真实目录，也不代表实际磁盘性能或文件监控状态。

运行 `zsh scripts/demo.sh` 可查看合成数据界面。演示不会扫描真实目录，不改动用户索引与偏好；虚构文件仅供展示，不支持实际打开或定位。退出演示后自动清理临时索引。

## 系统与工具

- 项目最低部署目标为 macOS 13；本机验证环境为 macOS 26、Apple Silicon。
- Swift 5.9 或更高、Xcode Command Line Tools、Python 3、系统 SQLite。
- 默认构建当前机器架构。Intel 构建路径已参数化，但尚未经过 Intel 实机运行验证。

安装 Apple 命令行工具后，确认 `swift --version` 与 `python3 --version` 可用。本项目不需要付费 API 或第三方服务账号。

## 构建与安装

```sh
# 只构建，不安装或启动
zsh build.sh

# 构建并更新唯一安装位置 /Applications/点觅.app
zsh build.sh --install
```

默认构建产物位于系统临时目录的 `xunji-artifacts/点觅.app`。可以指定输出：

```sh
zsh build.sh --output /tmp/xunji-preview/点觅.app
```

首次更新会将同 Bundle ID 的旧 `寻迹.app` 迁移为 `点觅.app`，不保留并列安装，数据目录与偏好域继续沿用 Xunji。

`--install` 会关闭正在运行的同一安装路径的点觅，并以验证后的包原位替换；保留索引与设置。安装到 `/Applications` 需要当前用户具有写权限。脚本不会更改系统权限设置，也不会关闭 Gatekeeper。

可通过 `XUNJI_ARCH=arm64` 或 `XUNJI_ARCH=x86_64` 请求指定架构构建；跨架构编译成功不代表已完成对应机器的运行验证。通过 `XUNJI_BUILD_DIR` 指定 SwiftPM 临时构建目录。

## 第一次使用

1. 选择“整台 Mac”或一个文件夹，建立文件信息索引。
2. 输入文件名关键词，按文件类型缩小结果。分类数字统计所有匹配结果，首批显示 200 项，可继续加载至最多 2,000 项。
3. 选择一条结果，再点击“在 Finder 中显示选中文件”。可按 ⌘Y 预览，⌘回车打开。
4. 常用文件夹只是快捷入口，不会因收藏而重复扫描；“索引管理”显示覆盖状态与跳过的位置。

“整台 Mac”并不意味着所有系统与程序文件都可搜索。默认跳过系统目录、用户 Library、废纸篓、`.git`、`.build`、`node_modules` 等位置，包和符号链接不递归。需要时可单独补充目录索引。文件权限、未连接磁盘与未下载的云端内容也会限制覆盖。

若确实需要读取受保护的位置，可在系统设置的“隐私与安全性 → 完全磁盘访问权限”中手动添加点觅。授权由使用者决定；临时签名构建在更新后可能需要系统重新确认。界面中的权限说明入口并不等于授权检测。

## 性能与数据

首次扫描、检索索引升级、大量文件变化和事件历史失效时会增加 CPU 与磁盘开销；普通重启会重放关闭期间的变化，必要时恢复相关范围扫描。后台事件合并约 2 秒处理一次，单次文件变化以最多 500 项的小批次提交，避免逐文件提交索引。没有基于所有电脑与文件规模的性能保证。

数据存于 `~/Library/Application Support/Xunji/`，包括文件名、完整路径、类型、大小、修改时间和索引覆盖状态。应用目前没有上传、账户、统计或遥测功能；系统预览由 macOS Quick Look 处理。详见 [隐私说明](PRIVACY.md)。

## 验证

```sh
# 核心检索、Unicode、范围边界、过滤、数据库迁移与十万条记录基准
zsh scripts/check.sh

# 上述检查 + 实际 macOS 文件变化、收藏和 Quick Look 生命周期检查
zsh scripts/check.sh --integration
```

安装迁移及性能检查可另外运行（先构建应用）：

```sh
zsh build.sh --output /tmp/dotmi-check/点觅.app
XUNJI_TEST_APP=/tmp/dotmi-check/点觅.app python3 Tests/verify_install.py
XUNJI_TEST_BINARY=/tmp/dotmi-check/点觅.app/Contents/MacOS/Xunji XUNJI_PERFORMANCE_REPORT=/tmp/dotmi-performance.json python3 Tests/measure_performance.py
```

安装检查仅使用临时目录，模拟系统注册失败以验证回滚；不会安装到 `/Applications`。性能检查生成 30,000 个合成文件，需要读取测试进程资源统计；输出为本机样本，不能代表所有磁盘与文件规模。系统要求补扫时会在测量中单独记录。

原生集成检查需要可使用 WindowServer 的登录桌面，会短暂打开测试窗口；使用隔离目录，不扫描真实文件或写入真实索引。CI 默认仅执行核心检查与构建，不把它们等同于完整桌面验证。

## 开发与发布

源码位于 `Sources/`，原生界面使用 SwiftUI/AppKit，检索核心使用系统 SQLite/FTS5。详见 [贡献说明](CONTRIBUTING.md) 和 [发布检查](docs/RELEASING.md)。

图标源文件为 `Resources/AppIcon.icon`，现代 macOS 使用由它编译的 `Resources/Assets.car`，旧系统保留 `AppIcon.icns`。常规构建使用仓库中的已编译资源，不需要单独安装完整 Xcode。修改图标后需要完整 Xcode，运行 `zsh scripts/compile_icon.sh` 重新生成资源，再构建应用。脚本支持通过 `DEVELOPER_DIR` 指定 Xcode，不修改系统默认工具链。

可在登录桌面运行 `swift Tests/inspect_icon.swift /Applications/点觅.app /tmp/dotmi-icon-preview.png --require-flat`，检查系统实际返回的蓝色字母内部颜色，而非只检查原始 PNG。该检查针对系统默认图标样式，不能替代 Dock 的实际外观检查。

## 许可证

本项目采用 **GNU GPL v3.0（GPL-3.0-only）**，完整条款见 [LICENSE](LICENSE)。Copyright (C) 2026 点觅 contributors。第三方组件和参考资料的来源说明见 [来源核对](docs/PROVENANCE.md)。
