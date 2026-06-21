-- ============================================================================
-- ROLLBACK for 202606190001_dealer_system_settings.sql
-- 回滾後狀態：完全移除 0001 建立的所有物件，回到「未跑任何本批 migration」的狀態。
--
-- ⚠️ 執行順序：必須先跑 202606190002_..._down.sql，再跑本檔。
--    （0002 依賴 0001 的 dealer_system_settings 與 current_dealer_role()）
--
-- ⚠️ 資料遺失警告：
--   - 會刪除 dealer_system_settings 整張表（workflow_parameters、role_permissions 等設定會消失）
--   - 會移除 recycler_matches.payment_deadline_at 欄位（已寫入的付款期限會消失）
--   執行前若需保留，請先備份。
--
-- 不要放在 supabase/migrations/ 內（會被 CLI 當成正式 migration 套用）。
-- ============================================================================

-- 1) 移除付款期限相關 trigger 與函式
DROP TRIGGER IF EXISTS trg_prevent_late_payment_submission ON public.recycler_matches;
DROP FUNCTION IF EXISTS public.prevent_late_payment_submission();

DROP TRIGGER IF EXISTS trg_apply_recycler_match_payment_deadline ON public.recycler_matches;
DROP FUNCTION IF EXISTS public.apply_recycler_match_payment_deadline();

-- 2) 移除 dealer_system_settings 的 updated_at trigger 與函式
DROP TRIGGER IF EXISTS trg_touch_dealer_system_settings_updated_at ON public.dealer_system_settings;
DROP FUNCTION IF EXISTS public.touch_dealer_system_settings_updated_at();

-- 3) 移除 dealer_system_settings 的 RLS 政策（0001 版；若已被 0002 取代，DROP IF EXISTS 仍安全）
DROP POLICY IF EXISTS "dealer_settings_select_manager_admin" ON public.dealer_system_settings;
DROP POLICY IF EXISTS "dealer_settings_insert_manager_admin" ON public.dealer_system_settings;
DROP POLICY IF EXISTS "dealer_settings_update_manager_admin" ON public.dealer_system_settings;

-- 4) 移除設定表
DROP TABLE IF EXISTS public.dealer_system_settings;

-- 5) 移除角色查詢函式
DROP FUNCTION IF EXISTS public.current_dealer_role();

-- 6) 還原 recycler_matches：移除付款期限欄位與索引
DROP INDEX IF EXISTS public.idx_recycler_matches_payment_deadline_at;
ALTER TABLE public.recycler_matches
  DROP COLUMN IF EXISTS payment_deadline_at;
