#!/bin/bash

zephyr_build_script_path="$(dirname $(readlink -f "$0"))"
zephyr_west_manifest_path="ecfwwork"

function get_center_window_position_row_col() {
    local ret=0

    if [ -n "$(command -v tput)" ]; then
        local rows=$(tput lines)
        local cols=$(tput cols)
    elif [ -n "$(command -v stty)" ]; then
        local rows=$(stty size | cut -d' ' -f1)
        local cols=$(stty size | cut -d' ' -f2)
    else
        local rows=24
        local cols=80
    fi

    local center_row=$((rows / 2))
    local center_col=$((cols / 2))

    if [ "$#" -eq 0 ]; then
        echo "${center_row} ${center_col}"
    else
        local args=()

        while [ "$#" -gt 0 ]; do
            case "$1" in
                "height"|"row")
                    args+=("${center_row}")
                    ;;
                "width"|"col")
                    args+=("${center_col}")
                    ;;
                *)
                    args+=("0")
                    ret=1
                    ;;
            esac
            shift
        done

        echo "${args[@]}"
    fi

    return ${ret}
}

function parameters_selection() {
    parameters=("soc_vendor" "soc_series" "ec_vendor" "ec_series")
    declare -A info

    # SoC series: depending on supported_soc_vendor
    # - format "supported_soc_<soc_vendor>=(<series1> <series2> ...)"
    supported_soc_vendor=("Intel" "AMD")
    supported_soc_intel=("Alder Lake" "Alder Lake P" "Meteor Lake" "Meteor Lake P")
    supported_soc_amd=("Hawk Point")
    # EC series: depending on supported_ec_series
    # - format "supported_ec_<ec_vendor>=(<series1> <series2> ...)"
    supported_ec_vendor=("microchip" "ite")
    supported_ec_microchip=("1501" "152x" "172x")
    supported_ec_ite=("82202")
    # default values
    info["soc_vendor"]=${supported_soc_vendor[0]}
    info["soc_series"]=${supported_soc_intel[0]}
    info["ec_vendor"]=${supported_ec_vendor[0]}
    info["ec_series"]=${supported_ec_microchip[0]}
    info["colorscheme"]="default"

    function dev_selection() {
        local dev="$1"; shift
        local title=
        local sel=

        for d in "${parameters[@]}"; do
            if [[ "${d}" == "${dev}" ]]; then
                title="${d}"
                break
            fi
        done

        if [ -z "${title}" ]; then
            echo "Error: device not found for ${dev}"
            exit 1
        fi

        while [ "$#" -gt 0 ]; do
            local selected="OFF"

            if [[ "${info["${dev}"]}" == "$1" ]]; then
                selected="ON"
            fi

            local lists+=("$1" "" "${selected}")
            shift
        done

        sel=$(whiptail --title "${title}" --radiolist "Please select one of options" \
            $(get_center_window_position_row_col) \
            $(($(get_center_window_position_row_col "height") / 3)) \
            "${lists[@]}" --nocancel --ok-button 'done' --clear \
            3>&1 1>&2 2>&3)

        if [ "$?" -ne 0 ]; then
            echo ""
        fi

        echo "${sel}"
    }

    function whiptail_colorscheme_select() {
        local newt_colors=('skyblue' 'darkblue' 'gruvbox' 'habamax')
        local skyblue='
            root=white,blue
            border=white,blue
            title=white,blue
            roottext=gray,blue
            window=white,blue
            textbox=gray,blue
            button=blue,white
            compactbutton=gray,blue
            listbox=gray,blue
            actlistbox=blue,gray
            actsellistbox=blue,white
            checkbox=white,blue
            actcheckbox=blue,white'
        local darkblue='
            root=,blue
            checkbox=,blue
            entry=,blue
            label=blue,
            actlistbox=,blue
            helpline=,blue
            roottext=,blue
            emptyscale=blue
            disabledentry=blue,'
        local gruvbox='
            root=green,black
            border=green,black
            title=green,black
            roottext=white,black
            window=green,black
            textbox=white,black
            button=black,green
            compactbutton=white,black
            listbox=white,black
            actlistbox=black,white
            actsellistbox=black,green
            checkbox=green,black
            actcheckbox=black,green'
        local habamax='
            root=white,black
            border=black,lightgray
            window=lightgray,lightgray
            shadow=black,gray
            title=black,lightgray
            button=black,cyan
            actbutton=white,cyan
            compactbutton=black,lightgray
            checkbox=black,lightgray
            actcheckbox=lightgray,cyan
            entry=black,lightgray
            disentry=gray,lightgray
            label=black,lightgray
            listbox=black,lightgray
            actlistbox=black,cyan
            sellistbox=lightgray,black
            actsellistbox=lightgray,black
            textbox=black,lightgray
            acttextbox=black,cyan
            emptyscale=,gray
            fullscale=,cyan
            helpline=white,black
            roottext=lightgrey,black'
        local sel=
        local tmp_colorscheme_file="/tmp/ami_ecfw_color_palette"

        if [ "$#" -ge 2 ]; then
            echo "Warn: only one color scheme can be selected at a time"
            return 1
        elif [ "$#" -eq 1 ]; then
            for c in "${newt_colors[@]}"; do
                if [[ "${c}" == "$1" ]]; then
                    sel="${c}"
                    break
                fi
            done

            if [ -n "${sel}" ]; then
                export NEWT_COLORS=$(eval "echo \${${sel}}")
            elif [ -z "${NEWT_COLORS}" ]; then
                if [ -f "${tmp_colorscheme_file}" ]; then
                    export NEWT_COLORS=$(cat "${tmp_colorscheme_file}")
                else
                    echo "Warn: invalid color scheme $1"
                    return 1
                fi
            fi
        else
            for c in "${newt_colors[@]}"; do
                local selected="OFF"

                if [[ "$(eval "echo \${${c}}")" == "${NEWT_COLORS}" ]]; then
                    selected="ON"
                fi

                local lists+=("${c}" "" "${selected}")
            done

            sel=$(whiptail --title "Whiptail Color Scheme" --radiolist "Please select one of color scheme" \
                $(get_center_window_position_row_col) \
                $(($(get_center_window_position_row_col "height") / 3)) \
                "${lists[@]}" --nocancel --ok-button 'done' --clear\
                3>&1 1>&2 2>&3)

            if [ "$?" -eq 0 ] && [ -n "${sel}" ]; then
                export NEWT_COLORS=$(eval "echo \${${sel}}")
                echo "${NEWT_COLORS}" > "${tmp_colorscheme_file}"
            fi
        fi

        if [ -n "${sel}" ]; then
            info["colorscheme"]="${sel}"
        fi

        return 0
    }

    function ecfw_board_selection() {
        local menu=
        local sel=

        while [ -z ${menu} ]; do
            menu=$(whiptail \
                --title "AMI EC" \
                --menu "Please enter one of options to select" \
                $(get_center_window_position_row_col) \
                $(($(get_center_window_position_row_col "height") / 3)) \
                "SoC Vendor"   "    ${info["soc_vendor"]}" \
                "SoC Series"   "    ${info["soc_series"]}" \
                "Ec Vendor"    "    ${info["ec_vendor"]}" \
                "Ec Series"    "    ${info["ec_series"]}" \
                "colorscheme"  "    ${info["colorscheme"]}" \
                --ok-button 'select' --cancel-button 'done' --clear \
                3>&1 1>&2 2>&3)

            if [ -z "${menu}" ]; then
                break
            fi

            case ${menu} in
                "SoC Vendor")
                    menu="soc_vendor"
                    sel=$(dev_selection "soc_vendor" "${supported_soc_vendor[@]}")

                    if [ -n "${sel}" ] && [[ ! "${sel}" =~ [Ee]rror ]] && \
                        [ "${sel,,}" != "${info["soc_vendor"],,}" ];
                    then
                        selected_soc="supported_soc_${sel,,}"
                        eval "soc_series=(\"\${${selected_soc}[@]}\")"
                        info["soc_series"]="${soc_series[0]}"
                    fi
                    ;;
                "SoC Series")
                    menu="soc_series"
                    selected_soc="supported_soc_${info["soc_vendor"],,}"
                    eval "soc_series=(\"\${${selected_soc}[@]}\")"
                    sel=$(dev_selection "soc_series" "${soc_series[@]}")
                    ;;
                "Ec Vendor")
                    sel=$(dev_selection "ec_vendor" "${supported_ec_vendor[@]}")
                    menu="ec_vendor"

                    if [ -n "${sel}" ] && [[ ! "${sel}" =~ [Ee]rror ]] && \
                        [ "${sel,,}" != "${info["ec_vendor"],,}" ];
                    then
                        selected_ec="supported_ec_${sel,,}"
                        eval "ec_series=(\"\${${selected_ec}[@]}\")"
                        info["ec_series"]="${ec_series[0]}"
                    fi
                    ;;
                "Ec Series")
                    menu="ec_series"
                    selected_ec="supported_ec_${info["ec_vendor"],,}"
                    eval "ec_series=(\"\${${selected_ec}[@]}\")"
                    sel=$(dev_selection "ec_series" "${ec_series[@]}")
                    ;;
                "colorscheme")
                    whiptail_colorscheme_select
                    sel="${info["colorscheme"]}"
                    ;;
                *)
                    echo "Error: invalid menu selection"
                    exit 1
                    ;;
            esac

            if [ -n "${sel}" ]; then
                if [[ "${sel}" =~ [Ee]rror ]]; then
                    echo "${sel}"
                    exit 1
                fi

                info["${menu}"]="${sel}"
            fi

            menu=
        done
    }

    function board_setup() {
        declare -A board_info

        if [ "${info["soc_vendor"]}" == "Intel" ]; then
            case ${info["soc_series"]} in
                "Alder Lake")
                    board_info["soc_series"]="adl"
                    ;;
                "Alder Lake P")
                    board_info["soc_series"]="adl_p"
                    ;;
                "Meteor Lake")
                    board_info["soc_series"]="mtl_s"
                    ;;
                "Meteor Lake P")
                    board_info["soc_series"]="mtl_p"
                    ;;
                *)
                    echo "${info["soc_vendor"]} ${info["soc_series"]} is not supporting in ecfw project"
                    exit 1
                    ;;
            esac
        elif [ "${info["soc_vendor"]}" == "AMD" ]; then
            case ${info["soc_series"]} in
                "Hawk Point")
                    board_info["soc_series"]="hkp"
                    ;;
                *)
                    echo "${info["soc_vendor"]} ${info["soc_series"]} is not supporting in ecfw project"
                    exit 1
                    ;;
            esac
        else
            echo "soc vendor ${info["soc_vendor"]} is not supporting in ecfw project"
            exit 1
        fi

        case ${info["ec_vendor"]} in
            "microchip")
                board_info["ec_vendor"]="mec"

                case ${info["ec_series"]} in
                    *)
                        board_info["ec_series"]="${info["ec_series"]}"
                        ;;
                esac
                ;;
            *)
                echo "${info["ec_vendor"]} ${info["ec_series"]} is not supporting in ecfw project"
                exit 1
                ;;
        esac

        zephyr_board="${board_info["ec_vendor"]}${board_info["ec_series"]}_${board_info["soc_series"]}"
        echo "zephyr board: ${zephyr_board}"
    }

    whiptail_colorscheme_select ${info["colorscheme"]}
    ecfw_board_selection
    board_setup
}

function check_and_setup_parameters() {
    if [ "$#" -gt 0 ]; then
        zephyr_board="$1"
    fi

    if [ -z "${zephyr_board}" ]; then
        zephyr_board="mec1501_adl"
    fi

    if [ -z "$BOARD" ]; then
        set_zephyr_board="--board $zephyr_board"
    else
        set_zephyr_board=" "
        zephyr_board="$BOARD"
    fi

    if [ -z "$ZEPHYR_TOOLCHAIN_VARIANT" ]; then
        export ZEPHYR_TOOLCHAIN_VARIANT='zephyr'
    fi
}

function check_and_setup_west_workspace() {
    zephyr_west_topdir="$(west topdir 2>/dev/null)" || {
        cd ${zephyr_build_script_path} || {
            echo "Error: failed to change directory to build script path to get west topdir"
            exit 1
        }
    }

    if [[ "$(west config --local manifest.path 2>/dev/null)" != \
        "$(basename ${zephyr_build_script_path})" ]];
    then
        west init -l "${zephyr_build_script_path}" || {
            echo "Error: failed to initialize west workspace in ${zephyr_build_script_path}"
            exit 1
        }

        if [[ "$(west config --local manifest.path 2>/dev/null)" != \
            "$(basename ${zephyr_build_script_path})" ]];
        then
            echo "Error: failed to set manifest path in west workspace by west init"
            exit 1
        fi

        cd "$(west topdir 2>/dev/null)" || {
            echo "Error: failed to change directory to west top directory"
            exit 1
        }
    fi

    zephyr_west_topdir="$(west topdir 2>/dev/null)" || {
        echo "Error:failed to get west topdir"
        exit 1
    }

    if [ ! -d "${zephyr_west_topdir}/${zephyr_west_manifest_path}" ]; then
        west update -n || {
            echo "Error: failed to update west workspace"
            exit 1
        }
    fi

    zephyr_base_path="${zephyr_west_topdir}/${zephyr_west_manifest_path}/zephyr_fork"

    if [[ "$(west config --local zephyr.base 2>/dev/null)" != "${zephyr_base_path}" ]]; then
        if [ -d "${zephyr_base_path}" ]; then
            west config --local zephyr.base "${zephyr_west_manifest_path}/zephyr_fork" || {
                echo "Error: failed to set zephyr base path in west workspace"
                exit 1
            }
        else
            echo "Error: zephyr_fork directory is not found in ${zephyr_west_topdir}/${zephyr_west_manifest_path}"
            exit 1
        fi
    fi

    if [[ "$(west config --local zephyr.base-prefer 2>/dev/null)" != "configfile" ]]; then
        west config --local zephyr.base-prefer "configfile" || {
            echo "Error: failed to set zephyr base path in west workspace"
            exit 1
        }
    fi
}

function setup_microchip_config() {
    # "mec_spi_gen_info" array contains below keys:
    # - "series": microchip series compatible with CPGZephyrDocs directory. ex. MEC1501, MEC152x, MEC172x
    # - "generator": spi generator file name. ex. everglades_spi_gen_lin64, everglades_spi_gen_RomE, mec172x_spi_gen_lin_x86_64
    # - "env": environment variable to set spi generator path. ex. EVERGLADES_SPI_GEN, MEC172X_SPI_GEN
    declare -A mec_spi_gen_info
    set_zephyr_dconfig=" "
    zephyr_mec_spi_gen_path="${zephyr_west_topdir}/${zephyr_west_manifest_path}/CPGZephyrDocs"
    mec_cpgzephyrdocs_repo="https://github.com/MicrochipTech/CPGZephyrDocs.git"

    if [ ! -d "${zephyr_mec_spi_gen_path}" ]; then
        echo "Warn: CPGZephyrDocs directory not found in ${zephyr_mec_spi_gen_path}"
        git clone --depth 1 ${mec_cpgzephyrdocs_repo} "${zephyr_mec_spi_gen_path}" || {
            echo "Error: failed to clone microchip spi generator into ${zephyr_mec_spi_gen_path}"
            exit 1
        }
    fi

    case "${zephyr_board}" in
        "mec150"*)
            mec_spi_gen_info["series"]="MEC1501"
            mec_spi_gen_info["generator"]="everglades_spi_gen_lin64"
            mec_spi_gen_info["env"]="EVERGLADES_SPI_GEN"

            if [[ $zephyr_board == *"modular_assy"* ]]; then
                set_zephyr_dconfig="-- -DCONFIG_MEC15XX_AIC_ON_TGL=y"
            fi
            ;;

        "mec152"*)
            mec_spi_gen_info["series"]="MEC152x"
            mec_spi_gen_info["generator"]="everglades_spi_gen_RomE"
            mec_spi_gen_info["env"]="EVERGLADES_SPI_GEN"
            # MEC152x compatible with MEC1501 in zephyr board
            zephyr_board="$(sed -e 's/mec152\w/mec1501/' <<< ${zephyr_board})"
            set_zephyr_board="--board ${zephyr_board}"

            if [[ $zephyr_board == *"modular_assy"* ]]; then
                set_zephyr_dconfig="-- -DCONFIG_MEC15XX_AIC_ON_TGL=y"
            fi
            ;;

        "mec172"*)
            mec_spi_gen_info["series"]="MEC172x"
            mec_spi_gen_info["generator"]="mec172x_spi_gen_lin_x86_64"
            mec_spi_gen_info["env"]="MEC172X_SPI_GEN"

            if [[ $zephyr_board == *"modular_assy"* ]]; then
                set_zephyr_dconfig=" "
            fi
            ;;

        *)
            echo "Error: ${zephyr_board} is not supporting in ecfw project"
            exit 1
            ;;
    esac

    mec_spi_gen_chip_series_dir="${zephyr_mec_spi_gen_path}/${mec_spi_gen_info["series"]}"

    if [ ! -d "${mec_spi_gen_chip_series_dir}" ]; then
        echo "Error: ${mec_spi_gen_chip_series_dir} directory not found for ${zephyr_board}"
        exit 1
    fi

    mec_spi_gen="$(find ${mec_spi_gen_chip_series_dir} -name "${mec_spi_gen_info["generator"]}" -type f -print 2>/dev/null)"

    if [ -z "${mec_spi_gen_info["generator"]}" ]; then
        echo "Error: spi generator not found for ${zephyr_board}"
        exit 1
    fi

    export "${mec_spi_gen_info["env"]}"="${mec_spi_gen}"

    if [ -z "$(git -C ${zephyr_base_path} status --porcelain)" ]; then
        patch_files=($(find ${zephyr_build_script_path}/zephyr_patches \
            -type f -name "patch*v[[:digit:]]*_[[:digit:]]*.patch" -print | sort))

        git -C ${zephyr_base_path} apply "${patch_files[$((${#patch_files[@]} - 1))]}" || {
            echo "Error: failed to apply patches on ecfw zephyr base kernel"
            exit 1
        }
    fi
}

function check_supported_board() {
    zephyr_ecfw_boards="$(ls ${zephyr_build_script_path}/out_of_tree_boards/boards/* 2>/dev/null)"
    found_supported_board='no'

    for board in ${zephyr_ecfw_boards}; do
        if [ "$(basename ${board})" == "${zephyr_board}" ]; then
            found_supported_board='yes'
            break
        fi
    done

    if [ "${found_supported_board}" != 'yes' ]; then
        echo "Error: ${zephyr_board} is not supported in ecfw project"
        exit 1
    fi
}

if [ "$#" -eq 0 ]; then
    parameters_selection
fi

check_and_setup_parameters
check_and_setup_west_workspace

if [[ "${zephyr_board}" =~ ^mec[[:digit:]]{2}.* ]]; then
    setup_microchip_config
fi

check_supported_board

zephyr_app_path="${zephyr_west_topdir}/$(west config --local manifest.path)"
west build -t menuconfig -p=always -d build $set_zephyr_board \
    $set_zephyr_dconfig "${zephyr_app_path}" && \
    west build
