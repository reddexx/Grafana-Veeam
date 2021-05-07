###################################### Report Logging Veeam ################################################
#Bereitstellung der Reports von Veeam
#
#
#Von
#Christian Heinrich
###################################### Konfiguration #######################################################

$Debug = "true" ### Debug modus
$ZeitSpanne = "-10" ### Lese alles vor x Minuten
$replaceFailed = "Failed-Error" ### Textplatzhalter für Failed Ergebniss
$replaceSuccess = "Success-Info" ### Textplatzhalter für Failed Ergebniss
$ReplaceNoneStatus = "Success-Info" ### Textplatzhalter für Failed Ergebniss


#############################################################################################################
######################################### Version Check V11 #################################################
$corePath = Get-ItemProperty -Path "HKLM:\Software\Veeam\Veeam Backup and Replication\" -Name "CorePath"
$depDLLPath = Join-Path -Path $corePath.CorePath -ChildPath "Packages\VeeamDeploymentDll.dll" -Resolve
$file = Get-Item -Path $depDLLPath
$version = $file.VersionInfo.ProductVersion # Abrufen der Veeam Version
$psVersion = "11" ## Version die erförderlich ist 

echo "Aktuelle Veeam Version: $version"
echo "Kompatible Powershell Version: $psVersion"

if($version -match $psVersion){
    Write-Host "Script läuft auf der richtigen Version " -ForegroundColor Green
    }
	 else { 
        ### Lade Snap IN Veeam Powershell ###
   Write-Host "[Achtung] Falsche Version .... Veeam Version: $version"  -ForegroundColor Red 
   Write-Host "[Achtung] Starte alter Script.... Bitte warten!" -ForegroundColor Yellow
function Set-Fix {
[cmdletbinding()]
param(
    [Parameter(Position=0, Mandatory=$false)]
        [string] $BRHost = "$env:computername") #### Host zum Veeam Backup Server login wird Local nicht benötigt

   }
  

if (!(Get-PSSnapin -Name VeeamPSSnapIn -ErrorAction SilentlyContinue)) {
	if (!(Add-PSSnapin -PassThru VeeamPSSnapIn)) {
		# Error out if loading fails
		Write-Error "`nFehler: Veeam Snapin kann nicht Installiert werden."
		Exit
	}
}
}

$TableName = "Backup Report"
 
#Erstelle Tabellen-Objekt
$table = New-Object system.Data.DataTable “$TableName”
 
#Definiere spalten
$col1 = New-Object system.Data.DataColumn Date,([string])
$col2 = New-Object system.Data.DataColumn Message,([string])
 
#Spalten hinzufügen
$table.columns.add($col1)
$table.columns.add($col2)


for($i=1) {
$allSesh = Get-VBRBackupSession
$seshListBk = @($allSesh | Where-Object {( $_.EndTime -ge (Get-Date).Addminutes($ZeitSpanne))})           # Fange alle Backups von der 10Minuten

###########################################################################

foreach ($BackupJob in $seshListBk)
    {
        $jobTime = $BackupJob.Endtime   ### Alle Informationen von EndTime, Name, Result ausgeben
        $jobName = $BackupJob.JobName
        $lastResult = $BackupJob.Result | Select -First 1
        $FailedReason = $BackupJob.GetTaskSessionsByStatus("Failed").info.reason | Select -First 1



        if ( $JobType -eq "BackupSync" ){ ## Wenn Job Typ nicht BackupSync ist wird der die VMS nicht ausgelesen
        if ( $lastResult -eq "Failed") { ## Wenn der Job Failed ausgibt werden die VMS ausgelesen
                     foreach ($failedVM in $seshListBk.GetTaskSessionsByStatus("Failed"))
    {
    $endResultVM = $failedVM.info.reason
    $endStateVM = $failedVM.Status
    }
    }
           if ( $lastResult -eq "Warning" ){ ## Wenn der Job Warning ausgibt werden die VMS ausgelesen
                     foreach ($failedVM in $seshListBk.GetTaskSessionsByStatus("Warning"))
    {
    $endResultVM = $failedVM.info.reason
    $endStateVM = $failedVM.Status
    }
    }
    
  #        if ( $lastResult = "Warning" ){ ## Wenn der Job Warning ausgibt werden die VMS ausgelesen
  #                foreach ($failedVM in $seshListBk.GetTaskSessionsByStatus(""))
  # {
  #  $endResultVM = $failedVM.info.reason
  #  $endStateVM = "Unbekannt"
  # }
  # }
    }

    $formatEndStateVM = $endStateVM | Select -First 1

        $JobType = $BackupJob.JobType
        

 
        $FTime = get-date $jobTime -Format "dd.MM.yyyy HH:mm:ss" ## Formatiert Zeit richtig

        if ( $JobType -eq "BackupSync" ){

        $EndResult = "$FTime [ $formatEndStateVM ] $jobName $endResultVM" -replace "Success","$replaceSuccess" -replace "Failed","$replaceFailed"   ### Erstelle ein end-ergebniss von JobTime, Result, JobName, Reason... wenn Success soll ersetzt werden durch Success-Info für grafana  

        } else {
         $EndResult = "$FTime [ $lastResult ] $jobName $FailedReason" -replace "Success","$replaceSuccess" -replace "Failed","$replaceFailed" -replace "none","$ReplaceNoneStatus"  ###  Erstelle ein end-ergebniss von JobTime, Result, JobName, Reason... wenn Success soll ersetzt werden durch Success-Info für grafana  
         }

        if ($Debug -eq "True" -eq "true"){
        Write-Host "$Date $EndResult"
        }



         
#Vorbereitung eine neue Zeile
$row = $table.NewRow()
        $row.Date = "$Date" 
        $row.Message = "$EndResult" -replace "[  ] "," $ReplaceNoneStatus "
 $table.Rows.Add($row)
   #Zeile hinzufügen zur Tabelle
        }


 

########################################################################

###########################################
## Ausgabe wird Ausgegeben (DEBUG) Optional
if ($Debug -eq "True" -eq "true") {
$table | format-table -Wrap 
}
###########################################
 
# Exportieren in eine CSV für den Telegrafen
$tabCsv = $table | export-csv "C:\Telegraf\logging.csv" -noType
Write-Host Fertig!
Write-Host Warte auf nächste Abfragezyklus
Start-Sleep -s 15

}