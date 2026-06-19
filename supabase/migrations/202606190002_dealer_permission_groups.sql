-- Decouple dealer identity roles from operational permissions.
-- Admin keeps implicit full access; non-admin users receive permissions through groups.

CREATE TABLE IF NOT EXISTS public.dealer_account_permission_groups (
  account_id uuid NOT NULL REFERENCES public.dealer_accounts(id) ON DELETE CASCADE,
  group_key text NOT NULL,
  assigned_by uuid REFERENCES public.dealer_accounts(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (account_id, group_key)
);

CREATE INDEX IF NOT EXISTS idx_dealer_account_permission_groups_group_key
  ON public.dealer_account_permission_groups(group_key);

ALTER TABLE public.dealer_account_permission_groups ENABLE ROW LEVEL SECURITY;

INSERT INTO public.dealer_system_settings (key, value, description)
VALUES (
  'permission_groups',
  '[
    {
      "id": "sales",
      "name": "業務組",
      "description": "案件、媒合通知與建議得標",
      "permissions": {
        "view_all_cases": false,
        "set_floor_price": false,
        "confirm_recommendations": true,
        "propose_winner": true,
        "approve_winner": false,
        "confirm_payment": false,
        "schedule_delivery": true,
        "complete_delivery": true,
        "close_case": false,
        "manage_recyclers": false,
        "manage_staff": false,
        "manage_workflow_parameters": false,
        "manage_permission_groups": false
      }
    },
    {
      "id": "supervisor",
      "name": "主管組",
      "description": "底價、得標核定與流程參數",
      "permissions": {
        "view_all_cases": true,
        "set_floor_price": true,
        "confirm_recommendations": true,
        "propose_winner": true,
        "approve_winner": true,
        "confirm_payment": false,
        "schedule_delivery": true,
        "complete_delivery": false,
        "close_case": true,
        "manage_recyclers": false,
        "manage_staff": false,
        "manage_workflow_parameters": true,
        "manage_permission_groups": false
      }
    },
    {
      "id": "finance",
      "name": "財務組",
      "description": "付款確認與款項退回",
      "permissions": {
        "view_all_cases": false,
        "set_floor_price": false,
        "confirm_recommendations": false,
        "propose_winner": false,
        "approve_winner": false,
        "confirm_payment": true,
        "schedule_delivery": false,
        "complete_delivery": false,
        "close_case": false,
        "manage_recyclers": false,
        "manage_staff": false,
        "manage_workflow_parameters": false,
        "manage_permission_groups": false
      }
    },
    {
      "id": "delivery",
      "name": "交付組",
      "description": "拉貨排程、交付簽署與交付照片",
      "permissions": {
        "view_all_cases": false,
        "set_floor_price": false,
        "confirm_recommendations": false,
        "propose_winner": false,
        "approve_winner": false,
        "confirm_payment": false,
        "schedule_delivery": true,
        "complete_delivery": true,
        "close_case": false,
        "manage_recyclers": false,
        "manage_staff": false,
        "manage_workflow_parameters": false,
        "manage_permission_groups": false
      }
    },
    {
      "id": "operations",
      "name": "營運管理組",
      "description": "回收商管理與流程參數",
      "permissions": {
        "view_all_cases": true,
        "set_floor_price": false,
        "confirm_recommendations": false,
        "propose_winner": false,
        "approve_winner": false,
        "confirm_payment": false,
        "schedule_delivery": false,
        "complete_delivery": false,
        "close_case": false,
        "manage_recyclers": true,
        "manage_staff": false,
        "manage_workflow_parameters": true,
        "manage_permission_groups": false
      }
    }
  ]'::jsonb,
  'Permission groups used to grant dealer backend capabilities to non-admin accounts.'
)
ON CONFLICT (key) DO NOTHING;

INSERT INTO public.dealer_account_permission_groups (account_id, group_key)
SELECT id, group_key
FROM public.dealer_accounts
CROSS JOIN LATERAL (
  VALUES
    ('sales'),
    ('finance'),
    ('delivery')
) AS agent_groups(group_key)
WHERE role = 'agent'
  AND status = 'approved'
ON CONFLICT (account_id, group_key) DO NOTHING;

INSERT INTO public.dealer_account_permission_groups (account_id, group_key)
SELECT id, group_key
FROM public.dealer_accounts
CROSS JOIN LATERAL (
  VALUES
    ('supervisor'),
    ('finance'),
    ('delivery'),
    ('operations')
) AS manager_groups(group_key)
WHERE role = 'manager'
  AND status = 'approved'
ON CONFLICT (account_id, group_key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.current_dealer_has_permission(permission_key text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
DECLARE
  dealer_role text;
BEGIN
  SELECT role
  INTO dealer_role
  FROM public.dealer_accounts
  WHERE id = auth.uid()
    AND status = 'approved'
  LIMIT 1;

  IF dealer_role IS NULL THEN
    RETURN false;
  END IF;

  IF dealer_role = 'admin' THEN
    RETURN true;
  END IF;

  RETURN EXISTS (
    SELECT 1
    FROM public.dealer_account_permission_groups account_group
    JOIN public.dealer_system_settings setting
      ON setting.key = 'permission_groups'
    CROSS JOIN LATERAL jsonb_array_elements(
      CASE
        WHEN jsonb_typeof(setting.value) = 'array' THEN setting.value
        ELSE '[]'::jsonb
      END
    ) AS permission_group(value)
    WHERE account_group.account_id = auth.uid()
      AND permission_group.value->>'id' = account_group.group_key
      AND permission_group.value->'permissions'->>permission_key = 'true'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.current_dealer_has_permission(text) TO authenticated;

DROP POLICY IF EXISTS "dealer_settings_select_manager_admin" ON public.dealer_system_settings;
DROP POLICY IF EXISTS "dealer_settings_select_approved_dealers" ON public.dealer_system_settings;
CREATE POLICY "dealer_settings_select_approved_dealers"
  ON public.dealer_system_settings
  FOR SELECT
  TO authenticated
  USING (public.current_dealer_role() IS NOT NULL);

DROP POLICY IF EXISTS "dealer_settings_insert_manager_admin" ON public.dealer_system_settings;
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

DROP POLICY IF EXISTS "dealer_settings_update_manager_admin" ON public.dealer_system_settings;
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

DROP POLICY IF EXISTS "dealer_account_permission_groups_select" ON public.dealer_account_permission_groups;
CREATE POLICY "dealer_account_permission_groups_select"
  ON public.dealer_account_permission_groups
  FOR SELECT
  TO authenticated
  USING (
    account_id = auth.uid()
    OR public.current_dealer_has_permission('manage_staff')
    OR public.current_dealer_has_permission('manage_permission_groups')
  );

DROP POLICY IF EXISTS "dealer_account_permission_groups_insert" ON public.dealer_account_permission_groups;
CREATE POLICY "dealer_account_permission_groups_insert"
  ON public.dealer_account_permission_groups
  FOR INSERT
  TO authenticated
  WITH CHECK (
    public.current_dealer_has_permission('manage_staff')
    OR public.current_dealer_has_permission('manage_permission_groups')
  );

DROP POLICY IF EXISTS "dealer_account_permission_groups_delete" ON public.dealer_account_permission_groups;
CREATE POLICY "dealer_account_permission_groups_delete"
  ON public.dealer_account_permission_groups
  FOR DELETE
  TO authenticated
  USING (
    public.current_dealer_has_permission('manage_staff')
    OR public.current_dealer_has_permission('manage_permission_groups')
  );

GRANT SELECT, INSERT, DELETE ON public.dealer_account_permission_groups TO authenticated;
