// Account creation. Reachable only from the "New User?" button on /open.
// TODO: on submit —
//   1. dither the uploaded pfp client-side (canvas, 100x100)
//   2. create a Firebase Auth user with a synthesized internal email
//      (handle@ctrls.zip.internal) + the chosen password
//   3. write the profile doc (handle, pfp URL) to Firestore

const form = document.getElementById("create-form");

form.addEventListener("submit", (e) => {
  e.preventDefault();
  // TODO: implement steps above.
  console.log("create account (not yet implemented)");
});
