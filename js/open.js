// /open — folder key redemption + folder claim flow.
// TODO: wire up to a Supabase "folder_keys" table once the schema is in
// place (the dev portal will be what generates these rows).

const form = document.getElementById("redeem-form");
const usernameStep = document.getElementById("username-step");
const newUserBtn = document.getElementById("new-user-btn");

form.addEventListener("submit", (e) => {
  e.preventDefault();
  // TODO: look up the entered key in Supabase, confirm it's unclaimed.
  usernameStep.hidden = false;
});

newUserBtn.addEventListener("click", () => {
  // New-user account creation only happens via this button, in a new tab.
  window.open("create.html", "_blank");
});
