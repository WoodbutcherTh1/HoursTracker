# Privacy Policy — HoursTracker

**Last updated:** 29 August 2026

HoursTracker (“the App”) is a personal work-hours companion for a single worker. This policy explains what data the App stores and how it is used.

## Who we are
HoursTracker is provided by the app developer for personal timesheet and pay estimation use.

## Data we store on your device
The App stores the following on your iPhone/iPad only (unless you explicitly enable iCloud sync in Settings):

- Worker profile you enter (name, ID number, employee number)
- Workplace name, contractor name, pay rates, and tax-related settings you enter
- Work sessions (clock-in/out times, breaks, notes, day type)
- Optional workplace coordinates you choose when tapping **Set Location**
- Timesheet and payslip images you choose to import (processed on-device by default; see **Smart Scanner cloud extraction** below for the optional exception)
- Payslip files you upload, and the pay figures extracted from them

Your national ID number is kept in the device Keychain and is not uploaded to iCloud.

## Cloud AI features (optional, off by default)

By default, timesheet and payslip scanning happens entirely on-device using Apple's Vision framework and a local heuristic — nothing is uploaded. If you turn on **Smart Scanner cloud extraction** in Settings and provide your own API key, the recognized text (not the image or PDF itself) is sent to a third-party AI provider you choose — **Google Gemini** or an OpenAI-compatible service such as Groq — to more accurately structure the data. This text can include employer name, employee name, and pay figures. It is sent directly from your device to that provider over an encrypted connection; we do not see or store it. Your API key is kept in the device Keychain. This feature stays off until you turn it on.

The same setting and the same API key also power the in-app **Assistant** (the icon in the navigation bar). When it is on, the exact question you type into the Assistant, plus today's date, is sent to that same provider — solely so the provider can tell the app which built-in report to run. Your shifts, pay, employer, name, and payslips are **not** sent: every figure in an answer is calculated on your device from your own records. If you turn **Smart Scanner cloud extraction** off, the Assistant stops sending anything and reports itself as unavailable.

## iCloud sync (optional)
iCloud sync is **off by default**. If you turn on **Sync with iCloud** in Settings (only available in builds that include CloudKit), work sessions and workplace settings are stored in **your** private iCloud database under your Apple ID. We do not operate a server that receives this data. Turning sync off offers to delete already-uploaded iCloud copies. **Delete All My Data** also erases local data and, when sync is available, your private iCloud copies.

## Location
- **While Using:** used only when you tap **Set Location** to save your workplace.
- **Always:** used only if you enable **Arrival reminders**. Then the App monitors a single geofence around your saved workplace (region monitoring) to remind you to clock in on arrival. The App does **not** use the continuous background-location mode, does **not** continuously track your movements, and does **not** sell location data.

## Camera & Photos
Used only when you import a timesheet photo or screenshot. Processing uses Apple’s on-device Vision frameworks.

## Tracking & advertising
The App does **not** track you across apps or websites, does **not** show ads, and does **not** use third-party analytics SDKs.

## Sharing
We do not sell your data. Data stays on your device and, only if you enable iCloud sync, in your personal iCloud account under Apple’s terms. If you separately opt into **Smart Scanner cloud extraction**, recognized document text — and any question you type into the Assistant — is sent to the third-party AI provider you configure — see **Cloud AI features** above.

## Your controls
In **Settings** you can:

- Edit or clear profile fields
- Turn off arrival reminders
- Turn iCloud sync on or off (and delete iCloud copies when turning off)
- Turn Smart Scanner cloud extraction on or off (this also enables/disables the cloud Assistant), and remove your saved API key(s)
- Hide the Assistant button, or leave it on but never use it — it only contacts the network when you send a question
- Delete individual shifts
- Use **Delete All My Data** to erase sessions, settings, logs, and iCloud copies when sync is available

## Children
The App is not directed at children under 13.

## Contact
For privacy questions, contact the developer via the support email shown in the App’s Settings → About & Legal section.

## Changes
We may update this policy. The “Last updated” date above will change when we do.
