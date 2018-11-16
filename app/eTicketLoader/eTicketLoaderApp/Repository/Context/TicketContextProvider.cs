using System;
using System.Collections.Generic;
using System.Text;

namespace eTicketLoaderApp
{
    public abstract class TicketContextProvider : IDisposable
    {
        private ITicketRepository _ticket;
        private ILogRepository _log;

        protected abstract string GetConnectionString();

        protected TicketContextProvider()
        {
            this._ticket = null;
            this._log = null;
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

        public ILogRepository Log
        {
            get
            {
                if (this._log == null)
                    this._log = new LogRepository(this.GetConnectionString());

                return this._log;
            }
        }


        public void Dispose()
        {

        }
    }
}
