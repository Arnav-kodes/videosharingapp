-- ============================================================
--  StreamVid — Supabase Database Schema
--  Run this in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================

-- 1. Users (extends Supabase auth.users)
create table public.profiles (
  id          uuid references auth.users(id) on delete cascade primary key,
  username    text unique not null,
  avatar_url  text,
  bio         text,
  created_at  timestamptz default now()
);

-- Automatically create a profile when a new user signs up
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, username)
  values (new.id, new.raw_user_meta_data->>'username');
  return new;
end;
$$ language plpgsql security definer;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- 2. Videos
create table public.videos (
  id           uuid default gen_random_uuid() primary key,
  title        text not null,
  description  text,
  creator_id   uuid references public.profiles(id) on delete cascade not null,
  video_url    text not null,       -- Supabase Storage URL
  thumbnail_url text,               -- Supabase Storage URL
  duration     integer default 0,   -- in seconds
  views        integer default 0,
  created_at   timestamptz default now()
);

-- 3. Likes / Dislikes
create table public.likes (
  id         uuid default gen_random_uuid() primary key,
  user_id    uuid references public.profiles(id) on delete cascade not null,
  video_id   uuid references public.videos(id) on delete cascade not null,
  type       text check (type in ('like', 'dislike')) not null,
  created_at timestamptz default now(),
  unique(user_id, video_id)  -- one reaction per user per video
);

-- 4. Comments
create table public.comments (
  id         uuid default gen_random_uuid() primary key,
  video_id   uuid references public.videos(id) on delete cascade not null,
  user_id    uuid references public.profiles(id) on delete cascade not null,
  text       text not null,
  created_at timestamptz default now()
);

-- 5. Subscriptions
create table public.subscriptions (
  id            uuid default gen_random_uuid() primary key,
  subscriber_id uuid references public.profiles(id) on delete cascade not null,
  channel_id    uuid references public.profiles(id) on delete cascade not null,
  created_at    timestamptz default now(),
  unique(subscriber_id, channel_id)
);

-- ── Row Level Security (RLS) ──────────────────────────────────

alter table public.profiles     enable row level security;
alter table public.videos       enable row level security;
alter table public.likes        enable row level security;
alter table public.comments     enable row level security;
alter table public.subscriptions enable row level security;

-- Profiles: anyone can read, only owner can update
create policy "Public profiles are viewable by everyone" on public.profiles for select using (true);
create policy "Users can update own profile" on public.profiles for update using (auth.uid() = id);

-- Videos: anyone can read, only creator can insert/update/delete
create policy "Videos are viewable by everyone" on public.videos for select using (true);
create policy "Users can insert own videos" on public.videos for insert with check (auth.uid() = creator_id);
create policy "Users can update own videos" on public.videos for update using (auth.uid() = creator_id);
create policy "Users can delete own videos" on public.videos for delete using (auth.uid() = creator_id);

-- Comments: anyone can read, authenticated users can post
create policy "Comments are viewable by everyone" on public.comments for select using (true);
create policy "Authenticated users can comment" on public.comments for insert with check (auth.uid() = user_id);
create policy "Users can delete own comments" on public.comments for delete using (auth.uid() = user_id);

-- Likes: anyone can read, authenticated users can react
create policy "Likes are viewable by everyone" on public.likes for select using (true);
create policy "Authenticated users can like" on public.likes for insert with check (auth.uid() = user_id);
create policy "Users can change their reaction" on public.likes for update using (auth.uid() = user_id);
create policy "Users can remove their reaction" on public.likes for delete using (auth.uid() = user_id);

-- ── Storage Bucket ────────────────────────────────────────────
-- Run this after creating the bucket named "videos" in Supabase Dashboard

insert into storage.buckets (id, name, public) values ('videos', 'videos', true);

create policy "Anyone can view videos" on storage.objects for select using (bucket_id = 'videos');
create policy "Authenticated users can upload" on storage.objects for insert with check (bucket_id = 'videos' and auth.role() = 'authenticated');
