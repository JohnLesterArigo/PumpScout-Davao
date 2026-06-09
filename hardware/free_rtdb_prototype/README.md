# PumpScout Hardware Crowd Prototype

Free-tier setup:

1. In Firebase Console, create a **Realtime Database**.
2. For a quick prototype, create this path:

```json
stationCrowd: {
  "1ab26M1Oe1CkO02Tayee": {
    "stationId": "1ab26M1Oe1CkO02Tayee",
    "stationName": "petron",
    "currentCount": 0,
    "capacity": 20,
    "status": "not_crowded",
    "updatedAt": 0
  }
}
```

3. In Arduino IDE, install these boards:
   - ESP32 board package for the entrance device.
   - ESP8266 board package for the NodeMCU exit device.

4. Edit the `.ino` files and fill in:
   - `WIFI_SSID`
   - `WIFI_PASSWORD`
   - `DATABASE_URL`

5. Upload:
   - `entrance_counter_esp32.ino` to the ESP32.
   - `exit_counter_nodemcu.ino` to the NodeMCU.

The Flutter app now reads Realtime Database first at:

```text
/stationCrowd/1ab26M1Oe1CkO02Tayee
```

If that RTDB record does not exist, the app falls back to the old Firestore `stationCrowd` record.

For a school demo, this is okay. For real deployment, do not leave Realtime Database rules fully open.
