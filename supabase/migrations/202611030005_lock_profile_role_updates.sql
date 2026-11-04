-- Prevent users from changing their own authorization role.
-- The application only edits contact fields from the client profile.
revoke update on table public.profiles from authenticated;
grant update (full_name, phone) on table public.profiles to authenticated;
