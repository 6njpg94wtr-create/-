# 在线翻译服务契约（第一阶段）

App 的在线翻译通过 `TranslationServing` 接口与供应商解耦。当前实现 `HTTPTranslationService` 发送真实 HTTPS 请求，不提供内置服务器，也不内置任何厂商 API 密钥。

## 配置

在 App 的“翻译 → 设置”填写完整 HTTPS 接口地址，例如由部署者管理的 `https://example.org/translate`。示例地址不是可用服务。App 不会自动补上 `/translate`。地址保存在本机；禁止把厂商 API 密钥放进地址、客户端代码或工程配置。

当前首阶段客户端适用于无需额外客户端登录的兼容网关。生产服务应在服务端保管翻译供应商密钥，实施访问控制、配额和限流。需要用户认证的服务应先补齐正式登录、短期会话凭据和 Keychain 存储；本版尚未实现登录协议，不应将有成本的开放接口直接投入公开运营。

## 请求

`POST <配置地址>`，`Content-Type: application/json`，最多 5,000 字符，超时 30 秒。

```json
{
  "text": "请问图书馆在哪里？",
  "sourceLanguage": "zh",
  "targetLanguage": "ru",
  "style": "polite"
}
```

- `sourceLanguage`、`targetLanguage`：`zh` 或 `ru`。客户端使用 Apple NaturalLanguage 提供可手动触发的语言识别，用户仍可纠正。
- `style`：`natural`、`formal` 或 `polite`。后端须真正将表达风格传给翻译引擎或 AI 服务，不能返回预设句子。

## 成功响应

HTTP 2xx，JSON 对象，必需的 `translation` 必须是非空字符串；可选的 `explanation` 为字符串或 null，用于语境和歧义说明。

```json
{
  "translation": "Подскажите, пожалуйста, где находится библиотека?",
  "explanation": "礼貌问路表达。"
}
```

此例只说明接口格式；App 不包含这段固定响应，不会用它作为真实翻译结果。

## 失败处理

| 情况 | 客户端行为 |
| --- | --- |
| 未配置地址 | 提示先配置服务，不发送请求 |
| 非 HTTPS、空主机、URL 含用户名/密码 | 拒绝地址 |
| HTTP 401 / 403 | 提示服务需要身份验证 |
| HTTP 402 | 提示余额或额度不足 |
| HTTP 429 | 提示限流或额度受限 |
| 其他非 2xx | 展示 HTTP 状态，不当作译文 |
| 非 JSON、缺少译文、空译文 | 提示接口格式无法解析 |
| 离线 / 超时 | 明确提示并保留输入 |
| 主动取消 / 离开页面 | 取消请求，不保存过期结果 |

## 本机记录和语音

成功的原文、译文、语言、时间、表达风格与说明保存在 UserDefaults 独立的 `russianwords.translation.history.v1` 键中。保留最近 200 条普通记录及所有收藏；解码失败时保留原始数据并停止覆盖写入。

“对话”页是轮流发言模式：申请麦克风和语音识别权限 → 使用 Apple Speech 识别 → 用户结束录音并检查/编辑文字 → 真实翻译请求 → AVFoundation 朗读。用户可选择中文或俄语、调整语速、中断并重新录音、重播历史译文。不宣称同声传译或无延迟。

音频可能由 Apple 联网识别，文字会发送到配置的服务。Xcode 目标必须配置 `NSMicrophoneUsageDescription`、`NSSpeechRecognitionUsageDescription`。录音、权限拒绝与恢复、语音可用性、音频中断、后台切换及不同 iPhone 的收音效果仍需真机验收。

## 验证范围

`Tests/TranslationServiceTests.swift` 使用 URLProtocol 拦截请求验证序列化、响应解析、状态码、空响应和取消；这些是协议单元测试，不等于真实服务验收。真实中俄双向翻译须由部署者提供可用网关后，输入未预设的新句子验证。语音识别与朗读须在 iPhone 实测。
