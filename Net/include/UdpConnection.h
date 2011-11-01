#ifndef UDPCONNECTION_H
#define UDPCONNECTION_H

#include "KfifoBuffer.h"

#include <boost/thread.hpp>
#include <boost/function.hpp>
#include <boost/shared_ptr.hpp>
#include <event.h>

struct timeval;
namespace Processor
{
    typedef boost::function<void ()> Job;
    class BoostProcessor;
}

namespace Net{

class IProtocol;
namespace Reactor
{
    class Reactor;
}
namespace Client
{
    class TcpClient;
}

namespace Connection
{

    class UdpConnection;
    typedef boost::shared_ptr<UdpConnection> UdpConnectionPtr;
    typedef boost::function<void (int, UdpConnectionPtr)> Watcher;

    class UdpConnection
    {
    public:
        UdpConnection(
            IProtocol* theProtocol,
            Reactor::Reactor* theReactor,
            Processor::BoostProcessor* theProcessor,
            evutil_socket_t theFd);
        ~UdpConnection();


        //interface for reactor
        int asynRead(int theFd, short theEvt);
        int asynWrite(int theFd, short theEvt);

        //interface for upper protocol
        void close();
        inline bool isClose() {return statusM == CloseE;}
        inline bool isRBufferHealthy(){return inputQueueM.isHealthy();};
        inline bool isWBufferHealthy(){return outputQueueM.isHealthy();};
        unsigned getRBufferSize(){return inputQueueM.size();};
        unsigned getWBufferSize(){return outputQueueM.size();};

        unsigned getInput(char* const theBuffer, const unsigned theLen);
        unsigned getnInput(char* const theBuffer, const unsigned theLen);
        unsigned peeknInput(char* const theBuffer, const unsigned theLen);
        unsigned sendn(char* const theBuffer, const unsigned theLen);

        void setLowWaterMarkWatcher(Watcher* theWatcher);

    private:
        friend class boost::function<void ()>;
        void addReadEvent();
        void addWriteEvent();
        void onRead(int theFd, short theEvt);
        void onWrite(int theFd, short theEvt);
        void _close();
        void _release();


    private:
        struct event* readEvtM;
        struct event* writeEvtM;

        IProtocol* protocolM;
        Reactor::Reactor* reactorM;
        Processor::BoostProcessor* processorM;

        evutil_socket_t fdM;

        //we ensure there is only 1 thread read/write the input queue
        //boost::mutex inputQueueMutexM;
        Net::Buffer::KfifoBuffer inputQueueM;
        boost::mutex outputQueueMutexM;
        Net::Buffer::KfifoBuffer outputQueueM;

        enum Status{ActiveE = 0, CloseE = 1};
        mutable int statusM;

        boost::mutex stopReadingMutexM;
        bool stopReadingM;
        boost::mutex watcherMutexM;
        Watcher* watcherM;

        Client::TcpClient* clientM;
        boost::mutex clientMutexM;
        bool isConnectedNotified;


    };

}
}

#endif /*UDPCONNECTION_H*/

