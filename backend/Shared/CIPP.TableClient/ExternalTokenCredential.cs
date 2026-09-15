using Azure.Core;
using System;
using System.Threading;
using System.Threading.Tasks;

namespace CIPP.TableClient;

internal class ExternalTokenCredential : TokenCredential
{
    private readonly string token;
    private DateTimeOffset expiresOn;

    public ExternalTokenCredential(string token, DateTimeOffset expiresOn)
    {
        this.token = token;
        this.expiresOn = expiresOn;
    }

    public override AccessToken GetToken(TokenRequestContext requestContext, CancellationToken cancellationToken) => new(token, expiresOn);

    public override ValueTask<AccessToken> GetTokenAsync(TokenRequestContext requestContext, CancellationToken cancellationToken) =>
        new(GetToken(requestContext, cancellationToken));
}
