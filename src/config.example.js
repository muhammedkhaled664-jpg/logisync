/* =====================================================================
   CLIENT CONFIG TEMPLATE
   Copy this file to config.js and fill in per-client branding + Supabase keys.
   config.js is git-ignored so real keys never get committed.
   ===================================================================== */
window.CLIENT_CONFIG = {

  brandName:   "LogiSync",
  tagline:     "Operations Authentication",
  logoFile:    "logo.svg",
  reportTitle: "LogiSync Weekly Report",
  exportPrefix:"LogiSync",

  accentColor: "#0d9488",
  accentLight: "#14b8a6",

  // QA pass-rate target (%) — used to colour the monthly report green/red
  qaTarget: 90,

  supabase: {
    url: "https://YOUR-PROJECT-REF.supabase.co",
    key: "YOUR-ANON-PUBLIC-KEY"
  },

  agents: [
    "Agent One", "Agent Two"
  ],

  categories: [
    "Coaching", "Escalations", "Meetings", "Appointments",
    "Training", "Validation", "Daily", "Floor Support"
  ],

  categoryColors: [
    "#38bdf8", "#f43f5e", "#8b5cf6", "#f59e0b",
    "#14b8a6", "#ec4899", "#6366f1", "#84cc16"
  ],

  priorities: ["Normal", "High", "CRITICAL"],

  labels: {
    telemetry:     "Shift Telemetry",
    priorityFocus: "Priority Focus",
    threats:       "Threats",
    liveFeed:      "Floor Status",
    newInput:      "New Priority Input"
  },

  /* ---- Coaching tab dropdowns ---- */
  coaching: {
    issueTags: ["#SystemFocus", "#Fatal", "#Feedback", "#Sticking", "#Incomplete Survey"],
    teams: ["Agent One", "Agent Two"],
    notes: [
      "Final Documentation", "Feedback Session", "Fatal Documentation", "1st Documentation",
      "Verbal", "1st Warning", "2nd Warning", "3rd Warning", "No Action", "Action Plan",
      "Termination", "Hold", "System Tampering"
    ],
    statuses: ["Yes", "No", "Not Fail", "Disregarded", "Left", "need follow up"]
  }
};
