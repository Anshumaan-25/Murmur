# Keydown download website

Run `python3 website/preview.py` from the repository and open the printed HTML file. The preview links only the two release artifacts on this Mac. No server or network is required for the layout, example, installer, or checksum.

For GitHub Pages, publish only `website/dist/` as the Pages artifact. First upload the DMG and its checksum to the matching GitHub Release and verify that both exact links in index.html work signed out. The current tag is v0.2.12-beta.1. The local preview directory is private build output and must never be deployed.

## Website analytics at launch

The public site uses the anshumaan GoatCounter account. The staging script clears the site code in local previews. The website requests the analytics script only on HTTPS and honors Do Not Track and Global Privacy Control. No analytics code is included in Keydown.

In the GoatCounter dashboard, use page views and estimated unique visitors for the landing page, and the download-mac-beta event for button clicks. The share of visitors who clicked can be estimated by comparing unique visitors for the event and the page over the same period. Script blockers and privacy settings affect the totals. GitHub Release asset download counts are a separate signal. None of these confirms an installation.
