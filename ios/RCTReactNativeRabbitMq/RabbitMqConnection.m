#import "RabbitMqConnection.h"

@interface RabbitMqConnection ()
    @property (nonatomic, readwrite) NSDictionary *config;
    @property (nonatomic, readwrite) RMQConnection *connection;
    @property (nonatomic, readwrite) id<RMQChannel> channel;
    @property (nonatomic, readwrite) bool connected;
    @property (nonatomic, readwrite) NSMutableArray *queues;
    @property (nonatomic, readwrite) NSMutableArray *exchanges;
@end

@implementation RabbitMqConnection

@synthesize bridge = _bridge;

RCT_EXPORT_MODULE();

RCT_EXPORT_METHOD(initialize:(NSDictionary *) config)
{
    self.config = config;

    self.connected = false;

    self.queues = [[NSMutableArray alloc] init];
    self.exchanges = [[NSMutableArray alloc] init];
}

RCT_EXPORT_METHOD(connect)
{

    RabbitMqDelegateLogger *delegate = [[RabbitMqDelegateLogger alloc] initWithBridge:self.bridge];

    NSInteger port = self.config[@"port"];
    if(port <= 5671) {
        NSString *uri = [NSString stringWithFormat:@"amqps://%@:%@@%@:%@/%@", self.config[@"username"], self.config[@"password"], self.config[@"host"], self.config[@"port"], self.config[@"virtualhost"]];
        NSLog(@"URI SSL %@",uri);
        self.connection = [[RMQConnection alloc] initWithUri:uri 
                                              channelMax:@65535 
                                                frameMax:@(RMQFrameMax) 
                                               heartbeat:@10
                                             syncTimeout:@10 
                                                delegate:delegate
                                           delegateQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)];

    } else {
        NSString *uri = [NSString stringWithFormat:@"amqp://%@:%@@%@:%@/%@", self.config[@"username"], self.config[@"password"], self.config[@"host"], self.config[@"port"], self.config[@"virtualhost"]];        
        self.connection = [[RMQConnection alloc] initWithUri:uri 
                                              channelMax:@65535 
                                                frameMax:@(RMQFrameMax) 
                                               heartbeat:@10
                                             syncTimeout:@10 
                                                delegate:delegate
                                           delegateQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)];
    }

    [self.connection start:^{ 
        
        self.connected = true;

        [self.bridge.eventDispatcher sendAppEventWithName:@"RabbitMqConnectionEvent" body:@{@"name": @"connected"}];

    }];
}

RCT_EXPORT_METHOD(close)
{
    [self.connection close];
}

RCT_EXPORT_METHOD(addQueue:(NSDictionary *) config arguments:(NSDictionary *)arguments)
{
    if (self.connected){ 
        self.channel = [self.connection createChannel];

        RMQQueueDeclareOptions queue_options = RMQQueueDeclareDurable;
        RabbitMqQueue *queue = [[RabbitMqQueue alloc] initWithConfig:config channel:self.channel bridge:self.bridge];

        [self.queues addObject:queue];
		NSString *name = [queue getname];
		NSString *qname = [queue getqueuename];
        [self.bridge.eventDispatcher sendAppEventWithName:@"RabbitMqConnectionEvent" body:@{@"name": @"addQueue",@"input_queue_name":name,@"output_queue_name":qname}];
    }
}

RCT_EXPORT_METHOD(bindQueue:(NSString *)exchange_name queue_name:(NSString *)queue_name routing_key:(NSString *)routing_key)
{

    id queue_id = [self findQueue:queue_name];
    id exchange_id = [self findExchange:exchange_name];

    if (queue_id != nil && exchange_id != nil){
        [queue_id bind:exchange_id routing_key:routing_key];
    }
    
}

RCT_EXPORT_METHOD(unbindQueue:(NSString *)exchange_name queue_name:(NSString *)queue_name routing_key:(NSString *)routing_key)
{
    id queue_id = [self findQueue:queue_name];
    id exchange_id = [self findExchange:exchange_name];

    if (queue_id != nil && exchange_id != nil){
        [queue_id unbind:exchange_id routing_key:routing_key];
    }
}

RCT_EXPORT_METHOD(removeQueue:(NSString *)queue_name)
{
    id queue_id = [self findQueue:queue_name];

    if (queue_id != nil){
        [queue_id delete];
    }
}


RCT_EXPORT_METHOD(addExchange:(NSDictionary *) config)
{

    RMQExchangeDeclareOptions options = RMQExchangeDeclareNoOptions;
    
    if ([config objectForKey:@"passive"] != nil && [[config objectForKey:@"passive"] boolValue]){
        options = options | RMQExchangeDeclarePassive;
    }

    if ([config objectForKey:@"durable"] != nil && [[config objectForKey:@"durable"] boolValue]){
        options = options | RMQExchangeDeclareDurable;
    }

    if ([config objectForKey:@"autoDelete"] != nil && [[config objectForKey:@"autoDelete"] boolValue]){
        options = options | RMQExchangeDeclareAutoDelete;
    }

    if ([config objectForKey:@"internal"] != nil && [[config objectForKey:@"internal"] boolValue]){
        options = options | RMQExchangeDeclareInternal;
    }

    if ([config objectForKey:@"NoWait"] != nil && [[config objectForKey:@"NoWait"] boolValue]){
        options = options | RMQExchangeDeclareNoWait;
    }

    
    NSString *type = [config objectForKey:@"type"];

    RMQExchange *exchange = nil;
    if ([type isEqualToString:@"fanout"]) {
        exchange = [self.channel fanout:[config objectForKey:@"name"] options:options];
    }else if ([type isEqualToString:@"direct"]) {
        exchange = [self.channel direct:[config objectForKey:@"name"] options:options];
    }else if ([type isEqualToString:@"topic"]) {
        exchange = [self.channel topic:[config objectForKey:@"name"] options:options];
    }
    
    if (exchange != nil){
        [self.exchanges addObject:exchange];
    }

}
 
RCT_EXPORT_METHOD(publishToQueue:(NSString *)message routing_key:(NSString *)routing_key)
{
    NSData* data = [message dataUsingEncoding:NSUTF8StringEncoding];

    id queue_id = [self findQueue:routing_key];

    if (queue_id != nil){
        NSLog(@"queue publish %@",queue_id);
		RMQQueue* q = [queue_id queue];
        [q publish:data];
    } else {
        NSLog(@"could not queue publish, no id found for %@",routing_key);
    }
}
RCT_EXPORT_METHOD(publishToQueue:(NSString *)message routing_key:(NSString *)routing_key message_properties:(NSDictionary *)message_properties)
{
    NSLog(@"RMQConnection:publishToQueue1");
    NSData* data = [message dataUsingEncoding:NSUTF8StringEncoding];

    NSLog(@"RMQConnection:publishToQueue2");
    id queue_id = [self findQueue:routing_key];

    if (queue_id != nil){
        NSLog(@"RMQConnection:publishToQueue3");
        bool hasProperties = false;
        NSMutableArray *properties = [[NSMutableArray alloc] init];
        NSLog(@"RMQConnection:publishToQueue4");
        for ( NSString *key in message_properties) {
            //do what you want to do with items
            hasProperties = true;
            NSLog(@"RMQConnection:%@=%@", key, [message_properties objectForKey:key]);
        }

        NSLog(@"RMQConnection:eval message_properties");
        if ([message_properties objectForKey:@"content_type"] != nil && [[message_properties objectForKey:@"content_type"] isMemberOfClass:[NSString class]]){
            [properties addObject:[[RMQBasicContentType alloc] init:[[message_properties objectForKey:@"content_type"] stringValue]]];
        }
        if ([message_properties objectForKey:@"content_encoding"] != nil && [[message_properties objectForKey:@"content_encoding"] isMemberOfClass:[NSString class]]){
            [properties addObject:[[RMQBasicContentEncoding alloc] init:[[message_properties objectForKey:@"content_encoding"] stringValue]]];
        }
        if ([message_properties objectForKey:@"delivery_mode"] != nil){
            [properties addObject:[[RMQBasicDeliveryMode alloc] init:[[message_properties objectForKey:@"delivery_mode"] intValue]]];
        }
        if ([message_properties objectForKey:@"priority"] != nil){
            [properties addObject:[[RMQBasicPriority alloc] init:[[message_properties objectForKey:@"priority"] intValue]]];
        }
        if ([message_properties objectForKey:@"correlation_id"] != nil){ // && [[message_properties objectForKey:@"correlation_id"] isMemberOfClass:[NSString class]]){
            NSString *cid = [message_properties objectForKey:@"correlation_id"];
            NSLog(@"RMQConnection:prop correlation_id=%@",cid);
            [properties addObject:[[RMQBasicCorrelationId alloc] init:cid]];
        }
        if ([message_properties objectForKey:@"expiration"] != nil && [[message_properties objectForKey:@"expiration"] isMemberOfClass:[NSString class]]){
            [properties addObject:[[RMQBasicExpiration alloc] init:[[message_properties objectForKey:@"expiration"] stringValue]]];
        }
        if ([message_properties objectForKey:@"message_id"] != nil && [[message_properties objectForKey:@"message_id"] isMemberOfClass:[NSString class]]){
            [properties addObject:[[RMQBasicMessageId alloc] init:[[message_properties objectForKey:@"message_id"] stringValue]]];
        }
        if ([message_properties objectForKey:@"type"] != nil && [[message_properties objectForKey:@"type"] isMemberOfClass:[NSString class]]){
            [properties addObject:[[RMQBasicType alloc] init:[[message_properties objectForKey:@"type"] stringValue]]];
        }
        if ([message_properties objectForKey:@"user_id"] != nil && [[message_properties objectForKey:@"user_id"] isMemberOfClass:[NSString class]]){
            [properties addObject:[[RMQBasicUserId alloc] init:[[message_properties objectForKey:@"user_id"] stringValue]]];
        }
        if ([message_properties objectForKey:@"app_id"] != nil && [[message_properties objectForKey:@"app_id"] isMemberOfClass:[NSString class]]){
            [properties addObject:[[RMQBasicAppId alloc] init:[[message_properties objectForKey:@"app_id"] stringValue]]];
        }
        if ([message_properties objectForKey:@"reply_to"] != nil) { // && [[message_properties objectForKey:@"reply_to"] isMemberOfClass:[NSString class]]){
            NSString *rt = [message_properties objectForKey:@"reply_to"];
            NSLog(@"RMQConnection:prop reply_to=%@",rt);
            [properties addObject:[[RMQBasicReplyTo alloc] init:rt]];
        }

        NSLog(@"RMQConnection:queue publish %@",queue_id);
        RMQQueue* q = [queue_id queue];

        if (hasProperties) {
			NSLog(@"RMQConnection:publish data + properties");
            [q publish:data properties:properties options:RMQBasicPublishNoOptions];
        } else {
			NSLog(@"RMQConnection:publish data only");
            [q publish:data];
        }
    } else {
        NSLog(@"RMQConnection:could not queue publish, no id found for %@",routing_key);
    }
}
RCT_EXPORT_METHOD(publishToExchange:(NSString *)message exchange_name:(NSString *)exchange_name routing_key:(NSString *)routing_key message_properties:(NSDictionary *)message_properties)
{

    id exchange_id = [self findExchange:exchange_name];

    if (exchange_id != nil){
        bool hasProperties = false;

        NSData* data = [message dataUsingEncoding:NSUTF8StringEncoding];

        NSMutableArray *properties = [[NSMutableArray alloc] init];

		for ( NSString *key in message_properties) {
			//do what you want to do with items
            hasProperties = true;
			NSLog(@"%@=%@", key, [message_properties objectForKey:key]);
		}
		
		NSLog(@"eval message_properties");
        if ([message_properties objectForKey:@"content_type"] != nil && [[message_properties objectForKey:@"content_type"] isMemberOfClass:[NSString class]]){
            [properties addObject:[[RMQBasicContentType alloc] init:[[message_properties objectForKey:@"content_type"] stringValue]]];
        }
        if ([message_properties objectForKey:@"content_encoding"] != nil && [[message_properties objectForKey:@"content_encoding"] isMemberOfClass:[NSString class]]){
            [properties addObject:[[RMQBasicContentEncoding alloc] init:[[message_properties objectForKey:@"content_encoding"] stringValue]]];
        }
        if ([message_properties objectForKey:@"delivery_mode"] != nil){
            [properties addObject:[[RMQBasicDeliveryMode alloc] init:[[message_properties objectForKey:@"delivery_mode"] intValue]]];
        }
        if ([message_properties objectForKey:@"priority"] != nil){
            [properties addObject:[[RMQBasicPriority alloc] init:[[message_properties objectForKey:@"priority"] intValue]]];
        }
		if ([message_properties objectForKey:@"correlation_id"] != nil){ // && [[message_properties objectForKey:@"correlation_id"] isMemberOfClass:[NSString class]]){
            NSString *cid = [message_properties objectForKey:@"correlation_id"];
            NSLog(@"prop correlation_id=%@",cid);
            [properties addObject:[[RMQBasicCorrelationId alloc] init:cid]];
        }
        if ([message_properties objectForKey:@"expiration"] != nil && [[message_properties objectForKey:@"expiration"] isMemberOfClass:[NSString class]]){
            [properties addObject:[[RMQBasicExpiration alloc] init:[[message_properties objectForKey:@"expiration"] stringValue]]];
        }
        if ([message_properties objectForKey:@"message_id"] != nil && [[message_properties objectForKey:@"message_id"] isMemberOfClass:[NSString class]]){
            [properties addObject:[[RMQBasicMessageId alloc] init:[[message_properties objectForKey:@"message_id"] stringValue]]];
        }
        if ([message_properties objectForKey:@"type"] != nil && [[message_properties objectForKey:@"type"] isMemberOfClass:[NSString class]]){
            [properties addObject:[[RMQBasicType alloc] init:[[message_properties objectForKey:@"type"] stringValue]]];
        }
        if ([message_properties objectForKey:@"user_id"] != nil && [[message_properties objectForKey:@"user_id"] isMemberOfClass:[NSString class]]){
            [properties addObject:[[RMQBasicUserId alloc] init:[[message_properties objectForKey:@"user_id"] stringValue]]];
        }
        if ([message_properties objectForKey:@"app_id"] != nil && [[message_properties objectForKey:@"app_id"] isMemberOfClass:[NSString class]]){
            [properties addObject:[[RMQBasicAppId alloc] init:[[message_properties objectForKey:@"app_id"] stringValue]]];
        }
		if ([message_properties objectForKey:@"reply_to"] != nil) { // && [[message_properties objectForKey:@"reply_to"] isMemberOfClass:[NSString class]]){
            NSString *rt = [message_properties objectForKey:@"reply_to"];
            NSLog(@"prop reply_to=%@",rt);
            [properties addObject:[[RMQBasicReplyTo alloc] init:rt]];
        }
		NSLog(@"publish");
        if (hasProperties) {
            NSLog(@"properties");
            [exchange_id publish:data routingKey:routing_key properties:properties options:RMQBasicPublishNoOptions];
        } else {
            NSLog(@"no properties");
            [exchange_id publish:data routingKey:routing_key];
        }
    } else {
        NSLog(@"publish nil");
    }
}

RCT_EXPORT_METHOD(deleteExchange:(NSString *)exchange_name)
{
   id exchange_id = [self findExchange:exchange_name];

    if (exchange_id != nil){
        [exchange_id delete];
    }
}


RCT_EXPORT_METHOD(ack:(nonnull NSNumber *)deliveryTag) 
{
    [self.channel ack:deliveryTag];
}

RCT_EXPORT_METHOD(nack:(nonnull NSNumber *)deliveryTag) 
{
    [self.channel nack:deliveryTag];
}

-(id) findQueue:(NSString *)name {
    id queue_id = nil;
    NSLog(@"findQueue:%@",name);
    for(id q in self.queues) {
        NSLog(@"compare vs:%@",[q name]);
        if ([[q name] isEqualToString:name]){
            NSLog(@"MATCH!");
            queue_id = q; 
        }
    }
    return queue_id;
}

-(id) findExchange:(NSString *)name {
    id exchange_id = nil;
    for(id e in self.exchanges) {
        if ([[e name] isEqualToString:name]){ exchange_id = e; }
    }

    return exchange_id;
}

@end
