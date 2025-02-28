#include <WiFi.h>
#include <WebServer.h>

// WiFi credentials
const char* ssid = "...";
const char* password = "";

// GPIO pin for the light
const int LIGHT_PIN = 2; // Using built-in LED for testing

// Light state
bool lightState = false;

// Web server
WebServer server(80);

void setup() {
    Serial.begin(115200);
  
    // Initialize light pin
    pinMode(LIGHT_PIN, OUTPUT);
    digitalWrite(LIGHT_PIN, lightState ? HIGH : LOW);
  
    // Setup WiFi
    setupWiFi();
  
    // Setup web server
    setupWebServer();
  
    Serial.println("ESP32 Ready: WiFi initialized");
}

void loop() {
    // Handle web server requests
    server.handleClient();
}

// WiFi setup function
void setupWiFi() {
    Serial.println("Connecting to WiFi...");
    WiFi.begin(ssid, password);
  
    int attempts = 0;
    while (WiFi.status() != WL_CONNECTED && attempts < 20) {
        delay(500);
        Serial.print(".");
        attempts++;
    }

    if (WiFi.status() != WL_CONNECTED) {
        Serial.println("\nWiFi connection failed. Restarting...");
        ESP.restart();
    }

    Serial.println("\nWiFi connected");
    Serial.print("IP address: ");
    Serial.println(WiFi.localIP());
}

// Web server setup function
void setupWebServer() {
    server.on("/", HTTP_GET, handleRoot);
    server.on("/toggle", HTTP_GET, handleToggle);
    server.on("/status", HTTP_GET, handleStatus);
  
    server.begin();
    Serial.println("HTTP server started");
}

// Web handlers
void handleRoot() {
    String html = "<html><head>";
    html += "<title>ESP32 Light Control</title>";
    html += "<meta name='viewport' content='width=device-width, initial-scale=1.0'>";
    html += "<style>";
    html += "body { font-family: Arial, sans-serif; text-align: center; margin-top: 50px; }";
    html += "button { padding: 15px 30px; font-size: 20px; margin: 10px; border-radius: 10px; }";
    html += "</style>";
    html += "</head><body>";
    html += "<h1>ESP32 Light Control</h1>";
    html += "<p>Light is currently " + String(lightState ? "ON" : "OFF") + "</p>";
    html += "<button onclick='location.href=\"/toggle\"'>Toggle Light</button>";
    html += "</body></html>";
    server.send(200, "text/html", html);
}

void handleToggle() {
    lightState = !lightState;
    digitalWrite(LIGHT_PIN, lightState ? HIGH : LOW);
  
    Serial.print("Light turned ");
    Serial.println(lightState ? "ON" : "OFF");
  
    server.sendHeader("Location", "/", true);
    server.send(302, "text/plain", "");
}

void handleStatus() {
    String status = lightState ? "ON" : "OFF";
    server.send(200, "text/plain", status);
}