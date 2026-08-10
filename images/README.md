# Images folder

Screenshots for the CurseForge description page. This folder is excluded from
the addon download (see .pkgmeta) - it's for the GitHub/CurseForge page only,
players never receive these files.

## Adding a screenshot
1. Save your screenshot here, named simply (e.g. gather-tally.png, route-compass.png).
2. Copy this whole addon folder into Repos, same as any other update.
3. Commit and push in GitHub Desktop like normal.

## Getting the link to use in the description
1. On GitHub.com, open this repo, click into the `images` folder, click the image file.
2. Click the "..." menu (or the download/raw button) and choose "Download raw file" -
   copy that page's URL from your browser's address bar.
3. Use it in markdown like this:
   ![Gather Tally](https://raw.githubusercontent.com/USERNAME/REPO/main/images/gather-tally.png)
