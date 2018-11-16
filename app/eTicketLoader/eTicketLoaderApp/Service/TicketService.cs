
using System;
using System.Collections.Generic;
using System.Text;

namespace eTicketLoaderApp
{
    public sealed class TicketService
    {
        /// <summary>檢查是否還有票券可以購買</summary>
        public bool HasTicketForSell(IEnumerable<TicketEventStatus> items)
        {
            foreach (TicketEventStatus item in items)
            {
                if (item.TicketLeft > 0)
                    return true;
            }

            return false;
        }

        public IEnumerable<TicketEventStatus> GetSellableTickets(IEnumerable<TicketEventStatus> items)
        {
            var _results = new List<TicketEventStatus>();

            foreach (var item in items)
            {
                if (item.TicketLeft > 0)
                    _results.Add(item);
            }

            if (_results.Count == 0)
                return null;

            return _results.ToArray();
        }

        //進行票券購買
        public bool BuyTicketAuto(TicketBuyer buyer)
        {
            using (TicketContextProvider context = new TicketContext())
            {
                return context.Ticket.BuyTicketAuto(buyer);
            }
        }

        //取得可以購買的票券清單
        public IEnumerable<TicketEventStatus> GetTicketEventStatus(int eventNo)
        {
            using(TicketContextProvider context = new TicketContext())
            {
                return context.Ticket.GetTicketEventStatus(eventNo);
            }
        }
    }
}
