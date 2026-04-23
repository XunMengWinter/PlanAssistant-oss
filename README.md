# PlanAssistant7

PlanAssistant7 是一个面向 iOS 26 以上系统的 AI 日程助理 App。用户可以通过语音或文字输入自然语言，App 将请求云端 AI 解析为日程、提醒或闹钟语义，并在用户确认后写入本地日程与系统日历。

项目使用 SwiftUI 构建界面，使用 SwiftData 持久化 App 内日程，并通过 EventKit、Speech、AlarmKit 等系统能力完成日历同步、语音录入和强提醒。

## 预览

> 预览图位置已预留。请在开源发布前将截图放到 `Docs/preview.png`。

![PlanAssistant7 Preview](Docs/preview.png)

## 核心功能

- 语音录入：按住麦克风说出安排，系统语音识别后自动填入输入框。
- 文字录入：支持自然语言和 emoji 输入，例如「明早 8 点叫我起床」。
- AI 解析流程：提交后先展示 AI 解析加载页，返回结果后在同一流程内展示确认页。
- 日程确认：用户可以在保存前调整标题、日期、时间、持续时间、提醒策略和备注。
- 今日视图：保存成功后跳转到“今日”页面，集中查看今天、明天和未来日程。
- 本地持久化：使用 SwiftData 保存 App 内日程镜像。
- 系统日历同步：创建类事件会写入系统日历；从 App 删除时同步删除系统日历事件。
- 外部删除同步：检测系统日历变化，如果对应事件已在系统日历中删除，App 内也会移除镜像。
- 闹钟语义：只有用户明确提及“闹钟 / 叫醒 / 叫我起床”等语义时，才额外创建 AlarmKit 闹钟。
- 提醒策略：默认提前 10 分钟提醒，也支持不提醒、准时提醒和自定义提前分钟数。

## 技术栈

- SwiftUI
- SwiftData
- Observation
- EventKit
- Speech
- AVFoundation
- AlarmKit
- iOS 26+ 系统设计与系统样式 TabView

## 运行要求

- macOS + Xcode，需包含 iOS 26 SDK。
- iPhone 17 Simulator 或支持 iOS 26 以上的真机。
- 当前工程部署目标为 iOS 26.2。
- 真机使用 AlarmKit 时，需要确认签名、系统版本和权限能力可用。

## 快速开始

1. 克隆仓库并进入项目目录。

   ```bash
   git clone <your-repo-url>
   cd PlanAssistant-oss
   ```

2. 使用 Xcode 打开项目。

   ```bash
   open PlanAssistant7.xcodeproj
   ```

3. 选择 `PlanAssistant7` scheme 和 iPhone 17 模拟器，然后运行。

4. 也可以使用命令行编译。

   ```bash
   xcodebuild -project PlanAssistant7.xcodeproj -scheme PlanAssistant7 -destination 'platform=iOS Simulator,name=iPhone 17' build
   ```

## 云端 API

默认 API 地址：

```text
https://planasstanttest-dbmejgslku.cn-hangzhou.fcapp.run
```

相关文档：

- API 文档：`https://zzz-pet.oss-cn-hangzhou.aliyuncs.com/doc/plan_assistant_API.md`
- OpenAPI 文档：`https://zzz-pet.oss-cn-hangzhou.aliyuncs.com/doc/plan_assistant_openapi.json`
- Pencil 设计稿：`https://zzz-pet.oss-cn-hangzhou.aliyuncs.com/doc/plan_assistant.pen`

App 侧会向云端发送用户输入、当前时间、时区、语言环境和本地日程上下文，并严格按云端 API 文档中的字段名、数据结构和数据类型解析响应。

## 权限说明

App 启动时会请求运行所需权限：

- 日历完整访问权限：用于创建、删除和同步系统日历事件。
- 语音识别权限：用于将语音录入转为文本。
- 麦克风权限：用于本机语音录入。
- AlarmKit 权限：用于在明确闹钟语义下创建系统闹钟。
- Live Activities 支持：AlarmKit 配置要求之一。

对应配置位于 `PlanAssistant7/Info.plist`，包括 `NSCalendarsFullAccessUsageDescription`、`NSSpeechRecognitionUsageDescription`、`NSMicrophoneUsageDescription`、`NSAlarmKitUsageDescription` 和 `NSSupportsLiveActivities`。

## 项目结构

```text
PlanAssistant7/
├── App/                  # App 入口、TabView 外壳和根视图
├── Features/
│   ├── Capture/          # 语音/文字录入
│   ├── Confirmation/     # AI 解析加载页与结果确认页
│   └── Upcoming/         # 今日与未来日程视图
├── Models/               # SwiftData 模型与 API 数据结构
├── Services/             # 云端 API、本地解析、日历/闹钟/语音服务
├── Support/              # 日期格式化与视觉样式
├── Assets.xcassets/
└── Info.plist
```

## 开源说明

发布开源版本前建议补充以下内容：

- `LICENSE`：请根据你的开源策略选择合适协议。
- `Docs/preview.png`：替换 README 中预留的 App 预览图。
- 云端 API 可用性说明：如果测试 API 不适合公开长期使用，建议在 README 中说明如何替换为自己的后端地址。

构建产生的 `.derivedData/`、`DerivedData/`、`*.xcactivitylog` 等临时文件已通过 `.gitignore` 排除，请不要提交到仓库。
