// Linux jumpbox VM for connecting to a private AKS cluster via Bastion.
// Cloud-init installs azure-cli, kubectl, kubelogin.
targetScope = 'resourceGroup'

@description('Azure region.')
param location string

@description('Jumpbox VM name.')
param vmName string

@description('Jumpbox subnet resource ID.')
param subnetId string

@description('VM size.')
param vmSize string = 'Standard_B2s'

@description('Admin username.')
param adminUsername string = 'azureuser'

@description('SSH public key (OpenSSH format).')
@secure()
param sshPublicKey string

@description('AKS cluster resource ID (used by cloud-init to pre-configure kubeconfig).')
param aksClusterId string = ''

@description('Resource tags.')
param tags object = {}

var aksSegs = split(aksClusterId, '/')
var aksRg = empty(aksClusterId) ? '' : aksSegs[4]
var aksName = empty(aksClusterId) ? '' : aksSegs[8]

var cloudInit = '''
#cloud-config
package_update: true
package_upgrade: false
packages:
  - curl
  - ca-certificates
  - gnupg
  - apt-transport-https
  - jq
runcmd:
  - curl -sL https://aka.ms/InstallAzureCLIDeb | bash
  - az aks install-cli
  - echo 'alias k=kubectl' >> /home/__ADMIN__/.bashrc
  - chown __ADMIN__:__ADMIN__ /home/__ADMIN__/.bashrc
write_files:
  - path: /etc/motd
    content: |
      ==== AKS Jumpbox ====
      Run: az login --identity ; az aks get-credentials -g __RG__ -n __CLUSTER__ --overwrite-existing ; kubectl get nodes
'''

var renderedCloudInit = replace(replace(replace(cloudInit, '__ADMIN__', adminUsername), '__RG__', aksRg), '__CLUSTER__', aksName)

resource nic 'Microsoft.Network/networkInterfaces@2024-01-01' = {
  name: '${vmName}-nic'
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: { id: subnetId }
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: vmName
  location: location
  tags: tags
  identity: { type: 'SystemAssigned' }
  properties: {
    hardwareProfile: { vmSize: vmSize }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: 'ubuntu-24_04-lts'
        sku: 'server'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: { storageAccountType: 'StandardSSD_LRS' }
      }
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      customData: base64(renderedCloudInit)
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: sshPublicKey
            }
          ]
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        { id: nic.id }
      ]
    }
  }
}

output vmId string = vm.id
output vmName string = vm.name
output principalId string = vm.identity.principalId
