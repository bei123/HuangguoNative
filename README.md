# HuangguoNative

独立的苹果原生 SwiftUI 客户端（不依赖 uni-app / HBuilder）。

## 参考

- 接口与加密：`../Huangguo-Short-Drama-App/huangguo-api-and-crypto.md`
- 页面结构参考 uni 工程：首页 / 发现 / 搜索 / 我的 / 详情 / 榜单 / 专题

## 能力

- `dx150-edge-v1`：ECDH P-256 + HKDF + AES-GCM（`Core/DxCrypto.swift`、`Core/EdgeClient.swift`）
- 封面 AES-128-CBC 解密加载（`UI/HGCoverImage.swift`）
- HLS 播放（`AVPlayer` + `VideoPlayer`）+ 音频会话
- 官方 Liquid Glass：系统 `TabView` + `glassEffect`（iOS 26）
- 登录/注册、赞藏评、评论、历史同步、我的列表/消息/改资料
- 专题详情、作者页、图文、推荐流、原创/排序

## 打开

```bash
open HuangguoNative.xcodeproj
```

Xcode 选择模拟器或真机，Run。部署目标 iOS 17.0。

## 目录

```
HuangguoNative/
  App/           入口与路由
  Core/          加密、Edge 会话、API、模型
  Features/      各页面
  UI/            主题、封面、卡片、TabBar
```
