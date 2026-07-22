# App Review reply — Guideline 2.5.4 (Submission ad18c580-b2fd-4e24-a7b5-56501eb53b75)

Paste into App Store Connect → Resolution Center (English is fine for App Review).

---

Hello App Review Team,

Thank you for the feedback on Guideline 2.5.4 regarding `UIBackgroundModes` / location.

**Resolution**

We have removed the `location` value from the `UIBackgroundModes` key. The binary under review (1.0 build 8) still declared that mode; the corrected build does **not**.

HoursTracker does **not** perform persistent / continuous background location updates. Optional workplace arrival reminders use **Core Location region monitoring** (`CLCircularRegion` / geofencing) around a single user-saved workplace. The app never sets `allowsBackgroundLocationUpdates` and never calls continuous `startUpdatingLocation` for background tracking.

- **Set Location** in Settings: one-shot foreground capture (`requestLocation`) with When In Use.
- **Arrival reminders** (optional): region monitoring only; Always authorization is requested only so the geofence can wake the app on entry/exit.

Please review the new build **1.0 (15)** (or later) which omits `UIBackgroundModes: location`.

Thank you,
HoursTracker team

---

## Arabic (for your notes / internal)

رفضوا لأن البيلد القديم (1.0 بناء 8) كان فيه `UIBackgroundModes = location` بدون تتبع مستمر. عدّلنا: شلنا المفتاح، والتذكير عند الوصول يعتمد فقط على geofence (region monitoring). ارفعوا بيلد 15 وأرسلوا الرسالة الإنجليزية أعلاه في Resolution Center.
