#!/bin/bash

######## Directory Paths ########

script_dir="$(dirname "${0}")"
persist_dir="${script_dir}/.carisa"

######## Utility Functions ########

# _has_content <file>
# Check if <file> has lines that are neither whitespace nor comments.
_has_content() {
	[ -f "${1}" ] && grep -Evq '^(#.*|[[:space:]]*)$' "${1}"
}

######## Output Formatting ########

# Color variables.
red="$(tput setaf 1)"
green="$(tput setaf 2)"
yellow="$(tput setaf 3)"
reset="$(tput sgr0)"

# Enclose non-printable characters (e.g. color escape sequences) with these
# characters when using anything involving readline, so that the line length is
# detected properly.
np_start=$'\001'
np_end=$'\002'

# Wrap the above color variables.
red_enclosed="${np_start}${red}${np_end}"
green_enclosed="${np_start}${green}${np_end}"
yellow_enclosed="${np_start}${yellow}${np_end}"
reset_enclosed="${np_start}${reset}${np_end}"

# Output the width of the terminal, or 80 if the terminal is wider than that.
_line_length() {
	local cols="$(tput cols)"

	if [ "${cols}" -gt '80' ]; then
		cols='80'
	fi

	echo "${cols}"
}

# _center_text <text> <width> <pad>
# Center <text> in <width> by repeatedly adding <pad> to either side, then
# removing characters from the end of the string.
_center_text() {
	local text="${1}"
	local width="${2}"
	local pad="${3}"

	# Pad on both sides repeatedly.
	while [ "${#text}" -lt "${width}" ]; do
		local text="${pad}${text}${pad}"
	done
	
	# Remove extra characters from the right end.
	echo "${text:0:${width}}"
}

# _function_banner <function_name>
# Output a nicely formatted banner showing the name of an installation step.
_function_banner() {
	local function_name="${1}"

	case "${function_name}" in
		_[0-9]00_*)
			local pad='#'
			;;
		_[0-9][0-9]0_*)
			local pad='='
			;;
		*)
			local pad='-'
			;;
	esac

	echo
	echo "$(_center_text " ${function_name} " "$(_line_length)" "${pad}")"
	echo
}

# _paragraph <text> [line_length]
# Output <text> with newlines converted to spaces, tabs removed, and text
# wrapped by breaking lines on whitespace. If [line_length] is not specified,
# it defaults to the value provided by _line_length.
_paragraph() {
	local line_length="${2:-"$(_line_length)"}"
	<<<"${1}" tr '\n' ' ' | tr -d '\t' | fold -s -w "${line_length}"
}

# _bullet <text> [bullet]
# Similar to _paragraph, but place "${bullet} " before the first line, and
# indent all additional lines with the appropriate number of spaces.
_bullet() {
	local bullet="${2:-"*"} "
	echo "$(_paragraph "${1}" "$(( $(_line_length) - ${#bullet} ))")" |
	{
		read -r line
		echo "${bullet}${line}"

		while read -r line; do
			echo "${bullet//?/ }${line}"
		done
	}
}

# Output text in different colors.

_error() {
	echo "${red}$(_paragraph "${1}")${reset}"
}

_success() {
	echo "${green}$(_paragraph "${1}")${reset}"
}

_warn() {
	echo "${yellow}$(_paragraph "${1}")${reset}"
}

_info() {
	echo "$(_paragraph "${1}")"
}

######## General User Input ########

# _pause [message]
# Make the user press any key to continue.
_pause() {
	local msg="${1:-"Press any key to continue..."}"
	read -s -n 1 -p "${green_enclosed}${msg}${reset_enclosed}"

	# Add a newline.
	echo
}

# _ask <prompt text> [default value]
# Output the line of input entered by the user.
_ask() {
	read -re -p "${1} " -i "${2}" input_text
	echo "${input_text}"
}

# _ask_str <prompt text> [default value]
# Simple wrapper for _ask with color.
_ask_str() {
	_ask "${yellow_enclosed}${1}${reset_enclosed}" "${2}"
}

# _ask_run <command>
# Allow the user to edit a command before running it.
_ask_run() {
	local ask_msg="${green_enclosed}Press Enter to run:${reset_enclosed}"
	eval "$(_ask "${ask_msg}" "${1}")"
}

# _parse_yes_no <input>
# Output 'yes', 'no', 'invalid', or the empty string, as appropriate.
_parse_yes_no() {
	# Convert to lowercase.
	case "$(tr '[:upper:]' '[:lower:]' <<< "${1}")" in
		y|yes)
			echo 'yes'
			;;
		n|no)
			echo 'no'
			;;
		'')
			echo ''
			;;
		*)
			echo 'invalid'
			;;
	esac
}

# _ask_yes_no <prompt text> [default choice]
# Return 0 for yes and 1 for no.
_ask_yes_no() {
	local default_choice="$(_parse_yes_no "${2}")"

	case "${default_choice}" in
		yes)
			local yn_text='Y/n'
			;;
		no)
			local yn_text='y/N'
			;;
		*)
			local yn_text='y/n'
			;;
	esac

	local prompt_text="${1} [${yn_text}]"

	while :; do
		case "$(_parse_yes_no "$(_ask_str "${prompt_text}")")" in
			yes)
				return 0
				;;
			no)
				return 1
				;;
			'')
				case "${default_choice}" in
					yes)
						return 0;
						;;
					no)
						return 1;
						;;
					*)
						echo -n 'No default selection. '
						;;
				esac
				;;
			*)
				echo -n 'Invalid input. '
		esac

		echo "Please enter y[es] or n[o]."
	done
}

######## Progress Tracking ########

progress_file="${persist_dir}/marked-complete"

# Ask the user to mark the calling function as having completed successfully.
_ask_mark_complete() {
	local function_name="${FUNCNAME[1]}"
	if [ -d "${persist_dir}" ]; then
		local ask_msg="Mark this step (${function_name}) as complete?"
		if _ask_yes_no "${ask_msg}" 'yes'; then
			echo "${function_name}" >> "${progress_file}"
		fi
	else
		_warn "Cannot mark this step (${function_name}) as complete,
				because persistence is disabled."
	fi
}

# _is_marked_complete <name>
# Return 0 if the function named <name> is marked as complete.
_is_marked_complete() {
	[ -f "${progress_file}" ] && grep -qx "${1}" "${progress_file}"
}

# Print a status message and return a status code for the calling function.
_marked_status() {
	if [ ! -d "${persist_dir}" ]; then
		echo 'Status unknown (persistence disabled).'
		return 3
	fi

	if _is_marked_complete "${FUNCNAME[1]}"; then
		echo 'This step was marked as complete.'
		return 0
	else
		echo 'This step has not been marked as complete yet.'
		return 1
	fi
}

######## Configuration ########

config_file="${persist_dir}/config"

# _config_get <key>
# Output the text following the last occurrence of <key> in the config file.
_config_get() {
	[ -f "${config_file}" ] || return 1
	echo "$(<"${config_file}" sed -En "s/${1}\s+(.*)/\1/p" | tail -n 1)"
}

# _config_set <key> <value>
# Set a key-value pair in the config file.
_config_set() {
	[ -d "${persist_dir}" ] || return 1
	echo "${1} ${2}" >> "${config_file}"
}

######## Specific User Input ########

# Output the name of the user's preferred text editor, asking the user if the
# user has not configured it yet.
_get_editor() {
	local editor="$(_config_get 'text_editor')"

	if [ ! -z "${editor}" ]; then
		echo "${editor}"
		return 0
	fi

	while [[ ! "${editor}" =~ ^(nano|vi|vim)$ ]]; do
		if [ ! -z "${editor}" ]; then
			>&2 _error 'Input does not match the available options.'
		fi
		
		>&2 echo
		>&2 _info "The text editors available in the Arch Linux live
				environment are 'nano', 'vi', and 'vim'. Please
				choose your preferred text editor."

		editor="$(_ask_str 'Text editor:' 'nano')"
	done

	_config_set 'text_editor' "${editor}"
	echo "${editor}"
}

# _ask_edit <file> [default yes/no]
# Let the user decide whether to edit a text file.
_ask_edit() {
	_ask_yes_no "Edit '${1}'?" "${2}" && "$(_get_editor)" "${1}"
}

# Output the name of the console keyboard layout selected by the user.
_ask_keyboard_layout() {
	local keymap='NONE'

	while ! grep -q "^${keymap}\$" <(localectl list-keymaps); do
		if [ -z "${keymap}" ]; then
			# Use stderr for all output, since only the selected
			# layout name should go to stdout.
			>&2 localectl list-keymaps
		elif [ "${keymap}" != 'NONE' ]; then
			>&2 _error "'${keymap}' is not a valid layout name."
		fi

		>&2 echo
		>&2 _info 'Enter the name of the desired keyboard layout.'
		>&2 _bullet 'To view a list of valid layout names, press Enter
				without typing anything.'
		keymap="$(_ask_str 'Keyboard layout name:')"
	done

	echo "${keymap}"
}

# _package_exists <package_name>
# Return 0 if this package exists in the repositories.
_package_exists() {
	[ -f "${package_names_file}" ] || return 0
	grep -q "^${1}\$" "${package_names_file}"
}

# _packages_exist [package_names...]
# Return 0 if all the provided package names exist in the repositories. If any
# packages can't be found, print the name of the first one which wasn't found.
_packages_exist() {
	local package
	for package in "${@}"; do
		if ! _package_exists "${package}"; then
			echo "${package}"
			return 1
		fi
	done

	return 0
}

# Output the package names entered by the user, separated by spaces.
_ask_packages() {
	local packages="$(_ask_str 'Enter package name(s):' "${*}")"
	
	local missing
	while ! missing="$(_packages_exist ${packages})"; do
		>&2 _error "The package '${missing}' does not exist."
		packages="$(_ask_str 'Enter package name(s):' "${packages}")"
	done

	echo "${packages}"
}

######## Installation Step Wrapper ########

# _get_status <step_name>
# Output an installation step's status message and return its status code.
_get_status() {
	local message
	local return_value

	message="$("${1}" -s)"
	return_value="${?}"

	echo "${message}"

	return "${return_value}"
}

# _status_color <status_code>
# Output an appropriate color for the given status code.
_status_color() {
	if [ "${1}" -eq 0 ] || [ "${1}" -eq 4 ]; then
		echo -n "${green}"
	elif [ "${1}" -eq 1 ]; then
		echo -n "${red}"
	else
		echo -n "${yellow}"
	fi
}

# _run_step <step_function>
# Run an installation step function.
_run_step() {
	local function_name="${1}"
	_function_banner "${function_name}"

	if [[ ${function_name} =~ ^_[0-9][0-9]0 ]]; then
		# This function will use _run_step to run its own substeps.
		"${function_name}"
	else
		local status_message
		local status

		status_message="$(_get_status "${function_name}")"
		status="${?}"

		if [ "${status_message}" ]; then
			_status_color "${status}"
			_bullet "${status_message}" 'Status:'
			echo -n "${reset}"
		fi
		
		if [ "${status}" -eq 0 ] && [ ! "${no_skip_completed}" ]; then
			return 0
		elif [ "${status}" -eq 2 ] || [ "${status}" -eq 4 ]; then
			return "${status}"
		fi

		[ "${status_message}" ] && echo
		"${function_name}"

		status_message="$(_get_status "${function_name}")"
		status="${?}"
		if [ "${status_message}" ]; then
			echo
			_status_color "${status}"
			_bullet "${status_message}" 'Status:'
			echo -n "${reset}"
		fi
	fi
}

######## Installation Stages ########

_stage_start() {
	_run_step _100_setup
	_run_step _200_preinstallation
	_run_step _300_installation
	_run_step _511_cleanup
	_run_step _611_reboot
}

_stage_chroot() {
	_run_step _400_configuration
	_run_step _511_cleanup

	echo
	_warn "You are now in a chroot shell. To exit the chroot shell and
			go back to carisa outside the chroot, use the 'exit'
			command or press Ctrl+D."
}

######## Installation Steps ########

_100_setup() {
	_run_step _111_readme
	_run_step _121_create_persist_dir
}

_111_readme() {
	local wiki_url='https://wiki.archlinux.org/index.php/installation_guide'

	# Always run this step.
	if [ "${1}" == '-s' ]; then
		return 1
	fi

	local title='Carisa: A Respectful Install Script for Arch'
	_center_text "${title}" "$(_line_length)" ' '
	echo
	_info 'Throughout the installation process, you may be prompted to
			switch to another TTY to perform an action manually.
			This can be done using the Alt+(arrow key) shortcut.'
	echo
	_info "You will be prompted before any commands that alter the system
			are run. These commands will be executed in the Bash
			shell, and you will see their output. You may also edit
			these commands, or delete them entirely if you don't
			want to run them. For example:"
	_ask_run "echo 'Hello World!'"
	_pause
	echo
	_info "It is highly recommended to have the Arch Linux installation
			guide at <${wiki_url}> open during the installation
			process, whether in another TTY using 'elinks' or on
			another device."
	echo
	_info 'You may press Ctrl+C to exit carisa at any time, and your
			progress will be remembered when you run carisa again.'
	_pause
}

_121_create_persist_dir() {
	if [ "${1}" == '-s' ]; then
		if [ -d "${persist_dir}" ]; then
			echo "The directory '${persist_dir}' exists."
			return 0
		else
			echo "The directory '${persist_dir}' does not exist."
			return 1
		fi
	fi

	_info "The optional persistence directory '${persist_dir}' is located in
			the same directory as 'carisa.sh'. It is used for the
			following purposes:"
	_bullet 'Storing user preferences (e.g. keyboard layout, text editor)'
	_bullet 'Remembering which steps have been marked as complete'
	echo	
	_ask_yes_no 'Create the optional persistence directory?' 'yes' || return 1
	_ask_run "mkdir '${persist_dir}'"
}

# Remind the user of how to switch TTYs.
_tty_reminder() {
	_bullet 'To leave carisa and perform this action manually, you may wish
			to switch to another TTY using Alt+(arrow key).'
}

_200_preinstallation() {
	_run_step _211_set_keyboard_layout
	_run_step _221_verify_boot_mode
	_run_step _231_test_internet_connection
	_run_step _241_update_system_clock
	_run_step _250_prepare_filesystems
}

_211_set_keyboard_layout() {
	if [ "${1}" == '-s' ]; then
		_marked_status
		return
	fi

	_info 'If you prefer a keyboard layout other than US QWERTY, you may
			change it now.'
	_bullet "If you have already changed the keyboard layout (e.g. using
			'loadkeys'), you may skip this step."
	echo
	if _ask_yes_no 'Change current keyboard layout?' 'no'; then
		local layout="$(_ask_keyboard_layout)"
		_config_set "keyboard_layout" "${layout}"
		_ask_run "loadkeys ${layout}"
	fi

	echo
	_ask_mark_complete
}

_221_verify_boot_mode() {
	local path='/sys/firmware/efi/efivars'

	if ls "${path}" > /dev/null; then
		echo "This system is booted in UEFI mode."
		# Output in green and never "actually run" this step.
		return 4
	else
		local msg="Could not access the directory '${path}'."
		msg+=' This system is probably not booted in UEFI mode.'
		echo "${msg}"
		return 2
	fi
}

_231_test_internet_connection() {
	if [ "${1}" == '-s' ]; then
		_marked_status
		return
	fi

	_info 'Please connect to the internet. (You may have already done this
			before downloading carisa.)'
	_tty_reminder

	echo
	_ask_yes_no "Test internet connection with 'ping'?" 'yes' || return 0
	_ask_run 'ping -c 4 archlinux.org'

	echo
	_ask_mark_complete
}

_241_update_system_clock() {
	if [ "${1}" == '-s' ]; then
		if timedatectl status | grep -q 'NTP service: active'; then
			echo 'The NTP service is active.'
			return 0
		else
			echo 'The NTP service has not been started yet.'
			return 1
		fi
	fi

	_ask_yes_no 'Sync the system clock using NTP?' 'yes' || return 1
	_ask_run 'timedatectl set-ntp true'
}

_250_prepare_filesystems() {
	_run_step _251_partition_disks
	_run_step _252_format_partitions
	_run_step _253_mount_filesystems
}

_251_partition_disks() {
	if [ "${1}" == '-s' ]; then
		_marked_status
		return
	fi

	_info "Please partition your disk(s) using 'fdisk' or similar. (This
			step is not automated, to give the user full control.)
			Consider including the following:"
	_bullet 'Root partition (required)'
	_bullet 'EFI system partition (for UEFI booting; might already exist)'
	_bullet 'Swap partition (or a swap file, if supported)'

	echo
	_tty_reminder

	echo
	_ask_mark_complete
}

_252_format_partitions() {
	if [ "${1}" == '-s' ]; then
		_marked_status
		return
	fi

	_info 'Please format the partitions you created in the previous step.'

	echo
	_info 'EFI partition example:'
	_bullet 'mkfs.fat -F32 /dev/sdX1' '#'

	echo
	_info 'Root partition example:'
	_bullet 'mkfs.ext4 /dev/sdX2' '#'

	echo
	_info 'Swap partition example:'
	_bullet 'mkswap /dev/sdX3' '#'
	_bullet 'swapon /dev/sdX3' '#'

	echo
	_tty_reminder

	echo
	_ask_mark_complete
}

_253_mount_filesystems() {
	if [ "${1}" == '-s' ]; then
		_marked_status
		return
	fi

	_info 'Please mount the partitions you formatted in the previous step.'

	echo
	_info 'Root partition example:'
	_bullet 'mount /dev/sdX2 /mnt' '#'

	echo
	_info 'EFI partition example:'
	_bullet 'mkdir /mnt/efi' '#'
	_bullet 'mount /dev/sdX1 /mnt/efi' '#'

	echo
	_tty_reminder

	echo
	_ask_mark_complete
}

_300_installation() {
	_run_step _310_packages
	_run_step _321_generate_fstab
	_run_step _331_chroot
}

_310_packages() {
	_run_step _311_select_mirrors
	_run_step _312_generate_package_names_file
	_run_step _313_pacstrap
}

mirrorlist_path='/etc/pacman.d/mirrorlist'
mirrorlist_url='https://www.archlinux.org/mirrorlist/'

_311_select_mirrors() {
	if [ "${1}" == '-s' ]; then
		_marked_status
		return
	fi

	_info "Please configure the pacman mirrorlist in '${mirrorlist_path}'."
	_bullet 'This mirrorlist will be used during installation, and will also
			be copied to the installed system.'
	_bullet 'Mirrors placed higher in the mirrorlist will be tried first for
			downloading packages, so it is recommended to have
			geographically closer mirrors at the top of the
			mirrorlist.'
	_bullet "You may edit the existing mirrorlist, or generate a customized
			mirrorlist tailored by geography, protocol, etc. using
			the mirrorlist generator at '${mirrorlist_url}'."

	echo
	if _ask_yes_no "Generate customized mirrorlist?" 'yes'; then
		echo
		_311a_generate_mirrorlist
	fi

	echo
	_ask_edit "${mirrorlist_path}" 'yes'
	
	echo
	_ask_mark_complete
}

_311a_generate_mirrorlist() {
	# Get the HTML content of the mirrorlist generator form, parse the
	# country selection options to get the available country codes and
	# country names, and store each pair as a tab-separated line.
	_info "Fetching list of countries from '${mirrorlist_url}'..."
	local countries="$(curl -s "${mirrorlist_url}" |
			grep '<option' |
			sed -En 's/.*value="([^"]+)"[^>]*>([^<]*)<.*/\1\t\2/p')"
	
	if [ -z "${countries}" ]; then
		_error 'Unable to fetch list of countries.'
		return 1
	else
		_success 'Fetched list of countries.'
	fi

	echo
	local country='NONE'
	while ! grep -Pq "^${country}\t|\t${country}\$" <<< "${countries}"; do
		if [ -z "${country}" ]; then
			less <<< "${countries}"
		elif [ "${country}" != 'NONE' ]; then
			_error "'${country}' does not correspond to a valid
					country name or country code."
		fi

		_info "Enter the country name (e.g. 'United States') or the
				two-letter country code (e.g. 'US') matching
				your geographic location."
		_bullet "To use mirrors in all countries, enter 'all'."
		_bullet 'To view the list of available country names and country
				codes, press Enter without typing anything.'
		country="$(_ask_str "Enter country name or two-letter code:")"
	done

	country="$(grep -P "^${country}\t|\t${country}\$" <<< "${countries}")"
	local country_code="$(grep -Po '^[^\t]+' <<< "${country}")"
	local country_name="$(grep -Po '[^\t]+$' <<< "${country}")"
	_success "Selected country '${country_name}' ('${country_code}')."

	local request_url="${mirrorlist_url}?country=${country_code}&"
	
	echo
	_info "Mirrors using the 'http' and 'https' protocols are available."
	_ask_yes_no "Include mirrors using the 'http' protocol?" 'yes' &&
			request_url="${request_url}protocol=http&"
	_ask_yes_no "Include mirrors using the 'https' protocol?" 'yes' &&
			request_url="${request_url}protocol=https&"

	echo
	_info 'Mirrors using IPv4 and IPv6 are available.'
	_ask_yes_no "Include mirrors using IPv4?" 'yes' &&
			request_url="${request_url}ip_version=4&"
	_ask_yes_no "Include mirrors using IPv6?" 'yes' &&
			request_url="${request_url}ip_version=6&"

	echo
	_info "Mirror status info can be used to exclude outdated mirrors."
	_ask_yes_no "Exclude outdated mirrors?" 'yes' &&
			request_url="${request_url}use_mirror_status=on&"

	# Remove the trailing & from the request URL, if any.
	request_url="$(sed 's/&$//' <<< "${request_url}")"

	echo
	_info "Downloading the generated mirrorlist will overwrite the existing
			mirrorlist at '${mirrorlist_path}'."
	_ask_yes_no 'Download generated mirrorlist?' 'yes' || return 1
	_ask_run "curl '${request_url}' > ${mirrorlist_path}"

	echo
	_ask_yes_no 'Uncomment all mirrors in mirrorlist?' 'yes' || return 0
	_ask_run "sed -i 's/^#Server/Server/' ${mirrorlist_path}"
}

package_names_file="${persist_dir}/package-names"
_312_generate_package_names_file() {
	if [ "${1}" == '-s' ]; then
		if [ -f "${package_names_file}" ]; then
			echo "The file '${package_names_file}' exists."
			return 0
		elif [ -d "${persist_dir}" ]; then
			echo "The file '${package_names_file}' does not exist."
			return 1
		else
			echo "Persistence disabled."
			return 2
		fi
	fi

	_info "To validate the names of packages you select for installation,
			carisa can store a list of all available package names
			in the file '${package_names_file}'."
	_ask_yes_no 'Generate list of package names?' 'yes' || return 1

	if ! pacman -Ssq > "${package_names_file}"; then
		# Make sure that an empty package names file isn't created,
		# which would make it impossible to select any packages for
		# installation.
		rm "${package_names_file}"
		
		echo
		_info 'To generate the list of package names, the package
				databases must be refreshed first.'
		_ask_yes_no 'Refresh package databases?' 'yes' || return 1
		_ask_run 'pacman -Sy'

		if ! pacman -Ssq > "${package_names_file}"; then
			rm "${package_names_file}"
			return 1
		fi
	fi
}

# Output 'intel' for Intel CPUs, 'amd' for AMD, and nothing if unsure.
_guess_cpu_vendor() {
	local vendor_id="$(grep '^vendor_id' '/proc/cpuinfo')"

	if [[ $vendor_id =~ AuthenticAMD ]]; then
		>&2 _info 'Detected AMD CPU.'
		echo 'amd'
		return 0
	elif [[ $vendor_id =~ GenuineIntel ]]; then
		>&2 _info 'Detected Intel CPU.'
		echo 'intel'
		return 0
	else
		>&2 _warn 'Failed to guess CPU manufacturer.'
		return 1
	fi
}

_313_pacstrap() {
	if [ "${1}" == '-s' ]; then
		if [ -d '/mnt/var/cache/pacman' ]; then
			echo 'The base system has been installed.'
			return 0
		else
			echo 'The base system has not been installed.'
			return 1
		fi
	fi

	_ask_yes_no 'Install the base system with pacstrap?' 'yes' || return 1

	local packages='base'

	echo
	_info 'Choose a kernel package. (May be optional for containers.)'
	packages="${packages} $(_ask_packages 'linux')"

	echo
	_info "Add any desired firmware packages. (May be optional for virtual
			machines and containers.) Note that 'linux-firmware'
			does not support all devices, so additional firmware
			packages may be necessary."
	packages="${packages} $(_ask_packages 'linux-firmware')"

	echo
	local cpu_vendor="$(_guess_cpu_vendor)"
	if [ ! -z "${cpu_vendor}" ]; then
		local ucode_package="${cpu_vendor}-ucode"
	fi
	_info 'Add the microcode package corresponding to the installed CPU.
			(Not required for virtual machines and containers.)
			Suggestions:'
	_bullet 'amd-ucode'
	_bullet 'intel-ucode'
	packages="${packages} $(_ask_packages "${ucode_package}")"

	echo
	_info 'Add support for additional filesystems? Suggestions:'
	_bullet 'btrfs-progs'
	_bullet 'dosfstools (for FAT filesystems)'
	_bullet 'exfat-utils'
	_bullet 'f2fs-tools'
	_bullet 'jfsutils'
	_bullet 'nilfs-utils'
	_bullet 'ntfs-3g'
	_bullet 'reiserfsprogs'
	_bullet 'udftools'
	_bullet 'xfsprogs'
	packages="${packages} $(_ask_packages)"

	echo
	_info 'Add a boot manager? Suggestions:'
	_bullet 'grub'
	_bullet 'os-prober (detect other operating systems for GRUB)'
	_bullet 'refind'
	packages="${packages} $(_ask_packages)"

	echo
	_info 'Add a text editor? Suggestions:'
	_bullet 'emacs'
	_bullet 'nano'
	_bullet 'vim'
	packages="${packages} $(_ask_packages "$(_config_get 'text_editor')")"

	echo
	_info 'Add networking software? Suggestions:'
	_bullet 'netctl (systemd network manager)'
	_bullet 'dhcpcd (DHCP client daemon)'
	_bullet 'wpa_supplicant (WPA wireless security)'
	_bullet 'ifplugd (automatic wired connection management)'
	_bullet "dialog (needed for netctl's 'wifi-menu')"
	packages="${packages} $(_ask_packages)"

	echo
	_info 'Add security and permissions tools? Suggestions:'
	_bullet 'sudo'
	_bullet 'polkit'
	packages="${packages} $(_ask_packages)"

	echo
	_info 'Add documentation and related tools? Suggestions:'
	_bullet 'man-db (read man pages)'
	_bullet 'man-pages (Linux man pages)'
	_bullet 'texinfo (read info pages)'
	packages="${packages} $(_ask_packages)"

	echo
	_info 'Add any other packages?'
	packages="${packages} $(_ask_packages "$(_config_get 'extra_pkgs')")"

	echo
	_ask_run "pacstrap /mnt $(
			sed -E 's/^\s+|\s+$// ; s/\s+/ /g' <<< "${packages}")"
}

_321_generate_fstab() {
	local path='/mnt/etc/fstab'

	if [ "${1}" == '-s' ]; then
		if _has_content "${path}"; then
			echo "The file '${path}' has been generated."
			return 0
		else
			echo "The file '${path}' has not been generated."
			return 1
		fi
	fi

	_info "The file '/etc/fstab' defines mountpoints and mounting options
			for each filesystem. Please ensure that all additional
			filesystems (e.g. home partition, EFI system partition)
			are mounted appropriately under '/mnt' before
			proceeding."
	_tty_reminder
	_ask_yes_no 'Generate fstab?' 'yes' || return 1

	echo
	_info "To define mountpoints using filesystem labels instead of UUIDs,
			use the option '-L' instead of '-U'."
	_ask_run "genfstab -U /mnt >> ${path}"

	echo
	_ask_edit "${path}" 'yes'
}

# Display the command used to (re)run carisa in the chroot.
_show_carisa_in_chroot_command() {
	_bullet 'bash /carisa.sh chroot' '#'
}

# Remind the user of how to exit carisa once in the chroot.
_ctrl_c_reminder() {
	_bullet 'To exit carisa and perform this action manually, you may use
			Ctrl+C to access the chroot shell. Once you are
			finished, the following command will start carisa
			again:'
	_show_carisa_in_chroot_command
}

_331_chroot() {
	if [ "${1}" == '-s' ]; then
		_marked_status
		return
	fi

	_ask_yes_no "Change root into the new system?" 'yes' || return 1

	_info 'To continue using carisa in the new system, the carisa script
			and its persistence folder (if any) must be copied into
			the chroot.'
	_ask_run "cp -v '${0}' /mnt"
	[ -d "${persist_dir}" ] && _ask_run "cp -rv '${persist_dir}' /mnt"

	echo
	_info 'Please chroot into the new system. You may start carisa in the
			chroot by entering the following command into the chroot
			shell:'
	_show_carisa_in_chroot_command
	_info 'Once carisa is running in the chroot, you may regain access to
			the chroot shell using Ctrl+C. To continue with carisa,
			simply enter the above command again.'
	_ask_run 'arch-chroot /mnt'

	echo
	_info 'Exited chroot.'
	# This doesn't actually seem to be caused by printing to stdout; it
	# seems like this only occurs when attempting to read from stdin.
	_warn "If you see a message showing 'suspended (tty output)' and are
			presented with a zsh prompt, please enter 'fg' to
			continue."
	echo
	_ask_mark_complete
}

_400_configuration() {
	_run_step _410_system_time
	_run_step _420_localization
	_run_step _430_network_configuration
	_run_step _441_recreate_initramfs
	_run_step _451_set_root_password
	_run_step _460_boot_manager
}

_410_system_time() {
	_run_step _411_set_time_zone
	_run_step _412_generate_etc_adjtime
}

_411_set_time_zone() {
	local path='/etc/localtime'

	if [ "${1}" == '-s' ]; then
		if [ -e "${path}" ]; then
			echo "Time zone set ('${path}' exists)."
			return 0
		else
			echo "Time zone not set ('${path}' does not exist)."
			return 1
		fi
	fi

	_ask_yes_no 'Set time zone?' 'yes' || return 1
	echo

	local tz_file="NONE"
	while [ ! -f "${tz_file}" ]; do
		if [ -d "${tz_file}" ]; then
			_error "'${tz_file}' is a directory, not a file. Did you
					mean to select a file within that
					directory?"
		elif [ "${tz_file}" != "NONE" ]; then
			_error "The file '${tz_file}' does not exist."
		fi

		_info "Select the time zone information file corresponding to
				this system's geographic location."
		_bullet 'To list available options, press Tab twice.'
		tz_file="$(_ask_str 'Time zone file:' '/usr/share/zoneinfo/')"
	done

	echo
	_ask_run "ln -sf '${tz_file}' '${path}'"
}

_412_generate_etc_adjtime() {
	local path='/etc/adjtime'

	if [ "${1}" == '-s' ]; then
		if [ -f "${path}" ]; then
			echo "The file '${path}' exists."
			return 0
		else
			echo "The file '${path}' does not exist."
			return 1
		fi
	fi

	_info "The file '${path}' stores configuration and calibration data for
			the hardware clock. This file can be generated by
			setting the hardware clock from the system time."
	_bullet "For more information, see 'man hwclock'."
	_ask_yes_no "Generate '${path}'?" 'yes' || return 1
	
	echo
	_info "If you would like the hardware clock to use local time instead of
			UTC, add the option '--localtime'."
	_ask_run 'hwclock --systohc'
}

_420_localization() {
	_run_step _421_select_locales
	_run_step _422_generate_locales
	_run_step _423_create_locale_conf
	_run_step _424_set_default_keyboard_layout
}

_421_select_locales() {
	local path='/etc/locale.gen'

	if [ "${1}" == '-s' ]; then
		if _has_content "${path}"; then
			echo "Locales have been selected in '${path}'."
			return 0
		else
			echo "Locales have not been selected in '${path}'."
			return 1
		fi
	fi

	_ask_yes_no 'Select system locale(s)?' 'yes' || return 1

	echo
	_info "Please uncomment the desired locale entries (e.g. 'en_US.UTF-8')
			in '${path}'."
	_ask_edit "${path}" 'yes'
}

_422_generate_locales() {
	if [ "${1}" == '-s' ]; then
		_marked_status
		return
	fi

	_ask_yes_no 'Generate system locale(s)?' 'yes' || return 1
	
	echo
	_ask_run 'locale-gen'

	echo
	_ask_mark_complete
}

# Attempt to guess the user's locale (e.g. 'en_US.UTF-8') from locale.gen.
_guess_locale() {
	local path='/etc/locale.conf'

	local guess
	if guess="$(grep -Eo -m 1 '^[^#][^ ]+' '/etc/locale.gen')"; then
		>&2 _info "Guessed locale from '${path}': '${guess}'."
		echo "${guess}"
		return 0
	else
		>&2 _warn "Failed to guess locale from '${path}'."
		return 1
	fi
}

_423_create_locale_conf() {
	local path='/etc/locale.conf'

	if [ "${1}" == '-s' ]; then
		if [ -f "${path}" ]; then
			echo "The file '${path}' exists."
			return 0
		else
			echo "The file '${path}' does not exist."
			return 1
		fi
	fi

	_ask_yes_no 'Set default system locale?' 'yes' || return 1

	echo
	_ask_run "echo 'LANG=$(_guess_locale)' > ${path}"
}

_424_set_default_keyboard_layout() {
	local path='/etc/vconsole.conf'

	if [ "${1}" == '-s' ]; then
		if [ -f "${path}" ] && grep -q '^KEYMAP=' "${path}"; then
			echo "Console keyboard layout is set in '${path}'."
			return 0
		else
			_marked_status
			return
		fi
	fi

	# Try using the previously selected keyboard layout, if any.
	local layout="$(_config_get 'keyboard_layout')"
	if [ ! -z "${layout}" ]; then
		_info "You previously selected the '${layout}' keyboard layout
				for use during the installation process. Would
				you like to make this the default keyboard
				layout for the installed system?"
		if _ask_yes_no "Make '${layout}' the default?" "yes"; then
			echo
			_ask_run "echo 'KEYMAP=${layout}' >> '${path}'"
			return 0
		fi
		echo
	fi

	_info "Choose the default virtual console keyboard layout for the
			installed system."
	_bullet 'If you selected an alternate keyboard layout earlier in the
			installation process, you may wish to select the same
			layout in this step. Otherwise, the installed system
			will use US QWERTY.'

	echo
	if _ask_yes_no 'Change default layout?' 'no'; then
		_ask_run "echo 'KEYMAP=$(_ask_keyboard_layout)' >> '${path}'"
	else
		echo
		_ask_mark_complete
	fi
}

_430_network_configuration() {
	_run_step _431_set_hostname
	_run_step _432_generate_etc_hosts
}

_431_set_hostname() {
	local path='/etc/hostname'

	if [ "${1}" == '-s' ]; then
		if [ -f "${path}" ]; then
			echo "Hostname file '${path}' exists."
			return 0
		else
			echo "Hostname file '${path}' does not exist."
			return 1
		fi
	fi

	_ask_yes_no "Set system hostname?" "yes" || return 1
	_ask_run "echo '$(_ask_str 'Enter hostname:')' > '${path}'"
}

_432_generate_etc_hosts() {
	local path='/etc/hosts'

	if [ "${1}" == '-s' ]; then
		if _has_content "${path}"; then
			echo "Host table '${path}' has been generated."
			return 0
		else
			echo "Host table '${path}' has not been generated."
			return 1
		fi
	fi

	_ask_yes_no "Generate static host table '${path}'?" "yes" || return 1

	local hostname_path='/etc/hostname'
	if [ -f "${hostname_path}" ]; then
		local hn="$(<"${hostname_path}")"
	else
		_error "Hostname not set in '${hostname_path}'! Please change
				the dummy hostname in the following commands."
		local hn='MYHOSTNAME'
	fi

	echo
	_info "Enter this system's permanent IP address, or leave the provided
			value unchanged if this system will not have a permanent
			IP address."
	local ip="$(_ask_str "IP address:" "127.0.1.1")"

	echo
	_ask_run "echo -e '127.0.0.1\tlocalhost' >> ${path}"
	_ask_run "echo -e '::1\t\tlocalhost' >> ${path}"
	_ask_run "echo -e '${ip}\t${hn}.localdomain\t${hn}' >> ${path}"

	echo
	_ask_edit "${path}" 'yes'
}

_441_recreate_initramfs() {
	local path='/etc/mkinitcpio.conf'
	if [ "${1}" == '-s' ]; then
		_marked_status
		return
	fi

	_info "If you need to customize the initramfs (e.g. to support LVM, disk
			encryption, or RAID), you may make these changes by
			editing '${path}' and regenerating the initramfs."
	if _ask_yes_no "Edit '${path}' and regenerate initramfs?" 'no'; then
		echo
		_ask_edit "${path}" 'yes'

		echo
		_ask_run 'mkinitcpio -P'
	fi

	echo
	_ask_mark_complete
}

_451_set_root_password() {
	local passwd_status=($(passwd -S))
	local username="${passwd_status[0]}"
	local state="${passwd_status[1]}"

	if [ "${username}" != 'root' ]; then
		local not_root_msg='Not running as root.'
	fi

	if [ "${1}" == '-s' ]; then
		if [ "${not_root_msg}" ]; then
			echo "${not_root_msg}"
			return 2
		elif [ "${state}" == 'P' ]; then
			echo 'Root password is set.'
			return 0
		elif [ "${state}" == 'NP' ]; then
			echo 'No root password set'.
			return 1
		elif [ "${state}" == 'L' ]; then
			echo 'Root password is locked.'
			return 1
		else
			echo "Unknown root password status '${state}'."
			return 1
		fi
	fi

	if [ "${not_root_msg}" ]; then
		_error "${not_root_msg}"
		return 2
	fi

	_ask_yes_no 'Set root password?' 'yes' || return 1
	_ask_run 'passwd'
}

_460_boot_manager() {
	if _package_installed 'grub'; then
		_run_step _461_install_grub
		_run_step _462_run_os_prober
		_run_step _463_grub_mkconfig
	else
		_warn 'The GRUB package is not installed. If you will use
				another boot manager (e.g. rEFInd) you may now
				install it manually.'
		_ctrl_c_reminder
		_pause
	fi
}

# _package_installed <package>
# Return 0 if the named package is installed.
_package_installed() {
	pacman -Q "${1}" &> /dev/null
}

_461_install_grub() {
	if _package_installed 'grub'; then
		local package_installed='true'
	fi

	local not_installed_msg='The GRUB package is not installed.'

	if [ "${1}" == '-s' ]; then
		if [ -d '/boot/grub' ]; then
			echo 'GRUB is installed.'
			return 0
		elif [ "${package_installed}" ]; then
			echo 'GRUB has not been installed.'
			return 1
		else
			echo "${not_installed_msg}"
			return 2
		fi
	fi

	if [ ! "${package_installed}" ]; then
		_warn "${not_installed_msg}"
		return 2
	fi

	_ask_yes_no 'Install the GRUB boot manager?' 'yes' || return 1

	echo
	_info "See 'man grub-install' for more information."

	echo
	_info 'Example for BIOS+MBR systems:'
	_bullet 'grub-install --target=i386-pc /dev/sdX' '#'

	echo
	_info 'Example for UEFI+GPT systems:'
	_bullet 'grub-install --target=x86_64-efi --efi-directory=/efi
			--bootloader-id=GRUB' '#'

	echo
	_info "If you are using UEFI and installing to a removable drive,
			consider adding the '--removable' option to make the
			drive itself bootable."

	echo
	_ask_run 'grub-install'
}

_462_run_os_prober() {
	if _package_installed 'os-prober'; then
		local package_installed='true'
	fi

	local not_installed_msg="The 'os-prober' package is not installed."

	if [ "${1}" == '-s' ]; then
		if [ "${package_installed}" ]; then
			_marked_status
			return
		else
			echo "${not_installed_msg}"
			return 2
		fi
	fi

	if [ ! "${package_installed}" ]; then
		_warn "${not_installed_msg}"
		return 2
	fi

	_info "The 'os-prober' utility detects other installed operating systems
			and adds GRUB boot entries for them."
	_ask_yes_no "Detect other operating systems?" 'yes' || return 1

	echo
	_info 'Please ensure that all partitions containing other operating
			systems are mounted before proceeding.'
	_ctrl_c_reminder

	echo
	_ask_run 'os-prober'

	echo
	_ask_mark_complete
}

_463_grub_mkconfig() {
	local path='/boot/grub/grub.cfg'

	if _package_installed 'grub'; then
		local package_installed='true'
	fi

	local not_installed_msg='The GRUB package is not installed.'

	if [ "${1}" == '-s' ]; then
		if [ -f "${path}" ]; then
			echo "The GRUB config file '${path}' exists."
			return 0
		elif [ "${package_installed}" ]; then
			echo "The GRUB config file '${path}' does not exist."
			return 1
		else
			echo "${not_installed_msg}"
			return 2
		fi
	fi

	if [ ! "${package_installed}" ]; then
		_warn "${not_installed_msg}"
		return 2
	fi

	_info "For GRUB to boot the system, the GRUB main configuration file at
			'${path}' must be generated."
	_ask_yes_no "Generate '${path}'?" 'yes' || return 1

	echo
	_info 'Would you like to edit the GRUB settings file first?'
	_ask_edit '/etc/default/grub' 'yes'

	echo
	_ask_run "grub-mkconfig -o ${path}"
}

_511_cleanup() {
	if [ "${1}" == '-s' ]; then
		if [ -f "${0}" ] || [ -d "${persist_dir}" ]; then
			echo 'Cleanup not complete.'
			return 1
		else
			echo 'Cleanup complete.'
			return 0
		fi
	fi

	_ask_yes_no 'Delete carisa and associated files?' 'yes' || return 1

	[ -f "${0}" ] && _ask_run "rm -v '${0}'"
	[ -d "${persist_dir}" ] && _ask_run "rm -rv '${persist_dir}'"
}

_611_reboot() {
	if [ "${1}" == '-s' ]; then
		echo 'A reboot is required to boot the newly installed system.'
		return 1
	fi

	_ask_yes_no 'Reboot into the installed system?' 'yes' || return 1
	_info 'Please remember to remove the installation medium, if necessary.'
	_ask_run 'reboot'
}

######## Usage and Version Messages ########

_usage() {
	cat << EOF
Usage:	${0} <installation_stage> [options...]

Installation Stages:
	start
		Begin the installation process.
	chroot
		Continue the installation process from within the chroot.

Options:
	--no-skip-completed
		Do not automatically skip previously completed steps. Can be
		useful if a step needs to be redone.
	-h, --help
		Display this message.
	--version
		Display version and copyright information.
EOF
}

_version() {
	cat << EOF
Carisa: A Respectful Install Script for Arch
Version 0.1.0

Copyright (C) 2020 Justin Yao Du.
Licensed under the MIT License.

See also: https://github.com/justinyaodu/carisa
EOF
}

######## Do Not Exit if Being Sourced ########

return 2>/dev/null

######## Argument and Option Parsing ########

# Parse the installation stage.
case "${1}" in
	start|chroot)
		install_stage="${1}"
		;;
	-h|--help)
		_usage
		exit 0
		;;
	--version)
		_version
		exit 0
		;;
	''|--*)
		_error 'Installation stage not provided.'
		_usage
		exit 2
		;;
	*)
		_error "Unrecognised installation stage '${1}'."
		_usage
		exit 2
		;;
esac
shift

# Parse all provided options.
while [ "${1}" ]; do
	case "${1}" in
		-h|--help)
			_usage
			exit 0
			;;
		--version)
			_version
			exit 0
			;;
		--no-skip-completed)
			no_skip_completed='true'
			;;
		-*)
			_error "Unrecognized option '${1}'."
			_usage
			exit 2
			;;
		*)
			_error "Unexpected argument '${1}'."
			_usage
			exit 2
			;;
	esac
	shift
done

# Run the selected installation stage.
"_stage_${install_stage}"
