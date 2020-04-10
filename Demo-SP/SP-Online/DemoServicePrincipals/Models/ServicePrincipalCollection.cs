using System.Collections.Generic;
using Newtonsoft.Json;

namespace DemoServicePrincipals.Models
{
    internal class ServicePrincipalCollection
    {
        [JsonProperty(ItemIsReference = true, PropertyName = "value")]
        public IList<ServicePrincipal> ServicePrincipals { get; set; }
    }
}
