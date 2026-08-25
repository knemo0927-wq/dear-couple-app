import { createClient } from 'npm:@supabase/supabase-js@2';

type StorageTarget = { bucket: string; path: string };

Deno.serve(async (request) => {
  if (request.method !== 'POST') {
    return Response.json({ error: 'METHOD_NOT_ALLOWED' }, { status: 405 });
  }

  const url = Deno.env.get('SUPABASE_URL');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const authorization = request.headers.get('authorization');
  const jwt = authorization?.replace(/^Bearer\s+/i, '');
  if (!url || !serviceKey || !jwt) {
    return Response.json({ error: 'AUTH_REQUIRED' }, { status: 401 });
  }

  const service = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: userData, error: userError } = await service.auth.getUser(jwt);
  const user = userData.user;
  if (userError || !user) {
    return Response.json({ error: 'AUTH_REQUIRED' }, { status: 401 });
  }

  const targets: StorageTarget[] = [];
  const addTarget = (bucket: string, value: unknown) => {
    const path = typeof value === 'string' ? value.trim() : '';
    if (path) targets.push({ bucket, path });
  };

  const { data: profile } = await service
    .from('profiles')
    .select('avatar_path')
    .eq('user_id', user.id)
    .maybeSingle();
  addTarget('profile-images', profile?.avatar_path);

  const mediaQueries = await Promise.all([
    service.from('messages').select('image_path').eq('sender_id', user.id),
    service
      .from('memory_album_photos')
      .select('storage_path')
      .eq('uploaded_by', user.id),
    service
      .from('travel_city_photos')
      .select('storage_path')
      .eq('uploaded_by', user.id),
    service
      .from('world_country_photos')
      .select('storage_path')
      .eq('uploaded_by', user.id),
  ]);
  for (const row of mediaQueries[0].data ?? []) {
    addTarget('chat-images', row.image_path);
  }
  for (const row of mediaQueries[1].data ?? []) {
    addTarget('memory-album-photos', row.storage_path);
  }
  for (const row of mediaQueries[2].data ?? []) {
    addTarget('travel-city-photos', row.storage_path);
  }
  for (const row of mediaQueries[3].data ?? []) {
    addTarget('world-country-photos', row.storage_path);
  }

  const grouped = new Map<string, Set<string>>();
  for (const target of targets) {
    const paths = grouped.get(target.bucket) ?? new Set<string>();
    paths.add(target.path);
    grouped.set(target.bucket, paths);
  }
  for (const [bucket, paths] of grouped.entries()) {
    for (const chunk of chunks([...paths], 100)) {
      const { error } = await service.storage.from(bucket).remove(chunk);
      if (error) {
        return Response.json(
          { error: 'STORAGE_CLEANUP_FAILED', bucket, detail: error.message },
          { status: 502 },
        );
      }
    }
  }

  const userScoped = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { authorization: `Bearer ${jwt}` } },
  });
  const { error: deleteError } = await userScoped.rpc('delete_my_account');
  if (deleteError) {
    return Response.json(
      { error: 'ACCOUNT_DELETE_FAILED', detail: deleteError.message },
      { status: 500 },
    );
  }

  return Response.json({ deleted: true, removed_objects: targets.length });
});

function chunks<T>(values: T[], size: number) {
  const result: T[][] = [];
  for (let index = 0; index < values.length; index += size) {
    result.push(values.slice(index, index + size));
  }
  return result;
}
