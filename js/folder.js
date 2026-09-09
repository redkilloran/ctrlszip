// Folder view: breadcrumb, subfolders, files (text posts for now —
// image/audio come later), comments, and live chat for event/user
// folders. Reached as folder.html?id=<folder id>.
import { supabase } from "./supabaseClient.js";
import { marked } from "https://cdn.jsdelivr.net/npm/marked@12/+esm";
import DOMPurify from "https://cdn.jsdelivr.net/npm/dompurify@3/+esm";

const folderId = new URLSearchParams(window.location.search).get("id");

const breadcrumbEl = document.getElementById("breadcrumb");
const notFoundEl = document.getElementById("not-found");
const folderViewEl = document.getElementById("folder-view");
const titleEl = document.getElementById("folder-title");
const ownerEl = document.getElementById("folder-owner");
const coverEl = document.getElementById("folder-cover");

const ownerControlsEl = document.getElementById("owner-controls");
const visibilitySelect = document.getElementById("visibility-select");
const privateControlsEl = document.getElementById("private-controls");
const grantForm = document.getElementById("grant-form");
const grantsListEl = document.getElementById("grants-list");

const subfolderListEl = document.getElementById("subfolder-list");
const newSubfolderForm = document.getElementById("new-subfolder-form");

const sortModeSelect = document.getElementById("sort-mode");
const fileListEl = document.getElementById("file-list");
const newFileForm = document.getElementById("new-file-form");

const chatSectionEl = document.getElementById("chat-section");
const chatLogEl = document.getElementById("chat-log");
const chatForm = document.getElementById("chat-form");
const chatInput = document.getElementById("chat-input");

let currentUserId = null;
let folder = null;
let files = [];
const handleCache = new Map();

async function getHandle(userId) {
  if (handleCache.has(userId)) return handleCache.get(userId);
  const { data } = await supabase.from("profiles").select("handle").eq("id", userId).single();
  const handle = data?.handle ?? "someone";
  handleCache.set(userId, handle);
  return handle;
}

async function init() {
  if (!folderId) {
    notFoundEl.hidden = false;
    return;
  }

  const { data: { session } } = await supabase.auth.getSession();
  currentUserId = session?.user?.id ?? null;

  // If this returns no row, RLS is doing its job — either the folder
  // doesn't exist, or it's private and you're not on the guest list.
  // Either way we show the same "not found", so a private folder's
  // existence isn't confirmed just by someone guessing its id.
  const { data, error } = await supabase
    .from("folders")
    .select("*, profiles(handle, pfp_url)")
    .eq("id", folderId)
    .single();

  if (error || !data) {
    notFoundEl.hidden = false;
    return;
  }

  folder = data;
  folderViewEl.hidden = false;

  await renderBreadcrumb();
  renderHeader();
  await loadSubfolders();
  await loadFiles();
  await loadGrantsIfNeeded();
  setupChat();
}

async function renderBreadcrumb() {
  const chain = [folder];
  let parentId = folder.parent_id;
  while (parentId) {
    const { data } = await supabase
      .from("folders")
      .select("id, codename, parent_id")
      .eq("id", parentId)
      .single();
    if (!data) break;
    chain.unshift(data);
    parentId = data.parent_id;
  }

  breadcrumbEl.innerHTML = "";
  const home = document.createElement("a");
  home.href = "index.html";
  home.textContent = "home";
  breadcrumbEl.appendChild(home);

  for (const node of chain) {
    const sep = document.createElement("span");
    sep.className = "sep";
    sep.textContent = "/";
    breadcrumbEl.appendChild(sep);

    const link = document.createElement("a");
    link.href = node.id === folder.id ? "#" : `folder.html?id=${node.id}`;
    link.textContent = node.codename || "(untitled)";
    breadcrumbEl.appendChild(link);
  }
}

function renderHeader() {
  titleEl.textContent = folder.codename || "(untitled folder)";

  const kindLabel = { event: "event folder", user: "folder", subfolder: "subfolder" }[folder.kind];
  titleEl.insertAdjacentHTML("beforeend", ` <span class="badge">${kindLabel}</span>`);
  if (folder.is_zipped) titleEl.insertAdjacentHTML("beforeend", ` <span class="badge">zipped</span>`);
  if (folder.visibility !== "public") {
    titleEl.insertAdjacentHTML("beforeend", ` <span class="badge">${folder.visibility}</span>`);
  }

  ownerEl.textContent = folder.profiles ? `kept by ${folder.profiles.handle}` : "";

  if (folder.cover_photo_url) {
    coverEl.src = folder.cover_photo_url;
    coverEl.hidden = false;
  }

  const isOwner = currentUserId && folder.owner_id === currentUserId;

  if (isOwner) {
    ownerControlsEl.hidden = false;
    visibilitySelect.value = folder.visibility;
    privateControlsEl.hidden = folder.visibility !== "private";
  }

  if (isOwner && !folder.is_zipped) {
    newSubfolderForm.hidden = false;
    newFileForm.hidden = false;
  }
}

visibilitySelect.addEventListener("change", async () => {
  const visibility = visibilitySelect.value;
  const { error } = await supabase.from("folders").update({ visibility }).eq("id", folderId);

  if (error) {
    alert(`Couldn't change visibility: ${error.message}`);
    visibilitySelect.value = folder.visibility;
    return;
  }

  folder.visibility = visibility;
  privateControlsEl.hidden = visibility !== "private";
  if (visibility === "private") loadGrants();
});

async function loadGrantsIfNeeded() {
  const isOwner = currentUserId && folder.owner_id === currentUserId;
  if (isOwner && folder.visibility === "private") await loadGrants();
}

async function loadGrants() {
  const { data: grants, error } = await supabase
    .from("folder_access_grants")
    .select("id, grantee_id")
    .eq("folder_id", folderId);

  grantsListEl.innerHTML = "";
  if (error || !grants) return;

  for (const grant of grants) {
    const { data: profile } = await supabase
      .from("profiles")
      .select("handle, sequence_number")
      .eq("id", grant.grantee_id)
      .single();

    const li = document.createElement("li");
    li.className = "card";
    li.textContent = profile ? `#${profile.sequence_number} ${profile.handle} ` : "unknown user ";

    const revokeBtn = document.createElement("button");
    revokeBtn.className = "icon-btn";
    revokeBtn.textContent = "revoke";
    revokeBtn.addEventListener("click", async () => {
      await supabase.from("folder_access_grants").delete().eq("id", grant.id);
      loadGrants();
    });
    li.appendChild(revokeBtn);
    grantsListEl.appendChild(li);
  }
}

grantForm.addEventListener("submit", async (e) => {
  e.preventDefault();
  const num = Number(document.getElementById("grant-number").value);

  const { error } = await supabase.rpc("grant_folder_access", {
    p_folder_id: folderId,
    p_grantee_sequence_number: num,
  });

  if (error) {
    alert(`Couldn't grant access: ${error.message}`);
    return;
  }

  document.getElementById("grant-number").value = "";
  loadGrants();
});

async function loadSubfolders() {
  const { data, error } = await supabase
    .from("folders")
    .select("id, codename")
    .eq("parent_id", folderId)
    .order("codename", { ascending: true });

  subfolderListEl.innerHTML = "";
  if (error || !data) return;

  for (const sub of data) {
    const li = document.createElement("li");
    li.className = "card";
    const link = document.createElement("a");
    link.href = `folder.html?id=${sub.id}`;
    link.textContent = sub.codename || "(untitled)";
    li.appendChild(link);
    subfolderListEl.appendChild(li);
  }
}

newSubfolderForm.addEventListener("submit", async (e) => {
  e.preventDefault();
  const nameInput = document.getElementById("new-subfolder-name");
  const codename = nameInput.value.trim();

  const { data: { session } } = await supabase.auth.getSession();
  const { error } = await supabase
    .from("folders")
    .insert({ kind: "subfolder", owner_id: session.user.id, parent_id: folderId, codename });

  if (error) {
    alert(`Couldn't create subfolder: ${error.message}`);
    return;
  }

  nameInput.value = "";
  await loadSubfolders();
});

async function loadFiles() {
  const { data, error } = await supabase
    .from("files")
    .select("*, profiles(handle, pfp_url)")
    .eq("folder_id", folderId);

  files = error || !data ? [] : data;
  renderFiles();
}

sortModeSelect.addEventListener("change", renderFiles);

function renderFiles() {
  const mode = sortModeSelect.value;
  const sorted = [...files].sort((a, b) =>
    mode === "alpha"
      ? (a.title || "").localeCompare(b.title || "")
      : new Date(b.created_at) - new Date(a.created_at)
  );

  fileListEl.innerHTML = "";
  for (const file of sorted) fileListEl.appendChild(renderFileCard(file));
}

function renderFileCard(file) {
  const li = document.createElement("li");
  li.className = "card";

  const titleRow = document.createElement("div");
  titleRow.className = "card-title-row";

  const titleSpan = document.createElement("strong");
  titleSpan.textContent = file.title || "(untitled)";
  titleRow.appendChild(titleSpan);

  const meta = document.createElement("span");
  meta.className = "hint";
  meta.textContent = `${file.profiles?.handle ?? "someone"} · ${new Date(file.created_at).toLocaleDateString()}`;
  titleRow.appendChild(meta);
  li.appendChild(titleRow);

  if (file.kind === "text") {
    const bodyDiv = document.createElement("div");
    bodyDiv.className = "card-body";
    bodyDiv.innerHTML = DOMPurify.sanitize(marked.parse(file.body || ""));
    li.appendChild(bodyDiv);
  } else if (file.kind === "image") {
    const img = document.createElement("img");
    img.src = file.media_url;
    img.alt = file.title || "image post";
    li.appendChild(img);
  } else if (file.kind === "audio") {
    const audio = document.createElement("audio");
    audio.controls = true;
    audio.src = file.media_url;
    li.appendChild(audio);
  }

  if (currentUserId && file.owner_id === currentUserId) {
    const delBtn = document.createElement("button");
    delBtn.className = "icon-btn";
    delBtn.textContent = "delete";
    delBtn.addEventListener("click", async () => {
      if (!confirm("Delete this file for good?")) return;
      await supabase.from("files").delete().eq("id", file.id);
      files = files.filter((f) => f.id !== file.id);
      renderFiles();
    });
    li.appendChild(delBtn);
  }

  const commentsUl = document.createElement("ul");
  commentsUl.className = "comment-list";
  li.appendChild(commentsUl);
  loadComments(file.id, commentsUl);

  if (currentUserId) {
    const commentForm = document.createElement("form");
    const input = document.createElement("input");
    input.type = "text";
    input.placeholder = "add a comment…";
    input.required = true;
    const submitBtn = document.createElement("button");
    submitBtn.type = "submit";
    submitBtn.textContent = "reply";
    commentForm.append(input, submitBtn);

    commentForm.addEventListener("submit", async (e) => {
      e.preventDefault();
      const body = input.value.trim();
      if (!body) return;

      const { data: { session } } = await supabase.auth.getSession();
      await supabase.from("comments").insert({ file_id: file.id, author_id: session.user.id, body });

      input.value = "";
      commentsUl.innerHTML = "";
      loadComments(file.id, commentsUl);
    });

    li.appendChild(commentForm);
  }

  return li;
}

async function loadComments(fileId, listEl) {
  const { data, error } = await supabase
    .from("comments")
    .select("*, profiles(handle)")
    .eq("file_id", fileId)
    .order("created_at", { ascending: true });

  if (error || !data) return;
  for (const comment of data) {
    const li = document.createElement("li");
    li.textContent = `${comment.profiles?.handle ?? "someone"}: ${comment.body}`;
    listEl.appendChild(li);
  }
}

newFileForm.addEventListener("submit", async (e) => {
  e.preventDefault();
  const titleInput = document.getElementById("new-file-title");
  const bodyInput = document.getElementById("new-file-body");
  const title = titleInput.value.trim() || null;
  const body = bodyInput.value.trim();

  if (!body) {
    alert("Text files need some text.");
    return;
  }

  const { data: { session } } = await supabase.auth.getSession();
  const { error } = await supabase
    .from("files")
    .insert({ folder_id: folderId, owner_id: session.user.id, kind: "text", title, body });

  if (error) {
    alert(`Couldn't post: ${error.message}`);
    return;
  }

  titleInput.value = "";
  bodyInput.value = "";
  await loadFiles();
});

function setupChat() {
  const hasChat = folder.kind === "event" || folder.kind === "user";
  if (!hasChat) return;

  chatSectionEl.hidden = false;
  loadChatHistory();

  supabase
    .channel(`chat-${folderId}`)
    .on(
      "postgres_changes",
      { event: "INSERT", schema: "public", table: "chat_messages", filter: `folder_id=eq.${folderId}` },
      async (payload) => appendChatMessage(payload.new, await getHandle(payload.new.author_id))
    )
    .subscribe();

  chatForm.addEventListener("submit", async (e) => {
    e.preventDefault();
    const body = chatInput.value.trim();
    if (!body) return;

    const { data: { session } } = await supabase.auth.getSession();
    if (!session) {
      alert("Log in to chat.");
      return;
    }

    const { error } = await supabase
      .from("chat_messages")
      .insert({ folder_id: folderId, author_id: session.user.id, body });

    if (error) {
      alert(`Couldn't send: ${error.message}`);
      return;
    }

    chatInput.value = "";
    // No need to append it here — the realtime subscription above will
    // receive this same insert and render it, including for the sender.
  });
}

async function loadChatHistory() {
  const { data, error } = await supabase
    .from("chat_messages")
    .select("*, profiles(handle)")
    .eq("folder_id", folderId)
    .order("created_at", { ascending: true })
    .limit(200);

  if (error || !data) return;
  for (const msg of data) {
    const handle = msg.profiles?.handle ?? "someone";
    handleCache.set(msg.author_id, handle);
    appendChatMessage(msg, handle);
  }
}

function appendChatMessage(msg, handle) {
  const div = document.createElement("div");
  div.textContent = `${handle}: ${msg.body}`;
  chatLogEl.appendChild(div);
  chatLogEl.scrollTop = chatLogEl.scrollHeight;
}

init();
