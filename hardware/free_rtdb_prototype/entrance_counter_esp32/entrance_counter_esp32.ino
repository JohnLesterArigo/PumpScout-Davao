#include <WiFi.h>
#include <HTTPClient.h>
#include <WiFiClientSecure.h>
#include <time.h>

const char* WIFI_SSID = ":>";
const char* WIFI_PASSWORD = "cagas123";
const char* DATABASE_URL = "https://pumpscout-davao-default-rtdb.asia-southeast1.firebasedatabase.app";

// Example: https://pumpscout-davao-default-rtdb.asia-southeast1.firebasedatabase.app

const char* STATION_ID = "1ab26M1Oe1CkO02Tayee";
const int CAPACITY = 20;

const int SENSOR_PIN = 18;
const unsigned long TRIGGER_COOLDOWN_MS = 2500;

unsigned long lastTriggerMs = 0;

void setup() {
  Serial.begin(115200);
  pinMode(SENSOR_PIN, INPUT_PULLUP);

  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  Serial.print("Connecting to WiFi");
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println("\nWiFi connected");

  configTime(0, 0, "pool.ntp.org", "time.nist.gov");
}

void loop() {
  bool detected = digitalRead(SENSOR_PIN) == LOW;
  unsigned long now = millis();

  if (detected && now - lastTriggerMs > TRIGGER_COOLDOWN_MS) {
    lastTriggerMs = now;
    changeCount(1);
  }
}

void changeCount(int delta) {
  int currentCount = getCurrentCount();
  int nextCount = constrain(currentCount + delta, 0, CAPACITY);
  String status = crowdStatus(nextCount);

  String body = "{";
  body += "\"stationId\":\"" + String(STATION_ID) + "\",";
  body += "\"stationName\":\"petron\",";
  body += "\"currentCount\":" + String(nextCount) + ",";
  body += "\"capacity\":" + String(CAPACITY) + ",";
  body += "\"status\":\"" + status + "\",";
  body += "\"updatedAt\":" + String(epochMilliseconds());
  body += "}";

  patchStationCrowd(body);
  Serial.println("Entrance detected. Count: " + String(nextCount));
}

int getCurrentCount() {
  WiFiClientSecure client;
  client.setInsecure();

  HTTPClient http;
  String url = String(DATABASE_URL) + "/stationCrowd/" + STATION_ID + "/currentCount.json";
  http.begin(client, url);
  int code = http.GET();
  String payload = http.getString();
  http.end();

  if (code != 200 || payload == "null" || payload.length() == 0) return 0;
  return payload.toInt();
}

void patchStationCrowd(String body) {
  WiFiClientSecure client;
  client.setInsecure();

  HTTPClient http;
  String url = String(DATABASE_URL) + "/stationCrowd/" + STATION_ID + ".json";
  http.begin(client, url);
  http.addHeader("Content-Type", "application/json");
  int code = http.PATCH(body);
  Serial.println("Firebase PATCH code: " + String(code));
  http.end();
}

String crowdStatus(int count) {
  float ratio = (float) count / (float) CAPACITY;
  if (ratio >= 0.8) return "crowded";
  if (ratio >= 0.5) return "moderate";
  return "not_crowded";
}

unsigned long long epochMilliseconds() {
  time_t now;
  time(&now);
  if (now < 100000) return 0;
  return (unsigned long long) now * 1000ULL;
}
