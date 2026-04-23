# AGENTS.md

我想做一个 AI 日程助理 App，用户可以通过语音/文字录入信息，通过 AI 解析成相应的日程记录在 App 中。

## 技术要求
- 代码保持简洁易读
- 使用 SwiftUI，支持 iOS 26以上
- 用到 `ObservableObject` 时需要 `import Combine`
- 支持 emoji 输入
- 严格遵循云端 API 文档的数据结构、数据类型、字段名
- 日程本地持久化使用 SwiftData
- 遵循 iOS 26 设计规范
- 底部导航 TabView 使用系统样式

## 核心交互流程
- 首页支持语音和文字录入。
- 用户提交后先进入 AI 解析页面，显示加载动画。
- AI 结果返回后，在同一流程中显示解析结果确认页。
- 用户确认并成功写入日程后，跳转到“今日”页面。

## 交付要求
- 使用 iPhone 17 编译
- 编译过程产生的临时文件不要加入到 Git

## 云端 API 地址
`https://planasstanttest-dbmejgslku.cn-hangzhou.fcapp.run`

## 云端 API 文档
`https://zzz-pet.oss-cn-hangzhou.aliyuncs.com/doc/plan_assistant_API.md`

## 云端 OpenAPI 文档
`https://zzz-pet.oss-cn-hangzhou.aliyuncs.com/doc/plan_assistant_openapi.json`

## Pencil 设计稿
`https://zzz-pet.oss-cn-hangzhou.aliyuncs.com/doc/plan_assistant.pen`

## 日程提醒策略
- 默认提前 10 分钟提醒
- 其它可选项：
  - 不提醒
  - 准时提醒
  - 自定义提醒
- 自定义提醒选中时，默认提前 60 分钟提醒，可以通过输入框更改提前分钟数

## 日历与系统同步规则
- 所有创建类事件都会同步到系统日历
- 从 App 删除日程时，也要删除系统日历事件
- 从系统日历删除日程后，App 内也要删除对应的日程

## 提醒与闹钟的语义规则
- 所有创建类事件都必须创建系统日历日程。
- 普通“提醒我”按日程处理，只创建系统日历日程及日历提醒。
- 只有用户明确提及“闹钟 / 叫醒 / 叫我起床 / 设个闹钟”等语义时，才额外使用 iOS 26 AlarmKit 创建系统闹钟。
- `kind = "alarm"` 表示“系统日历日程 + AlarmKit 强提醒”，不是只创建闹钟。
- 删除 `kind = "alarm"` 的事件时，必须同时删除系统日历事件和 AlarmKit 闹钟。
- 从系统日历删除该日程后，App 内也要删除对应事件，并尝试取消关联的 AlarmKit 闹钟。

## AlarmKit 配置要求
- 需要配置 `NSAlarmKitUsageDescription`
- 需要配置 `NSSupportsLiveActivities`
如有疑问请参考 Apple 官方文档完成配置

## 权限要求
- App 启动时即请求所需权限
