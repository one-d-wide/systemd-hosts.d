# systemd-hosts.d
## Keep your hosts records in logically separated files

- Service monitors /etc/hosts.d/*.conf files and updates /etc/hosts whether change.

## Instalation
- <img src="https://www.monitorix.org/imgs/archlinux.png" weight="20" height="20"> **Arch Linux**: in the [AUR](https://aur.archlinux.org/packages/systemd-hosts.d/)
- **Manual**
  ```shell
  mkdir /etc/hosts.d
  mv /etc/hosts /etc/hosts.d/hosts.conf
  cp systemd-hosts.d.path systemd-hosts.d.service /etc/systemd/system
  systemctl enable --now systemd-hosts.d.path

  # Optionally you can store result in ram
  ln -sf /run/hosts /etc/hosts
  systemctl enable --now systemd-hosts.d.service
