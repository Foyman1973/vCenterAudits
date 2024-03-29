<#
	.SYNOPSIS
		role and permission audit
	
	.DESCRIPTION
		This script will compare and report differences in defined Roles and 
		applied Roles in a set of vCenter instances based on an XML baseline 
		of a given instance.
	
	.NOTES
		========================================================================
		Windows PowerShell Source File
		Created with SAPIEN Technologies PrimalScript 2018
		
		NAME: vCenter_Security_Audit.ps1
		
		AUTHOR: Jason Foy, DaVita Inc.
		DATE  : 2/9/2018
		
		COMMENT:  To establish a new baseline for the audits run the script with a -remaster parameter
				.\vCenter_Security_Audit.ps1 -remaster
		
		==========================================================================
#>
param([switch]$remaster)
Clear-Host

# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
function Exit-Script{
	Write-Host "Script Exit Requested, Exiting..."
	Stop-Transcript
	exit
}
# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
function Exit-Script{
	Write-Host "Script Exit Requested, Exiting..."
	Stop-Transcript
	exit
}
# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
function Get-PowerCLI{
	$pCLIpresent=$false
	Get-Module -Name VMware.VimAutomation.Core -ListAvailable | Import-Module -ErrorAction SilentlyContinue
	try{$pCLIpresent=((Get-Module VMware.VimAutomation.Core).Version.Major -ge 10)}
	catch{}
	return $pCLIpresent
}
# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=

if(!(Get-PowerCLI)){Write-Host "* * * * No PowerCLI Installed or version too old. * * * *" -ForegroundColor Red;Exit-Script}
# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
function Get-Roles{
	$report = @()
	# $authMgr = Get-View AuthorizationManager
	# foreach($role in $authMgr.roleList){
	# 	$row = ""|Select-Object Name,Description,RoleId,System,Privilege
		# $row.Name=$role.name
		# $row.Description=$role.Description
		# $row.RoleId=$role.roleId
		# $row.System=$role.system
		# $row.Privilege=$role.privilege
		# $report += $row
	# }
	Get-VIRole|ForEach-Object{
		$row = ""|Select-Object Name,Description,RoleId,System,Privilege
		$row.Name=$_.name
		$row.Description=$_.Description
		$row.RoleId=$_.Id
		$row.System=$_.IsSystem
		$row.Privilege=$_.PrivilegeList
		$report += $row
	}
	return $report
}
# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
function Get-Permissions{
	$report = @()
	Get-VIPermission|ForEach-Object{
		# $thisObjectView = Get-View $_.EntityID
		# if(!($_.Entity)){$thisEntityName = $thisObjectView.Name}
		# else{$thisEntityName = $_.Entity}
		$row = ""|Select-Object Entity,EntityID,EntityType,Principal,Role,RoleID,isGroup,Propagate
		$row.Entity = $_.Entity.Name
		$row.EntityID = $_.EntityID
		$row.EntityType = $_.ExtensionData.Entity.Type
		$row.Principal = $_.Principal
		$row.Role = $_.Role
		$row.RoleID = $_.ExtensionData.RoleId
		$row.isGroup = $_.isGroup
		$row.Propagate = $_.Propagate
		$report += $row
	}
	return $report
}
# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
# ==============================================================================================

# ==============================================================================================
# ==============================================================================================
$Version = "2021.12.42"
$ScriptName = $MyInvocation.MyCommand.Name
$scriptPath = Split-Path $MyInvocation.MyCommand.Path
$CompName = (Get-Content env:computername).ToUpper()
$userName = ($env:UserName).ToUpper()
$userDomain = ($env:UserDomain).ToUpper()
$StartTime = Get-Date
$Date = Get-Date -Format g
$dateSerial = Get-Date -Format yyyyMMddhhmmss
$ReportFolder = Join-Path -Path $scriptPath -ChildPath "AuditResults"
$MasterFiles = Join-Path -Path $scriptPath -ChildPath "Masters"
$ReportFile = Join-Path -Path $ReportFolder -ChildPath "$dateSerial-vCenterAuditResults.html"
$logsfolder = Join-Path -Path $scriptPath -ChildPath "Logs"
$traceFile = Join-Path -Path $logsfolder -ChildPath "$ScriptName.trace"
if(!(Test-Path $logsfolder)){New-Item -Path $logsfolder -ItemType Directory|Out-Null}
Start-Transcript -Force -LiteralPath $traceFile
$configFile = Join-Path -Path $scriptPath -ChildPath "config.xml"
if(!(Test-Path $configFile)){Write-Host "! ! ! Missing CONFIG.XML file ! ! !";Exit-Script}
[xml]$XMLfile = Get-Content $configFile -Encoding UTF8
$RequiredConfigVersion = "1"
if($XMLFile.Data.Config.Version -lt $RequiredConfigVersion){Write-Host "Config version is too old!";Exit-Script}
if(!(Test-Path $ReportFolder)){New-Item -Path $ReportFolder -ItemType Directory|Out-Null}
if(!(Test-Path $MasterFiles)){New-Item -Path $MasterFiles -ItemType Directory|Out-Null}
if($XMLFile.Data.Config.DevMode.value -eq "TRUE"){
	$DEV_MODE=$true
	Write-Host "DEV_MODE ENABLED" -ForegroundColor Green
	$DebugPreference = "Continue"
}
else{
	Write-Host "DEV_MODE DISABLED" -ForegroundColor Red
	$DEV_MODE=$false
	$DebugPreference = "SilentlyContinue"
}
if($DEV_MODE){
	$vCenterFile = $XMLFile.Data.Config.vCenterList_TEST.value
	$FROM = $XMLFile.Data.Config.FROM_TEST.value
	$TO = $XMLFile.Data.Config.TO_TEST.value
	$reportTitle = "DEV $reportTitle"
}
else{
	$vCenterFile = $XMLFile.Data.Config.vCenterList.value
	$FROM = $XMLFile.Data.Config.FROM.value
	$TO = $XMLFile.Data.Config.TO.value
}
if(Test-Path $vCenterFile){
	Write-Host "Using vCenter List:" -NoNewline;Write-Host $vCenterFile -ForegroundColor Cyan
	$vCenterList = Import-Csv $vCenterFile -Delimiter ","|Sort-Object	CLASS,LINKED,NAME
	$vCenterCount = $vCenterList.Count	
}
else{Write-Host "No vCenter List Found" -ForegroundColor Red -NoNewline;Write-Host "[" -NoNewline;write-host $vCenterFile -NoNewline;Write-Host "]";Exit-Script}
$sendMail = $false;if($XMLFile.Data.Config.SendMail.value -eq "TRUE"){$sendMail=$true;Write-Host "SENDMAIL ENABLED" -ForegroundColor Green}else{Write-Host "SENDMAIL DISABLED" -ForegroundColor red}
$SMTP = $XMLFile.Data.Config.SMTP.value
$reportTitle = $XMLFile.Data.Config.ReportTitle.value
$subject = "$reportTitle $(Get-Date -Format yyyy-MMM-dd)"
Write-Host ("="*80) -ForegroundColor DarkGreen
Write-Host ""
Write-Host `t`t"$scriptName v$Version"
Write-Host `t`t"Started $Date"
Write-Host ""
Write-Host ("="*80) -ForegroundColor DarkGreen
Write-Host ""
$i = 0;$v = 1;$roleDeltaCount = 0;$roleRightsDeltaCount = 0;$permissionDeltaCount = 0;$auditFailCount = 0
$stopwatch = [Diagnostics.Stopwatch]::StartNew()
$roleModReport=@();$roleReport = @();$permReport = @();$reportBundle = @();$auditReport=@()
foreach($vCenter in $vCenterList){
	$goodvCenterConnect = $true;$goodMasterFile=$true
	$XMLAudit = [xml]"<Inventory><Info/><Roles/><Permissions/></Inventory>"
	$xmlInfo = $XMLAudit.SelectNodes("Inventory/Info")
	$xmlInfo.SetAttribute("GatherDate",$Date)
	$xmlInfo.SetAttribute("Collector",$ScriptName)
	$xmlInfo.SetAttribute("RunFrom",$CompName)	
	$xmlInfo.SetAttribute("CollectorVersion",$Version)
	$auditFailed = $false
	$thisvCenter = $vCenter.Name
	$thisDisplayName = $thisvCenter.Replace('.davita.corp','')
	$masterFileName = Join-Path -Path $MasterFiles -ChildPath "$thisDisplayName.xml"
	$auditFileName = Join-Path -Path $ReportFolder -ChildPath "$dateSerial-$thisDisplayName.xml"
	Write-Progress -Id 1 -Activity "Processing vCenters" -Status "$v of $vCenterCount" -PercentComplete ($v/$vCenterCount*100) -currentOperation "[ $thisvCenter ]";$v++
	if($remaster -and (!(Test-Path $masterFileName))){$XMLAudit.Save($masterFileName);Write-Host "Remaster with missing Master File" -ForegroundColor Red -BackgroundColor Yellow}
	if(Test-Path $masterFileName){
		Write-Host ("-"*80) -ForegroundColor DarkBlue
		Write-Host "Importing Master File for $thisvCenter : $masterFileName"
		[xml]$thisMasterFile = Get-Content $masterFileName -Encoding UTF8
		$xmlInfo.SetAttribute("MasterFile",$masterFileName)
		$xmlInfo.SetAttribute("vCenter", $thisvCenter)
		Write-Host "Connecting to vCenter $thisvCenter...." -NoNewline -ForegroundColor White
		$vConn = Connect-VIServer $vCenter.NAME -Credential (New-Object System.Management.Automation.PSCredential $vCenter.ID, (ConvertTo-SecureString $vCenter.Hash))
		if ($vConn){
			Write-Host "[" -NoNewline;Write-Host "OK" -ForegroundColor Green -NoNewline;Write-Host "]"
		
			Write-Host "Gathering Roles and Permissions..."
			$thisRoleSet = Get-Roles
			$thisPermissionSet = Get-Permissions
			Write-Host "Roles: $($thisRoleSet.Count)   Permissions: $($thisPermissionSet.Count)"
			Write-Host "Processing Roles..."
			$XMLRoles =  $XMLAudit.SelectNodes("Inventory/Roles")
			$thisRoleSet | Where-Object {-not $_.System} | ForEach-Object {
				$thisRoleName = $_.Name;$thisRoleID = $_.RoleId;$i++
				$XMLRole = $XMLRoles.AppendChild($XMLAudit.CreateElement("Role"))
				$XMLRole.SetAttribute( "Name", $_.Name)
				$XMLRole.SetAttribute("Description", $_.Description)
				$XMLRole.SetAttribute("RoleID", $_.RoleId)
				$_.Privilege | ForEach-Object {
					$XMLPrivilege = $XMLRole.AppendChild($XMLAudit.CreateElement("Privilege"))
					$XMLPrivilege.SetAttribute("Name", $_)
				}
				$thisReferenceObject=$null
				$thisReferenceObject = (($thisMasterFile.Inventory.Roles.Role|Where-Object{$_.Name -eq $thisRoleName}).Privilege.Name)
				$thisDifferenceObject = (($XMLAudit.Inventory.Roles.Role|Where-Object{$_.Name -eq $thisRoleName}).Privilege.Name)
				if($thisReferenceObject){
					$AuditResults=$null
					$AuditResults =  Compare-Object -ReferenceObject $thisReferenceObject -DifferenceObject $thisDifferenceObject
					if($AuditResults){
						Write-Host "Role Deltas Found" -ForegroundColor Magenta
						$auditFailCount++
						$AuditResults|ForEach-Object{
							$row=""|Select-Object vCenter,RoleName,RoleID,Permission,Delta
							$thisValue = $_.InputObject
							switch($_.SideIndicator){
								"<=" {
										$thisDelta="**REMOVED**"
										Write-Host `t"REMOVED : $thisRoleName : $thisValue" -ForegroundColor Yellow
									}
								"=>" {
										$thisDelta="**ADDED**"
										Write-Host `t"ADDED   : $thisRoleName : $thisValue" -ForegroundColor Red
									}
							}
							$row.RoleName = $thisRoleName
							$row.RoleID = $thisRoleID
							$row.vCenter = $thisvCenter
							$row.Permission = $thisValue
							$row.Delta = $thisDelta
							$roleModReport += $row
							$roleRightsDeltaCount++
						}
					}
					else{ Write-Debug -Message "$thisRoleName Identical" }
				}
 				else{Write-Debug -Message "New Role Added: $thisRoleName"}
			}
			Write-Host "Comparing Role Lists..."
			$thisReferenceObject = $thisMasterFile.Inventory.Roles.Role.Name
			$thisDifferenceObject = $XMLAudit.Inventory.Roles.Role.Name
			$AuditResults=$null
			$AuditResults =  Compare-Object -ReferenceObject $thisReferenceObject -DifferenceObject $thisDifferenceObject -ErrorAction SilentlyContinue
			if($AuditResults){
				Write-Host "Role List Deltas Found" -ForegroundColor Magenta
				$auditFailed = $true;$auditFailCount++
				$AuditResults|ForEach-Object{
					$row=""|Select-Object vCenter,RoleName,RoleID,Delta
					$thisValue = $_.InputObject
					switch($_.SideIndicator){
						"<=" {
								$thisDelta="**REMOVED**"
								Write-Host `t"REMOVED : " $thisValue -ForegroundColor Yellow
							}
						"=>" {
								$thisDelta="**ADDED**"
								Write-Host `t"ADDED   : " $thisValue -ForegroundColor Red
							}
					}
					$row.RoleName = $thisValue
					$row.RoleID = ($XMLAudit.Inventory.Roles.Role|Where-Object{$_.Name -eq $thisValue}).roleID
					$row.vCenter = $thisvCenter
					$row.Delta = $thisDelta
					$roleReport += $row
					$roleDeltaCount++
				}
			}
# 			else{ Write-Host "RoleList Identical" -ForegroundColor Green }
			
			Write-Host "Sorting Permissions..."
			$XMLPermissions = $XMLAudit.SelectNodes("Inventory/Permissions")
			$thisPrincipalSet = $thisPermissionSet.Principal|Select-Object -Unique|Sort-Object
			$masterPrincipalSet = ($thisMasterFile.Inventory.Permissions.Principal).Name
			$PrincipalAuditSet = ($masterPrincipalSet+$thisPrincipalSet)|Select-Object -Unique|Sort-Object
			foreach($Principal in $thisPrincipalSet){
				$thisName = $Principal;$i++
				$XMLPerm = $XMLPermissions.AppendChild($XMLAudit.CreateElement("Principal"))
				$XMLPerm.SetAttribute( "Name", $thisName )
				$thisSubSet = $thisPermissionSet|Where-Object{$_.Principal -eq $thisName}
				$thisSubSet|ForEach-Object{
					$XMLPerm.SetAttribute( "isGroup", $_.isGroup )
					$XMLentity = $XMLPerm.AppendChild($XMLAudit.CreateElement("Entity"))
					$XMLentity.SetAttribute( "Name", $_.Entity )
					$XMLentity.SetAttribute( "ID", $_.EntityID )
					$XMLentity.SetAttribute( "Type", $_.EntityType )
					$XMLentity.SetAttribute( "Propagate", $_.Propagate )
					$XMLentity.SetAttribute( "Role", $_.Role )
					$XMLentity.SetAttribute( "RoleID", $_.RoleID )
				}
			}
			Write-Host "Audting Permissions..."
			foreach($Principal in $PrincipalAuditSet){
				$thisName = $Principal
# 				Write-Host "Checking" $thisName -ForegroundColor Cyan
				$thisReferenceObject=$null;$thisDifferenceObject=$null
				$thisReferenceObject = ($thisMasterFile.Inventory.Permissions.Principal|Where-Object{$_.Name -eq $thisName}).Entity
				$thisDifferenceObject = ($XMLAudit.Inventory.Permissions.Principal|Where-Object{$_.Name -eq $thisName}).Entity
# 				if($thisDifferenceObject){Write-Host "difObject found"}
# 				else{Write-Host	"no difObject" -ForegroundColor Red}
				if($thisReferenceObject -and $thisDifferenceObject){
# 					Write-Host "refObject found" -ForegroundColor Green
					$AuditResults=$null
					$AuditResults =  Compare-Object -ReferenceObject $thisReferenceObject -DifferenceObject $thisDifferenceObject -Property Name,Role,Propagate,type,ID,RoleID
					if($AuditResults){
# 						Write-Host	"Applied Principal Deltas found" -ForegroundColor Magenta
						$auditFailed = $true;$auditFailCount++
						$AuditResults|ForEach-Object{
						$permissionDeltaCount++
							$row=""|Select-Object vCenter,Principal,RoleName,RoleID,EntityName,EntityID,EntityType,RolePropagation,Delta
							$thisValue = "role $($_.Role) added to $($_.Type) $($_.Name), Propagation is $($_.Propagate)"
							switch($_.SideIndicator){
								"<=" {
										$thisDelta="**REMOVED**"
										Write-Host `t"REMOVED : $thisName : $thisValue" -ForegroundColor Yellow
									}
								"=>" {
										$thisDelta="**ADDED**"
										Write-Host `t"ADDED   : $thisName : $thisValue" -ForegroundColor Red
									}
							}
							$row.Principal = $thisName
							$row.RoleName = $_.Role
							$row.RoleID = $_.RoleID
							$row.vCenter = $thisvCenter
							$row.EntityName = $_.Name
							$row.EntityID = $_.ID
							$row.EntityType = $_.Type
							$row.RolePropagation = $_.Propagate
							$row.Delta = $thisDelta
							$permReport+=$row
						}
					}
				}
				elseif((!($thisDifferenceObject)) -and ($thisReferenceObject)){
					Write-Host "Principal Removed: $thisName" -ForegroundColor Yellow
					$permissionDeltaCount++
					$thisReferenceObject|ForEach-Object{
						$row=""|Select-Object vCenter,Principal,RoleName,RoleID,EntityName,EntityID,EntityType,RolePropagation,Delta
						$row.Principal = $thisName
						$row.RoleName = $_.Role
						$row.RoleID = $_.RoleID
						$row.vCenter = $thisvCenter
						$row.EntityName = $_.Name
						$row.EntityID = $_.ID
						$row.EntityType = $_.Type
						$row.RolePropagation = $_.Propagate
						$row.Delta = "**REMOVED**"
						$permReport+=$row
						$auditFailed = $true;$auditFailCount++
					}
				}
				else{
					Write-Host "New Principal Applied: $thisName" -ForegroundColor Red
					$permissionDeltaCount++
					$thisDifferenceObject|ForEach-Object{
						$row=""|Select-Object vCenter,Principal,RoleName,RoleID,EntityName,EntityID,EntityType,RolePropagation,Delta
						$row.Principal = $thisName
						$row.RoleName = $_.Role
						$row.RoleID = $_.RoleID
						$row.vCenter = $thisvCenter
						$row.EntityName = $_.Name
						$row.EntityID = $_.ID
						$row.EntityType = $_.Type
						$row.RolePropagation = $_.Propagate
						$row.Delta = "**ADDED**"
						$permReport+=$row
						$auditFailed = $true;$auditFailCount++
					}
				}
			}
			if($auditFailed){
				Write-Host "Saving audit XML to disk..."
				$XMLAudit.Save($auditFileName)
				$reportBundle+=$auditFileName
				$auditFailCount++
			}
			if($remaster){
				Write-Host "Remastering vCenter $thisvCenter"
				$XMLAudit.Save($masterFileName)
			}
			Disconnect-VIServer $vConn -Confirm:$false
		}
		else{
			Write-Host "[" -NoNewline;Write-Host "ERROR" -ForegroundColor Red -NoNewline;Write-Host "]"
			$auditFailed=$true;$auditFailCount++
			$goodvCenterConnect=$false
		}
	}
	else{
		write-host ("*"*50) -ForegroundColor Yellow; Write-Host "Missing Master File for $thisvCenter" -ForegroundColor Red
		Write-Host "Re-run script with -remaster parameter to build baseline." -ForegroundColor Red
		write-host ("*"*50) -ForegroundColor Yellow
		$auditFailed=$true;$auditFailCount++
		$goodMasterFile=$false
	}
	$row=""|Select-Object vCenter,MasterFile,vConnGood,MasterFileGood
	$row.vCenter = $thisvCenter
	$row.MasterFile = $masterFileName
	$row.vConnGood = $goodvCenterConnect
	$row.MasterFileGood = $goodMasterFile
	$auditReport+=$row
}
if($i -gt 0){$thisStatus="<span style=""font-size:10px;font-weight:bold;color:Green"">Consistent</span>"}
else{$thisStatus="<span style=""font-size:10px;font-weight:bold;color:Red"">ERROR</span>"}
if($auditReport.Count -gt 0){$auditReportHTML = $auditReport|ConvertTo-Html vCenter,MasterFile,vConnGood,MasterFileGood -Head $XMLfile.Data.Config.TableFormats.Blue.value -Body "<h4>Audit Items</h4>"}
else{"<h4>Audit Items</h4><span style=""background-color:White; font-weight:Bold; font-size:12px;color:Red;align:right""><blockquote>!! Something Failed !!</blockquote></span>"}
$auditReportHTML=$auditReportHTML.Replace("False","<span style=""font-weight:bold;color:Red"">FALSE</span>")
$auditReportHTML=$auditReportHTML.Replace("True","<span style=""font-weight:bold;color:Green"">TRUE</span>")
$HTMLhead = "<style type=""text/css"">"
$HTMLhead += "body{font-family:calibri;font-size:10pt;font-weight:normal;color:black;}"
$HTMLhead += "th{text-align:center; background-color:#00417c; color:#FFFFFF; font-weight:bold; font-size:12px;}"
$HTMLhead += "td{background-color:#F5F5F5; font-weight:normal; font-size:10px; padding: 3px 10px 3px 10px;}"
$HTMLhead += "</style>"
$roleModReportHTML=$HTMLhead+"<h4>Role Changes</h4>$thisStatus"
$roleReportHTML=$HTMLhead+"<h4>Roles Added/Removed</h4>$thisStatus"
$permReportHTML=$HTMLhead+"<h4>Applied Permission Changes</h4>$thisStatus"
if($remaster){
	$reportReMasterHTML = "<span style=""background-color:White; font-weight:Bold; font-size:12px;color:Red;align:right""><blockquote>!! Audit Baselines were Re-Mastered by: $userName @ $userDomain !!</blockquote></span>"
	$subject = "< < REMASTERED > > "+$subject
	$roleDeltaCount = 0;$roleRightsDeltaCount = 0;$permissionDeltaCount = 0;$auditFailCount = 0
	$reportBundle = @()
}
if($auditFailCount -gt 0){
	if($roleModReport.Count -gt 0){$roleModReportHTML = $roleModReport|ConvertTo-Html vCenter,RoleName,RoleID,Permission,Delta -Head $XMLfile.Data.Config.TableFormats.Red.value -body "<h4>Role Changes</h4>"}
	if($roleReport.Count -gt 0){$roleReportHTML = $roleReport|ConvertTo-Html vCenter,RoleName,RoleID,Delta -Head $XMLfile.Data.Config.TableFormats.Red.value -body "<h4>Roles Added/Removed</h4>"}
	if($permReport.Count -gt 0){$permReportHTML = $permReport|ConvertTo-Html vCenter,Principal,RoleName,RoleID,EntityName,EntityID,EntityType,RolePropagation,Delta -Head $XMLfile.Data.Config.TableFormats.Red.value -body "<h4>Applied Permission Changes</h4>"}
	$subject = $subject+" !! FAILED !!"
}
$reportHeader = $HTMLhead+"<h3>$reportTitle</h3></br><table><th colspan=2>Audit Stats</th><tr><td>vCenters</td><td>$vCenterCount</td></tr><tr><td>Roles Added/Removed</td><td>$roleDeltaCount</td></tr><tr><td>Role Changes</td><td>$roleRightsDeltaCount</td></tr><tr><td>Permission Changes</td><td>$permissionDeltaCount</td></tr></table><hr>"
$reportHTML = $reportHeader
$reportHTML += $auditReportHTML
$reportHTML += $reportReMasterHTML
$reportHTML += $roleReportHTML
$reportHTML += $roleModReportHTML
$reportHTML += $permReportHTML
$reportHTML = $reportHTML.Replace("**ADDED**","<span style=""font-weight:bold;color:Red"">ADDED</span>")
$reportHTML = $reportHTML.Replace("**REMOVED**","<span style=""font-weight:bold;color:Orange"">REMOVED</span>")
$reportHTML += "<hr><span style=""background-color:White; font-weight:normal; font-size:10px;color:Orange;align:right""><blockquote>v$Version - $CompName : $userName @ $userDomain - $StartTime</blockquote></span>"
if($sendMail){
	Write-Host "Emailing Report..."
	if($reportBundle.Count -gt 0){
		Send-MailMessage -Subject $subject -From $FROM -To $TO -Body $reportHTML -BodyAsHtml -SmtpServer $SMTP -Attachments $reportBundle
	}
	else{
		Send-MailMessage -Subject $subject -From $FROM -To $TO -Body $reportHTML -BodyAsHtml -SmtpServer $SMTP
	}
}
Write-Host "Saving Report to Disk";$reportHTML|Out-File $ReportFile
# ==============================================================================================
# ==============================================================================================
$stopwatch.Stop()
$Elapsed = [math]::Round(($stopwatch.elapsedmilliseconds)/1000,1)
Write-Host ("="*80) -ForegroundColor DarkGreen
Write-Host ("="*80) -ForegroundColor DarkGreen
Write-Host ""
Write-Host "Script Completed in $Elapsed second(s)"
Write-Host ""
Write-Host ("="*80) -ForegroundColor DarkGreen
Stop-Transcript