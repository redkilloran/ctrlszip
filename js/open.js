// /open — folder key redemption + folder claim flow.
// TODO: wire up to Firestore once the "folder keys" collection schema is
// in place (dev portal will be what generates these).

const form = document.getElementById("redeem-form");
const usernameStep = document.getElementById("username-step");
const newUserBtn = document.getElementById("new-user-btn");

form.addEventListener("submit", (e) => {
  e.preventDefault();
  // TODO: look up the entered key in Firestore, confirm it's unclaimed.
  usernameStep.hidden = false;
});

newUserBtn.addEventListener("click", () => {
  // New-user account creation only happens via this button, in a new tab.
  window.open("create.html", "_blank");
});
