import { createClient } from 'npm:@supabase/supabase-js@2';

type CleanupJob = {
  id: number;
  bucket_id: string;
  object_path: string;
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
  if (!supabaseUrl || !serviceRoleKey) {
    return new Response(JSON.stringify({ error: 'WORKER_NOT_CONFIGURED' }), {
      status: 503,
      headers: jsonHeaders,
    });
  }
  if (request.headers.get('authorization') !== `Bearer ${serviceRoleKey}`) {
    return new Response(JSON.stringify({ error: 'SERVICE_ROLE_REQUIRED' }), {
      status: 403,
      headers: jsonHeaders,
    });
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const workerId = `storage-${crypto.randomUUID()}`;
  const { data, error } = await supabase.rpc('claim_storage_cleanup_jobs', {
    worker_id: workerId,
    batch_size: 50,
  });
  if (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: jsonHeaders,
    });
  }

  const results = await Promise.all(
    ((data ?? []) as CleanupJob[]).map(async (job) => {
      try {
        const { error: removeError } = await supabase.storage
          .from(job.bucket_id)
          .remove([job.object_path]);
        if (removeError) {
          const normalized = removeError.message.toLowerCase();
          if (!normalized.includes('not found') && !normalized.includes('404')) {
            throw removeError;
          }
        }
        await finishJob(supabase, job.id, true);
        return { id: job.id, status: 'removed' };
      } catch (caught) {
        const message = caught instanceof Error ? caught.message : String(caught);
        await finishJob(supabase, job.id, false, message);
        return { id: job.id, status: 'retry', error: message };
      }
    }),
  );

  return new Response(JSON.stringify({ claimed: results.length, results }), {
    status: 200,
    headers: jsonHeaders,
  });
});

async function finishJob(
  supabase: ReturnType<typeof createClient>,
  jobId: number,
  succeeded: boolean,
  errorMessage: string | null = null,
) {
  const { error } = await supabase.rpc('finish_storage_cleanup_job', {
    target_job_id: jobId,
    succeeded,
    error_message: errorMessage,
  });
  if (error) throw error;
}
