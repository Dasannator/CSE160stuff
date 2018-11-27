#include "../../includes/socket.h"
#include "../../includes/packet.h"
#include "../../includes/am_types.h"

configuration TransportC{
    provides interface Transport;
}

implementation{
    components TransportP;
    //Internal wiring
    components new PoolC(socket_t, MAX_NUM_OF_SOCKETS);
    components new QueueC(socket_t *, MAX_NUM_OF_SOCKETS);

    components new PoolC(reliable_store_t, MAX_NUM_OF_SOCKETS) as relPool;
    components new QueueC(reliable_store_t *, MAX_NUM_OF_SOCKETS) as relQueue;
    components new TimerMilliC() as relTimer;
    TransportP.RetransPool -> relPool;
    TransportP.RetransQueue -> relQueue;
    TransportP.RetransTimer -> relTimer;

    components new PoolC(pack, MAX_NUM_OF_SOCKETS) as SendPool;
    TransportP.SendPool->SendPool;

    // We do 2 times the pool since this will results in less cache misses
    components new HashmapC(socket_t *, MAX_NUM_OF_SOCKETS * 2);
    components RouteSendC;
    components RandomLfsrC;
    components TransportPacketC;


    //Internal Wiring
    TransportP.Pool -> PoolC;
    TransportP.Hashmap -> HashmapC;
    TransportP.Sender -> RouteSendC;
    TransportP.Receive -> RouteSendC;
    TransportP.Packet -> TransportPacketC;
    TransportP.Random -> RandomLfsrC;
    TransportP.SendQueue->QueueC;

    //External wiring
    Transport = TransportP.Transport;
}
