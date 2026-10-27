<div align="center">
  <h1>购件助手 · Goujian Assistant</h1>
  <p>把购物平台物流放在一起，让订单查询与物流追踪更简单。</p>
  <p>
    <img src="https://img.shields.io/badge/Android-7.0%2B-3DDC84?logo=android&logoColor=white" alt="Android 7.0 及以上">
    <img src="https://img.shields.io/badge/Windows-10%20%2F%2011-0078D4" alt="Windows 10 / 11">
    <a href="LICENSE"><img src="https://img.shields.io/badge/License-AGPL--3.0-blue" alt="AGPL-3.0"></a>
  </p>
</div>

## 项目介绍

**购件助手（Goujian Assistant）** 是一款面向 **Android 和 Windows** 的免费购物物流聚合应用，基于文析助手（AsterLink）二次开发。

登录购物平台账号后，可以查看订单列表、追踪物流轨迹，把常用订单和物流信息集中管理。支持多账号切换，物流状态自动刷新。

## 支持平台

- 拼多多

## 功能

- 应用内 WebView 登录（扫码/短信）
- 订单列表查看（待付款/待发货/待收货/待评价/全部）
- 物流轨迹追踪（运输中/已签收/已入柜等状态细分）
- 多账号管理与切换
- 登录状态自动检测与刷新

## 技术栈

- Flutter 3.41 / Dart 3.11
- flutter_inappwebview（WebView 登录与页面渲染）
- Dio（HTTP 请求）

## 编译

### 环境要求

- Flutter SDK 3.41+
- Android Studio / Visual Studio（Windows 端）

### Android 构建

```bash
flutter pub get
flutter build apk --release
```

产物：`build/app/outputs/flutter-apk/app-release.apk`

### Windows 构建

```bash
flutter pub get
flutter build windows --release
```

产物：`build/windows/x64/runner/Release/`

## 致谢

本项目基于 [文析助手 AsterLink](https://github.com/z7786/wenxi) 二次开发，感谢原作者的开源贡献。

## 许可证

本项目采用 **AGPL-3.0** 许可证，详见 [LICENSE](LICENSE)。
