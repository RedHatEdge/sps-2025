import datetime
import paho.mqtt.client as mqtt
import os
import time
import json
import random

# import env variables
MQTT_BROKER_URL=os.getenv('MQTT_BROKER_URL','192.168.1.247')
MQTT_BROKER_PORT=os.getenv('MQTT_BROKER_PORT',31883)
MQTT_BROKER_TOPIC=os.getenv('MQTT_BROKER_TOPIC','factory1/lineA/results')
# how much to wait before sending a random result to the result topic
WAIT_TIME=os.getenv('WAIT_TIME',1)
MQTT_CLIENT_ID=os.getenv('MQTT_CLIENT_ID','defect-rec-sim')
MQTT_USERNAME=os.getenv('MQTT_USERNAME','admin')
MQTT_PASSWORD=os.getenv('MQTT_PASSWORD','password')

# setting default values
active_model=True
piece_id=0
batch_id="X100000"
line_id=24
station_id=10
defective = True

# The callback for when the client receives a CONNACK response from the server.
def on_connect(client, userdata, flags, reason_code, properties=None):
    print(f"Connected with result code {reason_code}")
    # Subscribing in on_connect() means that if we lose the connection and
    # reconnect then subscriptions will be renewed.
    client.subscribe("model/#")
    client.publish("model/sim", "on")

# The callback for when a PUBLISH message is received from the server.
def on_message(client, userdata, msg):
    #print("Topic: "+msg.topic+" ------- Message: "+msg.payload.decode("utf-8"))
    global active_model, piece_id 

    # print(data["topic"])
    # enable model(s) based on msg in topic *model* and *beta*
    if msg.topic=="model/sim":
        if msg.payload.decode("utf-8")=="on":    
            active_model=True
            print('Defect analysis in progress...')
            #active_model=False
            payload = str(generate())
            client.publish(MQTT_BROKER_TOPIC, payload)
            print(f'Published to topic {MQTT_BROKER_TOPIC} payload: {payload}')
            print('Waiting for next part')
            time.sleep(int(WAIT_TIME))
            piece_id+=1
            client.publish("model/sim", "on")


def generate():
    global piece_id, batch_id, line_id, station_id, defective
    rand_defect= random.choices([0,1,2,3,4,5], k=1)[0]
    if rand_defect==0:
        # no defect
        defective = False
    rand_score = random.randrange(40,99)/100
    batch_id="X" + str(int(batch_id[1:])+int(piece_id/1000))
    result = json.dumps({'defect_type':rand_defect, 'defective':defective,'confidence_score':rand_score,'timestamp':datetime.datetime.now().replace(microsecond=0).isoformat(),'line_id':line_id, 'station_id':station_id, 'batch_id': batch_id,'id':piece_id})
    defective = True
    return result

mqttc = mqtt.Client(client_id=MQTT_CLIENT_ID, protocol=mqtt.MQTTv5)

mqttc.on_connect = on_connect
mqttc.on_message = on_message
mqttc.username_pw_set(username=MQTT_USERNAME, password=MQTT_PASSWORD)

mqttc.connect(MQTT_BROKER_URL, port=int(MQTT_BROKER_PORT), keepalive=60)

# Blocking call that processes network traffic, dispatches callbacks and
# handles reconnecting.
# Other loop*() functions are available that give a threaded interface and a
# manual interface.
mqttc.loop_forever()