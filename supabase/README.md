# Dear Supabase deployment

The migrations and Edge Function in this directory form one notification
pipeline. Deploy them together; deploying only the tables leaves jobs pending.

## Required secrets

1. Add the Firebase service-account JSON to the Edge Function environment.

   ```sh
   supabase secrets set FIREBASE_SERVICE_ACCOUNT_JSON='<service-account-json>'
   ```

2. Add the project URL and service-role key to Supabase Vault so `pg_cron` can
   invoke the worker. Run this in the project SQL editor and replace both
   placeholders.

   ```sql
   select vault.create_secret(
     'https://<project-ref>.supabase.co',
     'project_url'
   );
   select vault.create_secret(
     'SERVICE_ROLE_KEY',
     'service_role_key'
   );
   ```

3. In Firebase, upload the APNs authentication key for the iOS app. Android and
   iOS both use the FCM HTTP v1 worker; Firebase forwards iOS messages to APNs.

## Deploy

```sh
supabase db push
supabase functions deploy process-notification-jobs
supabase functions deploy process-storage-cleanup
supabase functions deploy delete-account
```

The `dear-anniversary-enqueue` cron creates anniversary jobs every 15 minutes.
The `dear-notification-dispatch` cron invokes the Edge Function every minute.
The worker claims jobs with `FOR UPDATE SKIP LOCKED`, applies the latest user
category preference, sends FCM/APNs messages, removes invalid device tokens,
and records retry state.

The `dear-storage-cleanup` cron runs every five minutes. Database delete
triggers enqueue removed chat, album, domestic-map, and world-map photo paths;
the service-role worker then removes those private objects with bounded
backoff, so a transient client Storage failure does not leave a permanent
orphan.

## Release verification

- Confirm all three Dear cron jobs appear in `cron.job`.
- Confirm `dear-storage-cleanup` also appears in `cron.job` and a deliberately
  failed object removal advances its retry attempt without losing the job.
- Confirm `vault.decrypted_secrets` contains `project_url` and
  `service_role_key` (never print the decrypted values in logs).
- Insert or send one message, one photo, one anniversary, and one Omok invite;
  confirm each job moves from `pending` to `sent` exactly once.
- On a physical iPhone, test denied, provisional, and authorized permission;
  foreground, background, and terminated delivery; quiet-hour data-only
  delivery; and each deep link.
- On Android, test notification permission, token refresh, quiet delivery, and
  each deep link.
