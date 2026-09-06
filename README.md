# HOS 150 ELD V3

Ground-up driver workflow prototype combining ELD-style HOS logging with 150-air-mile tracking.

Included:
- Dashboard with 11-hour, 14-hour and cycle clocks
- OFF DUTY / SLEEPER / DRIVING / ON DUTY
- 24-hour RODS-style graph
- Event history and annotations
- Browser GPS
- 150-air-mile radius map
- Destination radius checker
- Reporting-location setup
- 140-mile boundary warning
- HOS warnings
- Pre-trip and post-trip inspections
- Short-haul/daily records
- Cycle recap and CSV export
- Roadside inspection mode
- Driver/carrier/unit/USDOT/VIN/trailer fields
- Print/save-PDF daily log
- Local browser storage / offline-ready UI

IMPORTANT:
This is a prototype and is NOT an FMCSA-certified ELD. It does not yet connect to the truck ECM and does not replace a certified ELD. A production system needs compliant ECM/vehicle synchronization, required ELD event/data formats, security, diagnostics, malfunction handling, transfer, certification/testing, and other regulatory requirements.

The 150-air-mile boundary is an assistant feature. Being inside 150 air miles alone does not establish eligibility for a short-haul exception.


## V4 automatic GPS motion prototype

The V4 prototype adds phone GPS motion logic:
- GPS speed >= 5 mph -> automatically records DRIVING while a shift is active.
- When stopped while DRIVING, a configurable stop timer starts.
- Default stop timer is 5 minutes; when it expires, the prototype automatically changes to ON DUTY.
- Current GPS speed and automatic-motion state are shown on the dashboard.

IMPORTANT: phone GPS is for prototyping and cannot substitute for required ECM/vehicle synchronization in a certified FMCSA ELD. FMCSA requires automatic driving detection from the vehicle/ELD system and specifies a driving threshold not greater than 5 mph. Under FMCSA guidance, after 5 consecutive minutes stopped while in Driving, the compliant ELD prompts the driver; if there is no response within one minute, it changes to On-Duty Not Driving. The 2-minute setting here is therefore a configurable prototype behavior, not a claim of compliance.


## V6 timer fix
Duty-status timers now accumulate each completed status segment. Switching from Driving to On Duty, Sleeper, or Off Duty stops the previous timer and starts the new one without resetting the previous status total. The 11-hour driving clock also uses accumulated driving segments rather than resetting on each button press.


## V7 reporting-location display fix
The dashboard no longer incorrectly says "Set your normal reporting location" when a reporting location is already saved but phone GPS is unavailable. It now separately reports:
- reporting location saved + GPS unavailable, or
- reporting location saved + live distance/inside/outside radius.
The saved location is restored from local device storage on reload.


## V8 location permission gate
On app launch, V8 immediately checks phone location permission. If location is unavailable or permission is denied, the app shows a full-screen Location Services Required prompt with an Enable Location button and iPhone instructions. The app cannot switch iPhone Location Services on itself; the user must grant the browser/app permission.
