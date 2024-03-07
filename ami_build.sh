#!/bin/bash

zephyr_build_script_path="$(dirname $(readlink -f "$0"))"
zephyr_west_manifest_path="ecfwwork"

function parameters_selection() {
    parameters=("soc" "chipset" "series")
    declare -A info

    supported_dev_soc=("Alder Lake" "Alder Lake P" "Meteor Lake" "Meteor Lake P")
    supported_dev_chipset=("microchip")
    # chipset series: depending on supported_dev_chipset
    # - format "supported_dev_<chipset=(<series1> <series2> ...)"
    supported_dev_microchip=("1501" "152x" "172x")
    # default values
    info["soc"]=${supported_dev_soc[0]}
    info["chipset"]=${supported_dev_chipset[0]}
    info["series"]=${supported_dev_microchip[0]}

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

        sel=$(whiptail --title "${title}" --radiolist "Please select one of options" 20 60 10 \
            "${lists[@]}" 3>&1 1>&2 2>&3)

        echo "${sel}"
    }

    function ecfw_board_selection() {
        local menu=
        local sel=

        while [ -z ${menu} ]; do
            menu=$(whiptail \
                --title "AMI EC" \
                --menu "Please enter one of options to select" \
                20 60 10 \
                "soc"     "Platform series (${info["soc"]})"\
                "chipset" "EC chipset      (${info["chipset"]})" \
                "series"  "EC series       (${info["series"]})" \
                3>&1 1>&2 2>&3)

            if [ -z "${menu}" ]; then
                break
            fi

            case ${menu} in
                "soc")
                    sel=$(dev_selection "soc" "${supported_dev_soc[@]}")
                    ;;
                "chipset")
                    sel=$(dev_selection "chipset" "${supported_dev_chipset[@]}")
                    ;;
                "series")
                    selected_dev_chipset="supported_dev_${info["chipset"]}"
                    eval "dev_series=(\"\${${selected_dev_chipset}[@]}\")"
                    sel=$(dev_selection "series" "${dev_series[@]}")
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

        case ${info["soc"]} in
            "Alder Lake")
                board_info["soc"]="adl"
                ;;
            "Alder Lake P")
                board_info["soc"]="adl_p"
                ;;
            "Meteor Lake")
                board_info["soc"]="mtl_s"
                ;;
            "Meteor Lake P")
                board_info["soc"]="mtl_p"
                ;;
            *)
                echo "soc ${info["soc"]} is not supporting in ecfw project"
                exit 1
                ;;
        esac

        case ${info["chipset"]} in
            "microchip")
                board_info["chipset"]="mec"

                case ${info["series"]} in
                    *)
                        board_info["series"]="${info["series"]}"
                        ;;
                esac
                ;;
            *)
                echo "chipset ${info["chipset"]} is not supporting in ecfw project"
                exit 1
                ;;
        esac

        zephyr_board="${board_info["chipset"]}${board_info["series"]}_${board_info["soc"]}"
        echo "zephyr board: ${zephyr_board}"
    }

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
check_supported_board

if [[ "${zephyr_board}" =~ ^mec[[:digit:]]{2}.* ]]; then
    setup_microchip_config
fi

zephyr_app_path="${zephyr_west_topdir}/$(west config --local manifest.path)"
west build -t menuconfig -p=always -d build $set_zephyr_board \
    $set_zephyr_dconfig "${zephyr_app_path}" && \
    west build
