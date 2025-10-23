# Unraid Docker Template

This repository includes an Unraid docker template for easy deployment of the Dell iDRAC Fan Controller with GPU support.

## Installation

### Method 1: Template Repository (Recommended)
1. In Unraid, go to **Docker** tab
2. Click **Add Container**
3. Click **Template repositories** 
4. Add this repository URL: `https://github.com/daniellog/Dell_iDRAC_fan_controller_Docker_GPU_Support`
5. Click **Save**
6. The template will appear in your template list

### Method 2: Manual Template Installation
1. Download the `unraid-template.xml` file from this repository
2. In Unraid, go to **Docker** tab
3. Click **Add Container**
4. Click **Advanced View**
5. Copy and paste the XML content into the template field

## Configuration

### Required Settings
- **iDRAC Host**: IP address of your Dell iDRAC (e.g., `192.168.1.100`) or use `local` for local IPMI
- **iDRAC Username**: Usually `root` for Dell servers
- **iDRAC Password**: Your iDRAC password (usually `calvin` by default)

### Optional Settings
- **Fan Speed %**: Base fan speed when temperatures are normal (default: 5%)
- **CPU Temperature Threshold**: Temperature in Celsius above which fans increase (default: 50°C)
- **GPU Temperature Threshold**: GPU temperature threshold (default: 80°C)
- **Check Interval**: How often to check temperatures in seconds (default: 60)
- **Enable GPU Temperature Monitoring**: Set to `true` to monitor GPU temperatures

### Advanced Settings
- **Disable Third Party PCIe Card Response**: Disable Dell's default cooling for third-party cards
- **Keep Third Party PCIe Card State on Exit**: Preserve cooling state when container stops

## Prerequisites

### For Local IPMI (recommended)
- Dell server with IPMI support
- IPMI kernel modules loaded on Unraid host
- `/dev/ipmi0` device available (template includes this device mapping)

### For Remote iDRAC
- Network access to iDRAC interface
- iDRAC credentials

### For GPU Monitoring
- NVIDIA GPU: Install NVIDIA drivers on Unraid host
- AMD GPU: Install AMD ROCm drivers on Unraid host
- Set `Enable GPU Temperature Monitoring` to `true`

## Network Mode

This template uses **Host** network mode to ensure proper access to:
- IPMI devices for local communication
- iDRAC network interface for remote communication
- GPU monitoring tools

## Device Mapping

The template automatically maps `/dev/ipmi0` for local IPMI communication. If your system uses a different IPMI device, adjust the device mapping accordingly.

## Troubleshooting

1. **Container won't start**: Check that IPMI modules are loaded: `lsmod | grep ipmi`
2. **Can't connect to iDRAC**: Verify network connectivity and credentials
3. **GPU monitoring not working**: Ensure GPU drivers are installed on the host
4. **Permission errors**: Container runs in privileged mode to access IPMI devices

## Support

For issues and support, please visit the [GitHub repository](https://github.com/daniellog/Dell_iDRAC_fan_controller_Docker_GPU_Support).