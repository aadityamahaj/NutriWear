"use client";

import { getSupabase } from "./supabase";

/**
 * Per-user data: profile + preferences. When signed in, it's stored in Supabase
 * (table `profiles`, one row per auth user, protected by row-level security).
 * For guests, it's stored in localStorage. Same shape either way, so the UI
 * doesn't care which backend is active.
 *
 * Supabase schema (run once in the SQL editor):
 *   create table profiles (
 *     id uuid primary key references auth.users on delete cascade,
 *     display_name text,
 *     diet text,
 *     allergies text,
 *     prefs jsonb default '{}'::jsonb,
 *     updated_at timestamptz default now()
 *   );
 *   alter table profiles enable row level security;
 *   create policy "own profile" on profiles
 *     for all using (auth.uid() = id) with check (auth.uid() = id);
 */

export interface UserProfile {
  displayName: string;
  diet: string;
  allergies: string;
  prefs: Record<string, unknown>;
}

export const EMPTY_PROFILE: UserProfile = {
  displayName: "",
  diet: "No preference",
  allergies: "",
  prefs: {},
};

const GUEST_KEY = "nutriwear.guest.profile";

export async function loadProfile(userId: string | null): Promise<UserProfile> {
  if (!userId) return loadGuestProfile();
  const supabase = getSupabase();
  if (!supabase) return loadGuestProfile();
  const { data, error } = await supabase
    .from("profiles")
    .select("display_name, diet, allergies, prefs")
    .eq("id", userId)
    .maybeSingle();
  if (error || !data) return { ...EMPTY_PROFILE };
  return {
    displayName: data.display_name ?? "",
    diet: data.diet ?? EMPTY_PROFILE.diet,
    allergies: data.allergies ?? "",
    prefs: (data.prefs as Record<string, unknown>) ?? {},
  };
}

export async function saveProfile(userId: string | null, profile: UserProfile): Promise<void> {
  if (!userId) return saveGuestProfile(profile);
  const supabase = getSupabase();
  if (!supabase) return saveGuestProfile(profile);
  await supabase.from("profiles").upsert({
    id: userId,
    display_name: profile.displayName,
    diet: profile.diet,
    allergies: profile.allergies,
    prefs: profile.prefs,
    updated_at: new Date().toISOString(),
  });
}

function loadGuestProfile(): UserProfile {
  try {
    const raw = localStorage.getItem(GUEST_KEY);
    if (raw) return { ...EMPTY_PROFILE, ...JSON.parse(raw) };
  } catch {
    /* ignore */
  }
  return { ...EMPTY_PROFILE };
}

function saveGuestProfile(profile: UserProfile): void {
  try {
    localStorage.setItem(GUEST_KEY, JSON.stringify(profile));
  } catch {
    /* ignore */
  }
}
