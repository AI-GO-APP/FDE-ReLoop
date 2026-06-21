-- ============================================================================
-- 讓「非 admin、但具 manage_line_templates 權限」的人能寫入 line_templates 設定。
--
-- 背景：dealer_system_settings 的 INSERT/UPDATE RLS（migration 0002）原本只允許
--   admin、或 key=workflow_parameters(需 manage_workflow_parameters)、
--   key=permission_groups(需 manage_permission_groups)。
--   新增的 key='line_templates' 未涵蓋 → 非 admin 會被 RLS 擋下。
-- 本 migration 在兩條 policy 各加一個 OR 子句涵蓋 line_templates。
--   (admin 仍可寫；SELECT 不變：所有已核可盤商皆可讀)
-- ============================================================================

DROP POLICY IF EXISTS "dealer_settings_insert_by_permission" ON public.dealer_system_settings;
CREATE POLICY "dealer_settings_insert_by_permission"
  ON public.dealer_system_settings
  FOR INSERT
  TO authenticated
  WITH CHECK (
    public.current_dealer_role() = 'admin'
    OR (key = 'workflow_parameters' AND public.current_dealer_has_permission('manage_workflow_parameters'))
    OR (key = 'permission_groups' AND public.current_dealer_has_permission('manage_permission_groups'))
    OR (key = 'line_templates' AND public.current_dealer_has_permission('manage_line_templates'))
  );

DROP POLICY IF EXISTS "dealer_settings_update_by_permission" ON public.dealer_system_settings;
CREATE POLICY "dealer_settings_update_by_permission"
  ON public.dealer_system_settings
  FOR UPDATE
  TO authenticated
  USING (
    public.current_dealer_role() = 'admin'
    OR (key = 'workflow_parameters' AND public.current_dealer_has_permission('manage_workflow_parameters'))
    OR (key = 'permission_groups' AND public.current_dealer_has_permission('manage_permission_groups'))
    OR (key = 'line_templates' AND public.current_dealer_has_permission('manage_line_templates'))
  )
  WITH CHECK (
    public.current_dealer_role() = 'admin'
    OR (key = 'workflow_parameters' AND public.current_dealer_has_permission('manage_workflow_parameters'))
    OR (key = 'permission_groups' AND public.current_dealer_has_permission('manage_permission_groups'))
    OR (key = 'line_templates' AND public.current_dealer_has_permission('manage_line_templates'))
  );
