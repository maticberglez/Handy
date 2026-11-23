use std::{
    fs::{self, File},
    io::{Read, Seek, SeekFrom},
    path::PathBuf,
    process::{Command, Stdio},
    sync::Mutex,
};

static UPDATE: Mutex<(bool, Option<bool>)> = Mutex::new((false, None));

fn source_root() -> PathBuf {
    PathBuf::from(
        option_env!("HANDY_SOURCE_ROOT").unwrap_or(concat!(env!("CARGO_MANIFEST_DIR"), "/..")),
    )
}

#[derive(serde::Serialize, specta::Type)]
pub struct CustomUpdateStatus {
    available: bool,
    running: bool,
    success: Option<bool>,
    log: String,
}

#[tauri::command]
#[specta::specta]
pub fn custom_update_status() -> Result<CustomUpdateStatus, String> {
    let state = UPDATE.lock().map_err(|e| e.to_string())?;
    let root = source_root();
    let mut bytes = Vec::new();
    if let Ok(mut file) = File::open(root.join(".custom-updates.local/ui-update.log")) {
        let len = file.metadata().map_err(|e| e.to_string())?.len();
        file.seek(SeekFrom::Start(len.saturating_sub(32768)))
            .map_err(|e| e.to_string())?;
        file.read_to_end(&mut bytes).map_err(|e| e.to_string())?;
    }
    Ok(CustomUpdateStatus {
        available: cfg!(target_os = "macos")
            && root.join("scripts/update-custom-handy.sh").is_file(),
        running: state.0,
        success: state.1,
        log: String::from_utf8_lossy(&bytes).into_owned(),
    })
}

#[tauri::command]
#[specta::specta]
pub fn start_custom_update() -> Result<(), String> {
    let mut state = UPDATE.lock().map_err(|e| e.to_string())?;
    if state.0 {
        return Err("An update is already running.".into());
    }
    let root = source_root();
    let script = root.join("scripts/update-custom-handy.sh");
    if !cfg!(target_os = "macos") || !script.is_file() {
        return Err("The custom update script is unavailable.".into());
    }
    fs::create_dir_all(root.join(".custom-updates.local")).map_err(|e| e.to_string())?;
    let log = File::create(root.join(".custom-updates.local/ui-update.log"))
        .map_err(|e| e.to_string())?;
    let stderr = log.try_clone().map_err(|e| e.to_string())?;
    let mut child = Command::new("/bin/bash")
        .arg(script)
        .current_dir(root)
        .stdin(Stdio::null())
        .stdout(Stdio::from(log))
        .stderr(Stdio::from(stderr))
        .spawn()
        .map_err(|e| e.to_string())?;
    *state = (true, None);
    std::thread::spawn(move || {
        let success = child.wait().map(|s| s.success()).unwrap_or(false);
        if let Ok(mut state) = UPDATE.lock() {
            *state = (false, Some(success));
        }
    });
    Ok(())
}
