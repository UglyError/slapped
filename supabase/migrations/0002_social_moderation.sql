-- Slapped 0002: comments, activity, badges, blocking, reporting, account deletion.
-- Safe to run more than once.

-- ─────────────────────────────────────────────────────────────
-- Blocking
-- ─────────────────────────────────────────────────────────────
create table if not exists public.blocks (
  blocker_id uuid not null references public.profiles(id) on delete cascade,
  blocked_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);
alter table public.blocks enable row level security;

drop policy if exists "see own blocks" on public.blocks;
drop policy if exists "block as yourself" on public.blocks;
drop policy if exists "unblock as yourself" on public.blocks;
create policy "see own blocks" on public.blocks for select using (auth.uid() = blocker_id);
create policy "block as yourself" on public.blocks for insert with check (auth.uid() = blocker_id);
create policy "unblock as yourself" on public.blocks for delete using (auth.uid() = blocker_id);

-- Everyone I blocked or who blocked me. Definer so the second half is visible.
create or replace function public.blocked_ids()
returns setof uuid language sql stable security definer set search_path = public as $$
  select blocked_id from public.blocks where blocker_id = auth.uid()
  union
  select blocker_id from public.blocks where blocked_id = auth.uid();
$$;

-- Blocking severs follows both ways and cancels open trades between the two.
create or replace function public.on_block()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  delete from follows
  where (follower_id = new.blocker_id and following_id = new.blocked_id)
     or (follower_id = new.blocked_id and following_id = new.blocker_id);
  update trades set status = 'cancelled', responded_at = now()
  where status = 'pending'
    and ((proposer_id = new.blocker_id and recipient_id = new.blocked_id)
      or (proposer_id = new.blocked_id and recipient_id = new.blocker_id));
  return new;
end $$;

drop trigger if exists blocks_after_insert on public.blocks;
create trigger blocks_after_insert after insert on public.blocks
  for each row execute function public.on_block();

-- ─────────────────────────────────────────────────────────────
-- Comments
-- ─────────────────────────────────────────────────────────────
create table if not exists public.comments (
  id uuid primary key default gen_random_uuid(),
  sticker_id uuid not null references public.stickers(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check (char_length(trim(body)) between 1 and 280),
  hidden boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists comments_sticker_idx on public.comments (sticker_id, created_at);
alter table public.comments enable row level security;

drop policy if exists "comments are public" on public.comments;
drop policy if exists "comment as yourself" on public.comments;
drop policy if exists "delete own comment or on own sticker" on public.comments;
create policy "comments are public" on public.comments for select using (not hidden);
create policy "comment as yourself" on public.comments for insert
  with check (auth.uid() = user_id and hidden = false);
create policy "delete own comment or on own sticker" on public.comments for delete
  using (auth.uid() = user_id
         or exists (select 1 from public.stickers s where s.id = sticker_id and s.owner_id = auth.uid()));

alter table public.stickers add column if not exists comment_count int not null default 0;
alter table public.stickers add column if not exists hidden boolean not null default false;

create or replace function public.bump_comment_count()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    update stickers set comment_count = comment_count + 1 where id = new.sticker_id;
  elsif tg_op = 'DELETE' then
    update stickers set comment_count = greatest(comment_count - 1, 0) where id = old.sticker_id;
  end if;
  return null;
end $$;

drop trigger if exists comments_count on public.comments;
create trigger comments_count after insert or delete on public.comments
  for each row execute function public.bump_comment_count();

create or replace view public.comment_cards with (security_invoker = true) as
select c.id, c.sticker_id, c.body, c.created_at,
       c.user_id, p.username, p.avatar_url
from public.comments c
join public.profiles p on p.id = c.user_id
where c.user_id not in (select public.blocked_ids());

-- ─────────────────────────────────────────────────────────────
-- Read models: hide reported stickers and blocked users
-- ─────────────────────────────────────────────────────────────
create or replace view public.sticker_cards with (security_invoker = true) as
select
  s.id, s.name, s.description, s.image_url, s.lat, s.lng, s.place_name,
  s.like_count, s.trade_count, s.value, s.created_at,
  s.finder_id, f.username as finder_username, f.avatar_url as finder_avatar_url,
  s.owner_id, o.username as owner_username, o.avatar_url as owner_avatar_url,
  exists (select 1 from public.likes l
          where l.sticker_id = s.id and l.user_id = auth.uid()) as liked_by_me,
  s.comment_count
from public.stickers s
join public.profiles f on f.id = s.finder_id
join public.profiles o on o.id = s.owner_id
where not s.hidden
  and s.finder_id not in (select public.blocked_ids())
  and s.owner_id not in (select public.blocked_ids());

create or replace view public.profile_stats with (security_invoker = true) as
select
  p.id, p.username, p.display_name, p.avatar_url, p.bio, p.created_at,
  (select count(*) from public.stickers s where s.finder_id = p.id) as finds,
  (select count(*) from public.stickers s where s.owner_id = p.id) as owned,
  (select coalesce(sum(s.value), 0) from public.stickers s where s.owner_id = p.id) as collection_value,
  (select count(*) from public.follows f where f.following_id = p.id) as followers,
  (select count(*) from public.follows f where f.follower_id = p.id) as following,
  exists (select 1 from public.follows f
          where f.follower_id = auth.uid() and f.following_id = p.id) as followed_by_me,
  exists (select 1 from public.blocks b
          where b.blocker_id = auth.uid() and b.blocked_id = p.id) as blocked_by_me
from public.profiles p;

-- ─────────────────────────────────────────────────────────────
-- Reporting: 3 distinct reports auto-hide a sticker or comment
-- ─────────────────────────────────────────────────────────────
create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  sticker_id uuid references public.stickers(id) on delete cascade,
  comment_id uuid references public.comments(id) on delete cascade,
  reported_user_id uuid references public.profiles(id) on delete cascade,
  reason text not null check (char_length(reason) <= 200),
  created_at timestamptz not null default now(),
  check (num_nonnulls(sticker_id, comment_id, reported_user_id) >= 1)
);
alter table public.reports enable row level security; -- no policies: only the RPC writes, only you (dashboard) read

create or replace function public.report_content(
  p_reason text, p_sticker uuid default null, p_comment uuid default null, p_user uuid default null)
returns void language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  if exists (select 1 from reports where reporter_id = uid
             and sticker_id is not distinct from p_sticker
             and comment_id is not distinct from p_comment
             and reported_user_id is not distinct from p_user) then
    return;
  end if;
  insert into reports (reporter_id, sticker_id, comment_id, reported_user_id, reason)
  values (uid, p_sticker, p_comment, p_user, left(coalesce(p_reason, 'other'), 200));

  if p_sticker is not null
     and (select count(distinct reporter_id) from reports where sticker_id = p_sticker) >= 3 then
    update stickers set hidden = true where id = p_sticker;
  end if;
  if p_comment is not null
     and (select count(distinct reporter_id) from reports where comment_id = p_comment) >= 3 then
    update comments set hidden = true where id = p_comment;
  end if;
end $$;

-- ─────────────────────────────────────────────────────────────
-- Activity (notifications)
-- ─────────────────────────────────────────────────────────────
create or replace function public.my_activity(p_limit int default 60)
returns table (kind text, actor_id uuid, actor_username text, actor_avatar_url text,
               sticker_id uuid, sticker_name text, sticker_image_url text,
               body text, created_at timestamptz)
language sql stable security definer set search_path = public as $$
  select a.* from (
    select 'like'::text, l.user_id, p.username, p.avatar_url, s.id, s.name, s.image_url, null::text, l.created_at
    from likes l join stickers s on s.id = l.sticker_id join profiles p on p.id = l.user_id
    where s.finder_id = auth.uid() and l.user_id <> auth.uid()
    union all
    select 'comment', c.user_id, p.username, p.avatar_url, s.id, s.name, s.image_url, c.body, c.created_at
    from comments c join stickers s on s.id = c.sticker_id join profiles p on p.id = c.user_id
    where (s.finder_id = auth.uid() or s.owner_id = auth.uid()) and c.user_id <> auth.uid() and not c.hidden
    union all
    select 'follow', f.follower_id, p.username, p.avatar_url, null, null, null, null, f.created_at
    from follows f join profiles p on p.id = f.follower_id
    where f.following_id = auth.uid()
    union all
    select case when t.status = 'pending' then 'trade_offer' else 'trade_accepted' end,
           p.id, p.username, p.avatar_url, null, null, null, t.message, coalesce(t.responded_at, t.created_at)
    from trades t join profiles p on p.id = case when t.recipient_id = auth.uid() then t.proposer_id else t.recipient_id end
    where (t.recipient_id = auth.uid() and t.status = 'pending')
       or (t.proposer_id = auth.uid() and t.status = 'accepted')
  ) as a(kind, actor_id, actor_username, actor_avatar_url, sticker_id, sticker_name, sticker_image_url, body, created_at)
  where a.actor_id not in (select public.blocked_ids())
  order by a.created_at desc
  limit p_limit;
$$;

-- ─────────────────────────────────────────────────────────────
-- Badges (computed, Untappd-style)
-- ─────────────────────────────────────────────────────────────
create or replace function public.user_badges(p_user uuid)
returns table (code text, title text, detail text, icon text)
language sql stable set search_path = public as $$
  with s as (
    select
      (select count(*) from stickers where finder_id = p_user) as finds,
      (select count(*) from stickers where owner_id = p_user) as owned,
      (select count(distinct trade_id) from sticker_transfers where p_user in (from_id, to_id)) as trades,
      (select count(distinct round(lat::numeric, 1)::text || ',' || round(lng::numeric, 1)::text)
         from stickers where finder_id = p_user) as areas,
      (select coalesce(max(like_count), 0) from stickers where finder_id = p_user) as top_likes,
      (select count(*) from follows where following_id = p_user) as followers,
      (select count(*) from comments where user_id = p_user) as comments
  )
  select b.code, b.title, b.detail, b.icon
  from s, lateral (values
    ('first_find',  'First Slap',     'Logged your first sticker',          'seal.fill',                    s.finds >= 1),
    ('finds_10',    'Spotter',        'Logged 10 stickers',                 'binoculars.fill',              s.finds >= 10),
    ('finds_50',    'Hunter',         'Logged 50 stickers',                 'scope',                        s.finds >= 50),
    ('finds_100',   'Legend',         'Logged 100 stickers',                'crown.fill',                   s.finds >= 100),
    ('first_trade', 'Deal Maker',     'Completed your first trade',         'arrow.left.arrow.right',       s.trades >= 1),
    ('trades_10',   'Merchant',       'Completed 10 trades',                'storefront.fill',              s.trades >= 10),
    ('owned_25',    'Collector',      'Own 25 stickers at once',            'square.stack.3d.up.fill',      s.owned >= 25),
    ('areas_5',     'Explorer',       'Found stickers in 5 different areas','map.fill',                     s.areas >= 5),
    ('areas_20',    'Globetrotter',   'Found stickers in 20 different areas','globe.americas.fill',         s.areas >= 20),
    ('likes_10',    'Crowd Pleaser',  'A find got 10 props',                'flame.fill',                   s.top_likes >= 10),
    ('followers_10','Local Celeb',    '10 followers',                       'person.3.fill',                s.followers >= 10),
    ('comments_10', 'Chatterbox',     'Left 10 comments',                   'bubble.left.and.bubble.right.fill', s.comments >= 10)
  ) as b(code, title, detail, icon, earned)
  where b.earned;
$$;

-- ─────────────────────────────────────────────────────────────
-- Account deletion (App Store requirement). The app removes the
-- user's image files first; this deletes the auth user, which
-- cascades to their profile, stickers, likes, comments and trades.
-- ─────────────────────────────────────────────────────────────
create or replace function public.delete_account()
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  delete from auth.users where id = auth.uid();
end $$;

revoke execute on function public.report_content(text, uuid, uuid, uuid) from anon;
revoke execute on function public.delete_account() from anon;
revoke execute on function public.my_activity(int) from anon;
