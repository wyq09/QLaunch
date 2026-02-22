# QLaunch (macOS 原生启动台)

一个使用 SwiftUI 实现的 macOS 原生 Launchpad Demo，视觉风格为液态玻璃（Liquid Glass）。

开源地址：[https://github.com/wyq09/QLaunch](https://github.com/wyq09/QLaunch)

## 运行

1. 命令行运行：

```bash
swift run
```

2. 或在 Xcode 中打开：

```bash
open Package.swift
```

## 交互

- 实时应用列表：启动时扫描本机 `/Applications`、`/System/Applications`、`~/Applications` 等目录中的真实 `.app`
- 图标：直接读取系统应用图标（非占位图）
- 搜索：顶部搜索框（支持中文、拼音、应用名称与 Bundle ID 检索）
- 打开应用：点击图标后会直接启动对应应用
- 分页布局：固定每页 `5 * 7`（35）图标
- 翻页动效：整页水平滑动，支持拖拽翻页与键盘翻页
- 手势翻页：触控板横向滑动（左滑下一页，右滑上一页）
- 分页指示：底部分页点居中
- 透明玻璃背景：窗口与主界面均使用 macOS 玻璃材质
- 默认窗口：首次启动默认铺满可见屏幕
- 全局快捷键唤起：可自定义（默认 `⌃⌥⌘L`，应用运行时全局生效）
- 文件夹分组：支持拖拽应用图标到另一个图标上自动建文件夹、拖入已有文件夹、重命名、拖出文件夹、一键拆散文件夹
- 翻页：底部分页圆点，或键盘左右方向键

## 测试

```bash
swift test
```
