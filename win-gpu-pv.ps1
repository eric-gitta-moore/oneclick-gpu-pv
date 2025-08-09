set-executionpolicy remotesigned

$ErrorActionPreference = "Stop"

$signalLabel = "HeartBeat"
$okLabel = "OK"

if ((Get-WinSystemLocale).Name -eq "zh-CN") {
	$signalLabel = "检测信号"
	$okLabel = "确定"
}

$vmobject = Get-VM | Out-GridView -Title "Select VM to setup GPU-P" -OutputMode Single
$vmid = $vmobject.VMId
Write-Host "Stopping VM"
$vmobject | Stop-VM
Write-Host "Disabling checkpoints for VM"
$vmobject | Set-VM -CheckpointType Disabled
Write-Host "Enabling heartbeat service for VM"
$vmobject | Enable-VMIntegrationService -Name $signalLabel
if ($vmobject | Get-VMGpuPartitionAdapter) { $vmobject | Remove-VMGpuPartitionAdapter }
Write-Host "Starting VM"
$vmobject | Start-VM
do { Start-Sleep 2 } while (($vmobject | Get-VMIntegrationService -Name $signalLabel).PrimaryStatusDescription -ne $okLabel)
Write-Host "Connecting to VM"
$vmsess = New-PSSession -VMId $vmid
Write-Host "Copying display drivers to VM"
Invoke-Command -Session $vmsess { $prologWritten = $false }

# region choose gpu
$dev = Get-PnpDevice -Class Display -Status OK | Out-GridView -Title "Select Card to setup GPU-P" -OutputMode Single

$props = $dev | Get-PnpDeviceProperty
$pnpinf = ($props | where { $_.KeyName -eq "DEVPKEY_Device_DriverInfPath" }).Data
$infsection = ($props | where { $_.KeyName -eq "DEVPKEY_Device_DriverInfSection" }).Data
$cbsinf = (Get-WindowsDriver -Online | where { $_.Driver -eq "$pnpinf" }).OriginalFileName
If (-not $cbsinf) {
	Write-Host "Device not supported: $dev, inf: $pnpinf, cbs: $cbsinf"
	return;
}

$gpuName = $dev.FriendlyName
$path = $dev.InstanceId.replace('\', '#').ToLower()
$pvs = Get-VMHostPartitionableGpu
$targetGpu = $null
foreach ($pv in $pvs) {
	$name = $pv.Name.ToLower()
	echo "$name"
	if ($name.contains($path)) {
		$targetGpu = $pv
		$path = $pv.Name
	}
}

echo "============================"
echo "Using: $gpuName, pnpinf: $pnpinf, path: $path"
echo "============================"
# endregion choose gpu

# region copy driver
$inffile = (Get-Item -LiteralPath $cbsinf)
$drvpkg = $inffile.Directory
Write-Host "Copying driver package $drvpkg to VM, using $dev."
$hostdrvstorepath = Invoke-Command {
	New-Item -ItemType Directory "$env:SystemRoot\System32\HostDriverStore\FileRepository" -Force
} -Session $vmsess

# $hostdrvstorepath = Join-Path $remoteSystemRoot "System32\HostDriverStore\FileRepository"
Copy-Item -LiteralPath $drvpkg.FullName -ToSession $vmsess -Destination "$hostdrvstorepath" -Recurse -Force
$vminfpath = join-path (Join-Path $hostdrvstorepath $drvpkg.name) $inffile.Name
Invoke-Command -Session $vmsess -ScriptBlock {
	if (-not $prologWritten) {
		Set-Content -LiteralPath "$env:SystemDrive\GPUPAdditionalSetup.bat" -Encoding utf8 -Value @"
cd /d %TEMP%
set dirname=gpupaddlsetup%RANDOM%
mkdir %dirname%
cd %dirname%
"@
		$prologWritten = $true
	}
	Add-Content -LiteralPath "$env:SystemDrive\GPUPAdditionalSetup.bat" -Encoding utf8 -Value "start `"`" /wait rundll32 advpack.dll,LaunchINFSectionEx $using:vminfpath,$using:infsection,,4"
}

$scriptWritten = Invoke-Command -Session $vmsess -ScriptBlock {
	if ($prologWritten) {
		Add-Content -LiteralPath "$env:SystemDrive\GPUPAdditionalSetup.bat" -Encoding utf8 -Value @"
cd ..
rmdir /s /q %dirname%
"@
	}
	$prologWritten
}
# endregion copy driver

# region setup GPU-PV
Write-Host "Stopping VM"
$vmobject | Stop-VM
Write-Host "Configuring GPU-PV for VM"
$vmobject | Add-VMGpuPartitionAdapter -InstancePath "$path"
$vmobject | Set-VMGpuPartitionAdapter  `
	-MinPartitionVRAM $targetGpu.MinPartitionVRAM `
	-MaxPartitionVRAM $targetGpu.MaxPartitionVRAM `
	-OptimalPartitionVRAM $targetGpu.OptimalPartitionVRAM `
	-MinPartitionEncode $targetGpu.MinPartitionEncode `
	-MaxPartitionEncode $targetGpu.MaxPartitionEncode `
	-OptimalPartitionEncode $targetGpu.OptimalPartitionEncode `
	-MinPartitionDecode $targetGpu.MinPartitionDecode `
	-MaxPartitionDecode $targetGpu.MaxPartitionDecode `
	-OptimalPartitionDecode $targetGpu.OptimalPartitionDecode `
	-MinPartitionCompute $targetGpu.MinPartitionCompute `
	-MaxPartitionCompute $targetGpu.MaxPartitionCompute `
	-OptimalPartitionCompute $targetGpu.OptimalPartitionCompute
$vmobject | Set-VM -GuestControlledCacheTypes $true -LowMemoryMappedIoSpace 1Gb -HighMemoryMappedIoSpace 32GB
# endregion setup GPU-PV

Write-host "Done"
if ($scriptWritten) {
	Write-Host "Don't forget to run GPUPAdditionalSetup.bat in system drive as administrator for additional setup. This may enable video codec and alternative graphics/compute APIs."
}
