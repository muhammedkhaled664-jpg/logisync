const { execSync } = require("child_process");
const fs = require("fs");
const path = require("path");

const DEPLOYMENT_ID = "dpl_9WVekLx4jZtoQMMCJEvgjAJsDTN3";

const files = {
  "src/config.js": "f3b10ed05ac82e981dc32ebc6ebf856716da2f8a",
  "src/index.html": "bba9d3aea26b04f19254e7a09050ec507878f488",
  "src/logo.png": "b614af93c766c5aefdc72cba76f0d15920191fdc",
  "src/logo.svg": "0af01ab0650716e5f58f31d5133facb27df39691",
  "src/manifest.webmanifest": "484e636d0c5ddbd8e6d96bcd5d10bcf0db49dd84",
  "src/sw.js": "17555e354f2db12ce56e22a0cf73a8df80bbac24",
  "src/tailwind.build.css": "694d58d16352d499eb7d8a5eed6e6bdb1f7938fd",
};

for (const [relPath, uid] of Object.entries(files)) {
  const cmd = `vercel api "/v7/deployments/${DEPLOYMENT_ID}/files/${uid}"`;
  const out = execSync(cmd, {
    encoding: "utf8",
    env: { ...process.env, MSYS_NO_PATHCONV: "1" },
    maxBuffer: 1024 * 1024 * 50,
  });
  const jsonStart = out.indexOf("{");
  const parsed = JSON.parse(out.slice(jsonStart));
  const buf = Buffer.from(parsed.data, "base64");
  const outPath = path.join(__dirname, "..", relPath);
  fs.mkdirSync(path.dirname(outPath), { recursive: true });
  fs.writeFileSync(outPath, buf);
  console.log(`wrote ${relPath} (${buf.length} bytes)`);
}
