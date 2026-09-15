using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Text.Json;

namespace CIPP.TableClient;

public static class Helpers
{
    private const string ImdsTokenEndpoint = "http://169.254.169.254/metadata/identity/oauth2/token";
    private const string ImdsApiVersion = "2018-02-01";

    public static string GetManagedIdentityToken(string accountName, string? clientId = null)
    {
        // Get token for managed identity for Storage resource
        string resource = $"https://{accountName}.table.core.windows.net";

        string? identityEndpoint = Environment.GetEnvironmentVariable("IDENTITY_ENDPOINT");
        string? identityHeader = Environment.GetEnvironmentVariable("IDENTITY_HEADER");

        HttpWebRequest request;

        // App Service / Azure Functions have IDENTITY_ENDPOINT and IDENTITY_HEADER set
        if (!string.IsNullOrWhiteSpace(identityEndpoint) && !string.IsNullOrWhiteSpace(identityHeader))
        {
            string uri = $"{identityEndpoint}?api-version=2019-08-01&resource={resource}";
            if (!string.IsNullOrWhiteSpace(clientId))
            {
                uri += $"&client_id={clientId}";
            }
            request = (HttpWebRequest)WebRequest.Create(uri);
            request.Headers["X-IDENTITY-HEADER"] = identityHeader;
        }
        else
        {
            // Fall back to VM Instance Metadata Service (IMDS) endpoint
            string uri = $"{ImdsTokenEndpoint}?api-version={ImdsApiVersion}&resource={resource}";
            if (!string.IsNullOrWhiteSpace(clientId))
            {
                uri += $"&client_id={clientId}";
            }
            request = (HttpWebRequest)WebRequest.Create(uri);
            request.Headers["Metadata"] = "true";
        }

        request.Method = "GET";

        try
        {
            // request token
            HttpWebResponse response = (HttpWebResponse)request.GetResponse();

            // extract token from responsestream
            StreamReader streamResponse = new(response.GetResponseStream());
            string stringResponse = streamResponse.ReadToEnd();

            // deserialize token from JSON
            Dictionary<string, string>? tokenDict = JsonSerializer.Deserialize<Dictionary<string, string>>(stringResponse);
            if (tokenDict is null || !tokenDict.TryGetValue("access_token", out var accessToken))
            {
                throw new InvalidOperationException("Managed identity token response did not contain an access_token.");
            }
            return accessToken;
        }
        catch (Exception ex)
        {
            string errorText = string.Format("{0} \n\n{1}", ex.Message, ex.InnerException != null ? ex.InnerException.Message : "Acquire token failed");
            throw new WebException(errorText, ex);
        }
    }
}
