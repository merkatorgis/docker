create or replace function web.save_password
    ( in_email    text
    , in_password text
    )
returns void
language plpgsql
as $$
declare
begin
    update web.user
        set pass = crypt(in_password, gen_salt('bf'))
        , exp = web.fn_jwt_now() - 1 -- -1 to ensure before iat new token
        where email = in_email
        and   email = current_setting('request.jwt.claim.email')
    ;
    if not found
    then
        raise exception 'user not found';
    end if
    ;
end;
$$;
