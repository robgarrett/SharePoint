using Newtonsoft.Json;

namespace DemoServicePrincipals.Models
{
    internal class User
    {
        [JsonProperty("displayName")]
        public string DisplayName { get; set; }
    }
}
