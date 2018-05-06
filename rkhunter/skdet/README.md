# skdet
* * *

## Rkhunter Dependency

Skdet must be configured to allow checking for following rootkits:

* SucKIT
* Adore
* Adore-NG
* UNFshit
* UNFkmem
* frontkey

You can find out more from the official [Rkhunter skdet page](https://sourceforge.net/p/rkhunter/wiki/skdet)

## Instructions

This script must be executed by running `rkhunter-install.sh`:

**Full Install**:

```bash

$ rkhunter-install.sh --install

```

**Skdet Module Configuration Only**:

```bash

$ rkhunter-install.sh --configure skdet

```

* * *
