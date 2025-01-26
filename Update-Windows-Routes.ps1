### PowerShell script to update Windows Static Routing with exact metrics for multiple network interfaces ###

<#
    This script is useful when you have multiple network interfaces and VLANs in Windows, 
    and want precise control over your static routes and their metrics.

    Example Use Cases:
    - One interface connects to a management VLAN (no Internet)
    - Another interface connects to a personal/homelab VLAN (with Internet)
    - You want to specify 0.0.0.0/0 routes for each interface with different metrics
    - You have various subnets (e.g., 192.168.x.0/24) that each need a static route
#>

## 1. DEFINITIONS ##

# Gateways used for each route. Replace with your real gateway IPs.
$Gateways = @{
    Management = "192.168.0.1"
    Personal   = "192.168.50.1"
}

# Windows Network Adapters
#   - IfIndex is retrieved dynamically for each adapter
#   - IfIndex is required for setting the default route to a specific interface
$Adapters = @{
    Ethernet1 = @{
        Name    = "Ethernet 1"
        IfIndex = $null
    }
    Ethernet2 = @{
        Name    = "Ethernet 2"
        IfIndex = $null
    }
}

# Default Routes (for 0.0.0.0)
#   - "Key" must match one of the keys in $Adapters
#   - "Metric" is the route metric (not the interface metric)
$DefaultRoutes = @(
    @{ Key = "Ethernet1"; Gateway = $Gateways.Management; Metric = 20 },
    @{ Key = "Ethernet2"; Gateway = $Gateways.Personal; Metric = 10 }
)

# Static Routes (for VLAN/inter-VLAN subnets)
#   - Each route has its own destination, mask, gateway, and metric
$StaticRoutes = @(
    @{ Destination = "192.168.0.0"; Mask = "255.255.255.0"; Gateway = $Gateways.Management; Metric = 10 },
    @{ Destination = "192.168.50.0"; Mask = "255.255.255.248"; Gateway = $Gateways.Personal; Metric = 10 }
)

## 2. FUNCTIONS ##
# (A) Sets the adapter IfIndex dynamically
function Set-AdapterIfIndex {
    param (
        [Parameter(Mandatory)]
        [hashtable]$Adapters
    )

    Write-Output ">>> Retrieving and storing IfIndex for each adapter <<<"
    foreach ($key in $Adapters.Keys) {
        $adapterName = $Adapters[$key].Name
        $ifIndex = (Get-NetAdapter -Name $adapterName -ErrorAction SilentlyContinue).IfIndex

        if ($ifIndex) {
            $Adapters[$key].IfIndex = $ifIndex
            Write-Output "Adapter '$adapterName' -> IfIndex = $ifIndex"
        }
        else {
            Write-Output "Could not find IfIndex for '$adapterName'"
        }
    }

    Write-Output ">>> IfIndex retrieved and stored! <<<`n"
}

# (B) Clears all existing routes using route -f
#     WARNING: This can remove all existing static routes, so proceed with caution.
function Clear-Routes {
    Write-Output ">>> Clearing all routes <<<"
    route -f
    Write-Output ">>> Routes cleared! <<<`n`n"
}

# (C) Restarts all adapters to ensure changes apply
function Restart-NetworkAdapters {
    Write-Output ">>> Restarting all network adapters <<<`n"

    foreach ($Key in $Adapters.Keys) {
        $Name = $Adapters[$Key].Name
        Write-Output "Restarting adapter: $Name"
        Restart-NetAdapter -Name $Name -Confirm:$false
    }

    Start-Sleep -Seconds 10
    Write-Output ">>> All adapters restarted! <<<`n`n"
}

# (D) Adds a persistent static route for a given subnet
function Add-PersistentStaticRoute {
    param (
        [string]$Destination,
        [string]$Mask,
        [string]$Gateway,
        [int]$Metric
    )

    Write-Output "Adding persistent static route to $Destination via $Gateway (Metric: $Metric)"
    route -p add $Destination mask $Mask $Gateway metric $Metric
}

# (E) Disables auto-metric on an adapter and sets a manual metric
#     We call this after adding routes, because some commands can re-enable auto-metric
function Set-ManualAdapterMetric {
    param (
        [string]$Name,
        [int]$Metric
    )

    Write-Output "Disabling auto-metric and setting metric ($Metric) for adapter '$Name'..."

    $adapter = Get-NetIPInterface -InterfaceAlias $Name -ErrorAction SilentlyContinue
    if (-not $adapter) {
        Write-Output "Adapter '$Name' not found. Skipping."
        return
    }

    # Use -AutomaticMetric Disabled, not $false
    Set-NetIPInterface -InterfaceAlias $Name -AutomaticMetric Disabled -InterfaceMetric $Metric

    Write-Output "Auto-metric disabled and metric set to $Metric for adapter '$Name'."
}

# (F) Loop to set a manual metric for all adapters
function Set-AdapterMetrics {
    Write-Output ">>> Setting adapter metrics <<<`n"
    foreach ($Key in $Adapters.Keys) {
        $Name = $Adapters[$Key].Name
        Set-ManualAdapterMetric -Name $Name -Metric 10
    }
    Write-Output ">>> Adapter metrics set! <<<`n`n"
}

## 3. MAIN SCRIPT FLOW ##

# 1) Retrieve IfIndex for each adapter
Set-AdapterIfIndex -Adapters $Adapters

# 2) Clear all existing routes - optional if you want a fresh start each time
Clear-Routes

# 3) Restart adapters so Windows sees a clean slate
Restart-NetworkAdapters

# 4) Add static (non-default) routes
Write-Output ">>> Adding static routes <<<"
foreach ($Route in $StaticRoutes) {
    Add-PersistentStaticRoute -Destination $Route.Destination -Mask $Route.Mask -Gateway $Route.Gateway -Metric $Route.Metric
}
Write-Output ">>> Static routes added! <<<`n`n"

# 5) Add default routes using IfIndex
Write-Output ">>> Adding default routes <<<"
foreach ($Route in $DefaultRoutes) {
    $Key = $Route.Key
    $Name = $Adapters[$Key].Name
    $IfIndex = $Adapters[$Key].IfIndex
    $Gateway = $Route.Gateway
    $Metric = $Route.Metric

    if ($IfIndex) {
        Write-Output "Adding default route 0.0.0.0/0 to $Gateway (Metric=$Metric) on adapter '$Name' (IfIndex=$IfIndex)"
        route -p ADD 0.0.0.0 MASK 0.0.0.0 $Gateway METRIC $Metric if $IfIndex
    }
    else {
        Write-Output "Skipping default route for '$Name' - no IfIndex found!"
    }
}
Write-Output ">>> Default routes added! <<<`n`n"

# 6) Restart once more to ensure routes are recognized
Restart-NetworkAdapters

# 7) Finally, set manual metrics for each adapter (so Windows doesn't auto-modify them)
Set-AdapterMetrics

# 8) Show the final route table
Write-Output ">>> All routes added! <<<`n`n"
route print

Write-Output ">>> Completed! <<<"