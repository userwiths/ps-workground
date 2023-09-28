function Get-Repositories() {
    param(
        [Switch]$Verbose = $false
    );
    $token = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $global:github_username,$global:github_token)));
    $params = @{
        Method = "GET"
        Uri = "https://api.github.com/orgs/$global:github_org/repos"
        Headers = @{
            Authorization = ("Basic {0}" -f $token)
        }
        Body = @{
            per_page = 60
        }
    }
    $response = Invoke-RestMethod @params
    if($Verbose) {
        $response | Select-Object -Property name, html_url, language, created_at, updated_at, pushed_at, size, forks_count, open_issues_count, default_branch, permissions | Sort-Object -Property name | Format-Table -AutoSize;
    }
    return $response;
}

function Get-AllWorkflows() {
    $token = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $global:github_username,$global:github_token)));
    $params = @{
        Method = "GET"
        Uri = "https://api.github.com/orgs/$global:github_org/repos"
        Body = @{}
        Headers = @{
            Authorization = ("Basic {0}" -f $token)
        }
    }
    $repos = Invoke-RestMethod @params

    foreach ($repo in $repos) {
        $result = Get-WorkflowRuns -Repository $repo.name -PageSize 2;
        if ($result) {
            $result | Add-Member -MemberType NoteProperty -Name "Repository" -Value $repo.name -Force;
        }
    }
}

function Get-CostSummary () {
    $repositories = Get-Repositories;
    $costSummary = @();
    
    $total = [PSCustomObject]@{
        BillableToday = 0;
        BillableThisWeek = 0;
        BillableThisMonth = 0;
        Repository = "Total";
        FreeMinutesLeft = 0;
    };

    foreach ($repository in $repositories) {
        $temp = Get-CostSummaryForRepo -Repository $repository.name;
        if ($temp -ne $null) {
            # Add memeber free left
            $temp | Add-Member -MemberType NoteProperty -Name "FreeMinutesLeft" -Value $null -Force;
            $costSummary += $temp;
            $total.BillableToday += $temp.BillableTodayRaw;
            $total.BillableThisWeek += $temp.BillableThisWeekRaw;
            $total.BillableThisMonth += $temp.BillableThisMonthRaw;
        }
        # Progress
        Write-Progress -Activity "Calculating cost" -Status "Calculating cost for $($repository.name)" -PercentComplete (($repositories.IndexOf($repository) / $repositories.Count) * 100);
    }
    $total.FreeMinutesLeft = 2000 - $total.BillableThisMonth;

    $total.FreeMinutesLeft = "$([Math]::Round($total.FreeMinutesLeft)) Minutes Left";
    $total.BillableToday = "$([Math]::Round($total.BillableToday)) Minutes";
    $total.BillableThisWeek = "$([Math]::Round($total.BillableThisWeek)) Minutes";
    $total.BillableThisMonth = "$([Math]::Round($total.BillableThisMonth)) Minutes";

    $costSummary += $total;

    $costSummary | Sort-Object -Property CostThisWeek -Descending | Format-Table -AutoSize -Property Repository, BillableToday, BillableThisWeek, BillableThisMonth, FreeMinutesLeft;
}

function Get-CostSummaryForRepo() {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Repository
    );

    $token = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $global:github_username,$global:github_token)));
    $params = @{
        Method = "GET"
        Uri = "https://api.github.com/repos/$global:github_org/$Repository/actions/runs"
        Body = @{
            per_page = $pageSize
        }
        Headers = @{
            Authorization = ("Basic {0}" -f $token)
        }
    };
    $workflowRuns = Invoke-RestMethod @params;

    if ( $workflowRuns.total_count -eq 0 ) {
        return $null;
    }

    $ranToday = 0;
    $ranThisWeek = 0;
    $ranThisMonth = 0;

    foreach ($workflowRun in $workflowRuns.workflow_runs) {
        $runId = $workflowRun.id;
        $params.Uri = "https://api.github.com/repos/$global:github_org/$Repository/actions/runs/$runId/timing"
        $timing = Invoke-RestMethod @params;
        $jobTime = ($timing.billable.UBUNTU.jobs -as [int]) * 60000; # 1 minute = 60000 ms
        $jobTime = ($jobTime, $timing.run_duration_ms | Measure-Object -Maximum).Maximum;
        if ($workflowRun.created_at -gt (Get-Date).AddDays(-1)) {
            $ranToday += $jobTime;
            $ranThisWeek += $jobTime;
            $ranThisMonth += $jobTime;
        } elseif ($workflowRun.created_at -gt (Get-Date).AddDays(-7)) {
            $ranThisWeek += $jobTime;
            $ranThisMonth += $jobTime;
        } elseif ($workflowRun.created_at -gt (Get-Date).AddDays(-30)) {
            $ranThisMonth += $jobTime;
        } else {
            break;
        }
    }

    #$thisWeekCost = [Math]::Round($billableThisWeek / 1000000, 2);
    #$thisMonthCost = [Math]::Round($billableThisMonth / 1000000, 2);
    #$todayCost = [Math]::Round($billableThisToday / 1000000, 2);

    return [PSCustomObject]@{
            Repository = $Repository;
            BillableThisWeekRaw = ($ranThisWeek/1000)/60;
            BillableThisMonthRaw = ($ranThisMonth/1000)/60;
            BillableTodayRaw = ($ranToday/1000)/60;
            BillableThisWeek = "$([Math]::Round(($ranThisWeek/1000)/60)) Minutes";
            BillableThisMonth = "$([Math]::Round(($ranThisMonth/1000)/60)) Minutes";
            BillableToday = "$([Math]::Round(($ranToday/1000)/60)) Minutes";
    };
}

function Get-WorkflowRuns() {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Repository,
        [Parameter(Mandatory = $false)]
        [int]$PageSize = 5
    );
    $token = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $global:github_username,$global:github_token)));
    $params = @{
        Method = "GET"
        Uri = "https://api.github.com/repos/$global:github_org/$Repository/actions/runs"
        Body = @{
            per_page = $PageSize
        }
        Headers = @{
            Authorization = ("Basic {0}" -f $token)
        }
    };
    $response = Invoke-RestMethod @params;
    $response.workflow_runs | Select-Object -Property name, event, status, conclusion, run_number, html_url, logs_url | Sort-Object -Property created_at | Format-Table -AutoSize
    return $response;
}

function Get-PullRequests () {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Repository,
        [Parameter(Mandatory = $false)]
        [int]$PageSize = 5,
        [int]$Page = 1,
        [Switch]$Opened = $false,
        [Switch]$Closed = $false,
        [string]$BaseBranch = "main",
        [string]$Sort = "created",
        [string]$Direction = "desc"
    );
    $token = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $global:github_username,$global:github_token)));
    $params = @{
        Method = "GET"
        Uri = "https://api.github.com/repos/$global:github_org/$Repository/pulls"
        Body = @{
            per_page = $PageSize;
            page = $Page;
            state = ($Opened -and $Closed) ? "all" : ($Opened ? "open" : ($Closed ? "closed" : "open"));
            base = $BaseBranch;
            sort = $Sort;
            direction = $Direction;
        }
        Headers = @{
            Authorization = ("Basic {0}" -f $token)
        }
    };

    $response = Invoke-RestMethod @params;
    $response | Select-Object -Property number, title, html_url, state, created_at, updated_at | Sort-Object -Property created_at | Format-Table -AutoSize
}

function Get-PullRequest () {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Repository,
        [Parameter(Mandatory = $true)]
        [int]$PRNumber
    );
    $token = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $global:github_username,$global:github_token)));
    $params = @{
        Method = "GET"
        Uri = "https://api.github.com/repos/$global:github_org/$Repository/pulls/$PRNumber"
        Headers = @{
            Authorization = ("Basic {0}" -f $token)
        }
    };

    $response = Invoke-RestMethod @params;
    $response | Select-Object -Property id, title, html_url, state, created_at, updated_at | Sort-Object -Property created_at | Format-Table -AutoSize
    Show-Markdown -InputObject $response.body;
}

function Get-RepoEvents () {
    param (
        [Switch]$Public = $false,
        [int]$PageSize = 5,
        [int]$Page = 1,
        [string]$Org = $global:github_org
    );

    $token = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $global:github_username,$global:github_token)));
    $params = @{
        Method = "GET"
        Uri = "https://api.github.com/users/$global:github_username/events/orgs/$Org"
        Headers = @{
            Authorization = ("Basic {0}" -f $token)
        }
    };

    $response = Invoke-RestMethod @params;
    $response | Select-Object -Property id, type, created_at, actor.login, repo.name | Sort-Object -Property created_at | Format-Table -AutoSize
}

function Get-RepoCommits () {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Repository,
        [Parameter(Mandatory = $false)]
        [int]$PageSize = 5,
        [int]$Page = 1,
        [string]$Author,
        [string]$Commiter,
        [string]$Since,
        [string]$Until,
        [Switch]$Print = $false
    );

    $token = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $global:github_username,$global:github_token)));
    $body = @{
        per_page = $PageSize;
        page = $Page;
    };
    if ($Author) {
        $body.author = $Author;
    }
    if ($Commiter) {
        $body.commiter = $Commiter;
    }
    if ($Since) {
        $body.since = $Since;
    }
    if ($Until) {
        $body.until = $Until;
    }

    $params = @{
        Method = "GET"
        Uri = "https://api.github.com/repos/$global:github_org/$Repository/commits"
        Body = $body
        Headers = @{
            Authorization = ("Basic {0}" -f $token)
        }
    };

    $response = Invoke-RestMethod @params;
    if ( $Print ) {
        $response | Sort-Object -Property commit.author.date | Format-Table -AutoSize @{Label="Message";Expression={$_.commit.message}},
                                                                                           @{Label="Date";Expression={$_.commit.author.date}}, 
                                                                                           @{Label="Author";Expression={$_.commit.author.name}},
                                                                                           @{Label="Url";Expression={$_.html_url}};
        return;
    }
    return $response;
}

function Get-BillingData() {
    $token = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $global:github_username,$global:github_token)));
    $params = @{
        Method = "GET"
        Uri = "https://api.github.com/orgs/$global:github_org/settings/billing/actions"
        Headers = @{
            Authorization   = ("Basic {0}" -f $token)
        }
    }
    $response = Invoke-RestMethod @params
    $response | Select-Object -Property total_ms_used, total_paid_minutes_used, included_minutes
}