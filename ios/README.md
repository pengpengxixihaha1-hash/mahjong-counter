# 微乐五十K 记牌器 · iOS 版

iPhone 上用的五十K 记牌器：录屏广播收帧 → 识别 → 画中画（PiP）浮窗显示各牌点剩余张数与四家流水。

当前为**阶段 1 版本**：完整链路（录屏收帧、样本采集、PiP 浮窗、牌账引擎）已就绪，
识别模板需用你手机的真实对局样本制作（手机分辨率与 PC 不同）。

## 阶段 1 使用流程（采集样本）

1. 安装 App（见下文「云构建」+「Sideloadly 侧载」）
2. 打开 App →「样本采集模式」保持开启
3. 点「开始录屏广播」→ 系统弹窗选择「五十K记牌器」
4. 切到微乐，正常打**一局**（约 10 分钟）
5. 回到本 App →「导出样本」→ 把样本传到电脑
   - 方式 A：导出按钮会复制到「文件」，再用隔空投送/云盘传电脑
   - 方式 B：数据线连 Windows，iTunes（或 Apple Devices 应用）→ 文件共享 → 五十K记牌器 → 拷出「样本」文件夹
6. 样本发回来后即可制作手机版模板（阶段 2），然后开启识别（阶段 3）

## 云构建（无 Mac，免费）

1. 把整个项目推到 GitHub 仓库（main 分支）
2. 仓库 → Actions → 「iOS 云构建」→ Run workflow
3. 构建完成后在该次运行页下载 artifact「WeiLePoker50K-unsigned-ipa」→ 得到未签名 ipa

## Sideloadly 侧载安装（Windows）

1. 下载安装 [Sideloadly](https://sideloadly.io)（Windows 版）
2. iPhone 用数据线连电脑（首次需在手机上点「信任」）
3. Sideloadly：拖入 ipa → Apple ID 填你的个人 Apple 邮箱 → Sign
   - 若提示 App Groups 相关失败，勾选 Sideloadly 的修复选项重试
4. iPhone：设置 → 通用 → VPN 与设备管理 → 信任你的开发者证书
5. 打开 App 即可使用；**免费 Apple ID 签名 7 天有效，到期重签一次**（数据不受影响）

## 技术架构

```
ReplayKit 录屏广播（Broadcast Upload Extension）
  ├─ 降频 ~2fps，逐帧 autoreleasepool（扩展内存红线 ~50MB）
  ├─ 阶段1：样本采集 → App Group 容器 Samples/（上限 1200 帧）
  └─ 阶段3：ScreenRecognizer 识别 → PokerLedger 牌账
        ↓ App Group UserDefaults + Darwin 通知（IPC.swift）
主 App
  ├─ PiP 画中画浮窗（AVSampleBufferDisplayLayer，无声音频保活）
  └─ 主条（王2AKQJ09876543 剩余）+ 四家流水（对/上/下/我）
```

- 牌账引擎 `Shared/PokerLedger.swift`：PC 版 Ledger 逐行移植（新局重置 → 同点数去抖 →
  花色级差分 → 基数夹逼，回放 #12 守恒 0 违规验证版）
- 识别引擎 `BroadcastExtension/Recognition/CardMatcher.swift`：PC classify() 移植
  （letter_h / trim_top_band / 列投影聚簇 / 分层 NCC / 颜色先验 / 星标检测），
  匹配用纯 Swift + Accelerate vDSP，不依赖 OpenCV
- 四家分区阈值（seatTopY/seatBottomY/seatMidX）与 ROI 均为 PC 坐标系默认值，
  阶段 2 用真机样本重新标定

## 工程结构

```
ios/
├── project.yml                  # XcodeGen 工程定义（App + Broadcast Extension）
├── Shared/                      # 双 target 共享
│   ├── Models.swift             # 牌定义 / 检出 / Counter
│   ├── PokerLedger.swift        # 牌账状态机（PC 移植）
│   └── IPC.swift                # App Group 读写 + 快照
├── WeiLePoker50K/               # 主 App
│   ├── MainView.swift           # 主界面（状态/开关/导出）
│   ├── Pip/                     # PiP 浮窗（渲染/UI/控制）
│   ├── Audio/AudioKeepAlive.swift
│   ├── BroadcastPickerView.swift
│   └── SampleExportView.swift
└── BroadcastExtension/          # 录屏广播扩展
    ├── SampleHandler.swift      # 帧入口：降频 + 样本采集
    ├── ScreenRecognizer.swift   # 识别骨架（阶段 3 填充）
    └── Recognition/CardMatcher.swift
```

构建依赖：XcodeGen（CI 的 macOS runner 上 brew 安装），xcodebuild 不签名编译，
Sideloadly 在 Windows 上完成签名与安装。
