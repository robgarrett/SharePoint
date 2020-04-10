using System;
using Newtonsoft.Json;

namespace DemoServicePrincipals.Models
{
    internal class ServicePrincipal
    {
        [JsonProperty("id")] 
        public Guid Id { get; set; }

        [JsonProperty("displayName")]
        public string DisplayName { get; set; }

        [JsonProperty("servicePrincipalNames")]
        public string[] ServicePrincipalNames { get; set; }

        [JsonProperty("replyUrls")]
        public string[] ReplyUrls { get; set; }
    }
}
