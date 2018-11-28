#ifndef TCPpack_H
#define TCPpack_H

enum{
	TCP_HEADER_LENGTH = 9,
    TCP_MAX_PAYLOAD_SIZE = PACKET_MAX_PAYLOAD_SIZE
};

typedef nx_struct TCPpack{
    nx_uint8_t destPort;
    nx_uint8_t srcPort;
    nx_uint16_t seq;
    nx_uint16_t ack;
    nx_uint8_t flag;
    nx_uint8_t adertisedWindow;
    nx_uint8_t numBytes;
    nx_uint8_t payload[TCP_MAX_PAYLOAD_SIZE];
}TCPpack;

enum{
    SYN = 1,
    ACK = 2,
    FIN = 3,
    RST = 4
};

#endif 
