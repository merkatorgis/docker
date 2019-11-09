create or replace function logout()
returns void
language sql
security definer
as $$
    -- This will invalidate all user's tokens everywhere.
    -- To only logout locally on the client, just ditch that token there.
    select web.logout(current_user);
$$;

grant execute on function logout()
to web_user
;