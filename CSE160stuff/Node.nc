/*
* ANDES Lab - University of California, Merced
* This class provides the basic functions of a network node.
*
* @author UCM ANDES Lab
* @date   2013/09/03
*
*/
#include <Timer.h>
#include "includes/command.h"
#include "includes/packet.h"
#include "includes/protocol.h"
#include "includes/CommandMsg.h"
#include "includes/sendInfo.h"
#include "includes/channels.h"
#include "includes/socket.h"

module Node{
uses interface Boot;

uses interface SplitControl as AMControl;
uses interface Receive;

uses interface SimpleSend as Sender;

uses interface CommandHandler;
uses interface SimpleSend as Flood;
uses interface Receive as FloodReceive;
uses interface Receive as PingReplyReceive;

uses interface SimpleSend as RouteSend;
uses interface Receive as RouteReceive;
uses interface Receive as RouteReplyReceive;

uses interface NeighborDiscovery;
uses interface Routing;

uses interface Transport;
uses interface CounterServer;
uses interface CounterClient;
}

implementation{
pack sendPackage;

// Prototypes
void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, uint16_t seq, uint8_t *payload, uint8_t length);

event void Boot.booted(){
call AMControl.start();
call NeighborDiscovery.start();

dbg(GENERAL_CHANNEL, "Booted\n");
}

event void AMControl.startDone(error_t err){
if(err == SUCCESS){
dbg(GENERAL_CHANNEL, "Radio On\n");
}else{
//Retry until successful
call AMControl.start();
}
}

event void AMControl.stopDone(error_t err){}

event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len){
dbg(GENERAL_CHANNEL, "Packet Received\n");
if(len==sizeof(pack)){
pack* myMsg=(pack*) payload;
dbg(GENERAL_CHANNEL, "Package Payload: %s\n", myMsg->payload);
return msg;
}
dbg(GENERAL_CHANNEL, "Unknown Packet Type %d\n", len);
return msg;
}



event message_t* PingReplyReceive.receive(message_t* msg, void* payload, uint8_t len){
if(len==sizeof(pack)){
pack* myMsg=(pack*) payload;
dbg(GENERAL_CHANNEL, "REPLY ARRIVE:%s\n\tSeq:%d\n", myMsg->payload, myMsg->seq);

}
return msg;
}
event message_t* FloodReceive.receive(message_t* msg, void* payload, uint8_t len){
if(len==sizeof(pack)){
pack* myMsg=(pack*) payload;
dbg(GENERAL_CHANNEL, "ARRIVE:%s\n\tSeq:%d\n", myMsg->payload, myMsg->seq);

}
return msg;
}

event message_t* RouteReplyReceive.receive(message_t* msg, void* payload, uint8_t len){
if(len==sizeof(pack)){
pack* myMsg=(pack*) payload;
dbg(GENERAL_CHANNEL, "REPLY ARRIVE:%s\n", myMsg->payload);

}
return msg;
}
event message_t* RouteReceive.receive(message_t* msg, void* payload, uint8_t len){
if(len==sizeof(pack)){
pack* myMsg=(pack*) payload;
dbg(GENERAL_CHANNEL, "ARRIVE:%s\n\n", myMsg->payload);

}
return msg;
}
event void CommandHandler.ping(uint16_t destination, uint8_t *payload){
makePack(&sendPackage, TOS_NODE_ID, destination, 0, 0, 0, payload, PACKET_MAX_PAYLOAD_SIZE);
dbg(GENERAL_CHANNEL, "PING EVENT:%s\n",sendPackage.payload);
//call Flood.send(sendPackage, destination);
call RouteSend.send(sendPackage, destination);
}

event void CommandHandler.printNeighbors(){
call NeighborDiscovery.print();
}

event void CommandHandler.printRouteTable(){
call Routing.print();
}

event void CommandHandler.printLinkState(){}

event void CommandHandler.printDistanceVector(){}

event void CommandHandler.setTestServer(){
socket_t *s;
socket_port_t src = 20;

s = call Transport.socket();
call Transport.bind(s, src);
call Transport.listen(s);
}

event void CommandHandler.setTestClient(){
socket_t *s;
socket_addr_t addr;
s = call Transport.socket();
call Transport.bind(s, 70);

// Well known server
addr.addr = 1;
addr.port = 20;
call Transport.connect(s, addr);
}

event void Transport.accept(socket_t *s){
dbg(TRANSPORT_CHANNEL, "Server connected\n");
}

event void Transport.connectDone(socket_t *s){
dbg(TRANSPORT_CHANNEL, "Client Connected.\n");
}

event void CommandHandler.setAppServer(){}

event void CommandHandler.setAppClient(){}

void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length){
Package->src = src;
Package->dest = dest;
Package->TTL = TTL;
Package->seq = seq;
Package->protocol = protocol;
memcpy(Package->payload, payload, length);
}
}

