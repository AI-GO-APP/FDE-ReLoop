# FDE-ReLoop

退場設備回收媒合平台。盤商後台（`dealer_portal.html`）、回收商前台（`recycler_onboarding_v2.html`，含 LINE 登入/綁定）。後端 Supabase。

## 開發備註

### 安全（上線前必做）
目前盤商後台的權限與資料隔離**多為前端控管**（隱藏按鈕、函式內 `hasPermission` 檢查、清單依 `view_all_cases` 前端過濾）。前端能擋誤觸與一般使用，但無法擋「開瀏覽器 console 直接打 Supabase API」。

**正式上線前，須把相同規則同步寫入後端 RLS / RPC / trigger**，避免使用者繞過前端直接讀改資料。重點：
- 寫入權限（底價、核定、付款確認、設定…）以 `current_dealer_has_permission()` 寫進各表 RLS。
- 資料隔離（業務只能看自己案件/設備/客戶）以 RLS 用 `assigned_agent_id` 過濾，不能只靠前端。

### Migration
- 正式 migration 放 `supabase/migrations/`；**回滾腳本放 `supabase/rollback/`**（不可放 migrations，否則 CLI 會當正式 migration 套用）。
- migration 目前以 Supabase SQL Editor 手動套用（不一定在 migration 追蹤表內）。

### 測試
- `npm test`（零相依，純 Node）：冒煙（語法/DOM/事件接線/migration↔回滾/回收商檔不得引用底價欄位/無重複 id）、單元、整合。

### 待辦
- 業務專用前台（讓業務不進後台即可登錄設備）— 尚未開發。
- RLS 安全底線、E2E（Playwright + staging）。
