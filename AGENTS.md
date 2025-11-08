# Agent 指南

## 项目使命
- 本仓库用于 **Skydrivex**，这是一个优先支持 Linux 的第三方 OneDrive 客户端，后续计划覆盖 macOS 与 Windows。
- 项目目标是提供原生桌面体验，并保持与官方 OneDrive 服务的完整兼容。

## 技术栈
- **Flutter**（Dart）负责用户界面，各平台封装位于 `android/`、`ios/`、`linux/`、`macos/` 与 `windows/`。
- **Rust** 实现核心同步和 OneDrive 集成逻辑，并通过 `flutter_rust_bridge` 2.11.1 向 Flutter 暴露接口。
- 桥接配置保存在 `flutter_rust_bridge.yaml`；Rust 源码位于 `rust/`，Flutter 代码位于 `lib/`。

## 构建与集成说明
- 桥接代码需要使用标准 `flutter_rust_bridge_codegen generate` 工作流生成；请沿用现有配置并避免降级版本。
- 新增 Rust API 时，应先在桥接层公开并重新生成绑定，再处理 Dart 端逻辑。
- 每次变更都要确保 Linux 桌面目标保持可用；macOS 和 Windows 的脚手架需维持可编译状态，即使暂未完全支持。