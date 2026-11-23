# Updating your custom Handy

In a build containing the new button, click **Update Custom Handy** in the footer. Its panel shows progress, success or failure, and a **Copy log / error** button. Closing the panel does not stop the update. You can also double-click `Update Custom Handy.command` in this folder. You can drag it to the Dock (on the folder side) or make a Finder alias on your Desktop.

The launcher downloads the latest published official release, merges it with your committed custom code in `.custom-updates.local`, runs checks, and builds **Handy Update Preview**. Finder selects the finished app. It never installs over everyday Handy or changes your original branch.

Quit everyday Handy before opening the preview to avoid shortcut conflicts. Preview uses `com.maticberglez.handy.preview`, with separate settings and model selection. It may share settings with your existing development preview.

If a merge or check fails, the Terminal window explains why and shows the working folder. Its `update.log` contains the details. Ask for help with that folder; the launcher does not guess how to fix conflicts. If the launcher is forcibly interrupted, remove `.custom-updates.local/running.lock` after confirming no update is running.

Commit custom source changes before updating. Ignored files (including local build configuration) are not merged. The launcher intentionally supplies its own preview configuration. Build dependencies are cached in `.custom-updates.local/target`; the first run reuses an existing completed build through a symlink when available. Keep the old folder targeted by that symlink. Unchanged releases and custom commits skip the build. Each attempt retains its merged source and log. Conflicting merges are aborted after listing the affected files.

After testing, ask to adopt the update. Build the merged source with the everyday custom configuration and the existing `com.maticberglez.handy.custom` identifier, then replace the everyday app. Keep the merged Git history for future development. This final installation is intentionally manual.

To check prerequisites without downloading or building:

```sh
bash scripts/update-custom-handy.sh --check
```
