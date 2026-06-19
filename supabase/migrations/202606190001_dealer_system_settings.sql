-- Dealer backend system settings for permissions and workflow parameters.
-- This migration creates a small key/value settings table used by dealer_portal.html.

ALTER TABLE public.recycler_matches
  ADD COLUMN IF NOT EXISTS payment_deadline_at timestamptz;

CREATE INDEX IF NOT EXISTS idx_recycler_matches_payment_deadline_at
  ON public.recycler_matches(payment_deadline_at)
  WHERE payment_deadline_at IS NOT NULL;

CREATE OR REPLACE FUNCTION public.current_dealer_role()
RETURNS text
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT role
  FROM public.dealer_accounts
  WHERE id = auth.uid()
    AND status = 'approved'
  LIMIT 1
$$;

GRANT EXECUTE ON FUNCTION public.current_dealer_role() TO authenticated;

CREATE TABLE IF NOT EXISTS public.dealer_system_settings (
  key text PRIMARY KEY,
  value jsonb NOT NULL DEFAULT '{}'::jsonb,
  description text,
  updated_by uuid REFERENCES public.dealer_accounts(id) ON DELETE SET NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.dealer_system_settings ENABLE ROW LEVEL SECURITY;

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

GRANT SELECT, INSERT, UPDATE ON public.dealer_system_settings TO authenticated;

CREATE OR REPLACE FUNCTION public.touch_dealer_system_settings_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_touch_dealer_system_settings_updated_at ON public.dealer_system_settings;
CREATE TRIGGER trg_touch_dealer_system_settings_updated_at
  BEFORE UPDATE ON public.dealer_system_settings
  FOR EACH ROW
  EXECUTE FUNCTION public.touch_dealer_system_settings_updated_at();

INSERT INTO public.dealer_system_settings (key, value, description)
VALUES
  (
    'workflow_parameters',
    '{
      "bid_deadline_hours": 24,
      "payment_deadline_hours": 48,
      "default_invite_expiry_days": 3,
      "payment_last5_length": 5,
      "min_bid_ratio": 1,
      "enforce_min_bid": true,
      "delivery_requires_photos": true,
      "close_requires_payment": true
    }'::jsonb,
    'Dealer workflow parameters for bidding, invites, payment, and delivery.'
  ),
  (
    'role_permissions',
    '{
      "agent": {
        "view_all_cases": false,
        "set_floor_price": false,
        "confirm_recommendations": true,
        "propose_winner": true,
        "approve_winner": false,
        "confirm_payment": true,
        "schedule_delivery": true,
        "complete_delivery": true,
        "close_case": false,
        "manage_recyclers": false,
        "manage_staff": false
      },
      "manager": {
        "view_all_cases": true,
        "set_floor_price": true,
        "confirm_recommendations": true,
        "propose_winner": true,
        "approve_winner": true,
        "confirm_payment": true,
        "schedule_delivery": true,
        "complete_delivery": true,
        "close_case": true,
        "manage_recyclers": true,
        "manage_staff": false
      },
      "admin": {
        "view_all_cases": true,
        "set_floor_price": true,
        "confirm_recommendations": true,
        "propose_winner": true,
        "approve_winner": true,
        "confirm_payment": true,
        "schedule_delivery": true,
        "complete_delivery": true,
        "close_case": true,
        "manage_recyclers": true,
        "manage_staff": true
      }
    }'::jsonb,
    'Dealer role permissions consumed by the backend UI and future RPC/RLS rules.'
  )
ON CONFLICT (key) DO NOTHING;

UPDATE public.recycler_matches
SET payment_deadline_at = accepted_at + make_interval(hours => COALESCE((
  SELECT CASE
    WHEN value->>'payment_deadline_hours' ~ '^\d+$'
      THEN (value->>'payment_deadline_hours')::integer
    ELSE NULL
  END
  FROM public.dealer_system_settings
  WHERE key = 'workflow_parameters'
), 48))
WHERE status = 'accepted'
  AND accepted_at IS NOT NULL
  AND payment_deadline_at IS NULL;

CREATE OR REPLACE FUNCTION public.apply_recycler_match_payment_deadline()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  deadline_hours integer := 48;
BEGIN
  SELECT COALESCE(
    CASE
      WHEN value->>'payment_deadline_hours' ~ '^\d+$'
        THEN (value->>'payment_deadline_hours')::integer
      ELSE NULL
    END,
    48
  )
  INTO deadline_hours
  FROM public.dealer_system_settings
  WHERE key = 'workflow_parameters';

  deadline_hours := GREATEST(1, LEAST(COALESCE(deadline_hours, 48), 336));

  IF NEW.status = 'accepted' THEN
    IF NEW.accepted_at IS NULL THEN
      NEW.accepted_at = now();
    END IF;

    IF NEW.payment_deadline_at IS NULL THEN
      NEW.payment_deadline_at = NEW.accepted_at + make_interval(hours => deadline_hours);
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_apply_recycler_match_payment_deadline ON public.recycler_matches;
CREATE TRIGGER trg_apply_recycler_match_payment_deadline
  BEFORE INSERT OR UPDATE OF status, accepted_at, payment_deadline_at ON public.recycler_matches
  FOR EACH ROW
  EXECUTE FUNCTION public.apply_recycler_match_payment_deadline();

CREATE OR REPLACE FUNCTION public.prevent_late_payment_submission()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.payment_last5 IS NOT NULL
    AND NEW.payment_last5 IS DISTINCT FROM OLD.payment_last5
    AND NEW.status = 'accepted'
    AND NEW.payment_deadline_at IS NOT NULL
    AND now() > NEW.payment_deadline_at THEN
    RAISE EXCEPTION 'payment deadline has passed';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_late_payment_submission ON public.recycler_matches;
CREATE TRIGGER trg_prevent_late_payment_submission
  BEFORE UPDATE OF payment_last5 ON public.recycler_matches
  FOR EACH ROW
  EXECUTE FUNCTION public.prevent_late_payment_submission();
