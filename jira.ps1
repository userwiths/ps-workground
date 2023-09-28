function Get-Projects () {
    param (
        [Switch]$Print = $false,
        [string]$Key,
        [string]$Type
    )
    $token = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $global:jira_username,$global:jira_token)));
    $params = @{
        Method = 'GET'
        Uri = "$($global:jira_url)/rest/agile/1.0/board"
        Headers = @{
            Authorization = ("Basic {0}" -f $token)
        }
    };
    $response = Invoke-RestMethod @params;
    $projects = $response.values;

    if ( $Key ) {
        $projects = $projects | Where-Object { $_.location.projectKey -eq $Key };
    }
    if ( $Type ) {
        $projects = $projects | Where-Object { $_.type -eq $Type };
    }
    if ( $Print ) {
        $projects | Format-Table -AutoSize @{Label="Name";Expression={$_.location.projectName}}, 
                                                @{Label="Key";Expression={$_.location.projectKey}}, 
                                                @{Label="Address";Expression={("$global:jira_url/jira/software/c/projects/{0}/boards/{1}" -f ($_.location.projectKey, $_.id))}};
        return;
    }
    return $projects;
}

function Get-Sprints () {
    param (
        [string]$BoardId,
        [string]$BoardName,
        [Switch]$Active,
        [Switch]$Future,
        [Switch]$Closed,
        [Switch]$Print = $false
    );
    
    if ( -not $BoardId -and -not $BoardName ) {
        Write-Host "You must specify either BoardId or BoardName";
        return;
    }

    if ( $BoardName ) {
        $projects = Get-Projects -Type scrum -Key $BoardName;
        $BoardId =  $projects.id;
    }

    $token = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $global:jira_username,$global:jira_token)));
    $state = @();
    if ($Active) {
        $state += 'active';
    } elseif ($Future) {
        $state += 'future';
    } elseif ($Closed) {
        $state += 'closed';
    }
    $params = @{
        Method = 'GET'
        Uri = "$($global:jira_url)/rest/agile/1.0/board/$BoardId/sprint"
        Headers = @{
            Authorization = ("Basic {0}" -f $token)
        }
    };
    if ( $state ) {
        $params.Body = @{
            state = $state
        };
    }
    $response = Invoke-RestMethod @params;
    if ( $Print ) {
        $response.values | Format-Table -AutoSize @{Label="Id";Expression={$_.id}}, 
                                                  @{Label="Name";Expression={$_.name}}, 
                                                  @{Label="State";Expression={$_.state}}, 
                                                  @{Label="Start";Expression={$_.startDate}}, 
                                                  @{Label="End";Expression={$_.endDate}}, 
                                                  @{Label="Complete";Expression={$_.completeDate}};
    }
    return $response;
}

function Get-Issues () {
    param (
        [int]$BoardId,
        [string]$BoardName,
        [int]$SprintId,
        [int]$Before = 1,
        [Switch]$Mine = $false,
        [string]$User,
        [Switch]$Print = $false,
        [string]$Status
    );

    if ( -not $BoardId -and -not $BoardName ) {
        Write-Host "You must specify either BoardId or BoardName";
        return;
    }
    if ( $BoardName ) {
        $projects = Get-Projects -Type scrum;
        $BoardId =  $projects.values | Where-Object { $_.location.projectKey -eq $BoardName } | Select-Object -First 1 | Select-Object -ExpandProperty id;
    }
    if ( -not $SprintId ) {
        $sprints = Get-Sprints -BoardId $BoardId;
        $SprintId = $sprints.values[-1].id;
    } else {
        $sprints = Get-Sprints -BoardId $BoardId;
        $SprintId = $sprints.values[-($Before)].id;
    }

    $token = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $global:jira_username,$global:jira_token)));
    $params = @{
        Method = 'GET'
        Uri = "$($global:jira_url)/rest/agile/1.0/board/$BoardId/sprint/$SprintId/issue"
        Headers = @{
            Authorization = ("Basic {0}" -f $token)
        }
    };
    $response = Invoke-RestMethod @params;
    $issues = $response.issues;

    if ( $Mine ) {
        $issues = $issues | Where-Object { $_.fields.assignee.displayName -eq $global:jira_displayname };
    }
    if ( $User ) {
        $issues = $issues | Where-Object { $_.fields.assignee.displayName -eq $User };
    }
    if ( $Status ) {
        $issues = $issues | Where-Object { $_.fields.status.name -eq $Status };
    }
    if ( $Print ) {
        $issues | Format-Table -AutoSize @{Label="Id";Expression={$_.id}}, 
                                        @{Label="Key";Expression={$_.key}}, 
                                        @{Label="Summary";Expression={$_.fields.summary}}, 
                                        @{Label="Type";Expression={$_.fields.issuetype.name}}, 
                                        @{Label="Status";Expression={$_.fields.status.name}}, 
                                        @{Label="Assignee";Expression={$_.fields.assignee.displayName}},
                                        @{Label="Creator";Expression={$_.fields.creator.displayName}}
        return;
    }
    return $issues;
}

function Get-IssueHistory () {
    param (
        [string]$IssueId,
        [string]$IssueKey,
        [string]$Fields = 'description,comment',
        [int]$PageSize = 10,
        [int]$Page = 0,
        [Switch]$Print = $false
    );

    $token = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $global:jira_username,$global:jira_token)));
    $params = @{
        Method = 'GET'
        Uri = "$($global:jira_url)/rest/agile/1.0/issue/$($IssueKey ?? $IssueId)"
        Headers = @{
            Authorization = ("Basic {0}" -f $token)
        }
        Body = @{
            updateHistory = $false
            fields = $Fields
        }
    };
    $response = Invoke-RestMethod @params;
    $comments = $response.fields.comment.comments;
    
    if ( $Print ) {
        $comments | Format-Table -AutoSize @{Label="Author";Expression={$_.author.displayName}}, 
                                            @{Label="Date";Expression={$_.created}}, 
                                            @{Label="Body";Expression={$_.body}};
        return;
    }
    return $response;
}

function Create-IssueMarkdown () {
    param (
        [string]$IssueId,
        [string]$IssueKey,
        [Switch]$Comments = $false,
        [Switch]$Worklog = $false
    );

    $general = Get-IssueHistory -IssueId $IssueId -IssueKey $IssueKey -Fields 'description,comment,creator,created';
    $time = Get-IssueHistory -IssueId $IssueId -IssueKey $IssueKey -Fields 'worklog,timetracking';

    $resultText = "#{0} `n ## Author `n {1} `n ## Date of creation `n {2} `n ## Description: `n {3} `n" -f $general.key, $general.fields.creator.displayName, $general.fields.created, $general.fields.description;

    if ( $Comments ) {
        $resultText += "## Comments `n";
        foreach ($comment in $comments) {
            $resultText += "### {0} - {1} `n Comment: {2} `n" -f $comment.created, $comment.author.displayName, $comment.body;
        }
    }

    if ( $Worklog ) {
        $resultText += "## Worklog `n";
        foreach ($worklog in $time.fields.worklog.worklogs) {
            $resultText += "### {0} - {1} `n Comment: {2} `n Spent: {3} " -f $worklog.created, $worklog.author.displayName, $worklog.comment, $worklog.timeSpent + "`n";
        }
        $resultText += "### Total time spent: ";
        $resultText += $time.fields.timetracking.timeSpent;
    }
    Show-Markdown -InputObject $resultText;
}