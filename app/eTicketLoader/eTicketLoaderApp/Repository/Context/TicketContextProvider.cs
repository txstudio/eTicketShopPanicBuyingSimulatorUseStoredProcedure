using System;
using System.Collections.Generic;
using System.Text;

namespace eTicketLoaderApp
{
    public abstract class TicketContextProvider : IDisposable
    {
        private TicketRepository _ticket;

        protected abstract string GetConnectionString();

        protected TicketContextProvider()
        {

        }

        public ITicketRepository Ticket
        {
            get
            {
                if (this._ticket == null)
                    this._ticket = new TicketRepository(this.GetConnectionString());

                return this._ticket;
            }
        }

        public void Dispose()
        {

        }
    }
}
