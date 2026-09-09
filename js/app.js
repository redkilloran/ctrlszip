// Home page — lists public event folders, most recently active first.
// Unlisted and Private events never show up here by definition, so the
// query only ever asks for visibility = 'public'.
import { supabase } from "./supabaseClient.js";

const listEl = document.getElementById("event-list");
const statusEl = document.getElementById("home-status");

async function loadEventFolders() {
  const { data, error } = await supabase
    .from("folders")
    .select("id, codename, cover_photo_url, last_activity_at")
    .eq("kind", "event")
    .eq("visibility", "public")
    .order("last_activity_at", { ascending: false });

  if (error) {
    statusEl.textContent = `Couldn't load folders: ${error.message}`;
    return;
  }

  if (data.length === 0) {
    statusEl.textContent = "No folders yet.";
    return;
  }

  for (const folder of data) {
    const li = document.createElement("li");
    li.className = "card";

    const link = document.createElement("a");
    link.href = `folder.html?id=${folder.id}`;
    link.textContent = folder.codename || "(untitled event)";
    li.appendChild(link);

    const meta = document.createElement("span");
    meta.className = "hint";
    meta.textContent = ` · last active ${new Date(folder.last_activity_at).toLocaleDateString()}`;
    li.appendChild(meta);

    if (folder.cover_photo_url) {
      const img = document.createElement("img");
      img.src = folder.cover_photo_url;
      img.alt = "";
      li.appendChild(img);
    }

    listEl.appendChild(li);
  }
}

loadEventFolders();
