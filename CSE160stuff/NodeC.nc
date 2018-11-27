/**
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 */

#include <Timer.h>
#include "includes/CommandMsg.h"
#include "includes/packet.h"
#include "includes/dvrT.h"


configuration NodeC{
}
implementation {
    components MainC;
    components Node;
    components new AMReceiverC(AM_PACK) as GeneralReceive;
    components new ListC(pack, 64);
    components new ListC(uint16_t, 64) as Neighbors;
    components new TimerMilliC() as myTimerC;
    components new TimerMilliC() as DVRTimer;
    components new ListC(dvrTable, 64) as dvrTableC;

    Node.Boot -> MainC.Boot;
    Node.periodicTimer -> myTimerC; //Wire the interface to the component



    Node.Neighbors -> Neighbors;
    Node.Packets -> ListC;

    Node -> MainC.Boot;

    Node.Receive -> GeneralReceive;

    components ActiveMessageC;
    Node.AMControl -> ActiveMessageC;

    components new SimpleSendC(AM_PACK);
    Node.Sender -> SimpleSendC;

    Node.DVRList-> dvrTableC;
    Node.DVRNodeTimer -> DVRTimer;  // Wireing to interface

    components CommandHandlerC;
    Node.CommandHandler -> CommandHandlerC;
}
