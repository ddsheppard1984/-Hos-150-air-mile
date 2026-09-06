# HOS 150 ELD V2 Prototype

This is a ground-up prototype combining the requested:
- ELD-style driver workflow
- HOS clocks and duty statuses
- 24-hour RODS-style graph
- 150 air-mile radius map
- live GPS position
- reporting-location setup
- destination radius checks
- pre-trip/post-trip inspections
- short-haul/daily records
- previous-day recap
- supporting-document register
- driver certification workflow
- driver/carrier/vehicle settings
- HOS/radius warnings
- CSV export

IMPORTANT: This is NOT an FMCSA-certified or registered ELD. It is a development prototype. A compliant ELD must synchronize with the vehicle/engine to automatically capture required engine power, motion, miles and engine hours and must implement the required ELD event/data, security, audit, transfer and malfunction behavior.

The 150-air-mile circle is an assistant feature. Being inside the circle alone does not establish eligibility for a short-haul exception.

The prototype uses browser GPS and does not substitute for ECM-integrated vehicle data.

Deploy with GitHub Pages or open locally for non-GPS testing. Browser GPS normally requires HTTPS or localhost.
