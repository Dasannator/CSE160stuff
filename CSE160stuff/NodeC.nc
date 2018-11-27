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
#include "includes/am_types.h"
#include "includes/channels.h"

configuration NodeC{
}
implementation {
components MainC;
components Node;
components new AMReceiverC(AM_PACK) as GeneralReceive;

Node -> MainC.Boot;

Node.Receive -> GeneralReceive;

components ActiveMessageC;
Node.AMControl -> ActiveMessageC;

components new SimpleSendC(AM_PACK);
Node.Sender -> SimpleSendC;

components CommandHandlerC;
Node.CommandHandler -> CommandHandlerC;

components new FloodingC(AM_FLOODING);
Node.Flood -> FloodingC.SimpleSend;
Node.FloodReceive -> FloodingC.Receive;
Node.PingReplyReceive -> FloodingC.ReplyReceive;


// Neighbor Discovery
components NeighborDiscoveryC;
Node.NeighborDiscovery -> NeighborDiscoveryC;

components RoutingC, RoutePingC;
Node.Routing -> RoutingC;

Node.RouteSend -> RoutePingC.SimpleSend;
Node.RouteReceive -> RoutePingC.Receive;
Node.RouteReplyReceive -> RoutePingC.ReplyReceive;

// Transport Layer
components TransportC;
Node.Transport -> TransportC;

// App Layer
components CounterServerC;
Node.CounterServer -> CounterServerC;

components CounterClientC;
Node.CounterClient -> CounterClientC;
}

