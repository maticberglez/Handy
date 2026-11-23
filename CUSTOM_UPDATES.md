# Updating your custom Handy

Click **Update Custom Handy** in the footer, then the update button in its panel. It shows progress and a **Copy log / error** button. You can also double-click `Update Custom Handy.command`.

The updater checks the latest official release and your committed custom source against the installed app. If they match, it reports **Already up to date** without building anything. Otherwise it merges in a separate folder, runs lint, translations, Rust formatting and the production build, verifies the signed app, and installs directly into `/Applications/Handy.app`. No preview app is created. The existing `com.maticberglez.handy.custom` identifier keeps your settings and models.

After installation Handy restarts automatically. The updater runs separately so quitting the old app does not interrupt installation. Its result and log persist across the restart. Conflicts are listed and the merge is aborted; failed checks stop before replacing the app. Installation errors restore the previous app when it has already been replaced. An immediate launch failure also restores it; passing checks cannot guarantee that every feature behaves correctly.

Previous app builds and settings backups are kept in `.custom-updates.local/rollback`. Logs and merged source are kept in the update attempt's folder. Successful installation fast-forwards your original checkout to the merged history. Commit all changes before updating; edits made while a build runs stop installation.

Rust dependencies are reused through `.custom-updates.local/target`. This may be a symlink to an older build folder: keep that folder. New updates still need to compile the changed application code.

If anything needs attention, use **Copy log / error** and send the log for help. If the updater is forcibly terminated, remove `.custom-updates.local/running.lock` only after confirming it is no longer running.

Prerequisites without downloading or installing:

```sh
bash scripts/update-custom-handy.sh --check
```
