const fs = require('fs');
const path = require('path');
const { google } = require('googleapis');

console.log("=== upload_to_sheets.js (PROD) ===");

const SHEET_ID = "1tMHhhksprea8DxD944oe6WV8Anez14OgVi8lJZ76Kb8";
const SHEET_NAME = "mirasierra2";

const KEY_FILE = path.join(__dirname, "google_key.json");
const CSV_FILE = path.join(__dirname, "report.csv");

async function upload() {
  console.log("Iniciando upload a Google Sheets...");

  if (!fs.existsSync(KEY_FILE)) {
    console.error(`No existe google_key.json en: ${KEY_FILE}`);
    process.exit(1);
  }

  if (!fs.existsSync(CSV_FILE)) {
    console.log("No existe report.csv, nada que subir.");
    process.exit(0);
  }

  const csv = fs.readFileSync(CSV_FILE, "utf8").trim();

  if (!csv) {
    console.log("report.csv está vacío.");
    process.exit(0);
  }

  let rows = csv
    .split(/\r?\n/)
    .map(line => line.trim())
    .filter(line => line.length > 0)
    .map(line => line.split(","));

  if (rows.length === 0) {
    console.log("No hay filas para subir.");
    process.exit(0);
  }

  if (
    rows[0].length >= 4 &&
    rows[0][0].toLowerCase() === "fecha" &&
    rows[0][1].toLowerCase() === "imagen"
  ) {
    rows = rows.slice(1);
  }

  if (rows.length === 0) {
    console.log("No hay datos nuevos para subir.");
    process.exit(0);
  }

  const formattedRows = rows.map(r => {
    const fecha = r[0] || "";
    const imagen = r[1] || "";
    const video = r[2] || "";
    const url = r[3] || "";

    return [
      fecha,
      imagen,
      video,
      url ? `=HYPERLINK("${url}", "${url}")` : ""
    ];
  });

  console.log(`Filas a subir: ${formattedRows.length}`);

  const auth = new google.auth.GoogleAuth({
    keyFile: KEY_FILE,
    scopes: ["https://www.googleapis.com/auth/spreadsheets"],
  });

  const client = await auth.getClient();
  const sheets = google.sheets({ version: "v4", auth: client });

  await sheets.spreadsheets.values.append({
    spreadsheetId: SHEET_ID,
    range: `${SHEET_NAME}!A:D`,
    valueInputOption: "USER_ENTERED",
    insertDataOption: "INSERT_ROWS",
    requestBody: {
      values: formattedRows,
    },
  });

  console.log(`✅ Google Sheets actualizado correctamente en hoja: ${SHEET_NAME}`);
}

upload().catch(err => {
  console.error("❌ Error subiendo a Google Sheets:");
  console.error(err && err.stack ? err.stack : err);
  process.exit(1);
});