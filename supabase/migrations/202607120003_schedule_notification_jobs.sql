-- Supabase exposes pg_cron for database-side scheduling. Delivery itself stays
-- in the push worker, which consumes public.notification_jobs using service_role.
create extension if not exists pg_cron;

do $$
declare
  existing_job_id bigint;
begin
  select jobid into existing_job_id
  from cron.job
  where jobname = 'dear-anniversary-enqueue'
  limit 1;

  if existing_job_id is not null then
    perform cron.unschedule(existing_job_id);
  end if;

  perform cron.schedule(
    'dear-anniversary-enqueue',
    '*/15 * * * *',
    $command$select public.enqueue_due_anniversary_notifications(now());$command$
  );
end $$;
