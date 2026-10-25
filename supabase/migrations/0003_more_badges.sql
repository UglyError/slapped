-- Slapped 0003: full badge catalogue with tiers and progress. Safe to run more than once.

create or replace function public.badge_progress(p_user uuid)
returns table (code text, title text, detail text, icon text, tier text,
               progress int, target int, earned boolean)
language sql stable set search_path = public, extensions as $$
  with mine as (
    select s.*,
           -- approximate local time from longitude (15° per hour)
           (s.created_at at time zone 'UTC') + make_interval(hours => round(s.lng / 15)::int) as local_time
    from stickers s where s.finder_id = p_user
  ),
  s as (
    select
      (select count(*) from mine)::int as finds,
      (select count(*) from stickers where owner_id = p_user)::int as owned,
      (select coalesce(sum(value), 0) from stickers where owner_id = p_user)::int as clout,
      (select count(distinct trade_id) from sticker_transfers where p_user in (from_id, to_id))::int as trades,
      (select coalesce(max(trade_count), 0) from stickers where owner_id = p_user)::int as most_traded,
      (select count(distinct round(lat::numeric, 1)::text || ',' || round(lng::numeric, 1)::text) from mine)::int as areas,
      (select count(distinct round(lat::numeric, 0)::text || ',' || round(lng::numeric, 0)::text) from mine)::int as regions,
      (select count(*) from mine m where not exists (
          select 1 from stickers o
          where o.id <> m.id and o.created_at < m.created_at
            and st_dwithin(o.location, m.location, 1000)))::int as pioneers,
      (select count(*) from mine where extract(hour from local_time) < 5)::int as night_finds,
      (select count(*) from mine where extract(hour from local_time) between 5 and 6)::int as dawn_finds,
      (select count(*) from mine where extract(isodow from local_time) in (6, 7))::int as weekend_finds,
      (select count(distinct local_time::date) from mine)::int as hunt_days,
      (select coalesce(max(like_count), 0) from mine)::int as top_likes,
      (select count(*) from likes where user_id = p_user)::int as props_given,
      (select count(*) from follows where following_id = p_user)::int as followers,
      (select count(*) from follows where follower_id = p_user)::int as following,
      (select count(*) from comments where user_id = p_user)::int as comments
  )
  select b.code, b.title, b.detail, b.icon, b.tier, least(b.value, b.goal), b.goal, b.value >= b.goal
  from s, lateral (values
    -- hunting
    ('first_find',   'First Slap',      'Log your first sticker',                       'seal.fill',                          'bronze',   s.finds,         1),
    ('finds_10',     'Spotter',         'Log 10 stickers',                              'binoculars.fill',                    'bronze',   s.finds,        10),
    ('finds_25',     'Tracker',         'Log 25 stickers',                              'pawprint.fill',                      'silver',   s.finds,        25),
    ('finds_50',     'Hunter',          'Log 50 stickers',                              'scope',                              'silver',   s.finds,        50),
    ('finds_100',    'Legend',          'Log 100 stickers',                             'crown.fill',                         'gold',     s.finds,       100),
    ('finds_250',    'Mythic',          'Log 250 stickers',                             'sparkles',                           'platinum', s.finds,       250),
    -- exploring
    ('pioneer',      'Pioneer',         'Log the first sticker within 1 km',            'flag.fill',                          'bronze',   s.pioneers,      1),
    ('pioneer_10',   'Trailblazer',     'Be first within 1 km 10 times',                'flag.checkered',                     'gold',     s.pioneers,     10),
    ('areas_5',      'Explorer',        'Find stickers in 5 different areas',           'map.fill',                           'bronze',   s.areas,         5),
    ('areas_20',     'Wanderer',        'Find stickers in 20 different areas',          'figure.walk',                        'silver',   s.areas,        20),
    ('regions_3',    'Road Trip',       'Find stickers in 3 regions ~100 km apart',     'car.fill',                           'silver',   s.regions,       3),
    ('regions_10',   'Globetrotter',    'Find stickers in 10 regions',                  'globe.americas.fill',                'gold',     s.regions,      10),
    -- timing
    ('night_owl',    'Night Owl',       'Log a sticker between midnight and 5am',       'moon.stars.fill',                    'silver',   s.night_finds,   1),
    ('early_bird',   'Early Bird',      'Log a sticker between 5am and 7am',            'sunrise.fill',                       'silver',   s.dawn_finds,    1),
    ('weekend',      'Weekend Warrior', 'Log 10 stickers on weekends',                  'calendar',                           'silver',   s.weekend_finds,10),
    ('days_7',       'Regular',         'Hunt on 7 different days',                     'calendar.badge.clock',               'bronze',   s.hunt_days,     7),
    ('days_30',      'Dedicated',       'Hunt on 30 different days',                    'calendar.badge.checkmark',           'gold',     s.hunt_days,    30),
    -- trading
    ('first_trade',  'Deal Maker',      'Complete a trade',                             'arrow.left.arrow.right',             'bronze',   s.trades,        1),
    ('trades_5',     'Haggler',         'Complete 5 trades',                            'arrow.triangle.2.circlepath',        'silver',   s.trades,        5),
    ('trades_10',    'Merchant',        'Complete 10 trades',                           'storefront.fill',                    'silver',   s.trades,       10),
    ('trades_25',    'Tycoon',          'Complete 25 trades',                           'briefcase.fill',                     'gold',     s.trades,       25),
    ('hot_potato',   'Hot Potato',      'Own a sticker that has been traded 5 times',   'bolt.fill',                          'gold',     s.most_traded,   5),
    -- collecting
    ('owned_10',     'Stash',           'Own 10 stickers at once',                      'tray.full.fill',                     'bronze',   s.owned,        10),
    ('owned_25',     'Collector',       'Own 25 stickers at once',                      'square.stack.3d.up.fill',            'silver',   s.owned,        25),
    ('owned_100',    'Hoarder',         'Own 100 stickers at once',                     'archivebox.fill',                    'gold',     s.owned,       100),
    ('clout_250',    'Clout Chaser',    'Own a collection worth 250 clout',             'chart.line.uptrend.xyaxis',          'silver',   s.clout,       250),
    ('clout_1000',   'Kingpin',         'Own a collection worth 1,000 clout',           'diamond.fill',                       'platinum', s.clout,      1000),
    -- social
    ('likes_10',     'Crowd Pleaser',   'Get 10 props on one find',                     'flame.fill',                         'silver',   s.top_likes,    10),
    ('likes_50',     'Viral',           'Get 50 props on one find',                     'star.fill',                          'gold',     s.top_likes,    50),
    ('props_25',     'Hype Man',        'Give 25 props',                                'hands.clap.fill',                    'bronze',   s.props_given,  25),
    ('comments_10',  'Chatterbox',      'Leave 10 comments',                            'bubble.left.and.bubble.right.fill',  'bronze',   s.comments,     10),
    ('following_10', 'Networker',       'Follow 10 hunters',                            'person.badge.plus',                  'bronze',   s.following,    10),
    ('followers_10', 'Local Celeb',     'Get 10 followers',                             'person.3.fill',                      'silver',   s.followers,    10),
    ('followers_100','Icon',            'Get 100 followers',                            'star.circle.fill',                   'platinum', s.followers,   100)
  ) as b(code, title, detail, icon, tier, value, goal);
$$;

-- Older app versions call user_badges: keep it, backed by the catalogue.
create or replace function public.user_badges(p_user uuid)
returns table (code text, title text, detail text, icon text)
language sql stable set search_path = public as $$
  select b.code, b.title, b.detail, b.icon from public.badge_progress(p_user) b where b.earned;
$$;
