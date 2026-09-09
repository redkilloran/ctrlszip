// Dev portal — admin only. Create event folders, generate invite keys
// for printing on cards, and zip an event once it's over.
import { supabase } from "./supabaseClient.js";

const notAuthorizedEl = document.getElementById("not-authorized");
const portalEl = document.getElementById("portal");
const newEventForm = document.getElementById("new-event-form");
const eventListEl = document.getElementById("event-list");

async function init() {
  const { data: { session } } = await supabase.auth.getSession();
  if (!session) {
    notAuthorizedEl.hidden = false;
    return;
  }

  const { data: profile } = await supabase
    .from("profiles")
    .select("is_admin")
    .eq("id", session.user.id)
    .single();

  if (!profile?.is_admin) {
    notAuthorizedEl.hidden = false;
    return;
  }

  portalEl.hidden = false;
  await loadEvents();
}

async function loadEvents() {
  const { data, error } = await supabase
    .from("folders")
    .select("id, codename, is_zipped")
    .eq("kind", "event")
    .order("created_at", { ascending: false });

  eventListEl.innerHTML = "";
  if (error || !data) return;

  for (const event of data) eventListEl.appendChild(renderEventCard(event));
}

function renderEventCard(event) {
  const li = document.createElement("li");
  li.className = "card";

  const titleRow = document.createElement("div");
  titleRow.className = "card-title-row";
  const link = document.createElement("a");
  link.href = `folder.html?id=${event.id}`;
  link.textContent = event.codename || "(untitled event)";
  titleRow.appendChild(link);
  if (event.is_zipped) titleRow.insertAdjacentHTML("beforeend", ' <span class="badge">zipped</span>');
  li.appendChild(titleRow);

  const keysListEl = document.createElement("ul");
  keysListEl.className = "comment-list";

  const genBtn = document.createElement("button");
  genBtn.className = "icon-btn";
  genBtn.textContent = "Generate invite key";
  genBtn.addEventListener("click", async () => {
    const { data, error } = await supabase.rpc("create_folder_key", { p_parent_folder_id: event.id });
    if (error) {
      alert(`Couldn't generate key: ${error.message}`);
      return;
    }
    alert(`New key #${data.sequence_number}: ${data.code}\n\nPrint this on the invite card.`);
    loadKeys(event.id, keysListEl);
  });
  li.appendChild(genBtn);

  if (!event.is_zipped) {
    const zipBtn = document.createElement("button");
    zipBtn.className = "icon-btn";
    zipBtn.textContent = "Zip this event";
    zipBtn.addEventListener("click", async () => {
      const sure = confirm(
        `Zip "${event.codename}"? This freezes it and every folder inside it — nobody will be ` +
          `able to edit them again (deleting still works, and chat stays active).`
      );
      if (!sure) return;

      const { error } = await supabase.rpc("zip_event_folder", { p_folder_id: event.id });
      if (error) {
        alert(`Couldn't zip: ${error.message}`);
        return;
      }
      loadEvents();
    });
    li.appendChild(zipBtn);
  }

  li.appendChild(keysListEl);
  loadKeys(event.id, keysListEl);

  return li;
}

async function loadKeys(eventId, listEl) {
  const { data, error } = await supabase
    .from("folder_keys")
    .select("code, sequence_number, claimed_by")
    .eq("parent_folder_id", eventId)
    .order("sequence_number", { ascending: true });

  listEl.innerHTML = "";
  if (error || !data) return;

  for (const key of data) {
    const li = document.createElement("li");
    li.textContent = `#${key.sequence_number} ${key.code} — ${key.claimed_by ? "claimed" : "unclaimed"}`;
    listEl.appendChild(li);
  }
}

newEventForm.addEventListener("submit", async (e) => {
  e.preventDefault();
  const input = document.getElementById("new-event-name");
  const codename = input.value.trim();

  const { error } = await supabase.from("folders").insert({ kind: "event", codename });

  if (error) {
    alert(`Couldn't create event folder: ${error.message}`);
    return;
  }

  input.value = "";
  await loadEvents();
});

init();
