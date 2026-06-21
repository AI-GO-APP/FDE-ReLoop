-- ============================================================================
-- ROLLBACK for 202606200002_line_templates_rls.sql
-- 還原 dealer_system_settings 的 INSERT/UPDATE policy 為 migration 0002 的三子句版本
-- （移除 line_templates 的寫入允許）。不可放 supabase/migrations/。
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
  )
  WITH CHECK (
    public.current_dealer_role() = 'admin'
    OR (key = 'workflow_parameters' AND public.current_dealer_has_permission('manage_workflow_parameters'))
    OR (key = 'permission_groups' AND public.current_dealer_has_permission('manage_permission_groups'))
  );
