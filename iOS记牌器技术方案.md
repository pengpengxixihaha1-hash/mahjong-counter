# 微乐江西麻将记牌器 iOS 版 · 技术方案

> 版本：v1.0（2026-09-25）
> 范围：微信小程序「微乐江西麻将」对局辅助工具，iOS 平台，浮窗实时显示**剩余张数**
> 关联工程：`E:\微乐记牌器`（Android 版 PokerAutoCounter，OpenCV 方案，可复用识别资产）

---

## 1. 结论先行

1. **iOS 不能像 Android 那样做悬浮窗**。系统禁止任何 App 覆盖在其他 App 之上，唯一可行的"假浮窗"是**画中画（PiP）窗口**：把记牌器 UI 渲染成视频帧，通过 PiP 小窗浮在微信上方，可拖动、可缩放。这是同类 iOS 产品（各类棋牌记牌辅助）的通用做法。
2. **实时获取游戏画面的唯一系统级入口是 ReplayKit 录屏广播**（Broadcast Upload Extension）。用户在控制中心长按"屏幕录制"，选择本 App 开始广播，每一帧屏幕画面都会送入 Extension。
3. 完整链路：**录屏广播 → Extension 内识别牌面 → App Group 传结果 → 主 App 计数 → PiP 浮窗显示剩余张数**。
4. 整个方案成败的第一个验证点是 **P0：PiP 浮窗技术验证**（约 1~2 天工作量）。若 PiP 不可行（系统限制/审核门槛），退回方案 B（截图识别，见 §9）。

### 硬性前提（缺一不可）

| 前提 | 说明 |
|---|---|
| Mac + Xcode | 当前开发环境是 Windows，iOS 编译调试必须 macOS（Apple Silicon Mac mini 即可，或云 Mac） |
| Apple 开发者账号 | $99/年。Broadcast Extension、PiP、App Group 都需要签名与 entitlement |
| 真机 | iPhone（iOS 15+），模拟器不支持 ReplayKit 广播和 PiP |
| 对局样本截图 | 微乐江西麻将各分辨率下的对局截图若干张，用于制作识别模板 |

---

## 2. 需求定义

### 2.1 本期功能（MVP）

- 浮窗实时显示 **每种牌的剩余张数**（口径见 §5.1）
- 支持江西麻将 136 张牌制：万/筒/条 各 9 种 ×4，风牌（东南西北）×4，箭牌（中发白）×4
- 浮窗可拖动、可收起；对局开始/结束自动启停计数
- 手动校准工具：首次使用时框选牌池区域

### 2.2 明确不做（本期）

- 安全牌/危险牌（现物）提示、精牌信息 —— 预留接口，后续版本
- Android 版已有的其他功能照搬
- 自动出牌、任何形式的外挂行为（越界，见 §8 合规）

### 2.3 用户体验流程

```
打开 App → 引导开启录屏广播（控制中心 → 屏幕录制 → 选本 App）
        → 进入微信打开微乐对局
        → PiP 浮窗出现在微信上层，实时刷新剩余张数
        → 对局结束，点浮窗恢复按钮回到 App 查看复盘统计
```

---

## 3. 总体架构

```
┌─────────────────────────────────────────────────────────────┐
│                        iPhone 系统                           │
│                                                             │
│  ┌──────────────┐   屏幕帧    ┌──────────────────────────┐   │
│  │ 微信(微乐小程序)│ ─────────→ │ Broadcast Upload Extension│   │
│  └──────────────┘  ReplayKit │  ├ 帧接收/降频(1~2fps)     │   │
│                              │  ├ ROI 裁剪(牌池/副露区域)  │   │
│                              │  └ 牌面识别(模板匹配)       │   │
│                              └────────────┬─────────────┘   │
│                                           │ 识别结果 JSON    │
│                                           │ App Group +     │
│                                           │ Darwin 通知      │
│  ┌────────────────────────────────────────▼─────────────┐   │
│  │                     主 App                            │   │
│  │  ├ 计数引擎(136张牌账)   ├ PiP 渲染(UI→CVPixelBuffer)   │   │
│  │  └ 设置/校准/复盘 UI     └ PiP 浮窗(画中画窗口)          │   │
│  └───────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

模块职责：

| 模块 | 职责 | 关键技术 |
|---|---|---|
| Broadcast Extension | 收屏、裁剪、识别 | ReplayKit / OpenCV |
| 主 App · 计数引擎 | 维护 136 张牌账，计算剩余 | 纯 Swift |
| 主 App · PiP 渲染 | UI → 视频帧 → 画中画窗口 | AVSampleBufferDisplayLayer |
| SharedKit | 双进程共享的模型与常量 | App Group |

---

## 4. 关键技术设计

### 4.1 PiP 画中画浮窗（核心，风险最高）

- **API**：`AVPictureInPictureController(contentSource:)` + `AVSampleBufferDisplayLayer`（iOS 15+）。
- **原理**：把记牌器界面渲染成 `CVPixelBuffer`，按 5~10fps 喂给 SampleBufferDisplayLayer，系统会把这个"视频"放进 PiP 小窗，浮于任何 App 之上。
- **渲染循环**：
  1. 收到新计数结果 → 标记脏区域
  2. 用 Core Graphics 把记牌 UI 画入复用的 `CVPixelBuffer`（`kCVPixelFormatType_32BGRA`，尺寸如 480×270）
  3. 包装成 `CMSampleBuffer`（附带定时信息）入队 DisplayLayer
- **保活技巧**：PiP 需要活跃的 AVAudioSession。标准做法是播放一条无声音频循环（`AVAudioSessionCategoryPlayback`），否则退后台后 PiP 会被系统回收。
- **窗口形态**：比例固定 16:9；小窗约屏幕 1/4 宽，可拖动到四角、可放大。
- **iOS 版本要求**：iOS 15+ 全功能支持；iOS 14 及以下不做兼容。

### 4.2 ReplayKit 录屏广播（数据入口）

- App 内置 `RPSystemBroadcastPickerView`，用户一键拉起系统广播授权。
- `SampleHandler` 收到 `CMSampleBuffer`（屏幕帧，约 60fps）：
  - **降频**：只处理 1~2 fps（麻将牌池变化慢，足够），其余直接丢弃——省电、省内存。
  - **内存红线**：Broadcast Extension 系统内存上限约 50MB，超限直接被杀。因此**识别在 Extension 内完成，只把小体积 JSON 结果传出**，绝不传整帧图像。
- 结束广播：对局结束或用户手动停止后，`finishBroadcastWithError` 正常收尾。

### 4.3 牌面识别（Extension 内）

- **区域（ROI）**：
  - 牌池弃牌区：各家弃牌按行排列在桌面中央
  - 副露区：碰/杠示牌（明牌必须计入"已见"）
  - 自家手牌：可选，默认不计入
- **算法**：模板匹配优先（OpenCV iOS xcframework，归一化互相关 NCC，多尺度 3 档），与 Android 版同一套模板图与阈值参数。
- **识别目标**：牌面数字/花色 + 背面（背面不识别内容，只排除）。
- **预处理**：ROI 裁剪 → 缩放到基准宽度 → 灰度 → 自适应二值化。绿色桌面对比度好，难度低于一般场景。
- **稳定性策略**：
  - 逐帧结果做**滑动多数表决**（连续 2 帧一致才更新牌账），杜绝闪烁误识别
  - 已出牌只增不减：新帧识别出的牌池集合与上一帧做差集，只接受"新增"，异常回退
- **校准**：首次使用引导用户拖拽框选牌池区域，归一化到屏幕比例保存；不同机型只需校准一次。可选自动检测（桌面色块聚类）作为增强。

### 4.4 进程间通信（Extension → 主 App）

- `UserDefaults(suiteName: group.xxx)` 写识别结果 JSON（约 200B/次）
- `CFNotificationCenterPostNotification`（Darwin 通知）唤醒主 App 刷新计数
- App Group 容器同时用于保存校准配置、模板缓存

### 4.5 计数引擎（江西麻将规则）

- 牌账模型：27 种数牌 + 7 种字牌，每种 4 张
- 输入：每帧新增的"已见牌"（牌池 + 副露）
- 输出：每种牌 `剩余 = 4 − 已见`，以及派生信息（绝张列表、剩余总张数）
- 规则可配置：是否含花牌、是否计算自摸已亮牌等，为后续"精牌"功能预留

### 4.6 浮窗 UI（剩余张数视图）

```
┌─────────────────────────┐
│ 剩余张数        [收起 −] │
│ 万 4 4 3 4 4 4 3 4 4    │
│ 筒 4 4 4 2 4 4 4 4 4    │
│ 条 4 0 4 4 4 4 4 4 4    │
│ 字 4 4 4 4 · 4 4        │
└─────────────────────────┘
0=绝张(灰)  1=危险(橙)  其余正常色
```

- 小窗态（默认）：三行数牌 + 一行字牌，约 1/4 屏宽
- 收起态：缩成小圆点，点击展开
- 刷新：仅在牌账变化时重绘，静止帧不重绘

---

## 5. 数据口径与接口约定

### 5.1 "剩余张数"口径（重要）

麻将中他人手牌是扣着的，无法识别。因此口径为：

> **剩余张数 = 4 − 已见张数**，其中"已见" = 牌池弃牌 + 各家副露（碰/杠明牌）+（可选）自己手牌。

这与市面同类记牌器口径一致：数值含义是"还未在任何明面上出现的张数"，玩家用它判断绝张与成型概率。

### 5.2 识别结果 JSON（Extension → 主 App）

```json
{
  "ts": 1769347200,
  "roi": "discard",
  "tiles": [ {"t": "W5", "n": 1}, {"t": "T3", "n": 2} ],
  "frameId": 1832,
  "conf": 0.93
}
```

### 5.3 计数快照（主 App 内部）

```swift
struct TileLedger {
  var seen: [TileType: Int]      // 已见
  var remain: [TileType: Int]    // 剩余 = 4 - seen
  var lastUpdate: Date
}
```

---

## 6. 工程结构（Xcode）

```
WeiLeCounter/
├── WeiLeCounter.xcodeproj
├── App/                        # 主 App (SwiftUI + UIKit 混合)
│   ├── PiP/
│   │   ├── PipController.swift         # AVPictureInPictureController 封装
│   │   ├── BufferRenderer.swift        # UI → CVPixelBuffer 渲染
│   │   └── CounterOverlayView.swift    # 浮窗 UI（剩余张数视图）
│   ├── Counter/
│   │   ├── TileLedger.swift            # 牌账/计数引擎
│   │   └── JiangxiRule.swift           # 江西麻将规则配置
│   ├── Capture/
│   │   └── BroadcastPicker.swift       # RPSystemBroadcastPickerView 封装
│   ├── Settings/
│   │   ├── CalibrationView.swift       # ROI 框选校准
│   │   └── ReplayView.swift            # 复盘统计页
│   └── AppGroup/
│       └── SharedConstants.swift
├── BroadcastExtension/         # Broadcast Upload Extension
│   ├── SampleHandler.swift             # 帧入口、降频、生命周期
│   ├── Recognition/
│   │   ├── TileMatcher.swift           # OpenCV 模板匹配封装
│   │   ├── RoiLocator.swift            # ROI 裁剪
│   │   └── FrameVoter.swift            # 滑动表决/差集
│   └── Templates/                      # 牌面模板图（自 Android 工程迁移）
└── SharedKit/                  # 双 target 共享
    ├── Models.swift                    # TileType / RecognitionResult
    └── IPC.swift                       # App Group 读写 + Darwin 通知
```

依赖：OpenCV iOS xcframework（与 Android 版同版本，模板参数可直接迁移）。

---

## 7. 开发里程碑

| 阶段 | 内容 | 验收标准 |
|---|---|---|
| **P0 浮窗验证**（先做） | PiP Demo：静态 UI 渲染成帧 → PiP 窗口浮在微信上 | 真机上浮窗可拖动、退后台不被回收 |
| **P1 数据通路** | Broadcast Extension 收帧 + App Group 通路 | Demo：录屏帧率日志 + 主 App 收到结果 JSON |
| **P2 识别引擎** | 迁移模板 → ROI 裁剪 → 匹配 → 表决 | 给定样本截图，牌池识别准确率 ≥98% |
| **P3 计数+浮窗** | 牌账引擎 + 浮窗实时显示剩余张数 | 全真机对局跟牌 1 局，无错记 |
| **P4 产品化** | 校准工具、机型适配、降频省电、复盘页 | 3 种机型各 1 局稳定运行，Extension 不被杀 |
| **P5 分发** | TestFlight 打包 / 分发渠道决策 | 按合规结论执行 |

P0 与 P1 可并行；P2 依赖样本截图（见 §10）。

---

## 8. 风险与对策

| 风险 | 等级 | 对策 |
|---|---|---|
| App Store 审核拒（游戏辅助类） | 高 | 定位"复盘/学习工具"；主走 TestFlight/企业签分发；不上架则无审核问题 |
| 微信/微乐检测录屏与辅助 → 封号 | 高 | 只读不写（不注入、不改包、不自动操作）；文档明示风险由用户自担 |
| PiP 对非视频内容有系统限制 | 中 | P0 提前验证；备选方案 B（§9） |
| Extension 内存超限被杀 | 中 | 降频 + ROI 小图识别 + 结果 JSON 出传；P4 压测 |
| 不同机型/分辨率识别漂移 | 中 | 归一化校准 + 多尺度匹配 + 表决机制 |
| Mac/开发者账号缺失 | 阻塞 | 前置条件，未解决前项目无法启动 |

**合规边界（必须遵守）**：本工具只做屏幕内容的被动识别与统计展示，不做任何内存读取、协议注入、自动点击。该定位是同类产品在 iOS 上的安全线。

---

## 9. 备选方案 B：截图识别（PiP 失败时启用）

- 用户在对局中 iOS 截图 → 切回本 App → 自动读相册最新截图 → 同一套识别引擎 → App 内展示剩余张数
- 无浮窗、无广播、无 PiP，**审核风险最低、开发量约为方案 A 的 40%**
- 代价：需要手动截图，非实时
- 建议无论 A 是否成功，B 的识别管线与 A 完全共用，作为兜底入口

---

## 10. 启动前需要准备的材料清单

1. Apple 开发者账号（或确认由谁提供）
2. 一台 Mac（Xcode 15+）
3. 测试用 iPhone（iOS 15+，装好微信与微乐）
4. **对局样本截图 10~20 张**：覆盖不同机型分辨率、牌池不同牌数阶段、有副露的场景（这批截图同时用于 P2 的模板制作与验收）
5. 确认江西麻将具体玩法规则（是否南昌"精牌"玩法、花牌处理），影响牌账初始化

---

*本文档对应工程目录 `E:\微乐记牌器`，Android 版 OpenCV 模板资产位于 Android 工程内，P2 阶段迁移。*
