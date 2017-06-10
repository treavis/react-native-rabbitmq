import {DeviceEventEmitter} from 'react-native';

export class Queue {

    constructor(connection, queue_config, args) {

        this.callbacks = {};
        this.rabbitmqconnection = connection.rabbitmqconnection;

        this.name = queue_config.name;
        this.queue_config = queue_config;
        this.arguments = args || {};

        this.message_buffer = [];
        this.message_buffer_delay =  (queue_config.buffer_delay ? queue_config.buffer_delay : 1000);
        this.message_buffer_timeout = null;

        DeviceEventEmitter.addListener('RabbitMqQueueEvent', this.handleEvent.bind(this));
        
        this.rabbitmqconnection.addQueue(queue_config, this.arguments);
    }

    handleEvent(event){

        console.log('Queue.handleEvent on queue: '+event.queue_name+' vs '+this.name);
        if (event.queue_name != this.name){ return; }

        console.log('Queue.handleEvent: '+event.name);
        if (event.name == 'message'){

            if (this.callbacks.hasOwnProperty(event.name)){
                console.log('Queue.handleEvent.callback');
                this.callbacks['message'](event);
            }

            if (this.callbacks.hasOwnProperty('messages')){

                this.message_buffer.push(event);

                clearTimeout(this.message_buffer_timeout);

                this.message_buffer_timeout = setTimeout(() => { 
                    if (this.message_buffer.length > 0){
                        this.callbacks['messages'](this.message_buffer);
                        this.message_buffer = [];
                    }
                }, this.message_buffer_delay);

            }

        }else if (this.callbacks.hasOwnProperty(event.name)){
            this.callbacks[event.name](event);
        }

    }

    on(event, callback){
        this.callbacks[event] = callback;
    } 

    removeon(event){
        delete this.callbacks[event];
    } 

    bind(exchange, routing_key = ''){
        this.rabbitmqconnection.bindQueue(exchange.name, this.name, routing_key);    
    }

    unbind(exchange, routing_key = ''){
        this.rabbitmqconnection.unbindQueue(exchange.name, this.name, routing_key);    
    }
    publish(message, routing_key = '',properties = {}){
        console.log("Queue:publish");
        if (properties == {}) {
            console.log("Queue:publish:no properties");
            this.rabbitmqconnection.publishToQueue(message, this.name);
        } else {
            console.log("Queue:publish:properties");
            console.log(message);
            console.log(routing_key);
            console.log(properties);
            console.log("Queue:publish:properties call native");
            this.rabbitmqconnection.publishToQueue(message, routing_key, properties); 
        }  
    }
}

export default Queue;