begin;

-- CREATE OR REPLACE preserves old explicit grants. Some legacy projects gave
-- anon direct EXECUTE access before the response-state migration narrowed the
-- public contract, so revoke every client role before restoring intended ACLs.
revoke all on function public.accept_omok_push_invite(uuid)
  from public, anon, authenticated;
revoke all on function public.reject_omok_push_invite(uuid)
  from public, anon, authenticated;
revoke all on function public.expire_omok_invite_if_needed(uuid)
  from public, anon, authenticated;
revoke all on function public.expire_open_omok_invites()
  from public, anon, authenticated;

grant execute on function public.accept_omok_push_invite(uuid)
  to authenticated;
grant execute on function public.reject_omok_push_invite(uuid)
  to authenticated;
grant execute on function public.expire_omok_invite_if_needed(uuid)
  to authenticated;

do $$
begin
  if not has_function_privilege(
    'authenticated',
    'public.accept_omok_push_invite(uuid)',
    'execute'
  ) or has_function_privilege(
    'anon',
    'public.accept_omok_push_invite(uuid)',
    'execute'
  ) then
    raise exception 'Omok accept RPC has an unexpected ACL';
  end if;

  if not has_function_privilege(
    'authenticated',
    'public.reject_omok_push_invite(uuid)',
    'execute'
  ) or has_function_privilege(
    'anon',
    'public.reject_omok_push_invite(uuid)',
    'execute'
  ) then
    raise exception 'Omok reject RPC has an unexpected ACL';
  end if;

  if not has_function_privilege(
    'authenticated',
    'public.expire_omok_invite_if_needed(uuid)',
    'execute'
  ) or has_function_privilege(
    'anon',
    'public.expire_omok_invite_if_needed(uuid)',
    'execute'
  ) then
    raise exception 'Omok invite expiry RPC has an unexpected ACL';
  end if;

  if has_function_privilege(
    'authenticated',
    'public.expire_open_omok_invites()',
    'execute'
  ) or has_function_privilege(
    'anon',
    'public.expire_open_omok_invites()',
    'execute'
  ) then
    raise exception 'Omok expiry worker RPC has an unexpected ACL';
  end if;
end;
$$;

notify pgrst, 'reload schema';

commit;
