# Notes for App Review (draft)

Paste into App Store Connect › App Review Information › Notes.

---

SunClock is a clock and alarm app based on the sun's position. No account or sign-in is
needed, and the app makes no network requests.

**Location (When In Use, approximate).** Used only to calculate sunrise, sunset, twilight
and moon times on device. Location is never sent anywhere. Users can decline and enter a
location manually: Sun tab › location button (top right) › Manual.

**Alarms (AlarmKit).** Users create alarms relative to solar events, e.g. "30 min before
sunrise". Because solar times change daily, the app schedules each upcoming occurrence as
a fixed AlarmKit alarm, keeping about two weeks scheduled and refreshing on launch,
location or time-zone changes, and Background App Refresh. Snooze is 9 minutes.

**How to test an alarm quickly.**
1. Alarms tab › + .
2. Pick an event that is a few minutes away (the editor's footer shows "Next: …"), or pick
   any event and use Before/After to move it to a few minutes from now.
3. Save, allow alarms when prompted, and lock the device. The alarm rings at the shown
   time with Stop and Snooze.

**Background App Refresh** (`com.kray.circadian.refresh`) only recalculates and
reschedules alarms; it does no networking.

**Widgets and Apple Watch.** The Sun Ring widgets and Watch complications read the
location the app shares with them through its App Group; they show a "no location" icon
until the app has a location.

**Moon imagery** is NASA Scientific Visualization Studio's CGI Moon Kit (public domain,
credited in the app's README and listing).
