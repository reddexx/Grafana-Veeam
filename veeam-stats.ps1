<#
############################################################################################################
#Veeam Abfrage Script V2 (VEEAM Version 11) für Telegraf
#
#
#Von
#Christian Heinrich
############################################################################################################    
#>
 
[cmdletbinding()]
param(
    [Parameter(Position=0, Mandatory=$false)]
        [string] $BRHost = "$env:COMPUTERNAME", ### Hostname von BackupServer (Wird automatisch abgerufen)
    [Parameter(Position=1, Mandatory=$false)]
        $reportMode = "2" ### Abfrage Zeitraum
  )

#region: Starte Verbindung zum Server
$OpenConnection = (Get-VBRServerSession).Server
if($OpenConnection -eq $BRHost) {
	
} elseif ($OpenConnection -eq $null ) {
	
	Connect-VBRServer -Server $BRHost
} else {
    
    Disconnect-VBRServer
   
    Connect-VBRServer -Server $BRHost
}

$NewConnection = (Get-VBRServerSession).Server
if ($NewConnection -eq $null ) {
	Write-Error "`nError: BRHost Connection Failed"
	Exit
}
#endregion

#region: Convert modus (Zeitbereich) zu Stunden
If ($reportMode -eq "Monthly") {
        $HourstoCheck = 720
} Elseif ($reportMode -eq "Weekly") {
        $HourstoCheck = 168
} Else {
        $HourstoCheck = $reportMode
}
#endregion

#region: Collect and filter Sessions
# $vbrserverobj = Get-VBRLocalhost        # Abfrage VBR Server object
# $viProxyList = Get-VBRViProxy           # Abfrage Proxies
$repoList = Get-VBRBackupRepository     # Abfragen von Repositories
$allSesh = Get-VBRBackupSession         # Abfragen aller Backup Sessions (Backup/BackupCopy/Replica)
# $allResto = Get-VBRRestoreSession       # Abfragen aller Wiederherstellungs Sessions
$seshListBk = @($allSesh | Where-Object {($_.EndTime -ge (Get-Date).AddHours(-$HourstoCheck)) -and $_.JobType -eq "Backup"})           # Sammle alle Backup sessions im Zeitbereich
$seshListBkc = @($allSesh | Where-Object {($_.EndTime -ge (Get-Date).AddHours(-$HourstoCheck)) -and $_.JobType -eq "BackupSync"})      # Sammle alle BackupCopy sessions im Zeitbereich
$seshListRepl = @($allSesh | Where-Object {($_.EndTime -ge (Get-Date).AddHours(-$HourstoCheck)) -and $_.JobType -eq "Replica"})        # Sammle alle Replication sessions im Zeitbereich
#endregion

#region: Sammeln von Jobs
# $allJobsBk = @(Get-VBRJob | ? {$_.JobType -eq "Backup"})        # Gather Backup jobs
# $allJobsBkC = @(Get-VBRJob | ? {$_.JobType -eq "BackupSync"})   # Gather BackupCopy jobs
# $repList = @(Get-VBRJob | ?{$_.IsReplica})                      # Get Replica jobs
#endregion

#region: Abfragen von Backups
$totalxferBk = 0
$totalReadBk = 0
$seshListBk | %{$totalxferBk += $([Math]::Round([Decimal]$_.Progress.TransferedSize/1GB, 0))}
$seshListBk | %{$totalReadBk += $([Math]::Round([Decimal]$_.Progress.ReadSize/1GB, 0))}
#endregion

#region: Preparing Backup Session Reports
$successSessionsBk = @($seshListBk | ?{$_.Result -eq "Success"})
$warningSessionsBk = @($seshListBk | ?{$_.Result -eq "Warning"})
$noneSessionsBk = @($seshListBk | ?{$_.Result -eq "none"})
$failsSessionsBk = @($seshListBk | ?{$_.Result -eq "Failed"})
$runningSessionsBk = @($allSesh | ?{$_.State -eq "Working" -and $_.JobType -eq "Backup"})
$failedSessionsBk = @($seshListBk | ?{($_.Result -eq "Failed") -and ($_.WillBeRetried -ne "True")})
#endregion

#region:  Preparing Backup Copy Session Reports
$successSessionsBkC = @($seshListBkC | ?{$_.Result -eq "Success"})
$warningSessionsBkC = @($seshListBkC | ?{$_.Result -eq "Warning"})
$noneSessionsBkC = @($seshListBkC | ?{$_.Result -eq "none"})
$failsSessionsBkC = @($seshListBkC | ?{$_.Result -eq "Failed"})
$runningSessionsBkC = @($allSesh | ?{$_.State -eq "Working" -and $_.JobType -eq "BackupSync"})
$IdleSessionsBkC = @($allSesh | ?{$_.State -eq "Idle" -and $_.JobType -eq "BackupSync"})
$failedSessionsBkC = @($seshListBkC | ?{($_.Result -eq "Failed") -and ($_.WillBeRetried -ne "True")})
#endregion

#region: Preparing Replicatiom Session Reports
$successSessionsRepl = @($seshListRepl | ?{$_.Result -eq "Success"})
$warningSessionsRepl = @($seshListRepl | ?{$_.Result -eq "Warning"})
$noneSessionsRepl = @($seshListRepl | ?{$_.Result -eq "none"})
$failsSessionsRepl = @($seshListRepl | ?{$_.Result -eq "Failed"})
$runningSessionsRepl = @($allSesh | ?{$_.State -eq "Working" -and $_.JobType -eq "Replica"})
$failedSessionsRepl = @($seshListRepl | ?{($_.Result -eq "Failed") -and ($_.WillBeRetried -ne "True")})

############################################### Repository Abfrage Version 2 für VEEAM V11 ##########################################
$Repos = get-vbrbackuprepository
$RepoDetails = foreach ($repo in $Repos) {
    [PSCustomObject]@{
        'Name'      = $Repo.Name
        'ID'        = $Repo.ID
        'Size'      = $Repo.GetContainer().CachedTotalSpace.InBytes / 1GB
        'FreeSpace' = $Repo.GetContainer().CachedFreeSpace.InBytes / 1GB
        'FreeProzent' = [Math]::Round(($Repo.GetContainer().CachedFreeSpace.InBytes / $Repo.GetContainer().CachedTotalSpace.InBytes)*100)
        'UsedSpace' = [Math]::Round([Decimal]($Repo.GetContainer().CachedTotalSpace.InBytes - $Repo.GetContainer().CachedFreeSpace.InBytes) /1GB,2)
        
    }
} 

#region: Number of Endpoints
$number_endpoints = 0
foreach ($endpoint in Get-VBREPJob ) {
$number_endpoints++;
}
#endregion
 
 $Anzahljobs = Get-VBRJob -Name *

#region: Influxdb Output for Telegraf

 $Count = $Anzahljobs.Count
 $body="veeam-stats BackupAnzahl=$Count"
Write-Host $body

$Count = $successSessionsBk.Count
$body="veeam-stats successfulbackups=$Count"
Write-Host $body

$Count = $warningSessionsBk.Count
$body="veeam-stats warningbackups=$Count"
Write-Host $body

$Count = $failsSessionsBk.Count
$body="veeam-stats failesbackups=$Count"
Write-Host $body

$Count = $failedSessionsBk.Count
$body="veeam-stats failedbackups=$Count"
Write-Host $body

$Count = $runningSessionsBk.Count
$body="veeam-stats runningbackups=$Count"
Write-Host $body

$Count = $noneSessionsBk.Count
$body="veeam-stats unbekanntbackups=$Count"
Write-Host $body

$Count = $successSessionsBkC.Count
$body="veeam-stats successfulbackupcopys=$Count"
Write-Host $body

$Count = $warningSessionsBkC.Count
$body="veeam-stats warningbackupcopys=$Count"
Write-Host $body

$Count = $failsSessionsBkC.Count
$body="veeam-stats failesbackupcopys=$Count"
Write-Host $body

$Count = $failedSessionsBkC.Count
$body="veeam-stats failedbackupcopys=$Count"
Write-Host $body

$Count = $noneSessionsBkC.Count
$body="veeam-stats unbekanntbackupcopys=$Count"
Write-Host $body

$Count = $runningSessionsBkC.Count
$body="veeam-stats runningbackupcopys=$Count"
Write-Host $body

$Count = $IdleSessionsBkC.Count
$body="veeam-stats idlebackupcopys=$Count"
Write-Host $body

$Count = $successSessionsRepl.Count
$body="veeam-stats successfulreplications=$Count"
Write-Host $body

$Count = $warningSessionsRepl.Count
$body="veeam-stats warningreplications=$Count"
Write-Host $body

$Count = $failsSessionsRepl.Count
$body="veeam-stats failesreplications=$Count"
Write-Host $body

$Count = $noneSessionsRepl.Count
$body="veeam-stats unbekanntreplications=$Count"
Write-Host $body

$Count = $failedSessionsRepl.Count
$body="veeam-stats failedreplications=$Count"
Write-Host $body

$body="veeam-stats totalbackuptransfer=$totalxferBk"
Write-Host $body

#############  VERSION 2 KOMPATIBEL ZU VEEAM V11 #################
foreach ($Repo in $RepoDetails){
$Name = "REPO_TOTAL " + $Repo."Name" -replace '\s','_'
$RepoTotal = "{0:N2}" -f $Repo."Size" -replace '[.]',''
$Total = "$RepoTotal" -replace '[,]','.'
$body="veeam-stats $Name=$Total"
Write-Host $body
	}

foreach ($Repo in $RepoDetails){
$Name = "REPO_FREE " + $Repo."Name" -replace '\s','_'
$RepoTotal = "{0:N2}" -f $Repo."FreeSpace" -replace '[.]',''
$Total = "$RepoTotal" -replace '[,]','.'
$body="veeam-stats $Name=$Total"
Write-Host $body
	}

foreach ($Repo in $RepoDetails){
$Name = "REPO_FREE_PROZENT " + $Repo."Name" -replace '\s','_'
$RepoTotal = $Repo."FreeProzent" -replace '[.]',''
$Total = "$RepoTotal" -replace '[,]','.'
$body="veeam-stats $Name=$Total"
Write-Host $body
	}

foreach ($Repo in $RepoDetails){
$Name = "REPO_USE " + $Repo."Name" -replace '\s','_'
$RepoTotal =$Repo."UsedSpace" -replace '[.]',''
$Total = "$RepoTotal" -replace '[,]','.'
$body="veeam-stats $Name=$Total"
Write-Host $body
	}


$body="veeam-stats protectedendpoints=$number_endpoints"
Write-Host $body

$body="veeam-stats totalbackupread=$totalReadBk"
Write-Host $body

$Count = $runningSessionsRepl.Count
$body="veeam-stats runningreplications=$Count"
Write-Host $body

#endregion

#region: Debug
if ($DebugPreference -eq "Inquire") {
	$RepoReport | ft * -Autosize
    
    $SessionObject = [PSCustomObject] @{
	    "Successful Backups"  = $successSessionsBk.Count
	    "Warning Backups" = $warningSessionsBk.Count
	    "Failes Backups" = $failsSessionsBk.Count
	    "Failed Backups" = $failedSessionsBk.Count
	    "Running Backups" = $runningSessionsBk.Count
	    "Warning BackupCopys" = $warningSessionsBkC.Count
	    "Failes BackupCopys" = $failsSessionsBkC.Count
	    "Failed BackupCopys" = $failedSessionsBkC.Count
	    "Running BackupCopys" = $runningSessionsBkC.Count
	    "Idle BackupCopys" = $IdleSessionsBkC.Count
	    "Successful Replications" = $successSessionsRepl.Count
        "Warning Replications" = $warningSessionsRepl.Count
        "Failes Replications" = $failsSessionsRepl.Count
        "Failed Replications" = $failedSessionsRepl.Count
        "Running Replications" = $RunningSessionsRepl.Count
    }
    $SessionResport += $SessionObject
    $SessionResport
}
#endregion