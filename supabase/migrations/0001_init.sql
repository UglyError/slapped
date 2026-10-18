-- Slapped: social sticker hunting
-- Run in the Supabase SQL editor (or `supabase db push`).

create extension if not exists postgis with schema extensions;

-- ─────────────────────────────────────────────────────────────
-- Profiles
-- ─────────────────────────────────────────────────────────────
create table public.profiles (
  id uuid primary key references auth.users on delete cascade,
  username text unique not null check (username ~ '^[a-z0-9_]{3,20}$'),
  display_name text check (char_length(display_name) <= 40),
  avatar_url text,
  bio text check (char_length(bio) <= 160),
  created_at timestamptz not null default now()
);

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, username, display_name)
  values (
    new.id,
    coalesce(lower(new.raw_user_meta_data->>'username'),
             'hunter_' || substr(replace(new.id::text, '-', ''), 1, 8)),
    new.raw_user_meta_data->>'username'
  );
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ─────────────────────────────────────────────────────────────
-- Stickers
-- finder_id = who scanned it in the wild (never changes)
-- owner_id  = who holds it now (changes through trades)
-- value     = the sticker's worth in "clout", the trading currency
-- ─────────────────────────────────────────────────────────────
create table public.stickers (
  id uuid primary key default gen_random_uuid(),
  finder_id uuid not null references public.profiles(id) on delete cascade,
  owner_id uuid not null references public.profiles(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 60),
  description text check (char_length(description) <= 280),
  image_url text not null,
  phash bigint not null,
  lat double precision not null check (lat between -90 and 90),
  lng double precision not null check (lng between -180 and 180),
  location extensions.geography(Point, 4326),
  place_name text,
  like_count int not null default 0,
  trade_count int not null default 0,
  value int generated always as (10 + like_count * 2 + trade_count * 5) stored,
  created_at timestamptz not null default now()
);

create index stickers_location_idx on public.stickers using gist (location);
create index stickers_owner_idx on public.stickers (owner_id);
create index stickers_finder_idx on public.stickers (finder_id);
create index stickers_created_idx on public.stickers (created_at desc);
create index stickers_lat_lng_idx on public.stickers (lat, lng);

create or replace function public.set_sticker_location()
returns trigger language plpgsql set search_path = public, extensions as $$
begin
  new.location := st_setsrid(st_makepoint(new.lng, new.lat), 4326)::geography;
  return new;
end $$;

create trigger stickers_set_location
  before insert or update of lat, lng on public.stickers
  for each row execute function public.set_sticker_location();

-- ─────────────────────────────────────────────────────────────
-- Likes ("props"), follows, ownership history
-- ─────────────────────────────────────────────────────────────
create table public.likes (
  user_id uuid not null references public.profiles(id) on delete cascade,
  sticker_id uuid not null references public.stickers(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, sticker_id)
);
create index likes_sticker_created_idx on public.likes (sticker_id, created_at desc);

create or replace function public.bump_like_count()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    update stickers set like_count = like_count + 1 where id = new.sticker_id;
  elsif tg_op = 'DELETE' then
    update stickers set like_count = greatest(like_count - 1, 0) where id = old.sticker_id;
  end if;
  return null;
end $$;

create trigger likes_count
  after insert or delete on public.likes
  for each row execute function public.bump_like_count();

create table public.follows (
  follower_id uuid not null references public.profiles(id) on delete cascade,
  following_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower_id, following_id),
  check (follower_id <> following_id)
);

-- ─────────────────────────────────────────────────────────────
-- Trades
-- ─────────────────────────────────────────────────────────────
create type public.trade_status as enum ('pending', 'accepted', 'declined', 'cancelled');

create table public.trades (
  id uuid primary key default gen_random_uuid(),
  proposer_id uuid not null references public.profiles(id) on delete cascade,
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  status public.trade_status not null default 'pending',
  message text check (char_length(message) <= 200),
  created_at timestamptz not null default now(),
  responded_at timestamptz
);
create index trades_recipient_idx on public.trades (recipient_id, status);
create index trades_proposer_idx on public.trades (proposer_id, status);

create table public.trade_items (
  trade_id uuid not null references public.trades(id) on delete cascade,
  sticker_id uuid not null references public.stickers(id) on delete cascade,
  side text not null check (side in ('offer', 'request')),
  primary key (trade_id, sticker_id)
);
create index trade_items_sticker_idx on public.trade_items (sticker_id);

create table public.sticker_transfers (
  id uuid primary key default gen_random_uuid(),
  sticker_id uuid not null references public.stickers(id) on delete cascade,
  from_id uuid not null references public.profiles(id) on delete cascade,
  to_id uuid not null references public.profiles(id) on delete cascade,
  trade_id uuid references public.trades(id) on delete set null,
  created_at timestamptz not null default now()
);
create index sticker_transfers_sticker_idx on public.sticker_transfers (sticker_id, created_at desc);

-- ─────────────────────────────────────────────────────────────
-- Row level security
-- Stickers, trades and transfers are only written through the
-- security-definer functions below, so they get no write policies.
-- ─────────────────────────────────────────────────────────────
alter table public.profiles enable row level security;
alter table public.stickers enable row level security;
alter table public.likes enable row level security;
alter table public.follows enable row level security;
alter table public.trades enable row level security;
alter table public.trade_items enable row level security;
alter table public.sticker_transfers enable row level security;

create policy "profiles are public" on public.profiles for select using (true);
create policy "update own profile" on public.profiles for update
  using (auth.uid() = id) with check (auth.uid() = id);

create policy "stickers are public" on public.stickers for select using (true);
create policy "delete own untraded find" on public.stickers for delete
  using (auth.uid() = finder_id and auth.uid() = owner_id and trade_count = 0);

create policy "likes are public" on public.likes for select using (true);
create policy "like as yourself" on public.likes for insert with check (auth.uid() = user_id);
create policy "unlike as yourself" on public.likes for delete using (auth.uid() = user_id);

create policy "follows are public" on public.follows for select using (true);
create policy "follow as yourself" on public.follows for insert with check (auth.uid() = follower_id);
create policy "unfollow as yourself" on public.follows for delete using (auth.uid() = follower_id);

create policy "see your trades" on public.trades for select
  using (auth.uid() in (proposer_id, recipient_id));
create policy "see your trade items" on public.trade_items for select
  using (exists (select 1 from public.trades t
                 where t.id = trade_id and auth.uid() in (t.proposer_id, t.recipient_id)));

create policy "transfers are public" on public.sticker_transfers for select using (true);

-- ─────────────────────────────────────────────────────────────
-- Read models
-- ─────────────────────────────────────────────────────────────
create or replace view public.sticker_cards with (security_invoker = true) as
select
  s.id, s.name, s.description, s.image_url, s.lat, s.lng, s.place_name,
  s.like_count, s.trade_count, s.value, s.created_at,
  s.finder_id, f.username as finder_username, f.avatar_url as finder_avatar_url,
  s.owner_id, o.username as owner_username, o.avatar_url as owner_avatar_url,
  exists (select 1 from public.likes l
          where l.sticker_id = s.id and l.user_id = auth.uid()) as liked_by_me
from public.stickers s
join public.profiles f on f.id = s.finder_id
join public.profiles o on o.id = s.owner_id;

create or replace view public.profile_stats with (security_invoker = true) as
select
  p.id, p.username, p.display_name, p.avatar_url, p.bio, p.created_at,
  (select count(*) from public.stickers s where s.finder_id = p.id) as finds,
  (select count(*) from public.stickers s where s.owner_id = p.id) as owned,
  (select coalesce(sum(s.value), 0) from public.stickers s where s.owner_id = p.id) as collection_value,
  (select count(*) from public.follows f where f.following_id = p.id) as followers,
  (select count(*) from public.follows f where f.follower_id = p.id) as following,
  exists (select 1 from public.follows f
          where f.follower_id = auth.uid() and f.following_id = p.id) as followed_by_me
from public.profiles p;

-- ─────────────────────────────────────────────────────────────
-- Duplicate protection
-- A sticker counts as already logged when one with a near-identical
-- perceptual hash (any of the 4 rotations the client sends) exists
-- within 30 m.
-- ─────────────────────────────────────────────────────────────
create or replace function public.is_duplicate_sticker(
  p_hashes bigint[], p_lat double precision, p_lng double precision,
  p_radius_m double precision default 30, p_max_bits int default 10)
returns boolean language sql stable set search_path = public, extensions as $$
  select exists (
    select 1
    from public.stickers s, unnest(p_hashes) as h
    where st_dwithin(s.location, st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography, p_radius_m)
      and bit_count((s.phash # h)::bit(64)) <= p_max_bits
  );
$$;

create or replace function public.create_sticker(
  p_name text, p_description text, p_image_url text, p_hashes bigint[],
  p_lat double precision, p_lng double precision, p_place_name text)
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare
  uid uuid := auth.uid();
  new_id uuid;
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  if coalesce(cardinality(p_hashes), 0) = 0 then raise exception 'missing_hash'; end if;

  -- serialize creates so two people can't log the same sticker at once
  perform pg_advisory_xact_lock(hashtext('create_sticker'));

  if public.is_duplicate_sticker(p_hashes, p_lat, p_lng) then
    raise exception 'duplicate_sticker';
  end if;

  insert into public.stickers (finder_id, owner_id, name, description, image_url, phash, lat, lng, place_name)
  values (uid, uid, trim(p_name), nullif(trim(p_description), ''), p_image_url, p_hashes[1], p_lat, p_lng,
          nullif(trim(p_place_name), ''))
  returning id into new_id;

  return new_id;
end $$;

-- ─────────────────────────────────────────────────────────────
-- Discovery
-- ─────────────────────────────────────────────────────────────
create or replace function public.nearby_stickers(
  p_lat double precision, p_lng double precision,
  p_radius_m double precision default 5000, p_limit int default 50)
returns setof public.sticker_cards language sql stable set search_path = public, extensions as $$
  select c.*
  from public.sticker_cards c
  join public.stickers s on s.id = c.id
  where st_dwithin(s.location, st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography, p_radius_m)
  order by s.location <-> st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography
  limit p_limit;
$$;

create or replace function public.stickers_in_bounds(
  p_min_lat double precision, p_min_lng double precision,
  p_max_lat double precision, p_max_lng double precision, p_limit int default 300)
returns setof public.sticker_cards language sql stable set search_path = public as $$
  select c.*
  from public.sticker_cards c
  where c.lat between p_min_lat and p_max_lat
    and c.lng between p_min_lng and p_max_lng
  order by c.value desc, c.created_at desc
  limit p_limit;
$$;

create or replace function public.trending_stickers(p_days int default 7, p_limit int default 30)
returns setof public.sticker_cards language sql stable set search_path = public as $$
  select c.*
  from public.sticker_cards c
  left join lateral (
    select count(*) as n from public.likes l
    where l.sticker_id = c.id and l.created_at > now() - make_interval(days => p_days)
  ) recent on true
  order by recent.n desc, c.value desc, c.created_at desc
  limit p_limit;
$$;

create or replace function public.following_feed(p_limit int default 50)
returns setof public.sticker_cards language sql stable set search_path = public as $$
  select c.*
  from public.sticker_cards c
  where c.finder_id = auth.uid()
     or c.finder_id in (select following_id from public.follows where follower_id = auth.uid())
  order by c.created_at desc
  limit p_limit;
$$;

-- ─────────────────────────────────────────────────────────────
-- Trading
-- ─────────────────────────────────────────────────────────────
create or replace function public.propose_trade(
  p_recipient uuid, p_offered uuid[], p_requested uuid[], p_message text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  new_trade uuid;
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  if p_recipient = uid then raise exception 'cannot_trade_with_self'; end if;

  p_offered := array(select distinct unnest(p_offered));
  p_requested := array(select distinct unnest(p_requested));

  if cardinality(p_offered) = 0 or cardinality(p_requested) = 0 then
    raise exception 'empty_trade';
  end if;
  if (select count(*) from public.stickers where id = any(p_offered) and owner_id = uid) <> cardinality(p_offered) then
    raise exception 'not_owner_of_offered';
  end if;
  if (select count(*) from public.stickers where id = any(p_requested) and owner_id = p_recipient) <> cardinality(p_requested) then
    raise exception 'recipient_not_owner';
  end if;

  insert into public.trades (proposer_id, recipient_id, message)
  values (uid, p_recipient, nullif(trim(p_message), ''))
  returning id into new_trade;

  insert into public.trade_items (trade_id, sticker_id, side)
  select new_trade, unnest(p_offered), 'offer'
  union all
  select new_trade, unnest(p_requested), 'request';

  return new_trade;
end $$;

-- Returns 'accepted', 'declined' or 'stale' (someone no longer owns a sticker).
create or replace function public.respond_trade(p_trade uuid, p_accept boolean)
returns text language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  t public.trades;
begin
  select * into t from public.trades where id = p_trade for update;
  if not found or t.recipient_id is distinct from uid then raise exception 'trade_not_found'; end if;
  if t.status <> 'pending' then raise exception 'trade_not_pending'; end if;

  if not p_accept then
    update public.trades set status = 'declined', responded_at = now() where id = p_trade;
    return 'declined';
  end if;

  perform 1 from public.stickers
  where id in (select sticker_id from public.trade_items where trade_id = p_trade)
  for update;

  if exists (
    select 1 from public.trade_items i join public.stickers s on s.id = i.sticker_id
    where i.trade_id = p_trade
      and ((i.side = 'offer' and s.owner_id <> t.proposer_id)
        or (i.side = 'request' and s.owner_id <> t.recipient_id))
  ) then
    update public.trades set status = 'cancelled', responded_at = now() where id = p_trade;
    return 'stale';
  end if;

  insert into public.sticker_transfers (sticker_id, from_id, to_id, trade_id)
  select i.sticker_id,
         case when i.side = 'offer' then t.proposer_id else t.recipient_id end,
         case when i.side = 'offer' then t.recipient_id else t.proposer_id end,
         p_trade
  from public.trade_items i where i.trade_id = p_trade;

  update public.stickers s
  set owner_id = case when i.side = 'offer' then t.recipient_id else t.proposer_id end,
      trade_count = s.trade_count + 1
  from public.trade_items i
  where i.trade_id = p_trade and s.id = i.sticker_id;

  update public.trades set status = 'accepted', responded_at = now() where id = p_trade;

  -- any other open offer involving these stickers is now invalid
  update public.trades set status = 'cancelled', responded_at = now()
  where status = 'pending'
    and id in (select ti.trade_id from public.trade_items ti
               where ti.sticker_id in (select sticker_id from public.trade_items where trade_id = p_trade));

  return 'accepted';
end $$;

create or replace function public.cancel_trade(p_trade uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.trades set status = 'cancelled', responded_at = now()
  where id = p_trade and proposer_id = auth.uid() and status = 'pending';
  if not found then raise exception 'trade_not_found'; end if;
end $$;

revoke execute on function public.create_sticker(text, text, text, bigint[], double precision, double precision, text) from anon;
revoke execute on function public.propose_trade(uuid, uuid[], uuid[], text) from anon;
revoke execute on function public.respond_trade(uuid, boolean) from anon;
revoke execute on function public.cancel_trade(uuid) from anon;

-- ─────────────────────────────────────────────────────────────
-- Storage: public bucket, users write only inside their own folder
-- ─────────────────────────────────────────────────────────────
insert into storage.buckets (id, name, public)
values ('stickers', 'stickers', true)
on conflict (id) do nothing;

create policy "upload into own folder" on storage.objects for insert to authenticated
  with check (bucket_id = 'stickers' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "update own files" on storage.objects for update to authenticated
  using (bucket_id = 'stickers' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "delete own files" on storage.objects for delete to authenticated
  using (bucket_id = 'stickers' and (storage.foldername(name))[1] = auth.uid()::text);
