const https = require("https");

const TOKEN = process.env.SUPABASE_TOKEN;
const REF = "fyvotlygsmqmkxwpcrzf";
const query = process.argv[2];

const body = JSON.stringify({ query });

const req = https.request(
  {
    hostname: "api.supabase.com",
    path: `/v1/projects/${REF}/database/query`,
    method: "POST",
    headers: {
      Authorization: `Bearer ${TOKEN}`,
      "Content-Type": "application/json",
      "Content-Length": Buffer.byteLength(body),
    },
  },
  (res) => {
    let data = "";
    res.on("data", (c) => (data += c));
    res.on("end", () => {
      console.log(data);
    });
  }
);
req.on("error", (e) => console.error(e));
req.write(body);
req.end();
