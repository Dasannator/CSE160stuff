/*
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date    2013/09/03
 *
 */
#include <Timer.h>
#include "includes/command.h"
#include "includes/packet.h"
#include "includes/protocol.h"
#include "includes/CommandMsg.h"
#include "includes/sendInfo.h"
#include "includes/channels.h"

module Node {
    uses interface Boot;
    uses interface SplitControl as AMControl;
    uses interface Receive;
    uses interface CommandHandler;
    uses interface Flooding;
    uses interface NeighborDiscovery as NeighborDiscovery;
    uses interface DistanceVectorRouting as DistanceVectorRouting;
    uses interface Timer<TMilli> as acceptTimer;
    uses interface Timer<TMilli> as writeTimer;
    //uses interface List<socket_t> as serverConnections;

}

implementation {

    event void Boot.booted() {
        call AMControl.start();
        dbg(GENERAL_CHANNEL, "Booted\n");
        call NeighborDiscovery.start();
        call DistanceVectorRouting.start();
    }

    event void AMControl.startDone(error_t err) {
        if(err == SUCCESS) {
            dbg(GENERAL_CHANNEL, "Radio On\n");
        } else {
            //Retry until successful
            call AMControl.start();
        }
    }

    event void AMControl.stopDone(error_t err) {}

    event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len) {
        pack* myMsg = (pack*) payload;
        if(len!=sizeof(pack)) {
                dbg(GENERAL_CHANNEL, "Unknown Packet Type %d\n", len);
        } else if(myMsg->dest == 0) {
            call NeighborDiscovery.handleNeighbor(myMsg);
        } else if(myMsg->protocol == PROTOCOL_DV) {
            call DistanceVectorRouting.handleDV(myMsg);
        } else {
            call DistanceVectorRouting.routePacket(myMsg);
            //call Flooding.handleFlooding(myMsg);
        }
        return msg;
    }

    event void CommandHandler.ping(uint16_t destination, uint8_t *payload) {
        call DistanceVectorRouting.ping(destination, payload);
        //call Flooding.ping(destination, payload);
    }

    event void CommandHandler.printNeighbors() {
            call NeighborDiscovery.printNeighbors();
    }

    event void CommandHandler.printRouteTable() {
        //call DistanceVectorRouting.printRouteTable();
    }

    event void CommandHandler.printLinkState() {}

    event void CommandHandler.printDistanceVector() {}

    event void CommandHandler.printMessage(uint8_t *payload) {
        dbg(GENERAL_CHANNEL, "%s\n", payload);
    }

    event void CommandHandler.setTestServer(uint8_t port) {}

    event void CommandHandler.setTestClient(uint16_t dest, uint8_t srcPort, uint8_t destPort, uint16_t num) {}

    event void CommandHandler.setAppServer() {}

    event void CommandHandler.setAppClient() {}

  //  event void CommandHandler.closeConnection(uint16_t dest, uint8_t srcPort, uint8_t destPort){
  //socket_t toClose;
  //toClose = call Transport.findSocket(dest, srcPort, destPort);
//  if (toClose !=0){
//    call Transport.close(toClose);
  }
}


}

event void acceptTimer.fired(){
  socket_t temp;
  int sz;
  temp = call Transport.accept(socket);
  if (temp != 0) {
    call serverConnections.pushback(temp);
  }
  sz = call serverConnections.size();
  for (int i = 0; i <sz; i++) {
    newSocket = call serverConnections.get(i);
    nb = call Transport.read(newSocket, &numToSend, 2);

    while (nb !=0) {
      dbg(GENERAL_CHANNEL, "Socket %d received number: %d\n", newSocket, numToSend);
      nb = call Transport.read(newSocket, &numToSend, 2);
    }
  }
}

event void writeTimer.fired() {
  if (isNewConnection == 1) {
    while (isNewConnection) {
      bytesWrittenOrRead = call Transport.write(socket, &numToSend, 2);
      if (bytesWrittenOrRead == 2) {
        numToSend++;
      }
      if (numToSend == nb+1) {
        dbg(GENERAL_CHANNEL, "CLient done sending ");
        isNewConnection = 0;
      }
      if (bytesWrittenOrRead == 0)
      break;
    }
  }
}
