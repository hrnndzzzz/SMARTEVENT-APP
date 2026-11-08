-- Receipt photos are deleted from storage 30 days after upload, and this marks which ones.
ALTER TABLE public.receipts ADD COLUMN IF NOT EXISTS file_deleted_at timestamptz;

-- Deleting an inventory item that has history archives it instead.
ALTER TABLE public.inventory ADD COLUMN IF NOT EXISTS is_archived boolean NOT NULL DEFAULT false;
