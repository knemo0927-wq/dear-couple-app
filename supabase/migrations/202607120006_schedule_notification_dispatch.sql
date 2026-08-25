create extension if not exists pg_net with schema extensions;
create extension if not exists supabase_vault with schema vault;

create or replace function public.invoke_notification_worker()
returns void
language plpgsql
security definer
set search_path = public, vault, net
as $$
declare
  project_url text;
  service_role_key text;
begin
  select decrypted_secret into project_url
  from vault.decrypted_secrets
  where name = 'project_url'
  limit 1;

  select decrypted_secret into service_role_key
  from vault.decrypted_secrets
  where name = 'service_role_key'
  limit 1;

  if project_url is null or service_role_key is null then
    raise warning 'notification worker skipped: vault project_url/service_role_key missing';
    return;
  end if;

  perform net.http_post(
    url := rtrim(project_url, '/') ||
      '/functions/v1/process-notification-jobs',
    headers := jsonb_build_object(
      'content-type', 'application/json',
      'authorization', 'Bearer ' || service_role_key
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 50000
  );
end;
$$;

revoke all on function public.invoke_notification_worker()
  from public, anon, authenticated;
grant execute on function public.invoke_notification_worker() to service_role;

do $$
declare
  existing_job_id bigint;
begin
  select jobid into existing_job_id
  from cron.job
  where jobname = 'dear-notification-dispatch'
  limit 1;

  if existing_job_id is not null then
    perform cron.unschedule(existing_job_id);
  end if;

  perform cron.schedule(
    'dear-notification-dispatch',
    '* * * * *',
    $command$select public.invoke_notification_worker();$command$
  );
end $$;
