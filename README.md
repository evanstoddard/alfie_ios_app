<p align="center">
  <img src="Alfie/Assets.xcassets/AppIcon.appiconset/alfie_1024_1024.png" alt="Alfie Logo" width="200">
</p>

# Alfie iOS

A companion iOS app for the [Alfie firmware](https://github.com/evanstoddard/alfie_firmware) project. Provides SMS-style messaging over DECT NR+ by connecting to an Alfie device via BLE.

You can follow along with the development of this project in the [blog series](https://evanstoddard.com/posts/dect_nr_plus_alfie_part_1/).

## Overview

Alfie iOS connects to an Alfie DECT NR+ device over Bluetooth Low Energy, allowing you to send and receive short text messages between devices on the DECT NR+ network. The app serves as a mobile interface for the Alfie accessory.

## Features

- BLE scanning and connection to Alfie devices
- Send and receive text messages over DECT NR+
- Conversation management with contacts
- iPad split-view support
- Message persistence across app restarts

## Requirements

- iOS 18.6+
- An [Alfie](https://github.com/evanstoddard/alfie_firmware) device running the Alfie firmware

## Building

Open `Alfie.xcodeproj` in Xcode. The project uses Swift Package Manager for dependencies which will resolve automatically on first open.

## License

MIT License. See [LICENSE](LICENSE) for details.
