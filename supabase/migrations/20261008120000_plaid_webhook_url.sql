-- Which webhook URL each bank connection reports to.
--
-- Null for every item linked before plaid-webhook existed. plaid-sync points
-- those at the webhook on their next sync and writes the URL here, so the
-- move happens once per item and a changed URL is picked up the same way.
alter table public.plaid_items add column webhook_url text;
