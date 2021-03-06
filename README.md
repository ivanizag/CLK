![Clock Signal Application Icon](READMEImages/Icon.png)
# Clock Signal
Clock Signal ('CLK') is an emulator for tourists that seeks to be invisible. Users directly launch classic software with no emulator or per-emulated-machine learning curve.

macOS and source releases are [hosted on GitHub](https://github.com/TomHarte/CLK/releases). For desktop Linux it is also available as a [Snap](https://snapcraft.io/clock-signal). On the Mac it is a native Cocoa and Metal application; under Linux, BSD and other UNIXes and UNIX-alikes it uses OpenGL and can be built either with Qt or with SDL.

This emulator seeks to offer:
* single-click load of any piece of source media for any supported platform;
* with a heavy signal processing tilt for accurate reproduction of original outputs;
* while minimising latency.

It currently contains emulations of the:
* Acorn Electron;
* Amstrad CPC;
* Apple II/II+ and IIe;
* Atari 2600;
* Atari ST;
* ColecoVision;
* Commodore Vic-20 (and Commodore 1540/1);
* Macintosh 512ke and Plus;
* MSX 1;
* Oric 1/Atmos;
* Sega Master System; and
* Sinclair ZX80/81.

## Single-click Loading

Through static and runtime analysis CLK seeks automatically to select and configure the appropriate machine to run any provided disk, tape or ROM; to issue any commands necessary to run the software contained on the disk, tape or ROM; and to provide accelerated loading where feasible.

The full process of loading a title — even if you've never used the emulated machine before — is therefore:

1. locate it in your OS;
2. double click it.

## Signal Processing

Consider an ordinary, unmodified Commodore Vic-20. Its only video output is composite. Therefore the emulated machine's only video output is composite. In order to display the video output, your GPU must decode composite video. Therefore composite video artefacts are present and correct not because of a post hoc filter but because the real signal is really being processed.

Similar effort is put into audio generation. If the real machine normally generates audio at 192Khz then the emulator generates a 192Khz source signal and filters it down to whatever the host machine can output.

### Samples

| 1:1 Pixel Copying | Composite Decoded |
|---|---|
|![The Electron start screen, with a classic 1:1 pixel emulation](READMEImages/NaiveElectron.png)|![The Electron start screen, decoded from an interlaced composite feed](READMEImages/CompositeElectron.png)|
|![Repton 3 in game, with a classic 1:1 pixel emulation](READMEImages/NaiveRepton3.png)|![Repton 3 in game, decoded from an interlaced composite feed](READMEImages/CompositeRepton3.png)|
|![Stormlord with a classic 1:1 pixel emulation](READMEImages/NaiveStormlord.png)|![Stormlord decoded from a composite feed](READMEImages/CompositeStormlord.png)|
|![Road Fighter with a classic 1:1 pixel emulation](READMEImages/NaiveRoadFighter.png)|![Road Fighter decoded from a composite feed](READMEImages/CompositeRoadFighter.png)|
|![A segment of the ColecoVision Donkey Kong title screen with a classic 1:1 pixel emulation](READMEImages/NaivePresentsDonkeyKong.png)|![A segment of the ColecoVision Donkey Kong title screen decoded from a composite feed](READMEImages/CompositePresentsDonkeyKong.png)|
|![Sonic the Hedgehog with a classic 1:1 pixel emulation](READMEImages/NaiveSonic.jpeg)|![Sonic the Hedgehog screen PAL decoded from a composite feed](READMEImages/CompositeSonic.png)|

| 1:1 Pixel Copying | Correct Aspect Ratio, Filtered |
|---|---|
|![Amstrad text, with a classic 1:1 pixel emulation](READMEImages/NaiveCPC.png)|![Amstrad text, with correct aspect ratio and subject to a lowpass filter](READMEImages/FilteredCPC.png)|
|![The Amstrad CPC version of Stormlord, with a classic 1:1 pixel emulation](READMEImages/NaiveCPCStormlord.png)|![The Amstrad CPC version of Stormlord, with correct aspect ratio and subject to a lowpass filter](READMEImages/CPCStormlord.png)|

## Low Latency

The display produced is an emulated CRT, with phosphor decay. Therefore if you have a 140Hz 4k monitor it can produce 140 distinct frames per second at 4k resolution. Latency is dictated by the host hardware, not the emulated machine or emulator.

Audio latency is disjoint from frame rate and is generlaly restrained to 5–10ms.

## Accurate Emulation

Accuracy affects usability; the more accurate an emulator, the more likely that a user can run every piece of software they're interested in without further intervention.

This emulator attempts cycle-accurate emulation of all supported machines. In some cases it succeeds.

## Additional Screenshots
| | |
|---|---|
|![Apple IIe Prince of Persia](READMEImages/AppleIIPrinceOfPersia.png) | ![Apple Macintosh MusicWorks](READMEImages/MusicWorks.png)
|![Atari ST Stung Car Racer](READMEImages/STStuntCarRacer.png) | ![Amstrad CPC Chase HQ](READMEImages/CPCChaseHQ.png)
|![Acorn Electron Chuckie Egg](READMEImages/ElectronChuckieEgg.png) | ![ColecoVision Galaxian](READMEImages/ColecoVisionGalaxian.png)
|![ZX81 3D Monster Maze](READMEImages/ZX81MonsterMaze.png) | ![ZX80 Kong](READMEImages/ZX80Kong.png)
|![SG1000 Chack'n'Pop](READMEImages/SGChackNPop.png) | ![Atari 2600 Solaris](READMEImages/Atari2600Solaris.png)
|![Vic-20 Gridrunner](READMEImages/Vic20Gridrunner.png) | ![VIC-20 BASIC](READMEImages/Vic20BASIC.png)

![macOS Version](READMEImages/MultipleSystems.png)
![Qt Version](READMEImages/MultipleSystems-Ubuntu.png)

## Sponsorship

I've been asked several times whether it is possible to sponsor this project; I think that's a poor fit for this emulator's highly-malleable scope, and it makes me uncomfortable because as the author I primarily see only its defects.

An Amazon US wishlist is now attached in the hope of avoiding the question in future. A lot of it is old books now available only secondhand — I like to read about potential future additions well in advance of starting on them. Per the optimism of some book sellers, please don't purchase anything that is currnetly listed only at an absurd price.
