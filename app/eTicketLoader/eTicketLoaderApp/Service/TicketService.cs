using eTicketLoader.Data;
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

        //進行票券購買
        public bool BuyTicketAuto(TicketBuyer buyer)
        {
            throw new NotImplementedException();
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
