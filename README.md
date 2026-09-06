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
