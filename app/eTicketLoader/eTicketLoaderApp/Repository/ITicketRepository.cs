using eTicketLoader.Data;
using System.Collections.Generic;

namespace eTicketLoaderApp
{
    public interface ITicketRepository
    {
        IEnumerable<TicketEventStatus> GetTicketEventStatus(int eventNo);

        bool BuyTicketAuto(TicketBuyer buyer);
    }
}
