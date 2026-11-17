# XM6 Control（老系统版）

[中文](README.md) | [English](README_EN.md)

一个轻量的 iOS App，用来在**旧版 iOS** 上控制索尼 WH-1000XM6 的降噪模式与环境声级别。官方 Sound Connect 要求 iOS 17.0，老设备被迫淘汰；本项目直接走耳机自带的 ExternalAccessory 控制通道，不依赖官方 App，也不依赖新系统特性。

> 非官方项目，与 Sony 无关，未获索尼任何授权或支持。协议细节来自对官方 App 的蓝牙抓包分析。使用风险自负，因使用本软件造成的任何设备、耳机或数据问题由使用者自行承担。

## 功能

- 三态切换：降噪 / 环境声 / 关闭
- 环境声 1–20 级细调（拖动实时预览，松手提交）
- 进入 App 自动回读耳机当前模式与级别
- 断线、切后台回来自动重连
- 可选的本地收发日志（可一键导出 / 清除）
- 无网络请求、无第三方依赖、无统计

## 系统要求

| 项目 | 要求 |
|---|---|
| iOS | 11.0 及以上，64 位设备 |
| 蓝牙 | 经典蓝牙（iAP2 / RFCOMM），耳机已与手机配对 |
| 安装方式 | 越狱设备 + AppSync，或自行用证书重签 |

仅在一台 iPhone XR（iOS 13.6）上实测通过。因为手头没有更老的设备可以测试，无法确定最低能支持到哪个 iOS 版本——代码层面最低部署目标是 iOS 11.0，实际能跑到多低、更老的系统是否放行该 ExternalAccessory 协议，均未验证。

## 工作原理（简述）

官方 App 在经典蓝牙上用 iAP2 与耳机通信，iOS 的 ExternalAccessory 框架会替应用剥掉 iAP2 外层，因此应用层看到的就是索尼 MDR v2 帧：

```
3E | type(1) | seq(1) | len(4, 大端) | payload | checksum(1) | 3C
```

- `checksum` = 从 type 到 payload 末字节的累加和
- `seq` 在 0/1 之间交替；ACK 帧的 seq 为被确认帧 seq 取反
- 环境声 payload：`68 19 01 01 01 00 NN 00 00`（NN = 01–14）
- 降噪：`68 19 01 01 00 00 NN 00 00`
- 关闭：`68 19 01 00 00 00 NN 00 00`
- 查询状态：`66 19`，耳机回 `67 19 01 xx xx 00 NN 00 00`

未使用索尼任何私有代码或密钥。

## 构建

需要 `xcodegen` 与本机 Xcode：

```bash
xcodegen generate
xcodebuild -project XM6Control.xcodeproj -scheme XM6Control \
  -sdk iphoneos -configuration Release CODE_SIGNING_ALLOWED=NO
```

推送到 `main` 时 GitHub Actions 会自动构建未签名的 ipa 并作为 artifact 上传。

## 免责声明

本项目为个人研究与自用工具，与索尼公司（Sony Corporation）无任何关联，未获其授权、认可或支持。「SONY」「WH-1000XM6」等为其各自权利人的商标，此处仅用于说明兼容对象。

- 软件按「现状」提供，不对可用性、稳定性或对设备的适用性作任何担保
- 通过非官方通道与耳机通信，可能存在协议变更、固件更新导致失效的风险
- 在越狱设备上安装第三方签名的应用存在系统稳定性风险
- 使用本软件所产生的一切后果由使用者自行承担

## AI 声明

本项目的代码编写、协议逆向分析协助与文档撰写，使用了 AI 模型 DeepSeek-V4.1-Flash-1017 参与完成。所有协议结论均经真机与抓包实测验证。

## 许可证

[MIT License](LICENSE) © 2026 PDWYX
