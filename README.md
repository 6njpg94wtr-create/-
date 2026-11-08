# 俄语单词本

使用 SwiftUI 和 AVFoundation 的 iOS 应用，无第三方依赖，支持 iOS 15.0 及以上版本。

在 macOS 上使用 Xcode 15 或更新版本打开 `RussianWords.xcodeproj`，选择 `RussianWords` scheme 和 iPhone 或 iPad 模拟器，然后运行。应用入口为 `RussianWordsApp.swift`，主界面和功能代码位于 `MainAppView.swift`。

也可以在仓库目录执行不需要签名的模拟器编译：

```sh
xcodebuild -project RussianWords.xcodeproj \
  -scheme RussianWords \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/RussianWords-DerivedData \
  CODE_SIGNING_ALLOWED=NO build
```

真机运行需要在 Xcode 的 Signing & Capabilities 中选择自己的开发团队。语音使用系统俄语声音，词库保存在应用的 UserDefaults 中。

当前云环境为 Linux，不提供 Xcode、SwiftUI 或 Apple SDK，因此此环境内无法完成 iOS 编译验证。
