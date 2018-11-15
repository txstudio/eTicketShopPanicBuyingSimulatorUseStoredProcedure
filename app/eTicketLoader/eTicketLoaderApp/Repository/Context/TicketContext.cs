namespace eTicketLoaderApp
{
    public class TicketContext : TicketContextProvider
    {
        protected override string GetConnectionString()
        {
            return "Server=192.168.0.90;Database=eTicketShop;User Id=sa;Password=Pa$$w0rd;";
        }
    }

}
