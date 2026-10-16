BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    Add-Type -Path (Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll')

    # Accepts connections and never answers, so every request blocks until it is cancelled.
    $script:Listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $script:Listener.Start()
    $script:Uri = "http://127.0.0.1:$($script:Listener.LocalEndpoint.Port)/hang"
    $script:Server = [powershell]::Create().AddScript({
            param($Listener)
            $Held = [System.Collections.Generic.List[object]]::new()
            while ($true) {
                try { $Held.Add($Listener.AcceptTcpClient()) } catch { break }
            }
        }).AddArgument($script:Listener)
    $null = $script:Server.BeginInvoke()

    function Get-SendError([scriptblock]$Call) {
        $Watch = [System.Diagnostics.Stopwatch]::StartNew()
        try { & $Call; $Err = $null } catch { $Err = $_.Exception.InnerException ?? $_.Exception }
        [pscustomobject]@{ Error = $Err; Ms = $Watch.ElapsedMilliseconds }
    }
}

AfterAll {
    $script:Listener.Stop()
    $script:Server.Dispose()
}

Describe 'CIPPRestClient cancellation' {
    It 'Send stops on the caller token as a cancellation, not a server-cancel transport error' {
        $Cts = [System.Threading.CancellationTokenSource]::new(300)
        $Result = Get-SendError { [CIPP.CIPPRestClient]::Send($script:Uri, 'GET', $null, $null, $null, $true, 30, -1, $Cts.Token) }
        $Result.Error | Should -BeOfType [System.OperationCanceledException]
        $Result.Ms | Should -BeLessThan 10000
    }

    It 'Send still times out on timeoutSec when no token is passed' {
        $Result = Get-SendError { [CIPP.CIPPRestClient]::Send($script:Uri, 'GET', $null, $null, $null, $true, 1, -1, $null) }
        $Result.Error | Should -BeOfType [System.OperationCanceledException]
    }

    It 'SendConcurrent stops on the caller token instead of retrying' {
        $Requests = [CIPP.CIPPConcurrentRequest[]]@(1..3 | ForEach-Object { [CIPP.CIPPConcurrentRequest]@{ Uri = $script:Uri; TimeoutSec = 30 } })
        $Cts = [System.Threading.CancellationTokenSource]::new(300)
        $Result = Get-SendError { [CIPP.CIPPRestClient]::SendConcurrent($Requests, 3, 3, $Cts.Token) }
        $Result.Error | Should -BeOfType [System.OperationCanceledException]
        $Result.Ms | Should -BeLessThan 10000
    }
}
