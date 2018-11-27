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
#include "includes/CommandMsg.h"
#include "includes/sendInfo.h"
#include "includes/channels.h"
#include "includes/dvrT.h"

module Node{
  uses interface Boot;


  uses interface SplitControl as AMControl;
  uses interface Receive;

  uses interface SimpleSend as Sender;     // renames the nc file to sender

  uses interface CommandHandler;
  uses interface List<uint16_t> as Neighbors;
  uses interface List<pack> as Packets;
  uses interface Timer<TMilli> as periodicTimer;
  uses interface Timer<TMilli> as DVRNodeTimer;
  uses interface List<dvrTable> as DVRList;
}




implementation{
  pack sendPackage;
  uint16_t sequence = 0;

  // Prototypes



  //New code down to roughly 136

  dvrTable newdvr;
  event void DVRNodeTimer.fired(){
    uint8_t j = 0, counter = 0;
  dvrTable RoutingPacket[3];



    uint32_t i = 0;
    uint16_t max = call Neighbors.size();
    for(i = 0; i < max;i++){
      uint16_t Neighbor = call Neighbors.get(i);
      newdvr.dst = Neighbor;
      newdvr.nexthop = Neighbor;
      newdvr.cost = 1;

      call DVRList.pushback(newdvr);
    }


    for(i = 0; i < 3; i++) {

      RoutingPacket[i].dst = 0;

      RoutingPacket[i].nexthop = 0;

      RoutingPacket[i].cost = 0;

    }

    for(i = 0; i < max; i++ ){

      while(j <= call DVRList.size()){
        dvrTable Values = call DVRList.get(j);
        RoutingPacket[counter].dst = Values.dst;
        RoutingPacket[counter].cost= Values.cost;
        RoutingPacket[counter].nexthop= Values.nexthop;
        counter++;

        //if(split horizon)

        //if(poison reverse

        if (counter == 3 || j  == call DVRList.size()){

          makePack(&sendPackage, TOS_NODE_ID, TOS_NODE_ID, 1, PROTOCOL_DV, sequence++, &RoutingPacket, PACKET_MAX_PAYLOAD_SIZE);
          call Sender.send(&sendPackage, AM_BROADCAST_ADDR);
          //send your neighbors to the next node and add them to the routing table
          //example - for node 2 neighbors are 1 and 3. - send this 1 to node 3 .Here 1 will get to know that node 2 is connected to 3. So update the routing table.

          while (counter > 0) {

            counter--;

            RoutingPacket[counter].dst = 0;

            RoutingPacket[counter].cost = 0;

            RoutingPacket[counter].nexthop = 0;

          }
        }
        j++;
      }
      j=0;
    }
  }

  //void Split_Horizon {
  //if (myMsg -> dest != TOS_NODE_ID){
  //   if (isDuplicate(myMsg -> src, *myMsg) == TRUE)
  // return msg;
  //}
  // return;
  //}


  // void Poison_Reverse{
  //if (DVRList[j].nexthop != dest){
  //DVRList[j].nexthop == 255;
  //return;

  //}
  //else
  //return;

  //}

  void discoverNeighbors(){
    uint16_t tTol = 1;
    makePack(&sendPackage, TOS_NODE_ID, TOS_NODE_ID, 1, PROTOCOL_PING, sequence++, "HI NEIGHBOR", PACKET_MAX_PAYLOAD_SIZE);
    call Sender.send(sendPackage, AM_BROADCAST_ADDR);
    CommandHandler.printNeighbors;
  }
  event void periodicTimer.fired(){
    //ping(TOS_NODE_ID, "NEIGHBOR SEARCH");
    discoverNeighbors();
    //dbg(NEIGHBOR_CHANNEL,"Neighboring nodes %s\n", Neighbor);
    //CommandHandler.printNeighbors;
    //dbg(NEIGHBOR_CHANNEL,"Neighboring nodes %s\n", Neighbor);

  }

  event void Boot.booted(){
    call AMControl.start();
    call periodicTimer.startPeriodic(5000);
    call DVRNodeTimer.startPeriodic(35000);


    //dbg(GENERAL_CHANNEL, "Booted\n");
  }

  event void AMControl.startDone(error_t err){
    if(err == SUCCESS){
      //dbg(GENERAL_CHANNEL, "Radio On\n");
    }else{
      //Retry until successful
      call AMControl.start();
    }
  }

  bool isDuplicate(uint16_t from, pack newPack){

    uint16_t i;
    uint16_t max = call Packets.size();
    for (i = 0; i < max;i++){
      pack oldPack = call Packets.get(i);
      if (oldPack.src == newPack.src && oldPack.seq == newPack.seq){
        //dbg(FLOODING_CHANNEL, "Packet is duplicate so its dropped\n");
        return TRUE;
      }
    }
    return FALSE;
  }

  event void AMControl.stopDone(error_t err){

  }

  event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len){   //name implies

    if(len==sizeof(pack)){
      pack* myMsg=(pack*) payload;
      // dbg(GENERAL_CHANNEL, "Package Payload: %s\n", myMsg->payload);
      if (myMsg -> TTL == 0){
        //dbg(FLOODING_CHANNEL, "Packet Dropped due to TTL at 0\n");
        return msg;
      }
      else if (myMsg -> dest != TOS_NODE_ID){
        if (isDuplicate(myMsg -> src, *myMsg) == TRUE)
        return msg;
        else if (myMsg -> src == myMsg -> dest){
          int has = 0, i = 0;
          for (i = 0; i < call Neighbors.size(); i++){
            int temp = call Neighbors.get(i);
            if (temp == myMsg -> src)
            has++;
          }
          if (has == 0)
          call Neighbors.pushback(myMsg -> src);
          //CommandHandler.printNeighbors;
          //dbg(NEIGHBOR_CHANNEL,"test\n");
          //dbg(NEIGHBOR_CHANNEL, "we got a neighbor\n");
        }
        call Packets.pushback(*myMsg);

        myMsg -> TTL -= 1;
        dbg(FLOODING_CHANNEL, "Packet Received from %d, flooding\n", myMsg->src);

        call Sender.send(*myMsg, AM_BROADCAST_ADDR);
      }
      else if (myMsg -> dest == 0){
        call Neighbors.pushback(myMsg -> src);
        makePack(&sendPackage, TOS_NODE_ID, 0, MAX_TTL, PROTOCOL_PINGREPLY, sequence++, "Howdy Neighbor!", PACKET_MAX_PAYLOAD_SIZE);

        call Sender.send(sendPackage, AM_BROADCAST_ADDR);
      }

      else if (myMsg -> protocol == PROTOCOL_PINGREPLY && myMsg -> dest == TOS_NODE_ID){
        dbg(GENERAL_CHANNEL, "Packet Recieved: %s\n", myMsg -> payload);
      }
      //Ping Reply for the dvr table package
      else if(myMsg -> protocol == PROTOCOL_DV){
        dbg(ROUTING_CHANNEL, "Routing table has been recieved by neighbor: \n");
        mergeroute(RoutingPacket,myMsg,DVRList);
        call CommandeHandler.printRouteTable();
        // if( new routing table values != old routing table values )
        // call merge route to route add or modify routing tables

      }


      else {
        myMsg -> dest == TOS_NODE_ID;
        //dbg(GENERAL_CHANNEL, "Packet Recieved: %s\n", myMsg -> payload);
        call Packets.pushback(*myMsg);
        makePack(&sendPackage, TOS_NODE_ID, myMsg -> src, MAX_TTL, PROTOCOL_PINGREPLY, sequence++, "Thank You.", PACKET_MAX_PAYLOAD_SIZE);
        call Sender.send(sendPackage, AM_BROADCAST_ADDR);
      }
      return msg;
    }
    dbg(GENERAL_CHANNEL, "Unknown Packet Type %d\n", len);
    return msg;
  }


  event void CommandHandler.ping(uint16_t destination, uint8_t *payload){
    dbg(GENERAL_CHANNEL, "PING EVENT \n");
    makePack(&sendPackage, TOS_NODE_ID, destination, MAX_TTL, PROTOCOL_PING, sequence++, payload, PACKET_MAX_PAYLOAD_SIZE);
    call Packets.pushback(sendPackage);
    call Sender.send(sendPackage, AM_BROADCAST_ADDR);
  }



  event void CommandHandler.printNeighbors(){

    uint16_t i = 0;
    uint16_t max = call Neighbors.size();

    for(i = 0; i < max;i++){
      dbg(NEIGHBOR_CHANNEL,"i am printing\n");
      //uint16_t Neighbor = call Neighbors.get(i);
      //printf('%s', Neighbor);
      //dbg(NEIGHBOR_CHANNEL,"Neighboring nodes %s\n", Neighbor);

    }
  }

  event void CommandHandler.printRouteTable(){
    //uint8_t i;
    //dvrTable x;
    //uint8_t MaxR = call DVRList.size();
    //for(i = 0; i < MaxR; i++){
      //dvrTable XPRINT = call DVRList.get(i);
      //dbg(ROUTING_CHANNEL, "Dest = %u Next Node = %u Cost = %u:\n", XPRINT.dst,  XPRINT.nexthop, XPRINT.cost );

      //}
    }

  event void CommandHandler.printLinkState(){}

  event void CommandHandler.printDistanceVector(){}

  event void CommandHandler.setTestServer(){}

  event void CommandHandler.setTestClient(){
    int i;
    int max = call Neighbors.size();
    dbg(NEIGHBOR_CHANNEL, "I am node %u. my neighbors are:\n", TOS_NODE_ID);
    for(i = 0; i < max; i++){
      dbg(NEIGHBOR_CHANNEL, "%u\n", call Neighbors.get(i));
    }
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
    /* new values in payload */

  }


  void mergeroute(dvrTable RoutingPacket, pack* myMsg, dvrTable DVRList) {
    bool DVRupdate = FALSE;
    bool inTable = FALSE;
    uint8_t i,j=0;
    dvrTable InPack = call RoutingPacket.get(j);
    InPack->src;
    //dvrTable MastaList = call DVRList.get(i);
    //for(j = 0; j < RoutingPacket.size(); j++){
      //for(i = 0; i < DVRList.size(); i++){

        //if (InPack[j].nexthop != MastaList[i].nexthop){
          //inTable = TRUE;
          //if(InPack[j].cost + 1 <= MastaList[i].cost)){
            //MastaList[i].cost = InPack[j].cost + 1;
            //MastaList[i].nexthop = InPack[j].nexthop;
            //DVRupdate = TRUE;
          //}
        //}
        //if(DVRList.size()-1 == i && inTable == FALSE ){

          //newdvr.dst = InPack[j].dst;
          //newdvr.nexthop = InPack[j].nexthop;
          //newdvr.cost = InPack[j].cost+1;
          //call DVRList.pushback(newdvr);

        //}
        //DVRupdate = FALSE;
        //inTable = FALSE;

      //}
    //}

    //return DVRupdate;
  }
  // update the values mainly cost
  // add the new values in DVRList
}
