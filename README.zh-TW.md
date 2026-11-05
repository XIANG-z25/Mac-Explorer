# Mac Explorer Daily

[简体中文](README.md) · 繁體中文 · [English](README.en.md)

用熟悉的 Windows 11 檔案總管操作，在 Mac 上整理檔案。採用原生 Swift / AppKit 開發。

[下載 1.7.0 DMG](https://github.com/XIANG-z25/Mac-Explorer/releases/download/v1.7.0/Mac-Explorer-Daily-1.7.0-mac-arm64.dmg) · [版本說明](https://github.com/XIANG-z25/Mac-Explorer/releases/tag/v1.7.0)

## 1.7.0 更新

- 在分頁按右鍵即可複製分頁，新分頁會在右側開啟相同資料夾並保留選取項目。
- 按住 `⌘` 點選網址列路徑中的資料夾，或透過右鍵選單，即可在新分頁開啟。切回原分頁可繼續瀏覽。
- 在詳細資料檢視中，可從列內文字旁的空白拖曳框選多個項目。
- 切換圖示大小後立即重新排列群組。將滑鼠停在圖示上，指標旁會顯示完整名稱。

日常版也支援資料夾優先排序、依修改日期分組、批次重新命名檔案和資料夾、字型大小與啟動位置設定，以及啟動時自動重新連線 SMB。已連線的 OneDrive 和 Box 資料夾可從側邊欄瀏覽，同步與離線保留由各自的用戶端管理。

## 安裝

需要 Apple Silicon（M 系列）及 macOS 13 或以上。更新前先結束舊版，打開 DMG，將 **Mac Explorer Daily.app** 拖入「應用程式」。安裝包採用臨時簽署，未經 Apple 公證。請從[此儲存庫的 Releases](https://github.com/XIANG-z25/Mac-Explorer/releases/latest) 手動更新，該頁亦提供 SHA-256 校驗檔。

本版本以 [qixiaoyu27/Mac-Explorer](https://github.com/qixiaoyu27/Mac-Explorer) 為基礎，沿用 [GPL-3.0 授權](LICENSE)。如需從原始碼建置，請參閱[原生版開發文件](native/README.md)，並在儲存庫根目錄執行 `python3 -I native/scripts/build.py --personal`。
