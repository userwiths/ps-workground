. ./variables.ps1

. ./github.ps1
. ./status.ps1
. ./jira.ps1
#export DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1
Write-Host "Loaded all required files";
#Install-Module Microsoft.PowerShell.ConsoleGuiTools -> Out-COnsoleGridView
#Install-Module Microsoft.PowerShell.GraphicalTools -> Out-GridView

function Get-CommitsForSprint () {
    param (
        [string]$BoardId,
        [string]$BoardName,
        [string]$Repository,
        [int]$SprintId,
        [string]$During,
        [Switch]$Mine = $false,
        [Switch]$Print = $false,
        [int]$Before
    )

    if ( -not $BoardId -and -not $BoardName ) {
        Write-Host "You must specify either BoardId or BoardName";
        return;
    }
    if ( $BoardName ) {
        $sprints = Get-Sprints -BoardName $BoardName;
    } else {
        $sprints = Get-Sprints -BoardId $BoardId;
    }

    if ( $SprintId ) {
        $sprint = $sprints.values | Where-Object { $_.id -eq $SprintId };
    } elseif ( $Before ) {
        $sprint = $sprints.values[-$Before];
    } elseif ( $During ) {
        $sprint = $sprints.values | Where-Object { $_.startDate -le $During -and $_.endDate -ge $During };
    } else {
        # Last sprint
        $sprint = $sprints.values[-1];
    }

    if ( $Mine ) {
        $commits = Get-RepoCommits -Repository $Repository -Since $sprint.startDate -Until $sprint.endDate -Author $global:github_displayName;
    } else {
        $commits = Get-RepoCommits -Repository $Repository -Since $sprint.startDate -Until $sprint.endDate;
    }

    if ( $Print ) {
        $commits | Format-Table -AutoSize  @{Label="Message";Expression={$_.commit.message}},
                                           @{Label="Date";Expression={$_.commit.author.date}}, 
                                           @{Label="Author";Expression={$_.commit.author.name}},
                                           @{Label="Url";Expression={$_.html_url}};
        return;
    }
    return $commits;
}

function Get-SprintData () {
    param (
        [string]$BoardId,
        [string]$BoardName,
        [int]$SprintId,
        [string]$Repository,
        [Switch]$Print = $false,
        [Switch]$MyCommits = $false,
        [Switch]$MyIssues = $false
    );

    if ( -not $BoardId -and -not $BoardName ) {
        Write-Host "You must specify either BoardId or BoardName";
        return;
    }
    if ( $BoardName ) {
        $projects = Get-Projects -Type scrum -Key $BoardName;
        $BoardId =  $projects[0].id;
    }

    if ( -not $SprintId ) {
        $sprints = Get-Sprints -BoardId $BoardId;
        $SprintId = $sprints.values[-1].id;
    }

    $issues = Get-Issues -BoardId $BoardId -SprintId $SprintId -Mine:$MyIssues;

    if ( $MyCommits ) {
        $commits = Get-CommitsForSprint -BoardId $BoardId -SprintId $SprintId -Repository $Repository -Author $global:github_displayName;
    } else {
        $commits = Get-CommitsForSprint -BoardId $BoardId -SprintId $SprintId -Repository $Repository;
    }

    $data = @{
        sprint = $sprints.values | Where-Object { $_.id -eq $SprintId };
        issues = $issues;
        commits = $commits;
    };
    if ( $Print ) {
        $issues | Format-Table -AutoSize  @{Label="Key";Expression={$_.key}},
                                           @{Label="Summary";Expression={$_.fields.summary}},
                                           @{Label="Status";Expression={$_.fields.status.name}},
                                           @{Label="Assignee";Expression={$_.fields.assignee.displayName}},
                                           @{Label="Story Points";Expression={$_.fields.customfield_10002}},
                                           @{Label="Labels";Expression={$_.fields.labels}};
        Write-Host "--------------------------------------------------------------------------------";
        $commits | Format-Table -AutoSize  @{Label="Message";Expression={$_.commit.message}},
                                           @{Label="Date";Expression={$_.commit.author.date}}, 
                                           @{Label="Author";Expression={$_.commit.author.name}},
                                           @{Label="Url";Expression={$_.html_url}};
        return;
    }
    return $data;
}