
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;

namespace eTicketLoaderApp
{
    public class RandomService
    {
        Random _random;

        public RandomService()
        {
            this._random = new Random();
        }

        public TicketBuyer GetRandomTicket(IEnumerable<TicketEventStatus> status)
        {
            var _items = status.Where(x=>x.TicketLeft > 0).ToArray();
            var _index = this._random.Next(0, _items.Length);

            TicketBuyer _buyer = new TicketBuyer();
            _buyer.memberGUID = Guid.NewGuid();
            _buyer.GateNo = _items[_index].TicketGateNo;
            _buyer.TicketEventNo = 1;
            _buyer.TicketCount = this._random.Next(1, 5);

            return (_buyer);
        }
    }
}
