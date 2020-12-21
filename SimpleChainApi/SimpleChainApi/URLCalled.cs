using System;
using System.Net;

namespace SimpleChainApi
{
    public class URLCalled
    {
        public DateTime Date { get; set; }

        public string URI { get; set; }

        public bool Success { get; set; }

        public HttpStatusCode StatusCode { get; set; }
    }
}
