import { GoogleAuth } from 'npm:google-auth-library@9';
import { createClient } from 'npm:@supabase/supabase-js@2';

type NotificationJob = {
  id: string;
  user_id: string;
  category: 'anniversary' | 'message' | 'image' | 'game';
  route: string;
  payload: Record<string, unknown>;
  deliver_silently: boolean;
};

const jsonHeaders = { 'content-type': 'application/json; charset=utf-8' };

Deno.serve(async (request) => {
  if (request.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'METHOD_NOT_ALLOWED' }), {
      status: 405,
      headers: jsonHeaders,
    });
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const serviceAccountRaw = Deno.env.get('FIREBASE_SERVICE_ACCOUNT_JSON');
  const authorization = request.headers.get('authorization');
  if (!supabaseUrl || !serviceRoleKey || !serviceAccountRaw) {
    return new Response(JSON.stringify({ error: 'WORKER_NOT_CONFIGURED' }), {
      status: 503,
      headers: jsonHeaders,
    });
  }
  if (authorization !== `Bearer ${serviceRoleKey}`) {
    return new Response(JSON.stringify({ error: 'SERVICE_ROLE_REQUIRED' }), {
      status: 403,
      headers: jsonHeaders,
    });
  }

  const serviceAccount = JSON.parse(serviceAccountRaw) as {
    project_id: string;
    client_email: string;
    private_key: string;
  };
  const googleAuth = new GoogleAuth({
    credentials: serviceAccount,
    scopes: ['https://www.googleapis.com/auth/firebase.messaging'],
  });
  const authClient = await googleAuth.getClient();
  const accessTokenResult = await authClient.getAccessToken();
  const accessToken = typeof accessTokenResult === 'string'
    ? accessTokenResult
    : accessTokenResult?.token;
  if (!accessToken) {
    return new Response(JSON.stringify({ error: 'FCM_AUTH_FAILED' }), {
      status: 503,
      headers: jsonHeaders,
    });
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const workerId = `edge-${crypto.randomUUID()}`;
  const { data: claimed, error: claimError } = await supabase.rpc(
    'claim_notification_jobs',
    { worker_id: workerId, batch_size: 50 },
  );
  if (claimError) {
    return new Response(JSON.stringify({ error: claimError.message }), {
      status: 500,
      headers: jsonHeaders,
    });
  }

  const results = await Promise.all(
    ((claimed ?? []) as NotificationJob[]).map(async (job) => {
      try {
        const enabled = await categoryEnabled(supabase, job);
        if (!enabled) {
          await finishJob(supabase, job.id, false, 'PREFERENCE_DISABLED', true);
          return { id: job.id, status: 'cancelled' };
        }

        const { data: tokenRows, error: tokenError } = await supabase
          .from('device_push_tokens')
          .select('user_id,device_id,push_token')
          .eq('user_id', job.user_id);
        if (tokenError) throw tokenError;
        if (!tokenRows?.length) {
          await finishJob(supabase, job.id, false, 'NO_DEVICE_TOKEN', true);
          return { id: job.id, status: 'cancelled' };
        }

        let delivered = 0;
        const errors: string[] = [];
        for (const tokenRow of tokenRows) {
          const response = await fetch(
            `https://fcm.googleapis.com/v1/projects/${serviceAccount.project_id}/messages:send`,
            {
              method: 'POST',
              headers: {
                authorization: `Bearer ${accessToken}`,
                'content-type': 'application/json',
              },
              body: JSON.stringify({
                message: buildFcmMessage(job, tokenRow.push_token as string),
              }),
            },
          );
          if (response.ok) {
            delivered += 1;
            continue;
          }

          const raw = await response.text();
          errors.push(`${response.status}:${raw.slice(0, 300)}`);
          if (raw.includes('UNREGISTERED') || raw.includes('INVALID_ARGUMENT')) {
            await supabase
              .from('device_push_tokens')
              .delete()
              .eq('user_id', job.user_id)
              .eq('device_id', tokenRow.device_id);
          }
        }

        if (delivered > 0) {
          await finishJob(supabase, job.id, true);
          return { id: job.id, status: 'sent', delivered };
        }
        throw new Error(errors.join(' | ') || 'FCM_DELIVERY_FAILED');
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        await finishJob(supabase, job.id, false, message);
        return { id: job.id, status: 'failed', error: message };
      }
    }),
  );

  return new Response(
    JSON.stringify({ claimed: results.length, results }),
    { status: 200, headers: jsonHeaders },
  );
});

function buildFcmMessage(job: NotificationJob, token: string) {
  const title = String(job.payload.title ?? 'Dear');
  const body = String(job.payload.body ?? defaultBody(job.category));
  const data = Object.fromEntries(
    Object.entries({
      route: job.route,
      job_id: job.id,
      category: job.category,
      ...job.payload,
    }).map(([key, value]) => [
      key,
      typeof value === 'string' ? value : JSON.stringify(value),
    ]),
  );

  return {
    token,
    data,
    ...(job.deliver_silently ? {} : { notification: { title, body } }),
    android: {
      priority: job.deliver_silently ? 'normal' : 'high',
      ...(job.deliver_silently
        ? {}
        : { notification: { channel_id: `dear_${job.category}` } }),
    },
    apns: {
      headers: {
        'apns-push-type': job.deliver_silently ? 'background' : 'alert',
        'apns-priority': job.deliver_silently ? '5' : '10',
      },
      payload: {
        aps: {
          ...(job.deliver_silently
            ? { 'content-available': 1 }
            : { sound: 'default' }),
        },
      },
    },
  };
}

function defaultBody(category: NotificationJob['category']) {
  switch (category) {
    case 'anniversary':
      return '소중한 기념일이 찾아왔어요.';
    case 'image':
      return '새 사진이 도착했어요.';
    case 'game':
      return '오목 초대가 도착했어요.';
    default:
      return '새 메시지가 도착했어요.';
  }
}

async function categoryEnabled(
  supabase: ReturnType<typeof createClient>,
  job: NotificationJob,
) {
  const { data, error } = await supabase
    .from('notification_preferences')
    .select('message_enabled,image_enabled,anniversary_enabled,game_enabled')
    .eq('user_id', job.user_id)
    .maybeSingle();
  if (error) throw error;
  if (!data) return true;
  switch (job.category) {
    case 'message':
      return data.message_enabled;
    case 'image':
      return data.image_enabled;
    case 'anniversary':
      return data.anniversary_enabled;
    case 'game':
      return data.game_enabled;
  }
}

async function finishJob(
  supabase: ReturnType<typeof createClient>,
  jobId: string,
  succeeded: boolean,
  errorMessage: string | null = null,
  cancelJob = false,
) {
  const { error } = await supabase.rpc('finish_notification_job', {
    target_job_id: jobId,
    succeeded,
    error_message: errorMessage,
    cancel_job: cancelJob,
  });
  if (error) throw error;
}
