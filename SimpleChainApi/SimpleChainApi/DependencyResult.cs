using System.Collections.Generic;
using System.Linq;

namespace SimpleChainApi
{
    public class DependencyResult
    {
        public DependencyResult() {
            ExternalDependencies = Enumerable.Empty<URLCalled>();
            SelfCalled = Enumerable.Empty<SelfDependencyCalled>();
        }

        public IEnumerable<URLCalled> ExternalDependencies { get; set; }

        public IEnumerable<SelfDependencyCalled> SelfCalled { get; set; }
    }
}
