# Mac Explorer Daily · 本地日常精简版

本地开发分支 `zx/daily-native` 基于 qixiaoyu27/Mac-Explorer 的 Swift/AppKit 实现。3egirlsdream/Mac-Explorer 仅作为功能和布局参考，没有复制其 C# 实现。基线提交分别为 `f9652a6`（Swift）和 `350ce55`（C#）。两个上游均为 GPL-3.0；本仓库保留原许可证及署名。

## 第一版范围

- 保留 Windows 11 风格的标签栏、路径栏、目录树、搜索、详细列表和图标视图。
- 日常工具栏默认显示剪切、复制、粘贴、重命名、批量重命名、回收站、撤销。
- 保留 Ctrl / Command 文件操作、F2 重命名、空格 Quick Look 和多标签快捷键。
- 常用文字默认使用 13pt 系统字体和 medium 字重；恢复 AppKit 默认字体平滑，兼容中文回退字体。「设置 → 常规 → 字体大小」可选择 12–16pt，即时应用并记忆。
- 默认关闭 Git/SVN 检测，日常模式隐藏终端、网络、AirDrop 和开发相关设置；设置 → 常规 → 使用模式可即时切换完整功能。
- 默认采用详细列表，按名称排序，保留逐文件夹视图记忆。
- 压缩与解压、外接盘、iCloud Drive、收藏夹、回收站和原有文件安全检查继续可用。

这是界面精简版；高级能力的底层代码仍保留。没有宣称缩减安装体积或提升文件传输性能。

## 构建与运行

```sh
cd /Users/zx/Projects/mac-explorer-native
python3 -I native/scripts/build.py
open 'native/output/Mac Explorer.app'
```

普通本地产物使用独立 Bundle ID `local.zx.macexplorer.daily`，显示名称为 Mac Explorer Daily。不会覆盖已安装的上游应用或共享其偏好。自定义构建不显示上游更新入口，不自动下载上游版本；更新需重新构建本分支。版本号沿用上游，未作为新版本发布。应用为本地 ad-hoc 签名。

## 代码入口

- `ExplorerDailyProfile.swift`：默认配置与统一字体。
- `BrowserController.swift`：日常模式的工具栏、目录树和菜单。
- `ExplorerDialogs.swift`：日常/完整模式设置。
- `NativeDailyChecks.swift`：隔离模式切换及界面检查。

日常模式验证命令：`python3 -I native/scripts/smoke.py --validation --skip-build --daily`。

本轮验证结果见 `native/output/validation/smoke/` 下实际生成的报告。全部文件操作检查使用临时目录；真实 Finder 跨应用剪贴板、网络共享及隐私权限仍需实际使用验收。

## 本轮验证（2026-10-25）

- CoreChecks：80 项断言通过；FileActionChecks：231 项断言通过。
- 完整 AppKit 回归：476 项检查通过，10,003 个浏览夹具与文件内容保持完整。
- 日常模式：18 项检查通过，包含模式切换、快捷键保留和设置入口。
- 简中／繁中／英文文案映射检查通过；本地产物签名校验通过。
- 最新完整报告：`native/output/validation/smoke/full-report.json`；精简模式报告：`native/output/validation/smoke/daily-report.json`。

## Windows 排序与分组

工具栏「排序 → 分组依据」，或在空白区域右键选择「分组依据」：

- 支持修改日期、创建日期、类型和无分组。分组顺序与组内文件排序分别设置。
- 默认「文件夹始终置顶」：文件夹单独排在最上方，文件按今天、昨天、本周早些时候、上周、本月早些时候、上个月、更早分组。将来的日期与未知日期单独显示。
- 取消「文件夹始终置顶」后，文件夹也按实际日期进入对应分组，每组仍优先显示文件夹。
- 点击组标题展开／折叠，也可展开／折叠所有组。分组依据、方向、置顶选项、折叠状态按文件夹记忆；「应用到所有文件夹」同时应用分组设置。
- 详细信息、大／中／小图标、列表、平铺及内容视图均支持分组。组标题不参与选择、剪贴板文件列表或文件拖拽。
- 无分组时，名称、修改日期、创建日期、类型、大小的升序／降序均保持文件夹优先。
- 默认 Enter 打开、F2 重命名、Delete 移到系统回收站；保留 Ctrl / Command 剪切复制粘贴、Alt 方向键、Ctrl+L 路径栏、F5 刷新及空格预览。已有自定义快捷键优先。

分组使用已有目录元数据，不逐文件增加磁盘读取；日期按系统日历和时区划分，跨午夜后更新。图标分组布局按可见区域查询，滚动不会反复扫描整份目录。发布拷贝在签名前移除本地链接符号，不引入额外运行时。

分组专项验证：`python3 -I native/scripts/check-core.py GroupingChecks` 和 `python3 -I native/scripts/smoke.py --validation --skip-build --grouping`。截图与本机性能数据来自临时测试文件，不能代表所有磁盘、NAS 或真实文件类型的速度。

## 分组版本最终验收（2026-10-25）

- GroupingChecks：289 项断言通过；CoreChecks：80 项断言通过。
- 分组专项原生界面检查：46 项通过，包含八种布局、选择与拖拽身份、F2 重命名、无障碍折叠和组标题聚焦时的 Ctrl+L。
- 完整 AppKit 回归：476 项通过，临时文件完整性检查通过。
- 10,003 项目录本机分组视图更新约 116 ms；完整回归中目录读取约 132 ms，目录读取至表格更新约 253 ms。计时是隔离夹具的单次本机结果。
- 应用包 5254571 字节（约 5.01 MiB），Swift/AppKit 原生实现；签名与 574 条文案映射检查通过。
- 报告：`native/output/validation/smoke/grouping-report.json`、`native/output/validation/smoke/full-report.json`。
- 预览：`native/output/validation/smoke/grouped-details.png`、`grouped-icons.png`、`grouped-dark.png`。

## 字体、批量命名、远程重连与默认视图

- 「设置 → 常规 → 字体大小」调整界面文字；文件列表行高随字号增加，选择会保存到本地偏好。
- 「设置 → 常规 → 启动位置」除“此电脑”和个人文件夹外，也可选择桌面、下载、文稿、图片、音乐、影片或应用程序；它同时用于普通启动、新窗口和新标签。
- 日常版默认启用更接近 Windows 的紧凑间距；「设置 → 常规 → 布局间距」可随时切换。列表、图标和内容视图均缩小了项目间距。
- 「设置 → 常规 → 系统文件查看器」可由用户明确启用。它通过 macOS 的文件查看器偏好接收兼容应用的“在 Finder 中显示”请求，并完整保存、可恢复原设置；Finder 本身仍保留，应用不会强制替换它。
- 多选同一目录中的至少两个文件或文件夹后，可按工具栏「批量重命名」或右键菜单。规则支持前缀、后缀、文本替换、大小写、删除中英文圆/方/花括号内容、数字序列及文件扩展名修改，并在执行前显示预览；文件夹不会被添加或修改扩展名。执行前检查非法名称与目标重名，成功操作归入一次撤销。已有工具栏偏好会一次性加入该按钮，之后可自由关闭。
- 批量重命名顶部的「编辑源文件名」会带入第一个选中项的名称。直接删掉其中的网址、作者名等片段后，相同文字会从所有选中项目中移除；该输入仅接受删除，不允许把新增文字误批量应用。
- 如果目标名称已存在，会先逐项显示来源名称/大小与现有名称/大小，再提供「创建名称 (1)」和「替换现有项目」两个选项。前者保留原文件并继续可撤销；后者需要明确点击确认，覆盖操作不可撤销。
- 「设置 → 常规 → 远程服务器」可开启启动自动重连，默认关闭。只记录手动成功连接过的 SMB 地址（最多 20 个），不记录用户名、密码；系统挂载器使用自身凭据机制。启动时按保存顺序异步尝试，不阻塞主窗口。离线失败的地址保留，供下一次启动重试。真实远程认证和网络恢复需在用户自己的服务器上验收。
- 「查看 → 设为新文件夹的默认视图」设置后续未单独配置的文件夹布局，不改其他文件夹已记住的布局。「查看 → 应用到所有文件夹」把当前布局、排序和分组应用给全部文件夹，并清除之前逐文件夹的视图覆盖；这是想让每层目录一致时应选的命令。也可在「设置 → 常规 → 文件夹视图」直接选默认布局。
- 专项验证：`python3 -I native/scripts/check-core.py BatchRenameChecks`；原生界面测试通过 `python3 -I native/scripts/smoke.py --validation --skip-build --daily`。所有命名测试使用临时文件。

## 本机安装包

`python3 -I native/scripts/package-daily.py` 将已构建并签名的普通 Daily 应用打包到 `native/output/install/<版本>/`，生成 DMG、ZIP 和 SHA256SUMS.txt。此命令不安装、上传或覆盖已有安装包。DMG 内有 `Mac Explorer Daily.app` 和 Applications 快捷方式：打开 DMG 后将应用拖到 Applications 即可安装。安装后从「应用程序」打开 `Mac Explorer Daily`。它使用独立 Bundle ID，与 `/Applications/Mac Explorer.app` 并存。

当前本机已安装到 `/Applications/Mac Explorer Daily.app`；本地产物为临时 ad-hoc 签名，未经过 Apple 公证。其他 Mac 上的首次运行可能需要通过系统安全设置批准；不要关闭 Gatekeeper 或用上游安装器替换独立 Daily 版。
