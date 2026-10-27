<div align="center">
  <h1>购件助手 · Goujian Assistant</h1>
  <p>把购物平台物流放在一起，让订单查询与物流追踪更简单。</p>
  <p>
    <img src="https://img.shields.io/badge/Android-7.0%2B-3DDC84?logo=android&logoColor=white" alt="Android 7.0 及以上">
    <img src="https://img.shields.io/badge/Windows-10%20%2F%2011-0078D4" alt="Windows 10 / 11">
    <a href="LICENSE"><img src="https://img.shields.io/badge/License-AGPL--3.0-blue" alt="AGPL-3.0"></a>
  </p>
</div>

---

> **⚠️ 项目已归档，不再继续开发**
>
> 该项目核心方案需要逆向电商 APP 原生接口，或是使用 H5 网页接口，两种路线都无法做到一劳永逸。电商平台会持续更新 APP 版本、修改签名算法、调整接口地址、升级风控策略，软件上线后必须长期、持续迭代维护，一旦没有时间跟进适配，功能就会直接失效。
>
> **放弃原因：**
> 1. **维护成本很高。** 平台改动签名、接口、鉴权逻辑时，需要重新抓包、分析、逆向、改写请求与解析代码，单次适配工作量不小，没有充足的空余时间长期投入持续维护。
> 2. **风控压力持续存在。** 就算走 APP 原生接口路线，也存在账号验证码、账号风控、设备限制等问题，需要不断跟进平台新增的检测规则。
> 3. **合规风险高。** 通过逆向、绕过平台校验的方式拉取订单物流数据，存在侵犯平台数据保护机制、个人信息相关的法律风险，不适合长期分发使用。
> 4. **项目依赖第三方平台。** 项目的生存主动权不在自己手上，平台的改动可以直接让整个工具瘫痪，稳定性不可控。
>
> 综合权衡之后，决定放弃这个项目，更换不依赖第三方接口、几乎不需要持续维护的本地工具类项目。

---

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
