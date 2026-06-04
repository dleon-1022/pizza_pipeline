const fs = require('fs');
const path = require('path');
const moment = require('moment');
const { exec } = require('child_process');

  if (!process.argv[2]) {
    console.error('No location slug');
    return;
  }

// Get the S3 folder variable from command-line arguments, defaulting to "pcsapi-puerta" if not provided
const s3Folder = process.argv[2];

// Base directory where the pictures are stored
const baseDir = "C:\\Users\\gritseeuser1\\Pictures";

// Create a folder name based on today's date in "YYYY-MM-DD" format
const dateStr = moment().format("YYYY-MM-DD");
const dateFolder = path.join(baseDir, dateStr);

// 1. Create the folder if it doesn't already exist
if (!fs.existsSync(dateFolder)) {
  fs.mkdirSync(dateFolder, { recursive: true });
  console.log(`Created folder: ${dateFolder}`);
} else {
  console.log(`Folder already exists: ${dateFolder}`);
}

// 2. Move files that match the pattern "vlcsnap-*" into the date folder
fs.readdir(baseDir, (err, files) => {
  if (err) {
    console.error('Error reading directory:', err);
    return;
  }

  // Filter for files starting with "vlcsnap-"
  const vlcFiles = files.filter(file => file.startsWith("vlcsnap-"));

  if (vlcFiles.length === 0) {
    console.log("No vlcsnap files found.");
  } else {
    vlcFiles.forEach(file => {
      const oldPath = path.join(baseDir, file);
      const newPath = path.join(dateFolder, file);
      try {
        fs.renameSync(oldPath, newPath);
        console.log(`Moved file: ${file}`);
      } catch (error) {
        console.error(`Error moving file ${file}:`, error);
      }
    });
  }

  // 3. Upload the files to S3 using the AWS CLI sync command
  // The S3 destination path now uses the s3Folder variable:
  // "s3://gritsee-ensemble/<s3Folder>/quality/<date>"
  const awsCommand = `aws s3 sync --acl public-read "${dateFolder}" s3://gritsee-ensemble/${s3Folder}/quality/${dateStr}`;
  console.log(`Running command: ${awsCommand}`);
  
  exec(awsCommand, (error, stdout, stderr) => {
    if (error) {
      console.error(`Error executing AWS sync: ${error.message}`);
      return;
    }
    if (stderr) {
      console.error(`AWS sync stderr: ${stderr}`);
    }
    console.log('AWS sync output:');
    console.log(stdout);

// 4. Log the full S3 destination path for each uploaded file (including today's date)
try {
  const uploadedFiles = fs.readdirSync(dateFolder);
  console.log("Uploaded files:");
  uploadedFiles.forEach(file => {
    console.log(`https://gritsee-ensemble.s3.us-east-1.amazonaws.com/${s3Folder}/quality/${dateStr}/${file}`);
  });
} catch (readErr) {
  console.error("Error reading the date folder:", readErr);
}

  });
});
