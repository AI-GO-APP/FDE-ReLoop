-- ============================================================================
-- ROLLBACK for 202606190002_dealer_permission_groups.sql
-- 回滾後狀態：回到「只跑過 0001」的狀態（dealer_system_settings 仍在，
-- 但權限組機制移除、dealer_system_settings 的 RLS 還原為 0001 的 manager/admin 版本）。
--
-- ⚠️ 資料遺失警告：
--   - 會刪除 dealer_account_permission_groups 整張表（所有員工的權限組指派會消失）
--   - 會刪除 dealer_system_settings 中 key = 'permission_groups' 這一列
--   執行前若需保留，請先備份這兩處資料。
--
-- 不要放在 supabase/migrations/ 內（會被 CLI 當成正式 migration 套用）。
-- 手動執行：在 Supabase SQL Editor 貼上整段，或用 psql 連線執行。
-- ============================================================================

-- 1) 移除 0002 在 dealer_account_permission_groups 上建立的 RLS 政策
DROP POLICY IF EXISTS "dealer_account_permission_groups_select" ON public.dealer_account_permission_groups;
DROP POLICY IF EXISTS "dealer_account_permission_groups_insert" ON public.dealer_account_permission_groups;
DROP POLICY IF EXISTS "dealer_account_permission_groups_delete" ON public.dealer_account_permission_groups;

-- 2) 移除權限檢查函式
DROP FUNCTION IF EXISTS public.current_dealer_has_permission(text);

-- 3) 還原 dealer_system_settings 的 RLS 政策為 0001 版本（manager/admin）
DROP POLICY IF EXISTS "dealer_settings_select_approved_dealers" ON public.dealer_system_settings;
DROP POLICY IF EXISTS "dealer_settings_insert_by_permission" ON public.dealer_system_settings;
DROP POLICY IF EXISTS "dealer_settings_update_by_permission" ON public.dealer_system_settings;

DROP POLICY IF EXISTS "dealer_settings_select_manager_admin" ON public.dealer_system_settings;
CREATE POLICY "dealer_settings_select_manager_admin"
  ON public.dealer_system_settings
  FOR SELECT
  TO authenticated
  USING (public.current_dealer_role() IN ('manager', 'admin'));

DROP POLICY IF EXISTS "dealer_settings_insert_manager_admin" ON public.dealer_system_settings;
CREATE POLICY "dealer_settings_insert_manager_admin"
  ON public.dealer_system_settings
  FOR INSERT
  TO authenticated
  WITH CHECK (
    public.current_dealer_role() = 'admin'
    OR (public.current_dealer_role() = 'manager' AND key = 'workflow_parameters')
  );

DROP POLICY IF EXISTS "dealer_settings_update_manager_admin" ON public.dealer_system_settings;
CREATE POLICY "dealer_settings_update_manager_admin"
  ON public.dealer_system_settings
  FOR UPDATE
  TO authenticated
  USING (
    public.current_dealer_role() = 'admin'
    OR (public.current_dealer_role() = 'manager' AND key = 'workflow_parameters')
  )
  WITH CHECK (
    public.current_dealer_role() = 'admin'
    OR (public.current_dealer_role() = 'manager' AND key = 'workflow_parameters')
  );

-- 4) 刪除 0002 寫入的 permission_groups 設定列
DELETE FROM public.dealer_system_settings WHERE key = 'permission_groups';

-- 5) 移除權限組指派表（含所有指派資料）
DROP TABLE IF EXISTS public.dealer_account_permission_groups;
