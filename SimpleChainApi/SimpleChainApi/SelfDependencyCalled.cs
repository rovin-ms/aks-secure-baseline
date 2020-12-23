using System.Text.Json.Serialization;

namespace SimpleChainApi
{
    public class SelfDependencyCalled : URLCalled
    {
        [JsonPropertyName("dependencyResult")]
        public DependencyResult DependencyResult { set; get; }
    }
}
