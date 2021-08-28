
# 'VMware PowerCLI' Linux VM Deployment Scripts - Myles Petersen


## Created during my time at Reliable Controls as an automated method to easily create up to dozens of virtual Reliable Controls controllers. 
### Sensitive info removed (e.g. FIRMWARE_NAME, HYPERVISOR_IP, etc...), and posted with permission. 

---

## Main script files: MakeVM, MakeTemplate

## Example .CSV File for VM Creation in MakeVM

| Name | Template | Host | Datastore | IpAddr | Device | Port | SerialNum | Database | PortGroup | Folder | CPULimitMHz | CPUReservedMHz | TotalRAMGB | PercentRAMReserved | SubnetMask | Gateway |
| - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - |
| Example-VM | Linux-<FIRMWARE_NAME-RELEASE_VERSION> | <HYPERVISOR_IP> | <DATASTORE_NAME> | 192.168.#.# | 1000 | <PORT #> | EX-1 | ..\Database\example.db |  | Myles | 750 | 250 | 0.5 | 100 |  |  |
| Example-VM-VLAN | Linux-<OLDER_FIRMWARE_NAME-RELEASE_VERSION> | <HYPERVISOR_IP> | <DATASTORE_NAME> | 192.168.#.# | 2000 | <PORT #> | EX-1 | ..\Database\example.db | VLAN-# | Myles | 1000 | 500 | 1 | 0 | /21 | <GATEWAY_ADDRESS> |


