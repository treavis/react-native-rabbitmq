import {NativeModules, DeviceEventEmitter} from 'react-native';

const RabbitMqConnection = NativeModules.RabbitMqConnection;

export class Connection {
    
    constructor(config) {
        this.rabbitmqconnection = RabbitMqConnection;
        this.callbacks = {};
        
        this.connected = false;

        DeviceEventEmitter.addListener('RabbitMqConnectionEvent', this.handleEvent.bind(this));

        this.rabbitmqconnection.initialize(config);

    }
    
    connect() {
        this.rabbitmqconnection.connect();
    }    
    
    close() {
        this.rabbitmqconnection.close();
    }

    handleEvent(event) {

        console.log('Connection.handleEvent '+event.name);

        if (event.name == 'connected'){ this.connected = true; }

        if (this.callbacks.hasOwnProperty(event.name)){
            console.log('Connection.handleEvent callback '+event.name);
            console.log(event);
            this.callbacks[event.name](event)
        }

    }
    
    on(event, callback) {
        this.callbacks[event] = callback;
    } 

    removeon(event) {
        delete this.callbacks[event];
    }

    ack(id) {
        this.rabbitmqconnection.ack(id);
    }
    nack(id) {
        this.rabbitmqconnection.nack(id);
    }
}

export default Connection;