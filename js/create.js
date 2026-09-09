// Account creation. Reachable only from the "New User?" button on /open.
import { supabase, emailForHandle } from "./supabaseClient.js";
import { ditherImage } from "./dither.js";

const form = document.getElementById("create-form");
const statusEl = document.getElementById("create-status");

function setStatus(msg) {
  statusEl.textContent = msg;
}

form.addEventListener("submit", async (e) => {
  e.preventDefault();

  const handle = document.getElementById("handle").value.trim().toLowerCase();
  const password = document.getElementById("password").value;
  const pfpFile = document.getElementById("pfp").files[0];

  if (!/^[a-z0-9_]{3,20}$/.test(handle)) {
    setStatus("Handles must be 3–20 characters: lowercase letters, numbers, underscores only.");
    return;
  }

  setStatus("Creating account…");

  const { data: signUpData, error: signUpError } = await supabase.auth.signUp({
    email: emailForHandle(handle),
    password,
  });

  if (signUpError) {
    setStatus(`Couldn't create account: ${signUpError.message}`);
    return;
  }

  if (!signUpData.session) {
    setStatus(
      "Account created, but no session came back — check that \"Confirm email\" " +
        "is turned off in the Supabase dashboard (Authentication > Providers > Email)."
    );
    return;
  }

  const userId = signUpData.user.id;
  let pfpUrl = null;

  if (pfpFile) {
    setStatus("Dithering your picture…");
    const ditheredBlob = await ditherImage(pfpFile, 100, 100);
    const path = `${userId}/avatar.png`;

    const { error: uploadError } = await supabase.storage
      .from("media")
      .upload(path, ditheredBlob, { contentType: "image/png", upsert: true });

    if (uploadError) {
      setStatus(`Account created, but the picture upload failed: ${uploadError.message}`);
    } else {
      const { data: publicUrlData } = supabase.storage.from("media").getPublicUrl(path);
      pfpUrl = publicUrlData.publicUrl;
    }
  }

  setStatus("Saving profile…");

  const { error: profileError } = await supabase
    .from("profiles")
    .insert({ id: userId, handle, pfp_url: pfpUrl });

  if (profileError) {
    setStatus(`Account created, but the profile couldn't be saved: ${profileError.message}`);
    return;
  }

  setStatus("Account created! Go back to the other tab to claim your folder.");
});
