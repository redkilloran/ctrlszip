// Entry point for the site. Firebase is loaded via the CDN ESM build so
// there's no bundler/build step — this file is loaded directly as a
// <script type="module"> from index.html.

import { initializeApp } from "https://www.gstatic.com/firebasejs/10.12.2/firebase-app.js";
import { getFirestore } from "https://www.gstatic.com/firebasejs/10.12.2/firebase-firestore.js";
import { getAuth } from "https://www.gstatic.com/firebasejs/10.12.2/firebase-auth.js";
import { getStorage } from "https://www.gstatic.com/firebasejs/10.12.2/firebase-storage.js";
import { firebaseConfig } from "./firebase-config.js";

const app = initializeApp(firebaseConfig);
export const db = getFirestore(app);
export const auth = getAuth(app);
export const storage = getStorage(app);

// TODO: home page — load and render folders sorted by activity,
// excluding private folders.
console.log("CTRLS.zip booted. Firebase project:", firebaseConfig.projectId);
