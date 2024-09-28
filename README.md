# systemd-hosts.d
## Keep your hosts records in logically separated files

- Service monitors `/etc/hosts.d/*.conf` files and updates `/etc/hosts` whether change.

- There are 2 essential parts:

  - `systemd-hosts.d.path` unit monitors changes inside the `/etc/hosts.d` directory and triggers the service.

  - `systemd-hosts.d.service` unit upon activation reassembles the `/etc/hosts` file from the contents of `/etc/hosts.d/*.conf`.

- There is also a helper utility available to streamline updating simple hosts entries.
  ```sh
  $ hosts.d localhost 127.0.0.1 # -c, --create
  Writing '127.0.0.1 localhost' to '/etc/hosts.d/localhost.conf'

  $ hosts.d -l # --list
  ## From /etc/hosts.d/localhost.conf ##
  127.0.0.1 localhost

  $ hosts.d -m localhost local # --move
  Writing '127.0.0.1 local' to '/etc/hosts.d/local.conf'
  Deleting '/etc/hosts.d/localhost.conf'

  $ hosts.d -m local -p 99 # --priority 99
  Moving '/etc/hosts.d/local.conf' to '/etc/hosts.d/99-local.conf'

  $ hosts.d -d local # --delete
  Deleting '/etc/hosts.d/99-local.conf'

  $ ./hosts.sh -r google.com # --resolve
  Executing: 'dig' '+short' 'google.com'
  Writing 'XX.XX.XX.XX google.com' to '/etc/hosts.d/google.com.conf'

  $ hosts.d -h # --help
  A front-end to individually manipulate simple hosts.d entries

  Usage: ./hosts.sh [OPERATION] [OPTIONS] [--] [ARGS]
  Operations:
    -c, --create [HOST] [ADDR]
    -m, --move [SRC_HOST] [DST_HOST]
    -d, --delete [HOST]
    -r, --resolve [HOST]
    -l, --list [GLOB]
  Options:
    -t, --target-dir <path> [default: '/etc/hosts.d']
    -p, --priority <priority>
    -f, --force
    -q, --quiet
        --resolver-script <script>
        --resolver <command> [default: 'dig']
        --resolver-arg <arg> [default: '+short']
        --resolver-erase-args
        --dry-run
  ```

## Instalation

- <img src="https://www.monitorix.org/imgs/archlinux.png" weight="20" height="20"> **Arch Linux**: in the [AUR](https://aur.archlinux.org/packages/systemd-hosts.d/)

- **Manual**
  ```shell
  mkdir /etc/hosts.d
  mv /etc/hosts /etc/hosts.d/hosts.conf
  cp systemd-hosts.d.path systemd-hosts.d.service /etc/systemd/system
  systemctl enable --now systemd-hosts.d.path

  # Optionally you can store result in RAM
  ln -sf /run/hosts /etc/hosts
  systemctl enable --now systemd-hosts.d.service

  # Install the helper utility
  cp contrib/hosts.d /usr/local/bin
