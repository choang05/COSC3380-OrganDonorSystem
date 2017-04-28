$rootDir = Join-Path $env:HOME "SiteExtensions\Microsoft.ApplicationInsights.AzureWebSites"
$logDir = Join-Path  $env:HOME "LogFiles"
$logPath = Join-Path $logDir "\ApplicationInsightsExtension.log"

# Methods
function Is-AspNetCoreApplication
{
	param(
        [string] $applicationRoot
    )

	return (Get-ChildItem -Path $applicationRoot -Filter appsettings.json -Recurse -ErrorAction SilentlyContinue -Force).Count -ne 0
}

function Check-ApplicationInstrumentation
{
	param(
        [string] $applicationRoot
    )

	$configPath = Join-Path $applicationRoot "ApplicationInsights.config"
	$configNamespace = @{ns="http://schemas.microsoft.com/ApplicationInsights/2013/Settings"}

	$instrumented = Test-Path($configPath)
	if($instrumented)
	{
		Log-VerboseMessage "Loading config from $configPath"
		[xml] $content = Get-Content $configPath

		$extensionNode = Select-Xml -Xml $content -XPath "//ns:AzureWebSiteExtension" -Namespace $configNamespace
		if ($extensionNode)
		{
			$instrumented = $false
			Log-VerboseMessage "Application is instrumented with Application Insights Extension."
			$logger.LogEvent("AzureWebAppExtensionCheck", "Instrumentation", "Extension")
		}
		else
		{
			$applicationInsightsDll = Join-Path $applicationRoot "bin\Microsoft.ApplicationInsights.dll"
			$instrumented = Test-Path($applicationInsightsDll)
			if ($instrumented)
			{
				$assemblyVersion = [Reflection.AssemblyName]::GetAssemblyName($applicationInsightsDll).Version
				Log-VerboseMessage "Application is already instrumented with Application Insights version: $assemblyVersion"
				$logger.LogEvent("AzureWebAppExtensionCheck", "Instrumentation", "SDK")
			}
			else
			{
				Log-VerboseMessage "Application is not instrumented with Application Insights."
				$logger.LogEvent("AzureWebAppExtensionCheck", "Instrumentation", "No")
			}
		}
	}
	else
	{
		Log-VerboseMessage "Application is not instrumented with Application Insights."
		$logger.LogEvent("AzureWebAppExtensionCheck", "Instrumentation", "No")

		"<ApplicationInsights xmlns=`"http://schemas.microsoft.com/ApplicationInsights/2013/Settings`"></ApplicationInsights>" | Set-Content $configPath -Encoding Unicode
	}

    return $instrumented
}

function Enable-Profiler
{
	param(
		[string] $originPath,
		[string] $packagesLocation,
        [Microsoft.ApplicationInsights.WebSiteManager.PackageInstaller] $packageManager
    )

	Log-VerboseMessage "Starting Application Insights Profiler configuration..."

	$bitness = "x64"
	if ($env:PROCESSOR_ARCHITECTURE -eq "x86")
	{
		$bitness = "x86"
	}	

	Log-VerboseMessage "Current processor architecture: $bitness"

	# download RTIA nuget packages
	Download-Package "Microsoft.ApplicationInsights.Agent_$bitness" $originPath $packagesLocation $packageManager

	# install RTIA packages
	$destinationDirectory = Join-Path $rootDir "Agent"
	New-Item $destinationDirectory -Type directory -Force

	$originDirectory = Join-Path (Join-Path $packagesLocation "Microsoft.ApplicationInsights.Agent_$bitness.2.2.0") "content\RTIA\$bitness"
    Log-VerboseMessage "Ready to copy files from $originDirectory to $destinationDirectory"

	foreach($file in (Get-ChildItem $originDirectory))
	{
		# remove bitness depended file endings for 
		# 1. Microsoft.ApplicationInsights.ExtensionsHost_x64(x86).dll
		# 2. MicrosoftInstrumentationEngine_x64(x86).dll
		$destinationName = $file.Name
		if ($file.Name.StartsWith("Microsoft.ApplicationInsights.ExtensionsHost") -or $file.Name.StartsWith("MicrosoftInstrumentationEngine"))
		{
			$destinationName = $file.Name.Replace("_$bitness", "")
		}

		$destinationName = Join-Path $destinationDirectory $destinationName 

		try
		{
			Copy-Item $file.FullName $destinationName -Force
			Log-VerboseMessage "$file.Name was copied."
		}
		catch
		{
			Log-ErrorMessage "Cannot copy $file.Name: $_"
		}
	}

	Log-VerboseMessage "End of Application Insights Profiler configuration."
}

function Get-OriginalRepository
{
	return Join-Path $RootDir "appinsights"
}

function Get-LocalRepository
{
	return Join-Path $RootDir "Packages"
}

function Download-Package
{
	param(
        [string] $packageName,
		[string] $originLocation,
		[string] $packagesLocation,
		[Microsoft.ApplicationInsights.WebSiteManager.PackageInstaller] $packageManager
    )

	Log-VerboseMessage "Starting to download/install '$packageName' nuget package from $originLocation..."			
	$packageManager.DownloadPackages($originLocation, $packagesLocation, $packageName)
	Log-VerboseMessage "End of '$packageName' nuget package download/install."
}

function Get-ApplicationSourcesFolder
{
	return Join-Path $env:HOME "\site\approot"
}

function Get-ApplicationFolder
{
	return Join-Path $env:HOME "\site\wwwroot"
}

function Load-PackageManager
{
	$assemblyPath = Join-Path $RootDir "Microsoft.ApplicationInsights.WebSiteManager.dll"
	if(Test-Path($assemblyPath))
	{
		Log-VerboseMessage "Loading assembly from $assemblyPath"
		[Reflection.Assembly]::LoadFrom($assemblyPath) | Out-Null

		$packageManager = New-Object -TypeName Microsoft.ApplicationInsights.WebSiteManager.PackageInstaller
		$packageManager.LogFileName = $logPath

		return $packageManager
	}
	else
	{
		throw "Assembly is not found at $assemblyPath"
	}
}

function Load-TelemetryLogger
{
	$assemblyPath = Join-Path $RootDir "Microsoft.ApplicationInsights.WebSiteManager.dll"
	if(Test-Path($assemblyPath))
	{
		Log-VerboseMessage "Loading assembly from $assemblyPath"
		[Reflection.Assembly]::LoadFrom($assemblyPath) | Out-Null

		$telemetryManager = New-Object -TypeName Microsoft.ApplicationInsights.WebSiteManager.TelemetryLogger

		return $telemetryManager
	}
	else
	{
		throw "Assembly is not found at $assemblyPath"
	}
}
 
function Install-Package
{
	param(
        [string] $applicationRoot,
		[string] $packagesLocation,
		[string] $packageName,
		[Microsoft.ApplicationInsights.WebSiteManager.PackageInstaller] $packageManager
    )

	Log-VerboseMessage "Starting to install $packageName nuget package from $packagesLocation to $applicationRoot..."
	$packageManager.InstallPackage($packagesLocation, $applicationRoot, $packageName)
	Log-VerboseMessage "End of $packageName nuget package installation."
}

function Uninstall-Packages
{
	param(
        [string] $applicationRoot,
		[Microsoft.ApplicationInsights.WebSiteManager.PackageInstaller] $packageManager
    )

	Log-VerboseMessage "Starting to uninstall nuget packages..."

	$nugetSource = Join-Path $applicationRoot "App_Data\Packages"
			
	$packageManager.UninstallPackages($nugetSource, $applicationRoot)
	
	Log-VerboseMessage "End of nuget packages uninstallation."
}

function Log-ErrorMessage
{
    param(
        [string] $message
    )

    Log-Message "Error" $message
	$logger.LogException($message)
}

function Log-VerboseMessage
{
    param(
        [string] $message
    )

    Log-Message "Verbose" $message
}

function Log-Message
{
    param(
        [string] $messageLevel,
		[string] $message
    )

	try
	{
		if (!(Test-Path $logDir))
		{
			New-Item $logDir -ItemType directory
		}	

		Add-Content $logPath ("{0}: [{1}] {2}" -f (Get-Date), $messageLevel, $message)
		if ($messageLevel -eq "Error")
		{
			Add-Content err.txt ("{0}: [{1}] {2}" -f (Get-Date), $messageLevel, $message)
		}
	}
	catch 
	{
		// swallow exception during the logging
	}
}
# SIG # Begin signature block
# MIIarAYJKoZIhvcNAQcCoIIanTCCGpkCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUE/HNYSCGzTyx71wklkDLwpRe
# mvSgghWDMIIEwzCCA6ugAwIBAgITMwAAAMZ4gDYBdRppcgAAAAAAxjANBgkqhkiG
# 9w0BAQUFADB3MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4G
# A1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSEw
# HwYDVQQDExhNaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EwHhcNMTYwOTA3MTc1ODUz
# WhcNMTgwOTA3MTc1ODUzWjCBszELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hp
# bmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jw
# b3JhdGlvbjENMAsGA1UECxMETU9QUjEnMCUGA1UECxMebkNpcGhlciBEU0UgRVNO
# OkY1MjgtMzc3Ny04QTc2MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBT
# ZXJ2aWNlMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEArQsjG6jKiCgU
# NuPDaF0GhCh1QYcSqJypNAJgoa1GtgoNrKXTDUZF6K+eHPNzXv9v/LaYLZX2GyOI
# 9lGz55tXVv1Ny6I1ueVhy2cUAhdE+IkVR6AtCo8Ar8uHwEpkyTi+4Ywr6sOGM7Yr
# wBqw+SeaBjBwON+8E8SAz0pgmHHj4cNvt5A6R+IQC6tyiFx+JEMO1qqnITSI2qx3
# kOXhD3yTF4YjjRnTx3HGpfawUCyfWsxasAHHlILEAfsVAmXsbr4XAC2HBZGKXo03
# jAmfvmbgbm3V4KBK296Unnp92RZmwAEqL08n+lrl+PEd6w4E9mtFHhR9wGSW29C5
# /0bOar9zHwIDAQABo4IBCTCCAQUwHQYDVR0OBBYEFNS/9jKwiDEP5hmU8T6/Mfpb
# Ag8JMB8GA1UdIwQYMBaAFCM0+NlSRnAK7UD7dvuzK7DDNbMPMFQGA1UdHwRNMEsw
# SaBHoEWGQ2h0dHA6Ly9jcmwubWljcm9zb2Z0LmNvbS9wa2kvY3JsL3Byb2R1Y3Rz
# L01pY3Jvc29mdFRpbWVTdGFtcFBDQS5jcmwwWAYIKwYBBQUHAQEETDBKMEgGCCsG
# AQUFBzAChjxodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY3Jv
# c29mdFRpbWVTdGFtcFBDQS5jcnQwEwYDVR0lBAwwCgYIKwYBBQUHAwgwDQYJKoZI
# hvcNAQEFBQADggEBAJhbANzvo0iL5FA5Z5QkwG+PvkDfOaYsTYksqFk+MgpqzPxc
# FwSYME/S/wyihd4lwgQ6CPdO5AGz3m5DZU7gPS5FcCl10k9pTxZ4s857Pu8ZrE2x
# rnUyUiQFl5DYSNroRPuQYRZZXs2xK1WVn1JcwcAwJwfu1kwnebPD90o1DRlNozHF
# 3NMaIo0nCTRAN86eSByKdYpDndgpVLSoN2wUnsh4bLcZqod4ozdkvgGS7N1Af18R
# EFSUBVraf7MoSxKeNIKLLyhgNxDxZxrUgnPb3zL73zOj40A1Ibw3WzJob8vYK+gB
# YWORl4jm6vCwAq/591z834HDNH60Ud0bH+xS7PowggTtMIID1aADAgECAhMzAAAB
# QJap7nBW/swHAAEAAAFAMA0GCSqGSIb3DQEBBQUAMHkxCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xIzAhBgNVBAMTGk1pY3Jvc29mdCBDb2RlIFNp
# Z25pbmcgUENBMB4XDTE2MDgxODIwMTcxN1oXDTE3MTEwMjIwMTcxN1owgYMxCzAJ
# BgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25k
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xDTALBgNVBAsTBE1PUFIx
# HjAcBgNVBAMTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjCCASIwDQYJKoZIhvcNAQEB
# BQADggEPADCCAQoCggEBANtLi+kDal/IG10KBTnk1Q6S0MThi+ikDQUZWMA81ynd
# ibdobkuffryavVSGOanxODUW5h2s+65r3Akw77ge32z4SppVl0jII4mzWSc0vZUx
# R5wPzkA1Mjf+6fNPpBqks3m8gJs/JJjE0W/Vf+dDjeTc8tLmrmbtBDohlKZX3APb
# LMYb/ys5qF2/Vf7dSd9UBZSrM9+kfTGmTb1WzxYxaD+Eaxxt8+7VMIruZRuetwgc
# KX6TvfJ9QnY4ItR7fPS4uXGew5T0goY1gqZ0vQIz+lSGhaMlvqqJXuI5XyZBmBre
# ueZGhXi7UTICR+zk+R+9BFF15hKbduuFlxQiCqET92ECAwEAAaOCAWEwggFdMBMG
# A1UdJQQMMAoGCCsGAQUFBwMDMB0GA1UdDgQWBBSc5ehtgleuNyTe6l6pxF+QHc7Z
# ezBSBgNVHREESzBJpEcwRTENMAsGA1UECxMETU9QUjE0MDIGA1UEBRMrMjI5ODAz
# K2Y3ODViMWMwLTVkOWYtNDMxNi04ZDZhLTc0YWU2NDJkZGUxYzAfBgNVHSMEGDAW
# gBTLEejK0rQWWAHJNy4zFha5TJoKHzBWBgNVHR8ETzBNMEugSaBHhkVodHRwOi8v
# Y3JsLm1pY3Jvc29mdC5jb20vcGtpL2NybC9wcm9kdWN0cy9NaWNDb2RTaWdQQ0Ff
# MDgtMzEtMjAxMC5jcmwwWgYIKwYBBQUHAQEETjBMMEoGCCsGAQUFBzAChj5odHRw
# Oi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY0NvZFNpZ1BDQV8wOC0z
# MS0yMDEwLmNydDANBgkqhkiG9w0BAQUFAAOCAQEAa+RW49cTHSBA+W3p3k7bXR7G
# bCaj9+UJgAz/V+G01Nn5XEjhBn/CpFS4lnr1jcmDEwxxv/j8uy7MFXPzAGtOJar0
# xApylFKfd00pkygIMRbZ3250q8ToThWxmQVEThpJSSysee6/hU+EbkfvvtjSi0lp
# DimD9aW9oxshraKlPpAgnPWfEj16WXVk79qjhYQyEgICamR3AaY5mLPuoihJbKwk
# Mig+qItmLPsC2IMvI5KR91dl/6TV6VEIlPbW/cDVwCBF/UNJT3nuZBl/YE7ixMpT
# Th/7WpENW80kg3xz6MlCdxJfMSbJsM5TimFU98KNcpnxxbYdfqqQhAQ6l3mtYDCC
# BbwwggOkoAMCAQICCmEzJhoAAAAAADEwDQYJKoZIhvcNAQEFBQAwXzETMBEGCgmS
# JomT8ixkARkWA2NvbTEZMBcGCgmSJomT8ixkARkWCW1pY3Jvc29mdDEtMCsGA1UE
# AxMkTWljcm9zb2Z0IFJvb3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5MB4XDTEwMDgz
# MTIyMTkzMloXDTIwMDgzMTIyMjkzMloweTELMAkGA1UEBhMCVVMxEzARBgNVBAgT
# Cldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29m
# dCBDb3Jwb3JhdGlvbjEjMCEGA1UEAxMaTWljcm9zb2Z0IENvZGUgU2lnbmluZyBQ
# Q0EwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCycllcGTBkvx2aYCAg
# Qpl2U2w+G9ZvzMvx6mv+lxYQ4N86dIMaty+gMuz/3sJCTiPVcgDbNVcKicquIEn0
# 8GisTUuNpb15S3GbRwfa/SXfnXWIz6pzRH/XgdvzvfI2pMlcRdyvrT3gKGiXGqel
# cnNW8ReU5P01lHKg1nZfHndFg4U4FtBzWwW6Z1KNpbJpL9oZC/6SdCnidi9U3RQw
# WfjSjWL9y8lfRjFQuScT5EAwz3IpECgixzdOPaAyPZDNoTgGhVxOVoIoKgUyt0vX
# T2Pn0i1i8UU956wIAPZGoZ7RW4wmU+h6qkryRs83PDietHdcpReejcsRj1Y8wawJ
# XwPTAgMBAAGjggFeMIIBWjAPBgNVHRMBAf8EBTADAQH/MB0GA1UdDgQWBBTLEejK
# 0rQWWAHJNy4zFha5TJoKHzALBgNVHQ8EBAMCAYYwEgYJKwYBBAGCNxUBBAUCAwEA
# ATAjBgkrBgEEAYI3FQIEFgQU/dExTtMmipXhmGA7qDFvpjy82C0wGQYJKwYBBAGC
# NxQCBAweCgBTAHUAYgBDAEEwHwYDVR0jBBgwFoAUDqyCYEBWJ5flJRP8KuEKU5VZ
# 5KQwUAYDVR0fBEkwRzBFoEOgQYY/aHR0cDovL2NybC5taWNyb3NvZnQuY29tL3Br
# aS9jcmwvcHJvZHVjdHMvbWljcm9zb2Z0cm9vdGNlcnQuY3JsMFQGCCsGAQUFBwEB
# BEgwRjBEBggrBgEFBQcwAoY4aHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraS9j
# ZXJ0cy9NaWNyb3NvZnRSb290Q2VydC5jcnQwDQYJKoZIhvcNAQEFBQADggIBAFk5
# Pn8mRq/rb0CxMrVq6w4vbqhJ9+tfde1MOy3XQ60L/svpLTGjI8x8UJiAIV2sPS9M
# uqKoVpzjcLu4tPh5tUly9z7qQX/K4QwXaculnCAt+gtQxFbNLeNK0rxw56gNogOl
# VuC4iktX8pVCnPHz7+7jhh80PLhWmvBTI4UqpIIck+KUBx3y4k74jKHK6BOlkU7I
# G9KPcpUqcW2bGvgc8FPWZ8wi/1wdzaKMvSeyeWNWRKJRzfnpo1hW3ZsCRUQvX/Ta
# rtSCMm78pJUT5Otp56miLL7IKxAOZY6Z2/Wi+hImCWU4lPF6H0q70eFW6NB4lhhc
# yTUWX92THUmOLb6tNEQc7hAVGgBd3TVbIc6YxwnuhQ6MT20OE049fClInHLR82zK
# wexwo1eSV32UjaAbSANa98+jZwp0pTbtLS8XyOZyNxL0b7E8Z4L5UrKNMxZlHg6K
# 3RDeZPRvzkbU0xfpecQEtNP7LN8fip6sCvsTJ0Ct5PnhqX9GuwdgR2VgQE6wQuxO
# 7bN2edgKNAltHIAxH+IOVN3lofvlRxCtZJj/UBYufL8FIXrilUEnacOTj5XJjdib
# Ia4NXJzwoq6GaIMMai27dmsAHZat8hZ79haDJLmIz2qoRzEvmtzjcT3XAH5iR9HO
# iMm4GPoOco3Boz2vAkBq/2mbluIQqBC0N1AI1sM9MIIGBzCCA++gAwIBAgIKYRZo
# NAAAAAAAHDANBgkqhkiG9w0BAQUFADBfMRMwEQYKCZImiZPyLGQBGRYDY29tMRkw
# FwYKCZImiZPyLGQBGRYJbWljcm9zb2Z0MS0wKwYDVQQDEyRNaWNyb3NvZnQgUm9v
# dCBDZXJ0aWZpY2F0ZSBBdXRob3JpdHkwHhcNMDcwNDAzMTI1MzA5WhcNMjEwNDAz
# MTMwMzA5WjB3MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4G
# A1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSEw
# HwYDVQQDExhNaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EwggEiMA0GCSqGSIb3DQEB
# AQUAA4IBDwAwggEKAoIBAQCfoWyx39tIkip8ay4Z4b3i48WZUSNQrc7dGE4kD+7R
# p9FMrXQwIBHrB9VUlRVJlBtCkq6YXDAm2gBr6Hu97IkHD/cOBJjwicwfyzMkh53y
# 9GccLPx754gd6udOo6HBI1PKjfpFzwnQXq/QsEIEovmmbJNn1yjcRlOwhtDlKEYu
# J6yGT1VSDOQDLPtqkJAwbofzWTCd+n7Wl7PoIZd++NIT8wi3U21StEWQn0gASkdm
# EScpZqiX5NMGgUqi+YSnEUcUCYKfhO1VeP4Bmh1QCIUAEDBG7bfeI0a7xC1Un68e
# eEExd8yb3zuDk6FhArUdDbH895uyAc4iS1T/+QXDwiALAgMBAAGjggGrMIIBpzAP
# BgNVHRMBAf8EBTADAQH/MB0GA1UdDgQWBBQjNPjZUkZwCu1A+3b7syuwwzWzDzAL
# BgNVHQ8EBAMCAYYwEAYJKwYBBAGCNxUBBAMCAQAwgZgGA1UdIwSBkDCBjYAUDqyC
# YEBWJ5flJRP8KuEKU5VZ5KShY6RhMF8xEzARBgoJkiaJk/IsZAEZFgNjb20xGTAX
# BgoJkiaJk/IsZAEZFgltaWNyb3NvZnQxLTArBgNVBAMTJE1pY3Jvc29mdCBSb290
# IENlcnRpZmljYXRlIEF1dGhvcml0eYIQea0WoUqgpa1Mc1j0BxMuZTBQBgNVHR8E
# STBHMEWgQ6BBhj9odHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtpL2NybC9wcm9k
# dWN0cy9taWNyb3NvZnRyb290Y2VydC5jcmwwVAYIKwYBBQUHAQEESDBGMEQGCCsG
# AQUFBzAChjhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY3Jv
# c29mdFJvb3RDZXJ0LmNydDATBgNVHSUEDDAKBggrBgEFBQcDCDANBgkqhkiG9w0B
# AQUFAAOCAgEAEJeKw1wDRDbd6bStd9vOeVFNAbEudHFbbQwTq86+e4+4LtQSooxt
# YrhXAstOIBNQmd16QOJXu69YmhzhHQGGrLt48ovQ7DsB7uK+jwoFyI1I4vBTFd1P
# q5Lk541q1YDB5pTyBi+FA+mRKiQicPv2/OR4mS4N9wficLwYTp2OawpylbihOZxn
# LcVRDupiXD8WmIsgP+IHGjL5zDFKdjE9K3ILyOpwPf+FChPfwgphjvDXuBfrTot/
# xTUrXqO/67x9C0J71FNyIe4wyrt4ZVxbARcKFA7S2hSY9Ty5ZlizLS/n+YWGzFFW
# 6J1wlGysOUzU9nm/qhh6YinvopspNAZ3GmLJPR5tH4LwC8csu89Ds+X57H2146So
# dDW4TsVxIxImdgs8UoxxWkZDFLyzs7BNZ8ifQv+AeSGAnhUwZuhCEl4ayJ4iIdBD
# 6Svpu/RIzCzU2DKATCYqSCRfWupW76bemZ3KOm+9gSd0BhHudiG/m4LBJ1S2sWo9
# iaF2YbRuoROmv6pH8BJv/YoybLL+31HIjCPJZr2dHYcSZAI9La9Zj7jkIeW1sMpj
# tHhUBdRBLlCslLCleKuzoJZ1GtmShxN1Ii8yqAhuoFuMJb+g74TKIdbrHk/Jmu5J
# 4PcBZW+JC33Iacjmbuqnl84xKf8OxVtc2E0bodj6L54/LlUWa8kTo/0xggSTMIIE
# jwIBATCBkDB5MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4G
# A1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSMw
# IQYDVQQDExpNaWNyb3NvZnQgQ29kZSBTaWduaW5nIFBDQQITMwAAAUCWqe5wVv7M
# BwABAAABQDAJBgUrDgMCGgUAoIGsMBkGCSqGSIb3DQEJAzEMBgorBgEEAYI3AgEE
# MBwGCisGAQQBgjcCAQsxDjAMBgorBgEEAYI3AgEVMCMGCSqGSIb3DQEJBDEWBBRq
# qr7gkJgVV5+znSIiE1cHUyU7GzBMBgorBgEEAYI3AgEMMT4wPKAigCAAYgBhAHMA
# ZQBDAG8AbQBtAGEAbgBkAHMALgBwAHMAMaEWgBRodHRwOi8vbWljcm9zb2Z0LmNv
# bTANBgkqhkiG9w0BAQEFAASCAQB16cWaU++JbV/vVRU5Sg1qFxUjV8+tl0YJb1MI
# 9OmcmvVN3bSv9zhukrRw+sRLjP6FUxMA/2T2Py4STl3wZ0PDu1cOAn7O9TOvIri9
# jchQ54eOwFSiPLiv1EDENeE8mhvGcQM1U2N5dzNFt9ICumYYcRc4eMsQujv0X/xv
# 5UYT6wJYIiBRRIT9RHmFXFleEaYFsfs+TzOVNWDDCvxpp7pXnnTcsmtR9sJkrEjH
# K5SMWF90+rJMdiu2SOq/c+mDULfXYBW8U5tEZleyBIPFDWHNkxLNNFJ/7f82cWmW
# z7HAtB5y5v6rRuXHVl4ctguM36FhwE9I0BJ0vxIJpcIF9gwYoYICKDCCAiQGCSqG
# SIb3DQEJBjGCAhUwggIRAgEBMIGOMHcxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
# YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xITAfBgNVBAMTGE1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQQIT
# MwAAAMZ4gDYBdRppcgAAAAAAxjAJBgUrDgMCGgUAoF0wGAYJKoZIhvcNAQkDMQsG
# CSqGSIb3DQEHATAcBgkqhkiG9w0BCQUxDxcNMTYxMjEzMjIwMzIyWjAjBgkqhkiG
# 9w0BCQQxFgQUWCpBGEVxZSQ865zRag4T3+tQsPcwDQYJKoZIhvcNAQEFBQAEggEA
# LQ4YizgAAt0T/hYQBDlr3b2oBQ1OkpEJkZQd+M/Ak3+oif9ejAxDiEShbjUxmH2O
# UFGVQWzMEz6ox61x0rTErVMqnnl0xOga4iymOlvupv6OjRX8DWPrbfE7OV9R80BE
# h2A4pRzzntFoA2nf0AnPZyM5YUqkx6867rtLDektJQ2iH2xh9NlrMj+z1Tg2oAwp
# w1GJvFvRljT0xdlUytliH9p8y3EN/LC7hB0+PAnwGlQSEPmViyRSmIPQ4Au5L04W
# nLwjoYFKzXaW7Ay9uphCZSnP0MeaSIgbmN6rmi7hohPXP5XLHGHFtzoPgdHi0Aij
# T6NTmggRwiyUOouzTD8DQA==
# SIG # End signature block
