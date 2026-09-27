# PlantDoctor AI — Data Policy

**Last updated:** 24 September 2026
**Version:** 1.0

This Data Policy describes, in practical terms, what data the Application
stores, where it lives, how long it is kept, and how you can delete it.
It supplements the [Privacy Policy](PRIVACY_POLICY.md).

## 1. Where your data lives

In the current version, all data is stored **on your device**:

| Data | Storage location |
| --- | --- |
| Scan history, saved plants, notes | Local SQLite database inside the app's private storage |
| Plant photos and working images | Files in the app's private documents directory |
| App preferences (e.g., whether to show the disclaimer) | Local preferences storage |

**No data is uploaded to a server in the current version.** Analysis runs
entirely on the device.

## 2. What is stored when you use the app

| When you… | What is stored |
| --- | --- |
| Capture/select photos | Copies of your images (originals if saved) plus downscaled working copies used for analysis and display |
| Save a check-up | Scan record: date, photo thumbnails, identified-name guess, confidence, health index, condition labels, observed indicators, possible causes, follow-up answers, notes |
| Save a plant | Plant record: name, species, date added, photo, health index, notes |
| Answer follow-up questions | Your optional answers (e.g., location, watering, timeline) stored with the scan |

## 3. Retention

- Saved scans and plants are kept **until you delete them** or uninstall the app.
- Uninstalling the Application deletes its local database and stored photos.
- The current version does not run analytics, so there is no analytics data
  to retain.
- Data is not retained on any server because no data is sent to a server.

## 4. Your control over data

You can delete data yourself:

- **History** → open a scan → delete (removes that check-up).
- **My Plants** → open a plant → delete (removes the saved plant).
- Settings → clear app data (Android system feature) removes everything at once.

## 5. Device permissions

| Permission | Why it is used |
| --- | --- |
| Camera | To capture plant photos that you explicitly request |
| Gallery/Photos | To let you select images you uploaded/own |

Permissions are used only for the feature you trigger. Photos are not
transmitted anywhere.

## 6. Offline behaviour

- The Application works fully offline.
- If a future version introduces an online AI feature, that feature will be
  isolated, will notify you when an image would be sent, and will fail
  gracefully (with a clear message) if there is no internet connection.

## 7. Future changes

If the Application ever introduces server-side processing, this Data Policy
and the Privacy Policy will be updated **before** the change ships, and the new
behaviour will be clearly described in the Application.

## 8. Contact

For any data-deletion, correction, export or support request:

- **Email:** vanshdhimang9@gmail.com
- **Owner:** Vansh Dhiman (VanshDev)
- **Location:** Karnal, Haryana, India