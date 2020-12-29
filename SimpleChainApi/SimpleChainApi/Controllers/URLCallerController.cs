using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using System;
using System.Collections.Generic;
using System.Net.Http;
using System.Text.Json;
using System.Threading.Tasks;

namespace SimpleChainApi.Controllers
{
    [ApiController]
    [Route("[controller]")]
    public class URLCallerController : ControllerBase
    {
        private const string EXTERNAL_DEPENDENCIES = "EXTERNAL_DEPENDENCIES";

        private const string SELF_HOSTS_DEPENDENCIES = "SELF_HOSTS_DEPENDENCIES";

        private readonly ILogger<URLCallerController> _logger;

        private readonly IHttpClientFactory _clientFactory;

        private readonly IConfiguration _configuration;

        public URLCallerController(ILogger<URLCallerController> logger, IConfiguration configuration, IHttpClientFactory clientFactory)
        {
            _logger = logger;
            _clientFactory = clientFactory;
            _configuration = configuration;
        }

        [HttpGet]
        [Route("depth/{depth:int}")]
        public async Task<DependencyResult> GetAsync(int depth)
        {
            var dependencyResult = new DependencyResult();
            if (depth > 0)
            {
                var client = _clientFactory.CreateClient();

                await ComputeExternalDependenciesAsync(client, dependencyResult);

                await ComputeSelfDependenciesAsync(client, dependencyResult, depth);
            }

            return dependencyResult;
        }


        private async Task ComputeExternalDependenciesAsync(HttpClient client, DependencyResult dependencyResult)
        {
            var urlList = _configuration[EXTERNAL_DEPENDENCIES];
            _logger.LogInformation("URL external dependencies {urlList}", urlList);
            if (!string.IsNullOrWhiteSpace(urlList))
            {
                var result = new List<URLCalled>();
                foreach (var url in urlList.Split(','))
                {
                    var urlCalledResult = new URLCalled { Date = DateTime.Now, URI = url };
                    var request = new HttpRequestMessage(HttpMethod.Get, url);
                    try
                    {
                        var response = await client.SendAsync(request);
                        urlCalledResult.Success = response.IsSuccessStatusCode;
                        urlCalledResult.StatusCode = response.StatusCode;
                    }
                    catch (HttpRequestException)
                    {
                        urlCalledResult.Success = false;
                    }
                    result.Add(urlCalledResult);
                }

                dependencyResult.ExternalDependencies = result;
            }
        }

        private async Task ComputeSelfDependenciesAsync(HttpClient client, DependencyResult dependencyResult, int depth)
        {
            var hostPortList = _configuration[SELF_HOSTS_DEPENDENCIES];
            _logger.LogInformation("URL self dependencies {hostPortList}", hostPortList);
            if (!string.IsNullOrWhiteSpace(hostPortList) && depth > 0)
            {
                var result = new List<SelfDependencyCalled>();
                foreach (var hostPort in hostPortList.Split(','))
                {
                    var url = $"{hostPort}/URLCaller/depth/{--depth}";
                    var urlCalledResult = new SelfDependencyCalled { Date = DateTime.Now, URI = url };
                    var request = new HttpRequestMessage(HttpMethod.Get, url);
                    try
                    {
                        var response = await client.SendAsync(request);
                        urlCalledResult.Success = response.IsSuccessStatusCode;
                        urlCalledResult.StatusCode = response.StatusCode;
                        if (urlCalledResult.Success)
                        {
                            var innerDependencyResult = JsonSerializer.Deserialize<DependencyResult>(await response.Content.ReadAsStringAsync());
                            urlCalledResult.DependencyResult = innerDependencyResult;
                        }
                    }
                    catch (HttpRequestException)
                    {
                        urlCalledResult.Success = false;
                    }
                    result.Add(urlCalledResult);
                }

                dependencyResult.SelfCalled = result;
            }
        }
    }
}
