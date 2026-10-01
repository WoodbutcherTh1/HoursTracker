-- The earlier migration revoked EXECUTE from PUBLIC only; Supabase also grants
-- it to anon/authenticated by default, so anyone holding the publishable key
-- could call /rest/v1/rpc/check_feedback_rate_limit and burn other IPs' quota.
-- Only the submit-feedback Edge Function (service role) should call it.
revoke all on function public.check_feedback_rate_limit(inet, int, int) from public, anon, authenticated;
grant execute on function public.check_feedback_rate_limit(inet, int, int) to service_role;
