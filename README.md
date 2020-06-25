# Carisa: A Respectful Install Script for Arch

`carisa` is an unopinionated install script for Arch Linux, which closely follows the [installation guide](https://wiki.archlinux.org/index.php/installation_guide) on the ArchWiki. I call it "respectful" because it asks permission for everything and cleans up after itself.

## Usage

After booting the [Arch Linux live medium](https://www.archlinux.org/download/) and connecting to the internet:

```console
$ curl -O https://raw.githubusercontent.com/justinyaodu/carisa/master/carisa.sh
$ ./carisa.sh start
```

## Features

`carisa` lets you:

* View (and edit) the commands run for every installation step
* Skip any steps which you would rather do manually
* Exit at any time with <kbd>Ctrl</kbd>+<kbd>C</kbd>, and resume where you left off

Besides performing the essential steps listed in the installation guide, `carisa` can also:

* Generate a customized mirrorlist from the [official mirrorlist generator](https://www.archlinux.org/mirrorlist/)
* Suggest additional packages to install using `pacstrap` (e.g. text editor, networking)
* Install the GRUB boot manager (optional; other boot managers can be installed manually)

## Disclaimers

`carisa` is primarily designed to streamline the installation process for experienced users. As such, it assumes that the user has the knowledge and experience necessary to perform each step in the [installation guide](https://wiki.archlinux.org/index.php/installation_guide) manually.

Steps that **require** manual intervention include:

* Connecting to the internet
* Disk partitioning
* Bootloader installation

In the unlikely and unfortunate event that `carisa` breaks your system, I cannot be held responsible (as stated in the [license](LICENSE.md)). However, a bug report would be most appreciated in this case.

## License

`carisa` is licensed under the [MIT License](LICENSE.md).
