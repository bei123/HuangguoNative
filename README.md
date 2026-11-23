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
| Xcode | 26+（Liquid Glass / Tab API） |
| 部署目标 | **iOS 26.0** |
| 机型 | **iPhone 11 及更新**（含 iPhone SE 第 2 代及更新）；不支持 XS / XS Max / XR 及更早 |
| 签名 | Automatic，Bundle ID `com.huangguo.native` |

```bash
open HuangguoNative.xcodeproj
```

选模拟器或真机 Run 即可。

## 功能

- **首页**：Banner、精选、最近更新、分类推荐、专题入口
- **发现**：在线分类（自动隐藏已下线如 AI魔改 / AI换脸）、标签切换、上拉加载
- **刷剧**：竖屏整页滑动推荐流（默认第 1 集）+ 相邻预加载  
  - 点 **看全集**：在当前流中插入后续集，继续上滑连播；播完自动进下一集  
  - 点 **退出连播**（或滑到其它短剧）：回到推荐流  
  - 长按画面临时倍速（期间锁滑动）；拖动进度条可看时间与预览帧  
  - 评论半屏：分页加载 / 发送（需登录）
- **搜索**：热词、结果列表、分页
- **我的**：登录注册、历史 / 收藏 / 点赞 / 关注、消息、编辑资料、**切换线路**
- **详情播放**：系统 `AVPlayer`、全屏、长按临时倍速、集数切换、自动起播
- **内容**：榜单、专题、图文（灯箱 + 横竖图自适应）、推荐流、作者页、原创 / 排序列表
- **互动**：点赞、收藏、评分、评论分页（需登录）

## 技术要点

**边缘加密**（`Core/DxCrypto.swift` · `Core/EdgeClient.swift`）

- `dx150-edge-v1`：ECDH P-256 → HKDF → AES-GCM
- scope：`public` / `dynamic` / `playback` / `user`

**多域名测速**（`Core/EndpointRouter.swift`）

启动时并行探测主站与备用域名，选用最快可用线路；结果缓存约 30 分钟，连续失败自动换线。探测要求真实边缘 JSON（剔除对 POST 返回 405 的静态镜像）。

候选：`huangguoai.com`、`ea3.aqkmowihz.cc`、`wvyj3.aqkmowihz.cc`、`hccm.aqkmowihz.cc`、`fs0k.kplsifomz.cc`

「我的 → 切换线路」可查看各线延迟并手动选定。

**媒体**

- 封面：CDN 拉取 + AES-128-CBC 解密（`UI/HGCoverImage.swift`）；图文详情按横竖图自适应高度
- 播放：HLS + 异步音频会话；刷剧 / 详情支持预加载、进度条拖动预览（`AVPlayerItemVideoOutput`）

**UI**

- 系统 `TabView` + Liquid Glass（iOS 26）；刷剧 Tab 禁用底栏随滚收起，避免分页露边
- 自适应深浅色主题、骨架屏、无限滚动

## 目录

```
HuangguoNative/
├── App/                 # 入口、Tab、路由
├── Core/                # 加密、Edge、域名测速、API、模型、会话
├── Features/            # 各业务页面
│   ├── Home / Category / Search / Mine
│   ├── Feed/            # 推荐流 + ShortDramaFeedView（刷剧）
│   ├── Detail / Rank / Topics / Posts …
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

CI 通过 `HG_NO_LIQUID_GLASS` 避开部分 Liquid Glass API，保证无签名机可编过。

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

### 自签名与安装

Release / Artifact 里的包是**未签名**的，不能直接装；必须用你自己的 Apple ID（或开发者证书）重签后再装。

#### 方式 A：AltStore / Sideloadly（推荐给普通用户）

1. 从 [Releases](https://github.com/bei123/HuangguoNative/releases) 下载 `HuangguoNative-*-unsigned.ipa`
2. 电脑安装 [AltStore](https://altstore.io) 或 [Sideloadly](https://sideloadly.io)，用数据线连接 iPhone
3. 登录**自己的** Apple ID，选择该 IPA 进行重签并安装
4. 手机首次安装开发者签名 App：  
   **设置 → 通用 → VPN 与设备管理 → 对应 Apple ID / 开发者 → 信任**
5. 免费个人账号签名通常约 **7 天**过期，到期后用同一工具重新签名安装即可  
   （付费 Apple Developer / 企业签 / 超级签有效期更长，另论）

> TrollStore 等永久签方案仅适用于特定系统与设备，自行评估风险。

#### 方式 B：本机 Xcode 开发证书装真机（开发者）

前提：Mac 已登录 Apple ID、Xcode 能自动签名，`DEVELOPMENT_TEAM` 已填（本仓库为 `FP4K7G3F83` 时可改成你自己的 Team），手机已信任此电脑并开启**开发者模式**。

```bash
# 查看已连接设备 UDID
xcrun devicectl list devices

UDID="<你的设备 UDID>"
xcodebuild \
  -project HuangguoNative.xcodeproj \
  -scheme HuangguoNative \
  -configuration Debug \
  -destination "id=$UDID" \
  -derivedDataPath build/DeviceDerivedData \
  CODE_SIGN_STYLE=Automatic \
  build

APP=build/DeviceDerivedData/Build/Products/Debug-iphoneos/HuangguoNative.app
xcrun devicectl device install app --device "$UDID" "$APP"
```

首次打开前同样在手机上信任开发者证书（路径同上）。也可直接在 Xcode 里选真机点 Run。

> 未签名包不能上架 App Store；上述流程仅用于自用 / 测试分发。

## 说明

- 登录态存在本机 `UserDefaults`；退出登录会清本地会话
- 封面 Referer 跟随当前测速选中的域名
- **如果访问速度慢，请开启 VPN**
- Xcode 控制台里 `PointerUI` / `nw_path_necp` / `FigApplicationStateMonitor` 多为系统噪音，与业务无关
