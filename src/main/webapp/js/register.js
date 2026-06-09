/* ===========================================================================
   register.js — submits the form to /api/register and shows feedback inline
   =========================================================================== */

(function () {
  const form     = document.getElementById("registration-form");
  const feedback = document.getElementById("form-feedback");
  const submitBtn= document.getElementById("submit-btn");

  if (!form) return;

  form.addEventListener("submit", async function (evt) {
    evt.preventDefault();
    clearFeedback();

    const studentName = form.studentName.value.trim();
    const studentNo   = form.studentNo.value.trim();
    const workshop    = form.workshop.value;

    // Client-side validation
    if (!studentName || !studentNo) {
      showFeedback("err", "Please fill in both Student Name and Student No.");
      return;
    }

    setSubmitting(true);

    try {
      const res = await fetch("api/register", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ studentName, studentNo, workshop }),
      });

      const data = await res.json().catch(() => ({}));

      if (res.ok && data.status === "ok") {
        showFeedback(
          "ok",
          `✓ Registration received (ID #${data.id}). You will be contacted by the training coordinator.`
        );
        form.reset();
      } else {
        showFeedback(
          "err",
          data.message || "Something went wrong. Please try again."
        );
      }
    } catch (err) {
      showFeedback("err", "Network error — please check your connection.");
    } finally {
      setSubmitting(false);
    }
  });

  function showFeedback(kind, msg) {
    feedback.className = "form-feedback show " + kind;
    feedback.textContent = msg;
  }
  function clearFeedback() {
    feedback.className = "form-feedback";
    feedback.textContent = "";
  }
  function setSubmitting(isSubmitting) {
    submitBtn.disabled = isSubmitting;
    submitBtn.textContent = isSubmitting ? "Submitting…" : "Submit Registration";
  }
})();
