#include "../../includes/socket.h"
#include "../../includes/transport.h"
#include "../../includes/packet.h"

#define DEBUG_RECEIVED_DATA TRUE
#define DEBUG_READ_DATA TRUE
#define DEBUG_SENT_DATA TRUE

module TransportP{
    provides interface Transport;
    uses interface TransportPacket as Packet;
    uses interface Pool<socket_t>; uses interface Hashmap<socket_t *>;
    uses interface SimpleSend as Sender;
    uses interface Timer<TMilli> as RetransTimer;
    uses interface Receive;
    uses interface Random;

    uses interface Queue<socket_t *> as SendQueue;

    uses interface Pool<reliable_store_t> as RetransPool;
    uses interface Queue<reliable_store_t *> as RetransQueue;
    uses interface Pool<pack> as SendPool;
}

implementation{
//    pack sendPack;
    transpack sendTranspack;
    uint16_t RTT = 12000;

    // PROTOTYPES
    uint8_t calcAdvertiseWin(socket_t *s);
    uint8_t calcEffectiveWin(socket_t *s, uint16_t advertiseWindow);

    // Generates key to be used with hashmap based on a destination address
    // destination port, and source port.
    uint32_t key(uint16_t destAddr, uint8_t dest, uint8_t src){
        // address - 16 bits
        // port - 8 bits
        // src - 8 bits
        // If you or the above three shifted correctly this will generate a unique key
        return ((uint32_t) destAddr <<16) | ((uint32_t) dest <<8) |  (uint32_t) src;
    }

    // Generates a key to be used in a hashmap based on a passed socket.
    uint32_t socketKey(socket_t *fd){
        return key(fd->dest.addr, fd->dest.port, fd->src);
    }

    // Generates a key to be used in a hashmap based on a passed packet.
    uint32_t packKey(pack *p){
        transpack *t = call Packet.GetTransport(p);
        // Source is swapped since we are looking at it from our point of view.
        return key(p->src, t->src, t->dest);
    }


    void initReceiveBuff(socket_t *s, transpack *t){
        // Set the receiving values.
        s->lastRcvd = s->lastRead = t->seq;
        s->nextExpected = t->seq + 1;
    }

    void initSendBuff(socket_t *s, uint16_t seq){
        s->lastSent = s->lastWritten = s->lastAck = seq;
        s->lastAck++;
    }

    void updateAck(socket_t *s, transpack *t){
        if(t->ack > s->lastAck){
            s->lastAck = t->ack;
        // This is the wrap around check. We check to see if t->ack wraps
        // around to 2 and s->lastAck is 240, 240 - 2 = 238 which is larger
        // then 128* 3/4 = 96. We could probably be a less conservative about
        // this since we are not doing selective acknowledgements.
        }else if(s->lastAck - t->ack > (SOCKET_BUFFER_SIZE/4) * 3){
            s->lastAck = t->ack;
        }

        // Update window.
        s->effectiveWindow = calcEffectiveWin(s, t->advertiseWindow);
    }

    uint16_t min(uint16_t a, uint16_t b){
        if(a<b){
            return a;
        }
        return b;
    }


    uint8_t calcEffectiveWin(socket_t *s, uint16_t advertiseWindow){
        return advertiseWindow - (s->lastSent - s->lastAck - 1);
    }

    pack * send(socket_t *s, pack *p, uint16_t dest){
        transpack *t;
        t = call Packet.GetTransport(p);

        // Always include the advertise window and last acknowledgement
        t->advertiseWindow = calcAdvertiseWin(s);
        t->ack = s->nextExpected;

        // Include send info from port.
        t->src = s->src;
        t->dest = s->dest.port;
        call Sender.send(*p, dest);
        return p;
    }

    // Returns the ammount of data that can be written to a socket.
    uint16_t writeLen(socket_t *s){
        // This is the "normal" case with no wrap around pointers.
        if(s->lastWritten % SOCKET_BUFFER_SIZE >= (s-> lastAck -1)% SOCKET_BUFFER_SIZE){
            return SOCKET_BUFFER_SIZE  - (s->lastWritten % SOCKET_BUFFER_SIZE- s->lastAck% SOCKET_BUFFER_SIZE -2);
        }else{
            return s->lastAck % SOCKET_BUFFER_SIZE- s->lastWritten% SOCKET_BUFFER_SIZE - 2;
        }
    }

    uint16_t readLen(socket_t *s){
        // This is the "normal" case with no wrap around pointers.
        if(s->lastRcvd >= s->lastRead){
            return s->lastRcvd - s->lastRead;
        }else{
            return 0xFF - s->lastRcvd + s->lastRead;
        }
    }

    uint8_t calcAdvertiseWin(socket_t *s){
        uint16_t len;
        len = SOCKET_BUFFER_SIZE - readLen(s);
        if(len>1){
            len-=2;
        }
        return len;
    }

    uint16_t retransLen(socket_t *s, uint16_t lastSent){
        if(s->lastWritten >= lastSent){
            return s->lastWritten - lastSent;
        }else{
            return s->lastWritten + (0xFF - lastSent);
        }
    }

    uint16_t sendLen(socket_t *s){
        return retransLen(s, s->lastSent);
    }

    void addToReliableQueue(socket_t *s, transpack *t){
        reliable_store_t * rel;
        // Mark this value in the reliability queue.
        rel = call RetransPool.get();
        rel->socket = s;
        rel->flag = t->flags;
        rel->sentIndex = t->seq;
        rel->resendTime = call RetransTimer.getNow() + s->RTT;
        call RetransQueue.enqueue(rel);
        if( !call RetransTimer.isRunning()){
            call RetransTimer.startOneShotAt(rel->resendTime, 0);
        }
    }

    void sockPrint(socket_t *s){
        dbg(TRANSPORT_CHANNEL, "Socket (sp %hhu, dp %hhu, addr %hu)\n", s->src, s->dest.port, s->dest.addr);
        dbg(TRANSPORT_CHANNEL, "Sent: Last Written: %hu, Last Acked: %hu, Last Sent: %hu To Send: %hhu\n",
        s->lastWritten, s->lastAck, s->lastSent, sendLen(s));
        dbg(TRANSPORT_CHANNEL, "Recvd: Last Read: %hu, Last Received: %hu, Next Expected: %hu\n",
        s->lastRead, s->lastRcvd, s->nextExpected);
    }

    task void sendNewData(){
        socket_t *s;
        uint16_t len, i;
        pack * sendPack;
        transpack *t;
        sendPack = call SendPool.get();

        if(call SendQueue.empty()){
            return;
        }
        s = call SendQueue.dequeue();
        len = min(min(sendLen(s), DATA_MAX_SIZE), s->effectiveWindow);

        t = call Packet.GetTransport(sendPack);

        // Write data to packet.
        for(i=0; i<len; i++){
            t->payload[i] = s->sendBuff[(i+s->lastSent)%SOCKET_BUFFER_SIZE];
        }
        sockPrint(s);

        // Fill packet data header
        t->src = s->src;
        t->dest = s->dest.port;
        call Packet.SetData(t);
        t->seq = s->lastSent + 1;
        t->len = len;
        addToReliableQueue(s, t);

        // Send the data
        call SendPool.put(send(s, sendPack, s->dest.addr));
        dbg(TRANSPORT_CHANNEL, "%hu bytes were transmitted to port %hu, address %hhu Effective Window: %hhu\n", len, s->dest.port, s->dest.addr, s->effectiveWindow);
        sockPrint(s);


        // For debugging reasons, lets print it too.
        dbg(TRANSPORT_CHANNEL, "Payload: ");
        for(i=0; i<len; i++){
            dbg_clear(TRANSPORT_CHANNEL, "%hhu, ", t->payload[i]);
        }
        dbg_clear(TRANSPORT_CHANNEL, "\n");

        s->lastSent += len;
    }
    void restartRetrans(){
       uint16_t now;
       reliable_store_t * rel;

       // Retry again in a future time.
       if(call RetransQueue.empty()){
           return;
       }

       now =  call RetransTimer.getNow();
       rel = call RetransQueue.head();
       if(now < rel->resendTime){
           call RetransTimer.startOneShot(100);
       }else{
           uint16_t dt =  rel->resendTime - call RetransTimer.getNow();
           dbg(TRANSPORT_CHANNEL, "Current Time %hu: Refire Time %hu DT: %hu\n", now, rel->resendTime, dt);
           call RetransTimer.startOneShot(dt);
       }
    }

    // Given an entry in a reliable_store_t, check to see if has been acknowledged.
    bool wasAcked(reliable_store_t *r){
        // Get the socket stored in reliable_store_t for looks.
        socket_t *s = r->socket;
        // This is the typical case. Values between these two sections are
        // considered not acked.
        if( s->lastSent > s->lastAck ){
            if(r->sentIndex > s->lastAck && r->sentIndex < s->lastSent){
                return FALSE;
            }else{
                return TRUE;
            }
        // This is the wrap around case. Values between s->lastSent and s->lastAck
        // are considered acknowledged.
        }else{
            // If you fall between the two, in this case, you are considered acked.
            if(r->sentIndex <= s->lastAck && r->sentIndex >= s->lastSent){
                return TRUE;
            }else{
                return FALSE;
            }
        }
    }

   event void RetransTimer.fired(){
       reliable_store_t * rel;
       if( call RetransQueue.empty()){
           return;
       }

       rel = call RetransQueue.dequeue();
       // THIS IS CAUSING ACKS TO OCCUR EVEN IF THAT IS NOT THE CASE.
       if(!wasAcked(rel)){
           uint16_t i, len, lastSent;
           transpack *t;
           socket_t *storedSocket;
           //  The packet was dropped!
           dbg(TRANSPORT_CHANNEL, "\nPacket at %hhu was dropped! Reliable left: %hu\n\n", rel->sentIndex, call RetransPool.size());
           //sockPrint(rel->socket);


           // Now we are going to temporary store the last sent so we can dequeue
           // everything else.
           lastSent = rel->socket->lastAck-1;
           storedSocket = rel->socket;

           // Lets move the send queue back.
           rel->socket->lastSent = lastSent;
           call RetransPool.put(rel);

           len = call RetransQueue.size();
           for(i=0; i<len; i++){
               rel = call RetransQueue.dequeue();
               if(rel->socket == storedSocket){
                   // We will put everything back into the pool since our
                   // sender will requeue the data.
                   call RetransPool.put(rel);
               }else{
                    call RetransQueue.enqueue(rel);
               }
           }

           call SendQueue.enqueue(storedSocket);
       }else{
//           dbg(TRANSPORT_CHANNEL, "\nPacket at %hhu was transmitted successfully.\n\n", rel->sentIndex);
           call RetransPool.put(rel);
       }
       restartRetrans();
   }

    command socket_t* Transport.socket(){
        if (!call Pool.empty()){
            socket_t *s;
            s = call Pool.get();
            s->state = CLOSED;
            s->lastWritten = 0;
            s->lastAck = 0xFF;
            s->lastSent = 0;
            s->lastRead = 0;
            s->lastRcvd = 0;
            s->nextExpected = 0;
            s->RTT = RTT;
            return s;
        }else{
            return NULL;
        }
    }

    command error_t Transport.bind(socket_t *fd, socket_port_t port){
        fd->src = port;
        return SUCCESS;
    }

    command uint16_t Transport.write(socket_t *s, uint8_t *buff, uint16_t bufflen){
        uint16_t i, pos;
        // We are limited by either the buffer length or the amount which can be written length;
        uint16_t len = min(writeLen(s), bufflen);
        sockPrint(s);
        for(i=0; i<len;i++){
            s->sendBuff[ (s->lastWritten + i + 1) % SOCKET_BUFFER_SIZE] = buff[i];
        }

        dbg(TRANSPORT_CHANNEL, "Write Len is:%hu\n", writeLen(s));
        dbg(TRANSPORT_CHANNEL, "Writting %hu bytes of Data:", len);
        for(i=0; i < len; i++){
            pos = (s->lastWritten + i + 1) % SOCKET_BUFFER_SIZE;
            dbg_clear(TRANSPORT_CHANNEL, "%hhu at %hhu, ", s->sendBuff[pos], pos);
        }

        s->lastWritten += len;
        dbg_clear(TRANSPORT_CHANNEL, "\n");

        if(sendLen(s)>0){
            // We don't immediately send the data out.
            call SendQueue.enqueue(s);
            post sendNewData();
        }
        if(len == 0){
            //sockPrint(s);
        }
        return len;
    }

    command error_t Transport.receive(pack* package){
        return SUCCESS;
    }

    command uint16_t Transport.read(socket_t *s, uint8_t *buff, uint16_t bufflen){
        uint16_t i;
        uint16_t pos;
        // We are limited by either the buffer length or the amount which can be written length;
        uint16_t len = min(readLen(s), bufflen);
        for(i=0; i<len;i++){
            pos = (s->lastRead + i) % SOCKET_BUFFER_SIZE;
            buff[i] = s->rcvdBuff[pos];
            // For debugging purposes, we are going to overwrite data with the
            // position they are located at
            s->rcvdBuff[pos] = pos;
        }
        /*
        dbg(TRANSPORT_CHANNEL, "WHOLE TAMALE: ");

        for(i=0; i< SOCKET_BUFFER_SIZE; i++){
            dbg_clear(TRANSPORT_CHANNEL, "%hhu, ", s->rcvdBuff[i]);
        }
            dbg_clear(TRANSPORT_CHANNEL, "\n");
        */
        s->lastRead += len;
        return len;
    }

    command error_t Transport.connect(socket_t *fd, socket_addr_t addr){
        pack msg;
        transpack *tpack;

        // Set destination address
        fd->dest = addr;

        dbg(TRANSPORT_CHANNEL, "Initiating Connection from port %hhu to  port %hhu, address %d\n", fd->src, fd->dest.port, fd->dest.addr);
        // We are going to keep track of him now
        call Hashmap.insert(socketKey(fd), fd);

        // Make syn packet.
        tpack = call Packet.GetTransport(&msg);
        call Packet.clearFlags(tpack);
        call Packet.SetSyn(tpack);
        tpack->dest = fd->dest.port;
        tpack->src = fd->src;
        tpack->len = 0;

        // We are going to generate a random syn to start with.
        tpack->seq = call Random.rand16();
        initSendBuff(fd, tpack->seq);

        // Send first syn packet.
        send(fd, &msg, fd->dest.addr);
        addToReliableQueue(fd, tpack);

        fd->state = SYN_SENT;
        return SUCCESS;
    }

    command error_t Transport.close(socket_t *fd){
        return SUCCESS;
    }

    command error_t Transport.release(socket_t *fd){
        return SUCCESS;
    }

    command error_t Transport.listen(socket_t *fd){
        dbg(TRANSPORT_CHANNEL, "Server started to listen at port %d\n", fd->src);
        // Set destination address & port
        fd->dest.addr = ROOT_SOCKET_ADDR;
        fd->dest.port = ROOT_SOCKET_PORT;

        fd->state = LISTEN;
        // We are going to keep track of him now
        call Hashmap.insert(socketKey(fd), fd);
        return SUCCESS;
    }


    void handleHandshake(pack *p, transpack *tpack){
       if(call Packet.IsAck(tpack)){
           uint32_t k = packKey(p);
           if( call Hashmap.contains(k)){
               pack *sendPack;
               transpack *response;
               socket_t *sock = call Hashmap.get(k);
               sendPack = call SendPool.get();
               dbg(TRANSPORT_CHANNEL, "Received syn+ack response from addr %hhu - port %hhu\n", p->src, tpack->src);

               // Send back an acknowledgement
              response = call Packet.GetTransport(sendPack);
              call Packet.clearFlags(response);
              call Packet.SetAck(response);
              response->src = sock->src;
              response->dest = sock->dest.port;

              // We are going to ack the last message they sent us.
              response->ack = tpack->seq + 1;
              initReceiveBuff(sock, tpack);

              // Send the packet and change our state.
              sock->state = ESTABLISHED;
              call SendPool.put(send(sock, sendPack, p->src));

              signal Transport.connectDone(sock);
           }else{
               dbg(TRANSPORT_CHANNEL, "Received unexpected syn+ack response from addr %hhu - port %hhu. This socket is not active\n", p->src, tpack->src);
           }
       }else{
           // Check to see if we have a listening socket.
           uint32_t k = key(ROOT_SOCKET_ADDR, ROOT_SOCKET_PORT, tpack->dest);
           if( call Hashmap.contains(k) ){
              uint32_t connKey;
              socket_t *sock;
              pack *sendPack;
              transpack * response;
              sendPack = call SendPool.get();

              connKey = key(p->src, tpack->src, tpack->dest);

              // This is a connection we have seen. This may occur due to a
              // failed handshake.
              if( call Hashmap.contains(connKey)){
                  dbg(TRANSPORT_CHANNEL, "Re-attempting to connect to addr %hhu - port %hhu\n", p->src, tpack->src);
                  sock = call Hashmap.get(connKey);
              // This is a new socket.
              }else{
                  sock = call Transport.socket();
                  sock->src = tpack->dest;
                  sock->dest.port = tpack->src;
                  sock->dest.addr = p->src;

                  initSendBuff(sock, call Random.rand16());
                  call Hashmap.insert(connKey, sock);

                  dbg(TRANSPORT_CHANNEL, "New connection with addr %hhu, port %hhu, sequence %d\n", p->src, tpack->src, sock->lastWritten);
              }

              // Now lets send back a response.
              response = call Packet.GetTransport(sendPack);
              call Packet.clearFlags(response);
              call Packet.SetAck(response);
              call Packet.SetSyn(response);
              response->src = sock->src;
              response->dest = sock->dest.port;
              response->seq = sock->lastSent;

              // Set the defaults.
              sock->state = SYN_RCVD;
              initReceiveBuff(sock, tpack);
              call SendPool.put(send(sock, sendPack, p->src));
           }else{
               dbg(TRANSPORT_CHANNEL, "We are not listening on port %hhu\n", tpack->dest);
           }
       }
    }

    void handleData(socket_t *s, pack *p, transpack *t){
        pack * sendPack;
        transpack *response;
        uint16_t i;
        uint16_t pos;
        sendPack = call SendPool.get();

        // At the moment we only allow for in-order reception so if it is out of
        // order we drop it.
        if (s->nextExpected != t->seq){
            dbg(TRANSPORT_CHANNEL, "Packet received out of order. Expected %hhu, received %hhu\n", s->nextExpected, t->seq);

            // We are going to transmit an ack just in case our ack was lost.
            response = call Packet.GetTransport(sendPack);
            call Packet.clearFlags(response);
            call Packet.SetAck(response);
            call SendPool.put(send(s, sendPack, p->src));
            return;
        }

        // If they are the same then we can put them in our receive buffer.
        dbg(TRANSPORT_CHANNEL, "Receiving Data:");
        for(i=0; i < t->len; i++){
            pos = (s->nextExpected+i) % SOCKET_BUFFER_SIZE;
            s->rcvdBuff[pos] = t->payload[i];
            dbg_clear(TRANSPORT_CHANNEL, "%hhu at %hhu, ", s->rcvdBuff[pos], pos);
        }
        dbg_clear(TRANSPORT_CHANNEL, "\n");

        s->nextExpected += t->len;
        s->lastRcvd += t->len;
        //dbg(TRANSPORT_CHANNEL, "%hhu to be read. Located at [%hhu, %hhu]\n", readLen(s), s->lastRead, s->nextExpected);

        // Send an ack back.
        response = call Packet.GetTransport(sendPack);
        call Packet.clearFlags(response);
        call Packet.SetAck(response);
        call SendPool.put(send(s, sendPack, p->src));
    }

    event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len){
       pack *p;
       transpack *tpack;
       socket_t *s;
       p = (pack *)payload;
       tpack = call Packet.GetTransport(p);

       //call Packet.print(tpack);
       // First lets see if this is attempting to establish a new connection.
       if(call Packet.IsSyn(tpack) ){
           handleHandshake(p, tpack);
           return msg;

       // This connection should be available, get the socket.
       }else{
           // Get the socket.
           uint32_t k = packKey(p);
           if( call Hashmap.contains(k)){
               s = call Hashmap.get(k);
               if(s->state == CLOSED){
                   dbg(TRANSPORT_CHANNEL, "Socket is closed\n");
                   call Packet.print(tpack);
                   return msg;
               }
           }else{
               dbg(TRANSPORT_CHANNEL, "Socket does not exist\n");
               return msg;
           }
       }

       // If we get to this point, we have a valid socket. Lets update the ack
       // For all packages.
       updateAck(s, tpack);
       //sockPrint(s);

       if(call Packet.IsData(tpack)){
           handleData(s, p, tpack);
           return msg;
       }

       if(call Packet.IsAck(tpack)){
           if(s->state == SYN_RCVD){
               dbg(TRANSPORT_CHANNEL, "Handshake complete!\n");
               s->state = ESTABLISHED;
               signal Transport.accept(s);
           }

           if(tpack->ack > s->lastAck){
              s->lastAck = tpack->ack;
           }
           return msg;
       }

       return msg;
   }
}
