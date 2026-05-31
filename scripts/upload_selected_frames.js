const fs   = require('fs');
const path = require('path');
const { exec } = require('child_process');

const s3Folder = process.argv[2] || "default";

// Camino B: ResNet selecciona frames buenos → YOLO los recorta → subimos crops
const selectedDir = "C:\\pizza_pipeline\\cropped_frames";
const uploadBase  = "C:\\pizza_pipeline\\uploads";
const reportFile  = "C:\\pizza_pipeline\\report.csv";

// Evita que una corrida sin imagenes o con fallo reutilice un CSV anterior.
try {
  if (fs.existsSync(reportFile)) {
    fs.unlinkSync(reportFile);
    console.log(`CSV anterior eliminado: ${reportFile}`);
  }
} catch (err) {
  console.error(`No se pudo limpiar CSV anterior: ${err.message}`);
  process.exit(1);
}

function getDateStr() {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;
}

function cleanOldUploads(base, keepDays = 3) {
  if (!fs.existsSync(base)) return;
  const cutoff = Date.now() - keepDays * 24 * 60 * 60 * 1000;
  for (const entry of fs.readdirSync(base)) {
    const full = path.join(base, entry);
    try {
      const stat = fs.statSync(full);
      if (stat.isDirectory() && stat.mtimeMs < cutoff) {
        fs.rmSync(full, { recursive: true, force: true });
        console.log(`Limpiado uploads antiguo: ${entry}`);
      }
    } catch (_) {}
  }
}

const date      = getDateStr();
const uploadDir = path.join(uploadBase, date);
fs.mkdirSync(uploadDir, { recursive: true });

const files = fs.readdirSync(selectedDir).filter(f =>
  /\.(jpg|jpeg|png)$/i.test(f)
);

if (files.length === 0) {
  console.log("No hay imagenes para subir.");
  process.exit(0);
}

console.log(`Preparando ${files.length} imagenes para subir...`);

for (const f of files) {
  fs.copyFileSync(path.join(selectedDir, f), path.join(uploadDir, f));
}

const cmd = `aws s3 sync --acl public-read "${uploadDir}" s3://gritsee-ensemble/${s3Folder}/quality/${date}`;
console.log("Subiendo a S3...");

exec(cmd, (err, stdout, stderr) => {
  if (err) {
    console.error("Error AWS:", err.message);
    process.exit(1);
  }
  if (stderr) console.error(stderr);
  console.log(stdout);

  // Generar CSV de esta corrida
  const rows = ["fecha,imagen,video,url\n"];
  for (const f of files) {
    const url   = `https://gritsee-ensemble.s3.us-east-1.amazonaws.com/${s3Folder}/quality/${date}/${f}`;
    const video = f.split("_frame_")[0];
    rows.push(`${date},${f},${video},${url}\n`);
  }
  fs.writeFileSync(reportFile, rows.join(""), "utf8");
  console.log(`CSV actualizado: ${reportFile}`);

  // Limpiar uploads locales de mas de 3 dias
  cleanOldUploads(uploadBase, 3);
  console.log("Uploads locales antiguos limpiados.");
});
