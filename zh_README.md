# Skydrivex

Skydrivex 是一个以 Linux 为优先的第三方 OneDrive 桌面客户端，同时也支持 macOS 与 Windows。项目目标是提供原生桌面体验，并保持与官方 OneDrive 服务的完整兼容。

## 技术栈与结构
- Flutter + Riverpod 构建 UI，入口在 `lib/main.dart`，功能模块位于 `lib/features/`.
- Rust 负责核心同步与 OneDrive 集成逻辑，源代码在 `rust/`。
- Flutter 与 Rust 通过 `flutter_rust_bridge` 2.11.1 交互，配置在 `flutter_rust_bridge.yaml`。
- 构建脚本 `./build_rust.sh` 会编译 Rust crate 并重新生成桥接代码。

## 环境要求
- Flutter SDK 与 Dart（保持与本仓库 `pubspec.yaml` 对齐的渠道与版本）。
- Rust 稳定工具链、`cargo`。
- 已安装 `flutter_rust_bridge_codegen` 2.11.1（用于生成绑定）。

## 快速开始
1) 拉取依赖：
   ```bash
   flutter pub get
   ```
2) 编译 Rust 并生成桥接代码：
   ```bash
   ./build_rust.sh
   ```
   更改 Rust API 后需要重新运行此脚本。
3) 运行应用（Linux 优先）：
   ```bash
   flutter run -d linux
   ```
   macOS 与 Windows 脚手架需要保持可编译，但功能仍在推进中。

## 开发与验证
- Flutter 代码检查与测试：
  ```bash
  flutter analyze
  flutter test
  ```
- Rust 侧常规构建：
  ```bash
  cargo build --manifest-path rust/Cargo.toml
  ```

## 贡献指南
- 保持 Linux 桌面可用性，同时避免破坏 macOS/Windows 的编译。
- 新增或修改 Rust API 时，先更新桥接定义并重新生成绑定，再实现 Dart 逻辑。
- 确保桥接代码已更新。
