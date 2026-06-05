# FDE-ReLoop 專案指引

## 工作習慣
- 每次改完程式碼，都要 commit 並 push（除非使用者明確說先不要）
- 改完 `recycler_onboarding.html` 後，同步一份到 `C:\Users\apin2\Downloads\秧秧空間設計有限公司\recycler_onboarding.html`
- 不要動到已經正常運作的功能
- 每次有新的技術決策、畫面異動、架構調整，順手更新本檔案對應區塊（工作習慣、專案架構、技術決策記錄、主要畫面對應）

## 專案架構
- 單一 HTML 檔案 (`recycler_onboarding.html`)，前端邏輯全在這裡
- Docker + Nginx 部署，`docker-entrypoint.sh` 在容器啟動時注入 Supabase 環境變數
- Supabase 作為後端（Auth + DB），前端用 anon key 直連

## 技術決策記錄
- **Auth**：Supabase Auth 用 email 識別，實際以 `{統編}_{電話}@reloop.internal` 組成假 email，使用者看不到
- **合約簽名**：base64 PNG 存入 `contracts` 表，搭配 `contract_templates` 範本表
- **service_areas / service_exclusions**：帳號層級 `text[]`，存在 `recycler_onboarding_accounts`，MVP 夠用，未來可獨立成 `recycler_service_areas` 表
- **URL routing**：目前單頁靠 `goScreen()` 切換，hash routing 等所有畫面功能完成後再加
- **MVP → 目標系統**：MVP 跑通後再做 schema mapping，不提前拆表

## 主要畫面對應
| screen id | 說明 |
|---|---|
| screen-register | 新用戶預設首頁，含合作協議書簽署 |
| screen-login | 統編查詢 → 帳號選擇 → 密碼登入 |
| screen-profile | 基本資料（統編唯讀）|
| screen-prefs | 收貨偏好 + 收貨範圍 |
| screen-matches | 媒合列表 |
| screen-done | 註冊完成摘要 |
