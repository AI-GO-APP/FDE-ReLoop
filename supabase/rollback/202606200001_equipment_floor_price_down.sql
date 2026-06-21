-- ============================================================================
-- ROLLBACK for 202606200001_equipment_floor_price.sql
-- 回滾後狀態：移除 equipment_listings 的底價相關欄位與約束。
--
-- ⚠️ 資料遺失警告：會刪除所有設備的 floor_price 及審核狀態。執行前若需保留請先備份。
-- 不要放在 supabase/migrations/ 內（會被 CLI 當成正式 migration 套用）。
-- ============================================================================

DROP INDEX IF EXISTS public.idx_equipment_listings_floor_price_status;

ALTER TABLE public.equipment_listings
  DROP CONSTRAINT IF EXISTS equipment_listings_floor_price_status_check;

ALTER TABLE public.equipment_listings
  DROP COLUMN IF EXISTS floor_price,
  DROP COLUMN IF EXISTS floor_price_status,
  DROP COLUMN IF EXISTS floor_price_by,
  DROP COLUMN IF EXISTS floor_price_approved_by,
  DROP COLUMN IF EXISTS floor_price_updated_at;
