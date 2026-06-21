-- ============================================================================
-- 每台設備底價（floor price）+ 主管填寫 / admin 審核機制
--
-- 設計：
--   floor_price            每台設備底價金額（內部用，回收商看不到）
--   floor_price_status     none=未設定 / pending=主管已填待 admin 審核 / approved=已生效
--   floor_price_by         最後填寫者（dealer_accounts.id）
--   floor_price_approved_by 審核者（dealer_accounts.id）
--   floor_price_updated_at 最後異動時間
--
-- 權限（前端 hasPermission 控管；admin 一律 bypass）：
--   set_floor_price     主管/admin 可填底價（既有 key）
--   approve_floor_price 審核底價（預設只有 admin）
--   view_case_financials 查看案件成本/毛利彙總（預設只有 admin）
--   ※ 新權限 key 無需在此寫死進 permission_groups：前端缺漏視為 false、admin bypass；
--     admin 於「權限與參數」儲存後即會把新 key 寫回各權限組（預設 false）。
--
-- 安全：回收商前台只查 recycler_matches（select '*'，不帶 equipment_listings），
--       故 floor_price 不會外洩；此處不另加 column-level 限制。
-- ============================================================================

ALTER TABLE public.equipment_listings
  ADD COLUMN IF NOT EXISTS floor_price            numeric,
  ADD COLUMN IF NOT EXISTS floor_price_status     text NOT NULL DEFAULT 'none',
  ADD COLUMN IF NOT EXISTS floor_price_by         uuid REFERENCES public.dealer_accounts(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS floor_price_approved_by uuid REFERENCES public.dealer_accounts(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS floor_price_updated_at timestamptz;

-- 限制狀態值
ALTER TABLE public.equipment_listings
  DROP CONSTRAINT IF EXISTS equipment_listings_floor_price_status_check;
ALTER TABLE public.equipment_listings
  ADD CONSTRAINT equipment_listings_floor_price_status_check
  CHECK (floor_price_status IN ('none', 'pending', 'approved'));

-- 查待審核設備用
CREATE INDEX IF NOT EXISTS idx_equipment_listings_floor_price_status
  ON public.equipment_listings(floor_price_status)
  WHERE floor_price_status = 'pending';
