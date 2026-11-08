<div align="center">
  <img src="design/icon-selected-mirrored.png" width="88" alt="Mac Explorer Daily 图标">
  <h1>Mac Explorer Daily</h1>
  <p>用熟悉的 Windows 11 操作习惯，在 Mac 上整理文件。</p>
  <p>简体中文 · <a href="README.zh-TW.md">繁體中文</a> · <a href="README.en.md">English</a></p>
  <p><a href="https://github.com/XIANG-z25/Mac-Explorer/releases/download/v1.7.0/Mac-Explorer-Daily-1.7.0-mac-arm64.dmg"><strong>下载 1.7.0 DMG</strong></a> · <a href="https://github.com/XIANG-z25/Mac-Explorer/releases/tag/v1.7.0">发行说明</a></p>
  <p><sub>Apple Silicon（M 系列）· macOS 13 或以上 · Swift / AppKit</sub></p>
</div>

## 当前分支更新（1.7.6）

GitHub Release 提供 **1.7.0 DMG**。下列改动已进入 `zx/daily-native` 源码，想体验这些功能可按[源码构建说明](native/README.md#构建和打开)构建 Daily。

- **外置盘与 Mounty**。挂载后自动出现在侧栏「此电脑」下，右键可选「安全弹出」。NTFS 的读写能力由系统或 Mounty 提供。
- **同卷移动**。支持直接改名的卷会直接移动。Mounty 挂载的 NTFS 卷也可无复制移动普通文件，遇到同名目标时保留原目标。
- **统一传输窗口**。进行中的复制和移动集中显示，每项都有进度、速度和取消按钮。关闭窗口后可通过「窗口 → 传输文件」重新查看。

## 1.7.0 已发布功能

- **复制标签页**。右键任意标签，选择「复制标签页」。副本在右侧打开同一目录，并保留选中项。
- **从地址栏打开新标签**。按住 `⌘` 点击路径中的目录名，或右键选「在新标签页中打开」。切回原标签可以接着刚才的位置浏览。
- **列表内拖动框选**。在「详细信息」视图，从文件名或各列文字旁的空白拖动即可多选。
- **分组和完整文件名**。切换图标大小后立即按组排布。鼠标停在文件或文件夹图标上约半秒，完整名称会显示在指针旁。

## 日常功能

| 场景 | 可以怎么做 |
| --- | --- |
| 浏览与整理 | 目录树、快速访问、多标签、空格预览、紧凑视图。文件夹可排在文件前面，也可按修改日期等条件分组。 |
| 批量重命名 | 文件和文件夹都支持前后缀、查找替换、大小写、去括号内容、编号和修改扩展名。手动删除示例文件名里的一段文字，可把同一段应用到其他选中项。同名冲突时可查看双方名称和大小，再决定保留副本或替换。 |
| NAS 与云盘 | 支持 SMB，并可开启启动时自动重连。侧栏可浏览 macOS 中已接入的 iCloud Drive、OneDrive 和 Box 等云盘目录。同步和离线保留由各自的客户端管理。 |
| 个人设置 | 可调整字体大小、默认视图和启动位置。常用的「下载」可设为启动位置，单个文件夹也可保存自己的视图。 |

## 下载与安装

1. 从 [本仓库的 Release](https://github.com/XIANG-z25/Mac-Explorer/releases/latest) 下载 Apple Silicon 版 DMG。
2. 更新前先退出旧版。打开 DMG，将 **Mac Explorer Daily.app** 拖到「应用程序」，再从那里启动。
3. 安装包采用临时签名，未经 Apple 公证。若首次启动被拦截，先确认文件来自本仓库，并与 Release 附件 `SHA256SUMS.txt` 核对。

Daily 版通过本仓库的 Release 手动更新。

## 源码与反馈

Mac Explorer Daily 基于 [qixiaoyu27/Mac-Explorer](https://github.com/qixiaoyu27/Mac-Explorer)，保留原项目的 [GPL-3.0 许可](LICENSE)。本分支的改进可在 [提交记录](https://github.com/XIANG-z25/Mac-Explorer/commits/zx/daily-native/) 查看。源码构建请参阅 [原生版开发文档](native/README.md)，个人版可在仓库根目录运行 `python3 -I native/scripts/build.py --personal`。

<details>
<summary>版本策略</summary>

<a id="版本策略"></a>

兼容修复递增补丁版本，兼容功能递增次版本，不兼容变更递增主版本。已发布的标签和附件保留供回退。

</details>
