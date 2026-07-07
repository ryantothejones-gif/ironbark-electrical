/* Ironbark Electrical — shared page behaviour.
   Loaded at the end of <body>, so the DOM already exists when it runs. */

// ---------- Mobile nav toggle ----------
const navToggle = document.querySelector(".nav-toggle");
const navLinks = document.querySelector(".nav-links");

navToggle.addEventListener("click", () => {
  const isOpen = navLinks.classList.toggle("open");
  navToggle.setAttribute("aria-expanded", String(isOpen));
});

// Close the mobile menu when a link inside it is clicked
navLinks.addEventListener("click", (event) => {
  if (event.target.matches("a")) {
    navLinks.classList.remove("open");
    navToggle.setAttribute("aria-expanded", "false");
  }
});

// ---------- Footer year ----------
document.querySelectorAll("#year").forEach((el) => {
  el.textContent = new Date().getFullYear();
});

// ---------- Scroll-reveal ----------
// IntersectionObserver fires a callback whenever a watched element
// enters the viewport; we add .visible once and stop watching it.
const revealEls = document.querySelectorAll(".reveal");
const revealAll = () => revealEls.forEach((el) => el.classList.add("visible"));

if ("IntersectionObserver" in window) {
  let observerFired = false;

  const revealObserver = new IntersectionObserver(
    (entries) => {
      observerFired = true;
      for (const entry of entries) {
        if (entry.isIntersecting) {
          entry.target.classList.add("visible");
          revealObserver.unobserve(entry.target);
        }
      }
    },
    { threshold: 0.12 }
  );

  revealEls.forEach((el) => revealObserver.observe(el));

  // A working observer reports initial state almost immediately after
  // observe(). If it stays silent (some embedded webviews), give up on
  // the animation and show everything rather than leave content hidden.
  setTimeout(() => {
    if (!observerFired) revealAll();
  }, 800);
} else {
  revealAll();
}

// ---------- Contact form ----------
// The form POSTs to Formspree (see contact.html `action`), which emails the
// submission with no backend of our own. We submit via fetch() so the visitor
// stays on the page and sees an inline success message instead of a redirect.
//
// Until a real Formspree ID is pasted in, the action still contains the
// YOUR_FORM_ID placeholder. In that state we skip the network call and just
// show the success state so the demo works offline — but we console.warn so a
// real site can never silently ship a form that emails nobody.
const form = document.getElementById("quote-form");

if (form) {
  const successEl = document.getElementById("form-success");
  const errorEl = document.getElementById("form-error");
  const submitBtn = form.querySelector("button[type=submit]");
  const submitLabel = submitBtn ? submitBtn.textContent : "";
  const PLACEHOLDER = "YOUR_FORM_ID";

  const show = (el) => el && el.classList.add("show");
  const hide = (el) => el && el.classList.remove("show");

  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    hide(errorEl);

    // Trigger the browser's built-in validation UI for required fields
    if (!form.reportValidity()) return;

    // Demo mode: no real endpoint wired up yet.
    if (form.action.includes(PLACEHOLDER)) {
      console.warn(
        "[contact form] Formspree endpoint not set — showing demo success only. " +
          "Replace YOUR_FORM_ID in contact.html before going live (see GO-LIVE.md)."
      );
      show(successEl);
      if (submitBtn) submitBtn.disabled = true;
      return;
    }

    if (submitBtn) {
      submitBtn.disabled = true;
      submitBtn.textContent = "Sending…";
    }

    try {
      const res = await fetch(form.action, {
        method: "POST",
        body: new FormData(form),
        headers: { Accept: "application/json" },
      });

      if (res.ok) {
        form.reset();
        show(successEl);
        if (submitBtn) submitBtn.textContent = "Sent ✓";
      } else {
        throw new Error("Formspree responded " + res.status);
      }
    } catch (err) {
      console.error("[contact form] submit failed:", err);
      show(errorEl);
      if (submitBtn) {
        submitBtn.disabled = false;
        submitBtn.textContent = submitLabel;
      }
    }
  });
}
