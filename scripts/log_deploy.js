// log_deploy.js
// Sube un registro de deployment a la hoja "Deployments" del Google Sheet
// Uso: node log_deploy.js '<json>'

const fs   = require('fs');
const path = require('path');
const { google } = require('googleapis');

const SHEET_ID  = "1tMHhhksprea8DxD944oe6WV8Anez14OgVi8lJZ76Kb8";
const KEY_FILE  = "C:\\pizza_pipeline\\google_key.json";
const TAB_NAME  = "Deployments";
const HEADERS   = ["Fecha","Slug","Locacion","Estado","Python","Node","VC++","pip","npm","Tareas","Detalle"];

async function run() {
    const data = JSON.parse(process.argv[2] || "{}");

    if (!fs.existsSync(KEY_FILE)) {
        console.error("No existe google_key.json — log no subido.");
        process.exit(1);
    }

    const auth = new google.auth.GoogleAuth({
        keyFile: KEY_FILE,
        scopes: ["https://www.googleapis.com/auth/spreadsheets"]
    });

    const client = await auth.getClient();
    const sheets = google.sheets({ version: "v4", auth: client });

    // Crear hoja Deployments si no existe
    const ss = await sheets.spreadsheets.get({ spreadsheetId: SHEET_ID });
    const exists = ss.data.sheets.some(s => s.properties.title === TAB_NAME);

    if (!exists) {
        await sheets.spreadsheets.batchUpdate({
            spreadsheetId: SHEET_ID,
            requestBody: { requests: [{ addSheet: { properties: { title: TAB_NAME } } }] }
        });
        await sheets.spreadsheets.values.update({
            spreadsheetId: SHEET_ID,
            range: `${TAB_NAME}!A1`,
            valueInputOption: "RAW",
            requestBody: { values: [HEADERS] }
        });
    }

    const row = [
        data.fecha    || "",
        data.slug     || "",
        data.locacion || "",
        data.estado   || "",
        data.python   || "",
        data.node     || "",
        data.vcpp     || "",
        data.pip      || "",
        data.npm      || "",
        data.tareas   || "",
        data.detalle  || ""
    ];

    await sheets.spreadsheets.values.append({
        spreadsheetId: SHEET_ID,
        range: `${TAB_NAME}!A:K`,
        valueInputOption: "RAW",
        insertDataOption: "INSERT_ROWS",
        requestBody: { values: [row] }
    });

    console.log("Log de deployment subido OK.");
}

run().catch(err => {
    console.error("Error subiendo log:", err.message);
    process.exit(1);
});
