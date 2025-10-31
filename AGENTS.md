# Agent 指南

## 项目使命
- 本仓库用于 **Skydrivex**，这是一个优先支持 Linux 的第三方 OneDrive 客户端，后续计划覆盖 macOS 与 Windows。
- 项目目标是提供原生桌面体验，并保持与官方 OneDrive 服务的完整兼容。

## 技术栈
- **Flutter**（Dart）负责用户界面，各平台封装位于 `android/`、`ios/`、`linux/`、`macos/` 与 `windows/`。
- **Rust** 实现核心同步和 OneDrive 集成逻辑，并通过 `flutter_rust_bridge` 2.11.1 向 Flutter 暴露接口。
- 桥接配置保存在 `flutter_rust_bridge.yaml`；Rust 源码位于 `rust/`，Flutter 代码位于 `lib/`。

## 构建与集成说明
- 桥接代码需要使用标准 `flutter_rust_bridge` 工作流生成；请沿用现有配置并避免降级版本。
- 新增 Rust API 时，应先在桥接层公开并重新生成绑定，再处理 Dart 端逻辑。
- 每次变更都要确保 Linux 桌面目标保持可用；macOS 和 Windows 的脚手架需维持可编译状态，即使暂未完全支持。

## 协作约定
- 保持 Flutter 代码现有的格式、空安全以及异步模式。
- 遵循 Rust 2021 Edition 习惯，确保桥接使用的数据类型稳定且兼容。
- 请勿删除或覆盖本文件；如需补充面向 Agent 的说明，请在此继续追加。
