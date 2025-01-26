# Windows Static Routing Tool
---

This script helps configure **EXACT** static routes on Windows, crucial when:
 - You have **multiple physical network interfaces** or VLANs.
- Each interface might connect to a **different gateway** or subnet.
- You want **multiple** default (`0.0.0.0/0`) routes, each on a different interface, with unique metrics.
- You require **precise control** over route metrics (instead of letting Windows auto-assign them). Windows has a c**p way of managing it, making your life hell.

---

## 1 - How It Works
1. **Manually Set your parameters**
Type out your static routes, default routs, ethernet adapter names

2. **Retrieves Each Adapter's `IfIndex`**
Windows assigns a numeric interface index (`IfIndex`) to every network adapter. We gather those indexes at runtime so we can bind specific default routes to each interface.

3. **Clears Existing Routes**  
The script optionally removes all existing routes (`route -f`) so you start fresh.
> **Warning**: This will remove any existing static routes you may have added or any system routes that aren't automatically re-created. Use with caution.

4. **Adds Static (VLAN) Routes**  
You can define as many subnets as you need under `$StaticRoutes`. Each route has:
- **Destination** (e.g., `192.168.x.0`)
- **Subnet Mask** (e.g., `255.255.255.0`)
- **Gateway** (the IP of your router on that subnet)
- **Route Metric**

5. **Adds Default Routes**
You can define multiple default routes in `$DefaultRoutes`. For each:
- **Key** references your `$Adapters` key (e.g., `"Ethernet1"`)
- **Gateway** is where 0.0.0.0 traffic is sent
- **Metric** is the route metric

6. **Disables Auto-Metric**  
Windows sometimes tries to auto-adjust route metrics. We set each adapter's interface metric manually and disable this feature, so your script's metrics remain intact.

7. **Restarts Adapters**  
The script restarts adapters multiple times to ensure new routes and metrics register properly.

  

## 2 - Usage
1. **Edit the Script**  
   - **Gateways**: Replace with your real gateway IPs (e.g., `192.168.0.1`).
   - **Adapters**: Set your actual adapter names (as shown in `Control Panel -> Network Connections`). Keep the keys consistent with `$DefaultRoutes`.
   - **StaticRoutes**: Add any subnets you want to route manually (e.g., homelab, management VLANs).
   - **DefaultRoutes**: If you only want **one** default route, remove the extra entry.

2. **Run PowerShell as Administrator**  
You must have elevated privileges to modify routes and adapter settings.

3. **Execute the Script**  
```powershell
.\Update-Windows-Routes.ps1