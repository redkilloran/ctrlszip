// Single shared Supabase client, imported by every page's script.
import { createClient } from "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm";
import { SUPABASE_URL, SUPABASE_ANON_KEY } from "./supabase-config.js";

export const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

// Handles have no email, so accounts are created with a synthesized
// internal address instead — see SPEC.md's "Auth without email" section.
// This requires "Confirm email" to be turned OFF in the Supabase
// dashboard (Authentication > Providers > Email), since a confirmation
// link sent to a fake @ctrls.zip.internal address could never be opened.
export function emailForHandle(handle) {
  return `${handle}@ctrls.zip.internal`;
}
