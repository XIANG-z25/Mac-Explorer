# Mac Explorer Daily 1.12.0

本版基于上游 Mac Explorer 1.10.1，继续使用原生 Swift/AppKit，保留 Daily 的独立应用标识和个人设置。

- 整合上游至 1.10.1 的原生界面、文件操作和安装相关改进，保留个人版文件工作流及 OneDrive 通过 Finder 处理的入口。
- 增加安卓 USB（MTP）浏览、文件夹浏览和保存到 Mac。自带 libmtp/libusb，修复部分 OnePlus 设备连续读取时的会话重置问题，无需安装额外的 MTP 应用。当前只读，不支持向手机上传、改名或删除。
- 优化安卓目录读取，增加有容量和时效限制的缓存、列表控件复用及快速导航请求取消，保留文件夹优先和自然名称排序。
- 修复 NAS 批量重命名预览的同步元数据查询；预览使用已有目录清单，执行走同目录系统改名兼容路径，保留文件夹、同名保护和撤销支持。
- NAS 右键新增“移入 NAS 回收站”，支持撤销、重做及原位置记录。本机已适配共享中的 `trashbox`；未找到可用的现有回收站或没有权限时停止，不退回永久删除。不同品牌 NAS 的回收站权限与管理界面可能不同。

## 下载与安装

从本仓库 Release 下载 DMG，将 Mac Explorer Daily.app 拖入应用程序。更新前退出旧版。支持 Apple Silicon 和 macOS 13+，使用 ad-hoc 签名，未经 Apple 公证。

感谢 [上游作者 qixiaoyu27](https://github.com/qixiaoyu27) 及 [上游贡献者](https://github.com/qixiaoyu27/Mac-Explorer/graphs/contributors)；个人功能与集成由 [XIANG-z25](https://github.com/XIANG-z25) 维护。
