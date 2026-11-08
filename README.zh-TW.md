# Mac Explorer Daily

[简体中文](README.md) · 繁體中文 · [English](README.en.md)

用熟悉的 Windows 11 檔案總管操作，在 Mac 上整理檔案。採用原生 Swift / AppKit 開發。

[下載 1.7.8 DMG](https://github.com/XIANG-z25/Mac-Explorer/releases/download/v1.7.8/Mac-Explorer-Daily-1.7.8-mac-arm64.dmg) · [版本說明](https://github.com/XIANG-z25/Mac-Explorer/releases/tag/v1.7.8)

## Daily 1.7.8（組建 2）與上游 1.7.1 的差異

`zx/daily-native` 分支已合併[上游 1.7.1](https://github.com/qixiaoyu27/Mac-Explorer/commit/68a4677df9f6ba7b54e947577ded3ebd932e9357)。Daily 使用獨立的應用程式識別碼，保留先前 Daily 的偏好設定。**1.7.8 提供可直接安裝的 DMG，也可從原始碼建置。**

- 掛載後的外接磁碟（含 Mounty）會顯示在側邊欄「此電腦」，可按右鍵安全退出。唯讀掛載會顯示提示，NTFS 寫入由已安裝的驅動程式提供。
- 磁碟卷支援時直接移動檔案，Mounty NTFS 上的一般檔案也可無須複製內容即可移動，並保護目的地的同名檔案。複製和移動集中在同一視窗，可分別查看進度、速度或取消。
- 支援複製分頁、從位址列在新分頁開啟資料夾、在詳細資料列的留白處拖曳框選、切換圖示檢視時立即重新分組，以及在指標旁顯示完整檔名。
- 修正未輸入關鍵字時的篩選，以及清除最後一個篩選條件後返回資料夾清單的行為。側邊欄會合併指向相同位置的雲端硬碟入口。同步與離線保留由各自的用戶端管理。
- 大量選取時減少重複的磁碟卷檢查。詳細資料面板會重複使用文字預覽，減少切換檔案時的排版配置。

在儲存庫根目錄執行 `python3 -I native/scripts/build.py --personal`，再將 `native/output/personal/Mac Explorer Daily.app` 拖入「應用程式」。詳見[原生版開發文件](native/README.md#构建和打开)。

## 1.7.0 已發行功能

- 在分頁按右鍵即可複製分頁，新分頁會在右側開啟相同資料夾並保留選取項目。
- 按住 `⌘` 點選網址列路徑中的資料夾，或透過右鍵選單，即可在新分頁開啟。切回原分頁可繼續瀏覽。
- 在詳細資料檢視中，可從列內文字旁的空白拖曳框選多個項目。
- 切換圖示大小後立即重新排列群組。將滑鼠停在圖示上，指標旁會顯示完整名稱。

日常版也支援資料夾優先排序、依修改日期分組、批次重新命名檔案和資料夾、字型大小與啟動位置設定，以及啟動時自動重新連線 SMB。已連線的 OneDrive 和 Box 資料夾可從側邊欄瀏覽，同步與離線保留由各自的用戶端管理。

## 安裝

需要 Apple Silicon（M 系列）及 macOS 13 或以上。更新前先結束舊版，打開 DMG，將 **Mac Explorer Daily.app** 拖入「應用程式」。安裝包採用臨時簽署，未經 Apple 公證。請從[此儲存庫的 Releases](https://github.com/XIANG-z25/Mac-Explorer/releases/latest) 手動更新，該頁亦提供 SHA-256 校驗檔。

本版本以 [qixiaoyu27/Mac-Explorer](https://github.com/qixiaoyu27/Mac-Explorer) 為基礎，沿用 [GPL-3.0 授權](LICENSE)。如需從原始碼建置，請參閱[原生版開發文件](native/README.md)，並在儲存庫根目錄執行 `python3 -I native/scripts/build.py --personal`。
