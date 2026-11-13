# AG-BFLS calibration implementation handoff

Updated: 2026-11-13

## Repository and branch
- Repository: `aaronriquelme1001-pixel/calculadora`
- Working branch: `fix/ag-bfls-protocol-repair-mainline`
- Base: `main`
- Keep PR #4 in draft until CI and physical BFLS validation are complete.

## Product boundary
This repository contains the web tank calculator and Flutter application under `fuel_master_pro/`. The user generates the APK in a separate environment. Do not commit generated APKs, signing keys, keystores, credentials, or customer secrets.

## Official workbook reference
Workbook: `CALIBRACION SHVS36 782-415.xlsx`; sheet: `calibration`; headers: `Data | Level | Volume`.
- 29 records including origin; 28 measured non-zero points.
- Origin: 0 / 0 / 0.
- Last record: Data=5000, Level=546 mm, Volume=249.2 L.
- Imported Data is preserved as sensor coordinate/fixValue; do not clamp, interpolate, or overwrite it with a fresh sensor capture.
- The workbook itself is not committed. Equivalent reference rows are included in unit tests.

## Import and transfer model
- Excel/CSV columns are resolved by explicit header aliases; malformed populated rows fail with a diagnostic.
- Active records: 2..100. Origin is inserted only if absent.
- Data/fixValue range 0..5000; Level uint16; Volume finite and non-negative.
- Data and Level strictly increase after origin; Volume cannot decrease.
- Sensor table has 100 slots, written in ten blocks of ten records, eight bytes per record. Remaining slots are zero terminators.
- Imported Data coordinates are authoritative. Geometry-generated tables still require live 0x1B capture.
- Upload requires the manufacturer-issued eight-byte credential, negotiated MTU >=91, backup of all blocks, and read-back verification after each write.
- A failed write/read-back/output-mode check triggers best-effort restoration of the previous table and output mode.
- Never use default PINs or persist/log credentials.


## Last automated validation
- Code head at this validation: `582a3665a79fb0c462d681e5648563e746dc457a`.
- GitHub Actions run: https://github.com/aaronriquelme1001-pixel/calculadora/actions/runs/43442576737 — completed successfully.
- Web JavaScript syntax check: PASS.
- Flutter dependency resolution: PASS.
- Flutter static analysis command: `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings` — exit 0. It still reports 36 non-fatal info/warning notices, including pre-existing unused fields/elements in `main.dart`.
- Flutter unit tests: PASS, 21 tests.
- These results are software-only; they do not replace a physical BFLS test.

## Physical validation still required
Software tests do not prove hardware compatibility. On a bench AG-BFLS unit: connect, authenticate, read all ten blocks, import the official 29-row table, write all ten blocks, read back all 100 slots byte-for-byte, verify output mode 0x02 and liter telemetry, and safely test rollback. Also test the same workbook in official Fuel Master before claiming interchangeability. Record model/firmware, MTU, date, and sanitized logs. Never include credentials.

## Resume checklist
1. Check `git status`, branch head, and PR #4.
2. Run `flutter pub get`, `flutter analyze`, and `flutter test` in `fuel_master_pro/`.
3. Inspect GitHub Actions for this branch.
4. Complete physical BFLS validation and add evidence here.
5. Keep PR #4 draft until all gates pass.
