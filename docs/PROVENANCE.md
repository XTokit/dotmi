# 来源与授权核对

## 当前目录

- 应用及索引核心为本项目 Swift 源码；SwiftPM 未引用外部包。
- SQLite 通过系统库链接，未将第三方数据库源码复制入仓库。
- AppKit、SwiftUI、Quick Look、Carbon 与文件系统事件由 macOS SDK 提供。
- 应用图标采用用户选定的 B 字母组合方向，概念经图像生成后重新构建为几何矢量；`Resources/AppIcon.svg` 为母版，`Resources/export_brand.py` 保存同源导出几何，产物为 `AppIcon.icns` 和单色菜单栏图标。无第三方字体或嵌入位图依赖。
- 新版图标文档 `Resources/AppIcon.icon` 由项目自己的 SVG 几何构建；`Assets.car` 使用 Apple Xcode 的 actool 生成。未将 Apple 工具二进制或第三方图标工具源码打包进应用。
- 测试文件名、演示记录与公开演示截图使用合成数据。
- CI 使用 `actions/checkout`，不将该 Action 的源代码或运行环境打包进 App。

## 发布前尚需确认

项目所有者已选择 GPL-3.0-only。此前参考的文章、演示、素材或代码是否附带其他需要遵守的条款，仍需在发布前核对。本次整理没有把飞书文章正文、其他 App 的二进制、私人截图或历史交付包加入公开文件清单。

上述文件检查不构成对全部知识产权来源的法律保证。未确认来源的第三方内容不应直接加入源码发布包。
