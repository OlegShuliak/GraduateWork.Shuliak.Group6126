#include <WiFi.h>
#include <stdio.h>
#include "DHTesp.h"
#include <PubSubClient.h>

#define DHTPIN 33

DHTesp dht;

// WiFi
const char* ssid = "Wokwi-GUEST";
const char* pass = ""; 

// MQTT Broker
const char *mqtt_broker = "smart-home.gb-study-shuliak.ru";
const char *topic_temp = "Temreture_DHT22";
const char *topic_hum = "Humidity_DHT22";
const char *mqtt_username = "IoT";
const char *mqtt_password = "shuliak";
const int mqtt_port = 1883;

WiFiClient espClient;
PubSubClient client(espClient);

void setup() {
  Serial.begin(115200);
  dht.setup(DHTPIN, DHTesp::DHT22);
  setup_wifi();
  MQTT_connect();
}

void setup_wifi() {
  WiFi.begin(ssid, pass);
  while(WiFi.status() != WL_CONNECTED){
    delay(100);
    Serial.println(".");
  }
  Serial.println("WiFi connection success!");
  Serial.println(WiFi.localIP()); 
}

void MQTT_connect(){
  client.setServer(mqtt_broker, mqtt_port);
  client.setCallback(callback);
  while (!client.connected()) {
    String client_id = "Wokwi_Oleg_";
    client_id += String(WiFi.macAddress());
    Serial.printf("The client %s connects to the MQTT broker\n", client_id.c_str());
    if (client.connect(client_id.c_str(), mqtt_username, mqtt_password)) {
        Serial.println("MQTT broker connected");
    } else {
        Serial.print("failed with state ");
        Serial.print(client.state());
        delay(2000);
    }
  }
}

void callback(char *topic, byte *payload, unsigned int length) {
    Serial.print("Message arrived in topic: ");
    Serial.println(topic);
    Serial.print("Message:");
    for (int i = 0; i < length; i++) {
        Serial.print((char) payload[i]);
    }
    Serial.println();
    Serial.println("-----------------------");
}


void loop() {
  TempAndHumidity  data = dht.getTempAndHumidity();
  
  String temp = String((data.temperature - random(-6, 34)), 2);
  Serial.println("Temp: " + temp + "°C");
  Serial.println("---");

  String hum = String((data.humidity - random(-5, 5)), 2);
  Serial.println("Hum: " + hum + "%");
  Serial.println("---");
  
  const char *tempChar = temp.c_str();
  client.publish(topic_temp, tempChar);

  const char *humChar = hum.c_str();
  client.publish(topic_hum, humChar);

  client.loop();
  delay(10000);
}
