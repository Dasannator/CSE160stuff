//$Author: abeltran2 $
//$LastChangedBy: abeltran2 $

#ifndef PACKET_H
#define PACKET_H

# include "protocol.h"
#include "channels.h"

enum{
    MAXdvrT = 19; 
};

typedef nx_struct dvrTable{
    nx_uint16_t nexthop;
    nx_uint16_t dst;
    nx_uint16_t cost;        //Sequence Number
}dvrTable;

#endif
