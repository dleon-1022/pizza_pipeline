const fs = require('fs');
const path = require('path');
const { exec } = require('child_process');

const s3Folder = process.argv[2] || "default";

const selectedDir = "C:\\pizza_pipeline\\cropped_frames";
const uploadBase = "C:\\pizza_pipeline\\uploads";
const reportFile = "C:\\pizza_pipeline\\report.csv";

function getDateStr() {
  const d = new Date();
  const yyyy = d.getFullYear();
  const mm = String(d.getMonth() + 1).padStart(2, '0');
  const dd = String(d.getDate()).padStart(2, '0');
  return `${yyyy}-${mm}-${dd}`;
}

const date = getDateStr();
const uploadDir = path.join(uploadBase, date);

if (!fs.existsSync(uploadDir)) {
  fs.mkdirSync(uploadDir, { recursive: true });
}

const files = fs.readdirSync(selectedDir).filter(f =>
  f.toLowerCase().endsWith(".jpg") ||
  f.toLowerCase().endsWith(".jpeg") ||
  f.toLowerCase().endsWith(".png")
);

if (files.length === 0) {
  console.log("No hay imágenes para subir");
  process.exit(0);
}

// copiar archivos al folder del día
for (const f of files) {
  fs.copyFileSync(
    path.join(selectedDir, f),
    path.join(uploadDir, f)
  );
}

const cmd = `aws s3 sync --acl public-read "${uploadDir}" s3://gritsee-ensemble/${s3Folder}/quality/${date}`;

console.log("Subiendo a S3...");

exec(cmd, (err, stdout, stderr) => {
  if (err) {
    console.error("Error AWS:", err.message);
    process.exit(1);
  }

  if (stderr) {
    console.error(stderr);
  }

  console.log(stdout);

  // Regenerar CSV SOLO con la corrida actual
  let rows = [];
  rows.push("fecha,imagen,video,url\n");

  for (const f of files) {
    const url = `https://gritsee-ensemble.s3.us-east-1.amazonaws.com/${s3Folder}/quality/${date}/${f}`;
    const video = f.split("_frame_")[0];
    rows.push(`${date},${f},${video},${url}\n`);
  }

  fs.writeFileSync(reportFile, rows.join(""), "utf8");

  console.log("CSV actualizado:", reportFile);
});