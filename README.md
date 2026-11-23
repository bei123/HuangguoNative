# 黄果 · HuangguoNative

原生 SwiftUI **iOS** 客户端。对接黄果短剧站 `dx150-edge-v1` 加密网关，覆盖浏览、播放、账号与互动。

| | |
| --- | --- |
| 本仓库 | https://github.com/bei123/HuangguoNative |
| Android 版（uni-app x） | https://github.com/bei123/Huangguo-Short-Drama-App |
| 协议 | [MIT](./LICENSE) |

> Android 请用 [Huangguo-Short-Drama-App](https://github.com/bei123/Huangguo-Short-Drama-App)；该仓库以 Android 为主，iOS 兼容性不好，本仓库才是正式 iOS 方案。

## 环境

| 项 | 要求 |
| --- | --- |
| Xcode | 16+（Liquid Glass / iOS 26 Tab API 需较新 SDK） |
| 部署目标 | iOS 17.0+ |
| 签名 | Automatic，Bundle ID `com.huangguo.native` |

```bash
open HuangguoNative.xcodeproj
```

选模拟器或真机 Run 即可。

## 功能

- **首页**：Banner、精选、最近更新、分类推荐、专题入口
- **发现**：在线分类（自动隐藏已下线如 AI魔改 / AI换脸）、标签切换、上拉加载
- **搜索**：热词、结果列表、分页
- **我的**：登录注册、历史 / 收藏 / 点赞 / 关注、消息、编辑资料
- **播放**：系统 `AVPlayerViewController`、全屏、长按临时倍速、集数切换
- **内容**：榜单、专题、图文（灯箱）、推荐流、作者页、原创 / 排序列表
- **互动**：点赞、收藏、评分、评论（需登录）

## 技术要点

**边缘加密**（`Core/DxCrypto.swift` · `Core/EdgeClient.swift`）

- `dx150-edge-v1`：ECDH P-256 → HKDF → AES-GCM
- scope：`public` / `dynamic` / `playback` / `user`

**多域名测速**（`Core/EndpointRouter.swift`）

启动时并行探测主站与备用域名，选用最快可用线路；结果缓存约 30 分钟，连续失败自动换线。

候选：`huangguoai.com`、`hgai29.com`、`ea3.aqkmowihz.cc`、`huangguo88.pages.dev`、`wvyj3.aqkmowihz.cc`、`hccm.aqkmowihz.cc`、`fs0k.kplsifomz.cc`

**媒体**

- 封面：CDN 拉取 + AES-128-CBC 解密（`UI/HGCoverImage.swift`）
- 播放：HLS + 异步音频会话；全屏进度保持、长按倍速

**UI**

- 系统 `TabView` + Liquid Glass（iOS 26）
- 自适应深浅色主题、骨架屏、无限滚动

## 目录

```
HuangguoNative/
├── App/                 # 入口、Tab、路由
├── Core/                # 加密、Edge、域名测速、API、模型、会话
├── Features/            # 各业务页面
│   ├── Home / Category / Search / Mine
│   ├── Detail / Rank / Topics / Feed / Posts …
│   └── Login / Messages / MyList / ProfileEdit / Author
├── UI/                  # 主题、封面、播放器容器、骨架、卡片
└── Assets.xcassets/     # App Icon、色板
```

## 打包 IPA（自签 / 不上架）

默认走**未签名 IPA**：CI 与本地都不需要你的开发者证书。用户用自己的 Apple ID 重签安装（AltStore、Sideloadly、TrollStore 等）。

### GitHub Actions

`.github/workflows/build-ipa.yml`：

- **手动触发**：无签名编译 → Artifact 下载  
- **推送 `v*` 标签**：同上，并自动创建/更新 GitHub **Release**，把 `HuangguoNative-<tag>-unsigned.ipa` 挂到 **Assets**

**不需要**配置任何证书 Secrets（使用默认 `GITHUB_TOKEN` 发 Release）。

### 本地无签名包

```bash
xcodebuild -project HuangguoNative.xcodeproj \
  -scheme HuangguoNative \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build

APP=$(find build/DerivedData/Build/Products/Release-iphoneos -name '*.app' -maxdepth 1 | head -n 1)
mkdir -p build/Payload && cp -R "$APP" build/Payload/
( cd build && zip -r HuangguoNative-unsigned.ipa Payload )
```

### 用户怎么装

1. 下载 `HuangguoNative-unsigned.ipa`
2. 用 AltStore / Sideloadly 等，登录**自己的** Apple ID 重签并安装  
3. 免费账号签名一般约 **7 天**需重签；付费开发者账号或企业/超级签另论

> 未签名包不能直接装真机，也不能上架 App Store；仅适合分发后由用户自签。

## 说明

- 登录态存在本机 `UserDefaults`；退出登录会清本地会话
- 封面 Referer 跟随当前测速选中的域名
