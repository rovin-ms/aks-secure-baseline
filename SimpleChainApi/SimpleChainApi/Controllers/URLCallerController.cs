using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using System;
using System.Collections.Generic;
using System.Net;
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
        public async Task<DependencyResult> GetAsync()
        {
            var dependencyResult = new DependencyResult();

            await ComputeExternalDependencies(dependencyResult);

            await ComputeSelfDependencies(dependencyResult);

            return dependencyResult;
        }

        [HttpGet]
        [Route("endcall")]
        public Task<DependencyResult> GetEndCallAsync()
        {
            var dependencyResult = new DependencyResult();

            return Task.FromResult(dependencyResult);
        }

        private async Task ComputeExternalDependencies(DependencyResult dependencyResult)
        {
            var urlList = _configuration[EXTERNAL_DEPENDENCIES];
            _logger.LogInformation("URL external dependencies {urlList}", urlList);
            if (!string.IsNullOrWhiteSpace(urlList))
            {
                var client = _clientFactory.CreateClient();
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

        private async Task ComputeSelfDependencies(DependencyResult dependencyResult)
        {
            var hostPortList = _configuration[SELF_HOSTS_DEPENDENCIES];
            _logger.LogInformation("URL self dependencies {urlList}", hostPortList);
            if (!string.IsNullOrWhiteSpace(hostPortList))
            {
                var client = _clientFactory.CreateClient();
                var result = new List<SelfDependencyCalled>();
                foreach (var hostPort in hostPortList.Split(','))
                {
                    var url = $"http://{hostPort}/URLCaller/endcall";
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
                    catch (HttpRequestException e)
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
