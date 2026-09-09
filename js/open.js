// /open — folder key redemption + folder claim + customize flow.
import { supabase, emailForHandle } from "./supabaseClient.js";
import { ditherImage } from "./dither.js";

const keyStep = document.getElementById("key-step");
const authStep = document.getElementById("auth-step");
const customizeStep = document.getElementById("customize-step");
const statusEl = document.getElementById("open-status");

const keyForm = document.getElementById("key-form");
const loginForm = document.getElementById("login-form");
const newUserBtn = document.getElementById("new-user-btn");
const recheckBtn = document.getElementById("recheck-btn");
const customizeForm = document.getElementById("customize-form");
const customizeStatus = document.getElementById("customize-status");

let pendingCode = null;
let claimedFolder = null;

function setStatus(msg) {
  statusEl.textContent = msg;
}

keyForm.addEventListener("submit", async (e) => {
  e.preventDefault();
  pendingCode = document.getElementById("folder-key").value.trim().toUpperCase();
  keyStep.hidden = true;

  const { data: { session } } = await supabase.auth.getSession();
  if (session) {
    await claimFolder();
  } else {
    authStep.hidden = false;
  }
});

async function claimFolder() {
  setStatus("Claiming your folder…");

  const { data, error } = await supabase.rpc("redeem_folder_key", {
    p_code: pendingCode,
    p_codename: null,
    p_cover_photo_url: null,
  });

  if (error) {
    setStatus(`Couldn't claim that folder: ${error.message}`);
    authStep.hidden = false;
    return;
  }

  claimedFolder = data;
  authStep.hidden = true;
  customizeStep.hidden = false;
  setStatus("");
}

loginForm.addEventListener("submit", async (e) => {
  e.preventDefault();
  const handle = document.getElementById("login-handle").value.trim().toLowerCase();
  const password = document.getElementById("login-password").value;

  setStatus("Logging in…");
  const { error } = await supabase.auth.signInWithPassword({
    email: emailForHandle(handle),
    password,
  });

  if (error) {
    setStatus(`Couldn't log in: ${error.message}`);
    return;
  }

  await claimFolder();
});

newUserBtn.addEventListener("click", () => {
  window.open("create.html", "_blank");
});

recheckBtn.addEventListener("click", async () => {
  const { data: { session } } = await supabase.auth.getSession();
  if (session) {
    await claimFolder();
  } else {
    setStatus("Still not seeing an account in this tab — try again once you've finished creating one.");
  }
});

// If the account gets created in the other tab, Supabase's session token
// changes in localStorage, so this tab picks it up via a "storage" event
// without the user needing to click "Continue" themselves.
window.addEventListener("storage", async (e) => {
  if (!authStep.hidden && e.key && e.key.startsWith("sb-")) {
    const { data: { session } } = await supabase.auth.getSession();
    if (session) await claimFolder();
  }
});

customizeForm.addEventListener("submit", async (e) => {
  e.preventDefault();
  customizeStatus.textContent = "Saving…";

  const codename = document.getElementById("codename").value.trim();
  const coverFile = document.getElementById("cover-photo").files[0];
  let coverPhotoUrl = null;

  if (coverFile) {
    const { data: { session } } = await supabase.auth.getSession();
    const ditheredBlob = await ditherImage(coverFile, 440);
    const path = `${session.user.id}/cover-${claimedFolder.id}.png`;

    const { error: uploadError } = await supabase.storage
      .from("media")
      .upload(path, ditheredBlob, { contentType: "image/png", upsert: true });

    if (uploadError) {
      customizeStatus.textContent = `Couldn't upload cover photo: ${uploadError.message}`;
    } else {
      const { data: publicUrlData } = supabase.storage.from("media").getPublicUrl(path);
      coverPhotoUrl = publicUrlData.publicUrl;
    }
  }

  const update = { codename };
  if (coverPhotoUrl) update.cover_photo_url = coverPhotoUrl;

  const { error } = await supabase.from("folders").update(update).eq("id", claimedFolder.id);

  if (error) {
    customizeStatus.textContent = `Couldn't save: ${error.message}`;
    return;
  }

  customizeStatus.textContent = "Saved! Your folder is ready. (Folder browsing UI comes next.)";
});
