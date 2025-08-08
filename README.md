# biggerreactor_turbine

Scripts to control Bigger Reactors turbines with ComputerCraft/CC:Tweaked.

## Files

- `sender.lua`: run on the computer connected to the turbines through a modem. It broadcasts their state.
- `receiver.lua`: shows the turbine status on a remote screen and allows remote control.
- `turbine_control.lua`: wired version. Use only when turbines are directly connected to the computer with no modem.
- `setup.lua`: interactive script that downloads the correct program depending on the connection type (wired or wireless).

## Setup

To launch the setup, run `pastebin run eHsmkvYk`.

