# Wiring the Smart Vision Lights S75 to the groov RIO

Setup guide for adding a Smart Vision Lights [S75 Brick Light](https://cdn.shopify.com/s/files/1/0603/8129/8903/files/S75_Datasheet-2.pdf) (machine-vision spot light, for the defect-inspection camera — not a warning beacon) to the demo stand's `Opto22_RIO2` module.

Sources: the S75 datasheet linked above, [`2314_groov_Accessories_Data_Sheet.pdf`](2314_groov_Accessories_Data_Sheet.pdf) (cable/connector specs, in this folder), and [`2324_groov_RIO_Users_Guide.pdf`](2324_groov_RIO_Users_Guide.pdf) (Appendix A: Specifications, in this folder). `IMG_3518.jpg`–`IMG_3540.jpg` in this folder are reference photos of the current physical terminal wiring on both RIO modules.

## Electrical match

**S75 requirements** (from its datasheet):
- Power: 24VDC, up to 400mA / 9.6W
- Trigger: **NPN** (sinking) — activates when pulled to GND, draws only 14.4mA — or PNP (sourcing), not both
- Optional: 1–10VDC analog intensity control

**groov RIO discrete output** (Users Guide, Appendix A): channels 0–7 support `do_sinking` — Discrete DC Sinking Output, 5–30VDC line range, **1.0A continuous** (recommended fuse 1A/30VDC). A sinking output pulls its terminal to ground when active — the exact match for the S75's NPN trigger, and the 14.4mA it draws is trivial against the RIO's 1A rating.

**Important**: don't power the light through the RIO. The RIO output is a low-current control line, not a power feed — the S75's 400mA/9.6W draw must come straight from the shared 24VDC rail already powering the stack light, not through a RIO channel. The RIO only switches the trigger.

## Wiring plan

5-pin M12 connector on the light:

| Pin | Signal | Wire color | Connects to |
|---|---|---|---|
| 1 | Power In +24VDC | Brown | Shared +24VDC rail (same supply as the stack light) |
| 2 | NPN Sinking Signal | White | A free `do_sinking` output channel (0–7) on `Opto22_RIO2` |
| 3 | GND | Blue | Common/GND — bonded to the RIO's I/O common **and** the 24V supply's return |
| 4 | PNP Sourcing Signal | Black | Not used (leave disconnected — using NPN, not PNP) |
| 5 | Intensity Control 1–10VDC | Grey* | Not used, unless wiring up PLC-controlled brightness (see below) |

\* some S75 cables use green/yellow for pin 5 instead of grey.

Recommended module: `Opto22_RIO2`, not `RIO1` — RIO2 already drives the other actuator-type outputs (the stack lights), keeping all "things the PLC turns on" grouped on one module, consistent with how `RIO1` is all buttons/LEDs/relay.

The `GRV-TEX-26F6` flying-lead cable already terminated into both RIO modules is rated 4A/20AWG — comfortably enough for the trigger line. The S75 itself terminates in a 5-pin M12 connector, not flying leads, so you'll need either an M12-to-flying-leads pigtail cable, or to open the M12 connector and wire directly to its pins.

## Pin ↔ channel mapping

From the official wiring diagram (Users Guide, Appendix B, "GRV-R7-MM1001-10, GRV-R7-MM20001-10" page):

| Channel | Terminal pins | Configurable as |
|---|---|---|
| Ch 0 | 1, 2, 3 | Discrete/Switch/Voltage/Current/ICTD/Thermistor/**Thermocouple** input, **or DC Sinking** output |
| Ch 1 | 4, 5, 6 | same as Ch 0 |
| Ch 2 | 7, 8, 9 | same as Ch 0 |
| Ch 3 | 10, 11, 12 | same as Ch 0 |
| Ch 4 | 13, 14 | same input types minus thermocouple, **or DC Sinking / Analog Current-Voltage** output |
| Ch 5 | 15, 16 | same as Ch 4 |
| Ch 6 | 17, 18 | same as Ch 4 |
| Ch 7 | 19, 20 | same as Ch 4 |
| Ch 8 | 21, 22, 23 | **Fixed** Form C relay (NC/COM/NO) — not reconfigurable |
| Ch 9 | 24, 25, 26 | **Fixed** Form C relay (NC/COM/NO) — not reconfigurable |

### Polarity within a 2-pin channel (Ch4–7)

Pulled directly from the DC Sinking output symbol in the wiring diagram, not assumed: for every 2-pin sinking channel, **the lower-numbered pin is "−" (common/ground reference), the higher-numbered pin is "+" (external circuit connection)**. The RIO's internal switch connects "+" to "−" when the output activates.

| Channel | "−" pin (common/GND) | "+" pin (signal) |
|---|---|---|
| Ch 4 | 13 | 14 |
| Ch 5 | 15 | 16 |
| Ch 6 | 17 | 18 |
| Ch 7 | 19 | 20 |

So if using, say, **Ch 6**: the "+" pin (18) gets the S75's white wire (Pin 2, NPN Sinking Signal) — that's where external current flows in — and the "−" pin (17) gets tied to common/GND, bonded with the S75's blue wire (Pin 3) and the shared 24V supply's return. Same pattern for Ch 4, 5, or 7 — just substitute the pin numbers from the table above.

Channels 0–7 are genuinely universal — each is individually software-assigned to whatever input or output type is needed. `do_sinking` (what the S75's trigger needs) is available on any of them. Channels 8–9 are hardwired as mechanical relay outputs only.

To make sure you are using the correct channel and pin from above table, doublecheck beginning and ending of ferrules going into RIO2 (like could be seen in [image](IMG_3524.jpg))   

> [!IMPORTANT]  
> The actual wiring can be found in this [diagram](../../physical-layout/Electrical-Drawing-Red_Hat-REV-C.pdf)  

## Finding a free channel

**This can't be reliably determined from the wiring photos**, even now that the pin/channel map is known. The `GRV-TEX-26F6` cable is a fixed 26-wire bundle, all wires pre-ferruled and inserted at assembly — so essentially all 26 physical pins have a wire seated in them regardless of whether that channel is actually configured and used in software. A wire present in a pin doesn't mean that channel is in use; it just means that strand of the cable is physically terminated, same as every other strand. Physical wiring and logical channel configuration are two different things here, and only the configuration says what's free.

Two reliable ways to check, both faster than reverse-engineering photos:
1. **groov Manage** — the RIO's own web UI, reached by browsing directly to its IP (`192.168.100.11` for `RIO1`, `192.168.100.12` for `RIO2`, per [README §2.5](../../README.md#SetupGroovIOModules-GRV-R7-MM1001)). Shows exactly which channels currently have a signal type assigned.
2. **CODESYS IDE's device tree** — expand `Opto22_RIO2`; each configured channel appears as a named child object (`Toggle_1`, `Red_Stacklight`, etc. — 6 known so far). Anything not listed is free.

Any channel in 0–7 that comes back unconfigured works for the S75's `do_sinking` trigger.

## Tracing a specific wire by color

Once a free channel is confirmed logically (via groov Manage or the device tree), the `GRV-TEX-26F6` cable's fixed pin-to-color assignment tells you exactly which physical wire to follow from the RIO's terminal block to wherever it lands on the baseboard (a separate WAGO-style push-in terminal panel, alongside the 24V power supply and Ethernet switch — confirmed in `IMG_3527`–`IMG_3533`):

| Pin | Color | Pin | Color |
|---|---|---|---|
| 1 | White | 14 | White w/Orange stripe |
| 2 | White w/Black stripe | 15 | Gray |
| 3 | Red | 16 | White w/Gray stripe |
| 4 | White w/Red stripe | 17 | Violet |
| 5 | Black | 18 | White w/Violet stripe |
| 6 | Black w/White stripe | 19 | Pink |
| 7 | Green | 20 | Pink w/Black stripe |
| 8 | White w/Green stripe | 21 | Red w/Black stripe |
| 9 | Yellow | 22 | Blue w/Black stripe |
| 10 | White w/Yellow stripe | 23 | Red w/White stripe |
| 11 | Blue | 24 | Blue w/White stripe |
| 12 | White w/Blue stripe | 25 | Yellow w/White stripe |
| 13 | Orange | 26 | Red w/Blue stripe |

**This can't be done reliably from the reference photos alone** — worth knowing before relying on them. Two things get in the way: past pin 12, most colors are "White with an X stripe" (14, 16, 18, 20, 22, 24, 26), which are genuinely hard to tell apart on camera; and the panel's red ambient lighting (visible in several of the photos) shifts how colors render, making close calls worse. Each wire also carries a small printed ferrule tag (e.g. `417A`, `403A`) that would let it be matched end-to-end unambiguously, but these are too small/blurred in the current photos to read reliably. Use the table above as a guide for what to look for **in person**, not as a substitute for physically checking the actual wire at the terminal.

## Optional: PLC-controlled brightness

Channels 4–7 also support a `Voltage Output` (0–10V) signal type. If adjustable intensity from CODESYS is wanted instead of the light's fixed physical potentiometer, wire the S75's grey wire (Pin 5) to one of those channels instead of leaving it disconnected.

## Next step

Once wired and a channel is confirmed, this needs a new output variable in `GVL` (e.g. `Out_Strobe_Light`) bound to the chosen channel, and a decision on when `DEFECT_CHECK` should turn it on/off relative to the camera trigger (e.g., on during `WAITING_RESULT`, off otherwise) — see [`workloads/Codesys/CODESYS-Workflow.md`](../Codesys/CODESYS-Workflow.md) for the current state machine this would hook into.