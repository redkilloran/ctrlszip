// Entry point for the site. Supabase is loaded via the jsDelivr ESM build
// so there's no bundler/build step — this file is loaded directly as a
// <script type="module"> from index.html.

import { createClient } from "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm";
import { SUPABASE_URL, SUPABASE_ANON_KEY } from "./supabase-config.js";

export const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

// TODO: home page — load and render folders sorted by activity,
// excluding private folders.
console.log("CTRLS.zip booted. Supabase project:", SUPABASE_URL);
