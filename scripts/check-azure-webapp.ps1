param(
    [string]$ResourceGroup = "rg-sql-sso-crud-dev",
    [string]$AppName = "sso-azure-sql-crud",
    [string]$SqlServer = "sql-sso-crud-dev-6931936",
    [string]$SqlDatabase = "sqldb-crud-dev",
    [string]$SsoClientId = "57694959-05d4-412a-bf3a-4c16ff1f9828",
    [string]$TenantId = "b7cb14b9-dc5c-44fe-a920-7e6bb7e310a6",
    [string]$WorkflowFile = ".github/workflows/main_sso-azure-sql-crud.yml"
)

$ErrorActionPreference = "Stop"

function Write-Check {
    param([string]$Message)
    Write-Host "[CHECK] $Message" -ForegroundColor Cyan
}

function Write-Pass {
    param([string]$Message)
    Write-Host "[OK]    $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "[WARN]  $Message" -ForegroundColor Yellow
}

function Write-Fail {
    param([string]$Message)
    Write-Host "[FAIL]  $Message" -ForegroundColor Red
}

function Invoke-AzJson {
    param([string[]]$Arguments)
    $output = & az @Arguments -o json 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw ($output -join "`n")
    }
    if (-not $output) {
        return $null
    }
    return ($output | ConvertFrom-Json)
}

function Get-AppSettingValue {
    param($Settings, [string]$Name)
    $setting = $Settings | Where-Object { $_.name -eq $Name } | Select-Object -First 1
    if ($setting) {
        return $setting.value
    }
    return $null
}

Write-Host ""
Write-Host "Azure Web App Deployment Double Check" -ForegroundColor White
Write-Host "====================================" -ForegroundColor White
Write-Host ""

Write-Check "Azure CLI login and subscription"
try {
    $account = Invoke-AzJson @("account", "show")
    Write-Pass "Signed in as $($account.user.name)"
    if ($account.tenantId -eq $TenantId) {
        Write-Pass "Tenant matches expected tenant $TenantId"
    } else {
        Write-Warn "Current tenant is $($account.tenantId), expected $TenantId"
    }
    Write-Host "        Subscription: $($account.name) [$($account.id)]"
} catch {
    Write-Fail "Azure CLI is not signed in. Run: az login"
    throw
}

Write-Host ""
Write-Check "Local deployment files"
if (Test-Path -LiteralPath $WorkflowFile) {
    Write-Pass "Workflow exists: $WorkflowFile"
} else {
    Write-Fail "Workflow is missing: $WorkflowFile"
}

if (Test-Path -LiteralPath "api/main.py") { Write-Pass "api/main.py exists" } else { Write-Fail "api/main.py missing" }
if (Test-Path -LiteralPath "api/requirements.txt") { Write-Pass "api/requirements.txt exists" } else { Write-Fail "api/requirements.txt missing" }
if (Test-Path -LiteralPath "package.json") { Write-Pass "package.json exists" } else { Write-Fail "package.json missing" }

Write-Host ""
Write-Check "App Service status and runtime"
$webapp = Invoke-AzJson @("webapp", "show", "--resource-group", $ResourceGroup, "--name", $AppName)
$defaultHost = $webapp.defaultHostName
$productionUrl = "https://$defaultHost"
Write-Host "        Default host: $defaultHost"

if ($webapp.state -eq "Running") {
    Write-Pass "App Service state is Running"
} elseif ($webapp.state -eq "QuotaExceeded") {
    Write-Fail "App Service is over quota. Check App Service Plan -> Quotas or scale temporarily."
} else {
    Write-Warn "App Service state is $($webapp.state)"
}

$config = Invoke-AzJson @("webapp", "config", "show", "--resource-group", $ResourceGroup, "--name", $AppName)
if ($config.linuxFxVersion -match "PYTHON\|3\.13") {
    Write-Pass "Runtime stack is $($config.linuxFxVersion)"
} else {
    Write-Warn "Runtime stack is $($config.linuxFxVersion); expected Python 3.13"
}

$expectedStartup = "python -m uvicorn api.main:app --host 0.0.0.0 --port 8000"
if ($config.appCommandLine -eq $expectedStartup) {
    Write-Pass "Startup command is correct"
} else {
    Write-Fail "Startup command mismatch. Current: '$($config.appCommandLine)' Expected: '$expectedStartup'"
}

Write-Host ""
Write-Check "App Service application settings"
$settings = Invoke-AzJson @("webapp", "config", "appsettings", "list", "--resource-group", $ResourceGroup, "--name", $AppName)
$requiredSettings = @(
    "AZURE_TENANT_ID",
    "AZURE_CLIENT_ID",
    "AZURE_SQL_SERVER",
    "AZURE_SQL_DATABASE",
    "AZURE_SQL_ODBC_DRIVER",
    "ALLOWED_ORIGINS",
    "USER_ROLE",
    "ADMIN_ROLE",
    "PYTHONPATH",
    "SCM_DO_BUILD_DURING_DEPLOYMENT"
)

foreach ($name in $requiredSettings) {
    $value = Get-AppSettingValue $settings $name
    if ([string]::IsNullOrWhiteSpace($value)) {
        Write-Fail "Missing app setting: $name"
    } else {
        Write-Pass "Found app setting: $name"
    }
}

$allowedOrigins = Get-AppSettingValue $settings "ALLOWED_ORIGINS"
if ($allowedOrigins -and ($allowedOrigins.Split(",").Trim() -contains $productionUrl)) {
    Write-Pass "ALLOWED_ORIGINS contains exact production URL"
} else {
    Write-Fail "ALLOWED_ORIGINS should contain exact production URL: $productionUrl"
}

$pythonPath = Get-AppSettingValue $settings "PYTHONPATH"
if ($pythonPath -eq "/home/site/wwwroot/.python_packages/lib/site-packages") {
    Write-Pass "PYTHONPATH points at packaged GitHub Actions dependencies"
} else {
    Write-Fail "PYTHONPATH should be /home/site/wwwroot/.python_packages/lib/site-packages"
}

$managedIdentityClientId = Get-AppSettingValue $settings "AZURE_MANAGED_IDENTITY_CLIENT_ID"

Write-Host ""
Write-Check "Managed identity"
$identity = Invoke-AzJson @("webapp", "identity", "show", "--resource-group", $ResourceGroup, "--name", $AppName)
Write-Host "        Identity type: $($identity.type)"
Write-Host "        Principal ID: $($identity.principalId)"

if ($identity.type -match "SystemAssigned") {
    Write-Pass "System-assigned managed identity is enabled"
    if ($managedIdentityClientId) {
        Write-Warn "AZURE_MANAGED_IDENTITY_CLIENT_ID is set, but this web app is using system-assigned identity. Remove it unless a user-assigned identity is attached."
    } else {
        Write-Pass "AZURE_MANAGED_IDENTITY_CLIENT_ID is absent, correct for system-assigned identity"
    }
} else {
    Write-Fail "System-assigned managed identity is not enabled"
}

if ($identity.userAssignedIdentities -and -not $managedIdentityClientId) {
    Write-Warn "User-assigned identities are attached. If you intend to use one, set AZURE_MANAGED_IDENTITY_CLIENT_ID to its client ID."
}

Write-Host ""
Write-Check "Microsoft Entra app registration"
try {
    $app = Invoke-AzJson @("ad", "app", "show", "--id", $SsoClientId)
    Write-Pass "Found SSO app registration"
    $redirects = @()
    if ($app.spa -and $app.spa.redirectUris) {
        $redirects = @($app.spa.redirectUris)
    }
    if ($redirects -contains $productionUrl) {
        Write-Pass "SPA redirect URI contains production URL"
    } else {
        Write-Fail "Missing SPA redirect URI: $productionUrl"
    }
    if ($redirects -contains "http://localhost:5177") {
        Write-Pass "SPA redirect URI contains local localhost URL"
    } else {
        Write-Warn "Missing local redirect URI: http://localhost:5177"
    }

    $roleValues = @($app.appRoles | Where-Object { $_.isEnabled -eq $true } | ForEach-Object { $_.value })
    foreach ($role in @("User", "Admin")) {
        if ($roleValues -contains $role) {
            Write-Pass "App role exists and is enabled: $role"
        } else {
            Write-Fail "Missing or disabled app role: $role"
        }
    }
} catch {
    Write-Warn "Could not inspect Entra app registration. You may need directory read permissions. Error: $($_.Exception.Message)"
}

Write-Host ""
Write-Check "Azure SQL network access"
$sqlServerInfo = Invoke-AzJson @("sql", "server", "show", "--resource-group", $ResourceGroup, "--name", $SqlServer)
if ($sqlServerInfo.publicNetworkAccess -eq "Enabled") {
    Write-Pass "SQL public network access is Enabled"
} else {
    Write-Fail "SQL public network access is $($sqlServerInfo.publicNetworkAccess)"
}

$rules = Invoke-AzJson @("sql", "server", "firewall-rule", "list", "--resource-group", $ResourceGroup, "--server", $SqlServer)
$allowAzure = $rules | Where-Object {
    $_.startIpAddress -eq "0.0.0.0" -and $_.endIpAddress -eq "0.0.0.0"
} | Select-Object -First 1
if ($allowAzure) {
    Write-Pass "SQL firewall allows Azure services/resources"
} else {
    Write-Fail "SQL firewall does not have 0.0.0.0 -> 0.0.0.0 rule. Enable 'Allow Azure services and resources to access this server' or add App Service outbound IPs."
}

Write-Host ""
Write-Check "Azure SQL database identity grants"
Write-Warn "This script cannot verify SQL contained users without connecting to the database."
Write-Host "        Confirm in Azure SQL Query Editor that this has been run:"
Write-Host "        CREATE USER [$AppName] FROM EXTERNAL PROVIDER;"
Write-Host "        ALTER ROLE db_datareader ADD MEMBER [$AppName];"
Write-Host "        ALTER ROLE db_datawriter ADD MEMBER [$AppName];"

Write-Host ""
Write-Check "Production endpoint smoke test"
try {
    $health = Invoke-WebRequest "$productionUrl/api/health" -UseBasicParsing -TimeoutSec 75
    if ($health.StatusCode -eq 200) {
        Write-Pass "/api/health returned 200"
    } else {
        Write-Warn "/api/health returned $($health.StatusCode)"
    }
} catch {
    Write-Warn "/api/health did not return within 75 seconds or failed: $($_.Exception.Message)"
    Write-Host "        If using Free F1, check App Service Plan -> Quotas and try again after the app warms up."
}

Write-Host ""
Write-Host "Done. If the app still shows 500 after these checks, open App Service -> Log stream and look for the latest traceback." -ForegroundColor White
