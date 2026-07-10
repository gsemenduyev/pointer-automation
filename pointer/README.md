# Pointer Automation

Clean menu bar app implementation with separate worker and mover backend.

## Files

- PointerAutomation.swift: menu bar app (state, settings UI, launch checks)
- pointer_worker.sh: automation loop + validation
- mouse_mover.swift: low-level pointer movement backend
- pointer_config.sh: runtime settings
- build_app.sh: builds PointerAutomation.app
- Launch Pointer Automation.command: Finder-friendly launcher

## Build

bash build_app.sh

## Launch

Finder:

- Double-click Launch Pointer Automation.command

Terminal:

- open PointerAutomation.app

## Use

- Click the menu bar icon and use Start Automation / Stop Automation
- Open Settings... to edit config without manually editing files
- Remaining time appears in the menu

## Config

- TOTAL_TIME_MINUTES supports decimals (example: 0.25)
- INTERVAL_SECONDS must be a positive integer
- MOUSE_MOVE_MODE must be small or large
- MOVE_DISTANCE_PIXELS must be a positive integer

## Permissions

Grant Accessibility and Input Monitoring permissions to PointerAutomation.app (and Terminal if you run scripts directly).
