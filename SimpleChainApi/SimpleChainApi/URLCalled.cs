using System;
using System.Net;
using System.Text.Json.Serialization;

namespace SimpleChainApi
{
    public class URLCalled
    {
        [JsonPropertyName("date")]
        public DateTime Date { get; set; }

        [JsonPropertyName("uri")]
        public string URI { get; set; }

        [JsonPropertyName("success")]
        public bool Success { get; set; }

        [JsonPropertyName("statusCode")]
        public HttpStatusCode StatusCode { get; set; }
    }
}
